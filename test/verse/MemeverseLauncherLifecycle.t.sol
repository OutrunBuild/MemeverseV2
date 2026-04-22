// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    IOFT,
    SendParam,
    MessagingFee,
    MessagingReceipt,
    OFTReceipt,
    OFTLimit,
    OFTFeeDetail
} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta, toBalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";

import {MemeverseLauncher} from "../../src/verse/MemeverseLauncher.sol";
import {IMemeverseLauncher} from "../../src/verse/interfaces/IMemeverseLauncher.sol";
import {IMemeverseSwapRouter} from "../../src/swap/interfaces/IMemeverseSwapRouter.sol";
import {IMemeverseUniswapHook} from "../../src/swap/interfaces/IMemeverseUniswapHook.sol";

interface IRefundCallbackObserver {
    /// @notice Handles the token refund callback emitted by the test refund token.
    /// @dev Used to assert CEI ordering during refund-sensitive launcher flows.
    function onRefundCallback() external;
}

contract MockLaunchSettlementHookForLauncherTest {
    struct LaunchSwapResult {
        uint256 amountIn;
        uint256 amountOut;
    }

    struct FeeQuote {
        uint256 fee0;
        uint256 fee1;
    }

    address internal boundLauncher;
    mapping(bytes32 => LaunchSwapResult) internal launchSwapResults;
    mapping(bytes32 => uint40) internal publicSwapResumeTimes;
    mapping(bytes32 => FeeQuote) internal previewQuotes;
    mapping(bytes32 => FeeQuote) internal claimQuotes;
    uint160 internal expectedZeroForOneSqrtPriceLimitX96;
    uint160 internal expectedOneForZeroSqrtPriceLimitX96;
    bool internal enforceExpectedSqrtPriceLimitX96;
    bool internal revertLaunchSettlement;
    string internal launchSettlementRevertReason;
    bool internal lastLaunchSettlementZeroForOne;
    uint160 internal lastLaunchSettlementSqrtPriceLimitX96;
    uint256 internal launchSettlementCallCount;

    constructor(address boundLauncher_) {
        boundLauncher = boundLauncher_;
    }

    function launcher() external view returns (address launcher_) {
        return boundLauncher;
    }

    function setLaunchSwapResult(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut) external {
        launchSwapResults[keccak256(abi.encode(_pairKey(tokenIn, tokenOut), tokenIn, tokenOut))] =
            LaunchSwapResult({amountIn: amountIn, amountOut: amountOut});
    }

    function setPreviewQuote(address tokenA, address tokenB, address owner, uint256 fee0, uint256 fee1) external {
        previewQuotes[keccak256(abi.encode(_pairKey(tokenA, tokenB), owner))] = FeeQuote({fee0: fee0, fee1: fee1});
    }

    function setClaimQuote(address tokenA, address tokenB, address owner, uint256 fee0, uint256 fee1) external {
        claimQuotes[keccak256(abi.encode(_pairKey(tokenA, tokenB), owner))] = FeeQuote({fee0: fee0, fee1: fee1});
    }

    function setPublicSwapResumeTime(bytes32 poolId, uint40 resumeTime) external {
        require(msg.sender == boundLauncher, "unauthorized launcher");
        publicSwapResumeTimes[poolId] = resumeTime;
    }

    function setPublicSwapResumeTime(address tokenA, address tokenB, uint40 resumeTime) external {
        require(msg.sender == boundLauncher, "unauthorized launcher");
        publicSwapResumeTimes[_poolId(tokenA, tokenB)] = resumeTime;
    }

    function publicSwapResumeTime(bytes32 poolId) external view returns (uint40 resumeTime) {
        return publicSwapResumeTimes[poolId];
    }

    function claimableFees(PoolKey calldata key, address owner) external view returns (uint256 fee0, uint256 fee1) {
        address token0 = Currency.unwrap(key.currency0);
        address token1 = Currency.unwrap(key.currency1);
        FeeQuote memory quote = previewQuotes[keccak256(abi.encode(_pairKey(token0, token1), owner))];
        return (quote.fee0, quote.fee1);
    }

    function claimFeesCore(IMemeverseUniswapHook.ClaimFeesCoreParams calldata params)
        external
        returns (uint256 fee0, uint256 fee1)
    {
        address token0 = Currency.unwrap(params.key.currency0);
        address token1 = Currency.unwrap(params.key.currency1);
        FeeQuote memory quote = claimQuotes[keccak256(abi.encode(_pairKey(token0, token1), msg.sender))];

        fee0 = quote.fee0;
        fee1 = quote.fee1;

        if (fee0 != 0) MockERC20(token0).mint(params.recipient, fee0);
        if (fee1 != 0) MockERC20(token1).mint(params.recipient, fee1);
    }

    function setExpectedLaunchSqrtPriceLimit(bool zeroForOne, uint160 expectedSqrtPriceLimitX96) external {
        if (zeroForOne) {
            expectedZeroForOneSqrtPriceLimitX96 = expectedSqrtPriceLimitX96;
        } else {
            expectedOneForZeroSqrtPriceLimitX96 = expectedSqrtPriceLimitX96;
        }
        enforceExpectedSqrtPriceLimitX96 = true;
    }

    function setLaunchSettlementRevert(string calldata reason) external {
        revertLaunchSettlement = true;
        launchSettlementRevertReason = reason;
    }

    function lastSettlementZeroForOne() external view returns (bool zeroForOne) {
        return lastLaunchSettlementZeroForOne;
    }

    function lastSettlementSqrtPriceLimitX96() external view returns (uint160 sqrtPriceLimitX96) {
        return lastLaunchSettlementSqrtPriceLimitX96;
    }

    function settlementCallCount() external view returns (uint256 count) {
        return launchSettlementCallCount;
    }

    function executeLaunchSettlement(IMemeverseUniswapHook.LaunchSettlementParams calldata params)
        external
        returns (BalanceDelta delta)
    {
        require(msg.sender == boundLauncher, "unauthorized launcher");
        if (revertLaunchSettlement) revert(launchSettlementRevertReason);
        lastLaunchSettlementZeroForOne = params.params.zeroForOne;
        lastLaunchSettlementSqrtPriceLimitX96 = params.params.sqrtPriceLimitX96;
        launchSettlementCallCount++;
        if (enforceExpectedSqrtPriceLimitX96) {
            uint160 expectedSqrtPriceLimitX96 =
                params.params.zeroForOne ? expectedZeroForOneSqrtPriceLimitX96 : expectedOneForZeroSqrtPriceLimitX96;
            require(params.params.sqrtPriceLimitX96 == expectedSqrtPriceLimitX96, "unexpected sqrtPriceLimitX96");
        }
        address tokenIn =
            params.params.zeroForOne ? Currency.unwrap(params.key.currency0) : Currency.unwrap(params.key.currency1);
        address tokenOut =
            params.params.zeroForOne ? Currency.unwrap(params.key.currency1) : Currency.unwrap(params.key.currency0);
        LaunchSwapResult memory result =
            launchSwapResults[keccak256(abi.encode(_pairKey(tokenIn, tokenOut), tokenIn, tokenOut))];
        if (result.amountOut != 0) {
            MockERC20(tokenOut).mint(params.recipient, result.amountOut);
        }
        require(uint256(-params.params.amountSpecified) == result.amountIn, "unexpected amountIn");

        if (params.params.zeroForOne) {
            return toBalanceDelta(-int128(int256(result.amountIn)), int128(int256(result.amountOut)));
        }
        return toBalanceDelta(int128(int256(result.amountOut)), -int128(int256(result.amountIn)));
    }

    function _pairKey(address tokenA, address tokenB) internal pure returns (bytes32) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        return keccak256(abi.encode(token0, token1));
    }

    function _poolId(address tokenA, address tokenB) internal view returns (bytes32) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        return PoolId.unwrap(
            PoolKey({
                    currency0: Currency.wrap(token0),
                    currency1: Currency.wrap(token1),
                    fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
                    tickSpacing: 200,
                    hooks: IHooks(address(this))
                }).toId()
        );
    }
}

// `MemeverseLauncherSwapIntegration.t.sol` currently covers the real launch-settlement path and exposes the
// current real-stack `mintPOLToken` / fee-claim blockers.
// This mock router remains for broader lifecycle-focused tests that isolate launcher control flow from router internals.
contract MockSwapRouter {
    using SafeERC20 for IERC20;

    struct Quote {
        uint256 fee0;
        uint256 fee1;
    }

    struct AddLiquidityResult {
        uint128 liquidity;
        uint256 amount0Used;
        uint256 amount1Used;
    }

    mapping(bytes32 => Quote) internal previewQuotes;
    mapping(bytes32 => Quote) internal claimQuotes;
    mapping(bytes32 => address) internal lpTokens;
    mapping(bytes32 => AddLiquidityResult) internal addLiquidityResults;
    mapping(bytes32 => uint256) internal paddedLiquidityQuoteAmountA;
    mapping(bytes32 => uint256) internal paddedLiquidityQuoteAmountB;
    mapping(bytes32 => uint256) internal exactLiquidityQuoteAmountA;
    mapping(bytes32 => uint256) internal exactLiquidityQuoteAmountB;
    MockLaunchSettlementHookForLauncherTest internal immutable settlementHook;
    uint256 internal addLiquidityCallCount_;
    uint256 internal addLiquidityDetailedCallCount_;

    constructor(address launcher_) {
        settlementHook = new MockLaunchSettlementHookForLauncherTest(launcher_);
    }

    /// @notice Exposes the mock hook used by the router.
    /// @dev Returns the helper hook that supports explicit launch settlement execution.
    /// @return hookAddress Mock hook address.
    function hook() external view returns (address) {
        return address(settlementHook);
    }

    function addLiquidityCallCount() external view returns (uint256 count) {
        return addLiquidityCallCount_;
    }

    function addLiquidityDetailedCallCount() external view returns (uint256 count) {
        return addLiquidityDetailedCallCount_;
    }

    function _pairKey(address tokenA, address tokenB) internal pure returns (bytes32) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        return keccak256(abi.encode(token0, token1));
    }

    function _normalizePairAmounts(address tokenA, address tokenB, uint256 amountA, uint256 amountB)
        internal
        pure
        returns (uint256 amount0, uint256 amount1)
    {
        if (tokenA < tokenB) return (amountA, amountB);
        return (amountB, amountA);
    }

    function _liquidityKey(address tokenA, address tokenB, uint128 liquidityDesired) internal pure returns (bytes32) {
        return keccak256(abi.encode(_pairKey(tokenA, tokenB), liquidityDesired));
    }

    /// @notice Sets both preview and claim fee quotes for a token pair and owner.
    /// @dev Used by tests to keep preview and redemption expectations aligned.
    /// @param tokenA First token in the pair.
    /// @param tokenB Second token in the pair.
    /// @param owner Owner whose quote should be returned.
    /// @param fee0 Mock fee amount for token0.
    /// @param fee1 Mock fee amount for token1.
    function setQuote(address tokenA, address tokenB, address owner, uint256 fee0, uint256 fee1) external {
        setPreviewQuote(tokenA, tokenB, owner, fee0, fee1);
        setClaimQuote(tokenA, tokenB, owner, fee0, fee1);
    }

    /// @notice Sets the preview fee quote for a token pair and owner.
    /// @dev Stores fees using normalized token ordering.
    /// @param tokenA First token in the pair.
    /// @param tokenB Second token in the pair.
    /// @param owner Owner whose preview quote should be returned.
    /// @param fee0 Mock fee amount for token0.
    /// @param fee1 Mock fee amount for token1.
    function setPreviewQuote(address tokenA, address tokenB, address owner, uint256 fee0, uint256 fee1) public {
        previewQuotes[keccak256(abi.encode(_pairKey(tokenA, tokenB), owner))] = Quote({fee0: fee0, fee1: fee1});
        settlementHook.setPreviewQuote(tokenA, tokenB, owner, fee0, fee1);
    }

    /// @notice Sets the claim fee quote for a token pair and owner.
    /// @dev Stores fees using normalized token ordering.
    /// @param tokenA First token in the pair.
    /// @param tokenB Second token in the pair.
    /// @param owner Owner whose claim quote should be returned.
    /// @param fee0 Mock fee amount for token0.
    /// @param fee1 Mock fee amount for token1.
    function setClaimQuote(address tokenA, address tokenB, address owner, uint256 fee0, uint256 fee1) public {
        claimQuotes[keccak256(abi.encode(_pairKey(tokenA, tokenB), owner))] = Quote({fee0: fee0, fee1: fee1});
        settlementHook.setClaimQuote(tokenA, tokenB, owner, fee0, fee1);
    }

    /// @notice Sets the LP token returned for a token pair.
    /// @dev Stores the LP token using normalized token ordering.
    /// @param tokenA First token in the pair.
    /// @param tokenB Second token in the pair.
    /// @param liquidityToken Mock LP token address for the pair.
    function setLpToken(address tokenA, address tokenB, address liquidityToken) external {
        lpTokens[_pairKey(tokenA, tokenB)] = liquidityToken;
    }

    /// @notice Sets the mocked add-liquidity execution result for a pair.
    /// @dev Stores the actual token usage and LP liquidity that `addLiquidity(...)` should produce.
    /// @param tokenA First token in the pair.
    /// @param tokenB Second token in the pair.
    /// @param liquidity Mock LP liquidity to mint.
    /// @param amountAUsed Mock amount of `tokenA` consumed.
    /// @param amountBUsed Mock amount of `tokenB` consumed.
    function setAddLiquidityResult(
        address tokenA,
        address tokenB,
        uint128 liquidity,
        uint256 amountAUsed,
        uint256 amountBUsed
    ) external {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        (uint256 amount0Used, uint256 amount1Used) = _normalizePairAmounts(tokenA, tokenB, amountAUsed, amountBUsed);
        addLiquidityResults[_pairKey(token0, token1)] =
            AddLiquidityResult({liquidity: liquidity, amount0Used: amount0Used, amount1Used: amount1Used});
    }

    /// @notice Sets the mocked exact-liquidity quote for a pair.
    /// @dev Stores the required input amounts using the caller-facing token order.
    /// @param tokenA First token in the pair.
    /// @param tokenB Second token in the pair.
    /// @param liquidityDesired Target liquidity to quote.
    /// @param amountARequired Mock required amount of `tokenA`.
    /// @param amountBRequired Mock required amount of `tokenB`.
    function setQuoteAmountsForLiquidity(
        address tokenA,
        address tokenB,
        uint128 liquidityDesired,
        uint256 amountARequired,
        uint256 amountBRequired
    ) external {
        bytes32 key = _liquidityKey(tokenA, tokenB, liquidityDesired);
        paddedLiquidityQuoteAmountA[key] = amountARequired;
        paddedLiquidityQuoteAmountB[key] = amountBRequired;
    }

    /// @notice Sets the mocked exact-liquidity quote for a pair.
    /// @dev Stores the exact-path input amounts separately from the padded quote fixture.
    /// @param tokenA First token in the pair.
    /// @param tokenB Second token in the pair.
    /// @param liquidityDesired Target liquidity to quote.
    /// @param amountARequired Mock exact-path amount of `tokenA`.
    /// @param amountBRequired Mock exact-path amount of `tokenB`.
    function setExactQuoteAmountsForLiquidity(
        address tokenA,
        address tokenB,
        uint128 liquidityDesired,
        uint256 amountARequired,
        uint256 amountBRequired
    ) external {
        bytes32 key = _liquidityKey(tokenA, tokenB, liquidityDesired);
        exactLiquidityQuoteAmountA[key] = amountARequired;
        exactLiquidityQuoteAmountB[key] = amountBRequired;
    }

    /// @notice Sets the mocked launch preorder swap result for a pair.
    /// @dev Stores the input budget consumed and the memecoin amount returned to the recipient.
    /// @param tokenIn Input token used by the launch settlement swap.
    /// @param tokenOut Output token returned by the launch settlement swap.
    /// @param amountIn Mock amount of `tokenIn` consumed.
    /// @param amountOut Mock amount of `tokenOut` returned.
    function setLaunchSwapResult(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut) external {
        settlementHook.setLaunchSwapResult(tokenIn, tokenOut, amountIn, amountOut);
    }

    /// @notice Returns the mocked preview fees for a token pair and owner.
    /// @dev Mimics router-side pair normalization.
    /// @param tokenA First token in the pair.
    /// @param tokenB Second token in the pair.
    /// @param owner Owner whose preview quote is requested.
    /// @return fee0 Mock fee amount for token0.
    /// @return fee1 Mock fee amount for token1.
    function previewClaimableFees(address tokenA, address tokenB, address owner)
        external
        view
        returns (uint256 fee0, uint256 fee1)
    {
        Quote memory quote = previewQuotes[keccak256(abi.encode(_pairKey(tokenA, tokenB), owner))];
        return (quote.fee0, quote.fee1);
    }

    /// @notice Returns the mocked LP token for a token pair.
    /// @dev Mimics router-side pair normalization.
    /// @param tokenA First token in the pair.
    /// @param tokenB Second token in the pair.
    /// @return liquidityToken Mock LP token address for the pair.
    function lpToken(address tokenA, address tokenB) external view returns (address liquidityToken) {
        return lpTokens[_pairKey(tokenA, tokenB)];
    }

    /// @notice Returns the mocked required token amounts for a target liquidity.
    /// @dev Reads the caller-facing token-order quote seeded by the test.
    /// @param tokenA First token in the pair.
    /// @param tokenB Second token in the pair.
    /// @param liquidityDesired Target liquidity to quote.
    /// @return amountARequired Mock required amount of `tokenA`.
    /// @return amountBRequired Mock required amount of `tokenB`.
    function quoteAmountsForLiquidity(address tokenA, address tokenB, uint128 liquidityDesired)
        external
        view
        returns (uint256 amountARequired, uint256 amountBRequired)
    {
        bytes32 key = _liquidityKey(tokenA, tokenB, liquidityDesired);
        return (paddedLiquidityQuoteAmountA[key], paddedLiquidityQuoteAmountB[key]);
    }

    function quoteExactAmountsForLiquidity(address tokenA, address tokenB, uint128 liquidityDesired)
        external
        view
        returns (uint256 amountARequired, uint256 amountBRequired)
    {
        bytes32 key = _liquidityKey(tokenA, tokenB, liquidityDesired);
        return (exactLiquidityQuoteAmountA[key], exactLiquidityQuoteAmountB[key]);
    }

    /// @notice Returns a normalized mock pool key for a token pair.
    /// @dev Matches the launcher's expectations for router pool-key derivation.
    /// @param tokenA First token in the pair.
    /// @param tokenB Second token in the pair.
    /// @return key Mock pool key for the pair.
    function getHookPoolKey(address tokenA, address tokenB) external view returns (PoolKey memory key) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        return PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 200,
            hooks: IHooks(address(settlementHook))
        });
    }

    /// @notice Mints mocked claim fees to the requested recipient.
    /// @dev Uses the caller as the fee owner, matching launcher integration tests.
    /// @param key Mock pool key whose fees are claimed.
    /// @param recipient Recipient of the mocked claimed fees.
    /// @param deadline Unused mock signature deadline.
    /// @param v Unused mock signature recovery byte.
    /// @param r Unused mock signature r value.
    /// @param s Unused mock signature s value.
    /// @return fee0 Mock claimed fee amount for token0.
    /// @return fee1 Mock claimed fee amount for token1.
    function claimFees(PoolKey calldata key, address recipient, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
        returns (uint256 fee0, uint256 fee1)
    {
        deadline;
        v;
        r;
        s;
        address token0 = Currency.unwrap(key.currency0);
        address token1 = Currency.unwrap(key.currency1);
        Quote memory quote = claimQuotes[keccak256(abi.encode(_pairKey(token0, token1), msg.sender))];

        fee0 = quote.fee0;
        fee1 = quote.fee1;

        if (fee0 != 0) MockERC20(token0).mint(recipient, fee0);
        if (fee1 != 0) MockERC20(token1).mint(recipient, fee1);
    }

    /// @notice Executes a mocked add-liquidity call for a pair.
    /// @dev Pulls the configured used amounts from the caller and mints mock LP shares to `to`.
    /// @param currency0 First pool currency.
    /// @param currency1 Second pool currency.
    /// @param amount0Desired Unused desired amount for `currency0`.
    /// @param amount1Desired Unused desired amount for `currency1`.
    /// @param amount0Min Unused minimum amount for `currency0`.
    /// @param amount1Min Unused minimum amount for `currency1`.
    /// @param to Recipient of the mocked LP shares.
    /// @param deadline Unused deadline.
    /// @return liquidity Mock LP liquidity minted to `to`.
    function addLiquidity(
        Currency currency0,
        Currency currency1,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        address to,
        uint256 deadline
    ) external returns (uint128 liquidity) {
        addLiquidityCallCount_++;
        (liquidity,,) = _addLiquidityDetailed(
            currency0, currency1, amount0Desired, amount1Desired, amount0Min, amount1Min, to, deadline
        );
    }

    /// @notice Executes a mocked add-liquidity call and returns the actual spend alongside minted liquidity.
    /// @dev Mirrors the router detailed entrypoint by normalizing pool order internally but returning spend in caller order.
    /// @return liquidity Mock LP liquidity minted to `to`.
    /// @return amount0Used Mock amount of the first supplied currency consumed.
    /// @return amount1Used Mock amount of the second supplied currency consumed.
    function addLiquidityDetailed(
        Currency currency0,
        Currency currency1,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        address to,
        uint256 deadline
    ) external returns (uint128 liquidity, uint256 amount0Used, uint256 amount1Used) {
        addLiquidityDetailedCallCount_++;
        return _addLiquidityDetailed(
            currency0, currency1, amount0Desired, amount1Desired, amount0Min, amount1Min, to, deadline
        );
    }

    function _addLiquidityDetailed(
        Currency currency0,
        Currency currency1,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        address to,
        uint256 deadline
    ) internal returns (uint128 liquidity, uint256 amount0Used, uint256 amount1Used) {
        amount0Min;
        amount1Min;
        deadline;

        address tokenA = Currency.unwrap(currency0);
        address tokenB = Currency.unwrap(currency1);
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        (uint256 amount0Budget, uint256 amount1Budget) =
            _normalizePairAmounts(tokenA, tokenB, amount0Desired, amount1Desired);
        AddLiquidityResult memory result = addLiquidityResults[_pairKey(token0, token1)];
        require(result.amount0Used <= amount0Budget && result.amount1Used <= amount1Budget, "mock over budget");
        (uint256 amountAUsed, uint256 amountBUsed) =
            tokenA < tokenB ? (result.amount0Used, result.amount1Used) : (result.amount1Used, result.amount0Used);
        if (amountAUsed != 0) IERC20(tokenA).safeTransferFrom(msg.sender, address(this), amountAUsed);
        if (amountBUsed != 0) IERC20(tokenB).safeTransferFrom(msg.sender, address(this), amountBUsed);

        address liquidityToken = lpTokens[_pairKey(token0, token1)];
        if (result.liquidity != 0 && liquidityToken != address(0)) {
            MockERC20(liquidityToken).mint(to, result.liquidity);
        }
        return (result.liquidity, amountAUsed, amountBUsed);
    }

    /// @notice Executes a mocked pool bootstrap for a pair.
    /// @dev Reuses the configured add-liquidity result and returns the normalized pool key.
    /// @param tokenA First bootstrap token.
    /// @param tokenB Second bootstrap token.
    /// @param amountADesired Unused desired amount for `tokenA`.
    /// @param amountBDesired Unused desired amount for `tokenB`.
    /// @param startPrice Unused pool start price.
    /// @param recipient Recipient of mocked LP shares.
    /// @param deadline Unused deadline.
    /// @return liquidity Mock LP liquidity minted to `recipient`.
    /// @return poolKey Normalized mock pool key for the pair.
    function createPoolAndAddLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint160 startPrice,
        address recipient,
        uint256 deadline
    ) external returns (uint128 liquidity, PoolKey memory poolKey) {
        amountADesired;
        amountBDesired;
        startPrice;
        deadline;

        poolKey = this.getHookPoolKey(tokenA, tokenB);
        AddLiquidityResult memory result = addLiquidityResults[_pairKey(tokenA, tokenB)];
        address liquidityToken = lpTokens[_pairKey(tokenA, tokenB)];
        if (result.liquidity != 0 && liquidityToken != address(0)) {
            MockERC20(liquidityToken).mint(recipient, result.liquidity);
        }
        return (result.liquidity, poolKey);
    }
}

contract MockSwapRouterWithBrokenPoolKey {
    address internal immutable hookAddress;

    constructor(address hookAddress_) {
        hookAddress = hookAddress_;
    }

    function hook() external view returns (address) {
        return hookAddress;
    }

    function getHookPoolKey(address, address) external pure returns (PoolKey memory) {
        revert("pool key helper unused");
    }
}

contract MockLiquidProof is MockERC20 {
    uint256 public burnedAmount;
    bytes32 public lastPoolId;

    constructor() MockERC20("POL", "POL", 18) {}

    /// @notice Burns POL from an account and records the amount.
    /// @dev Extends the mock token so tests can assert the burn side effect.
    /// @param from Account whose balance is burned.
    /// @param value Amount of POL to burn.
    function burn(address from, uint256 value) public override {
        burnedAmount += value;
        super.burn(from, value);
    }

    /// @notice Stores the latest pool id configured by the launcher.
    /// @dev Mirrors the launcher-only hook setup side effect for tests.
    /// @param poolId Mock pool id.
    function setPoolId(bytes32 poolId) external {
        lastPoolId = poolId;
    }
}

contract RefundCallbackToken is MockERC20 {
    address public callbackTarget;

    constructor(string memory name_, string memory symbol_) MockERC20(name_, symbol_, 18) {}

    /// @notice Sets the address that should receive the refund callback.
    /// @dev Tests point this at an observer contract to detect transfer ordering.
    /// @param target Callback recipient triggered after successful transfers.
    function setCallbackTarget(address target) external {
        callbackTarget = target;
    }

    /// @notice Transfers tokens and triggers the test refund callback when needed.
    /// @dev Calls `onRefundCallback()` only when the recipient matches `callbackTarget`.
    /// @param to Transfer recipient.
    /// @param amount Token amount to transfer.
    /// @return success True when the ERC20 transfer succeeded.
    function transfer(address to, uint256 amount) public override returns (bool) {
        bool success = super.transfer(to, amount);
        if (success && to == callbackTarget) {
            IRefundCallbackObserver(to).onRefundCallback();
        }
        return success;
    }
}

contract MintPolRefundObserver is IRefundCallbackObserver {
    MemeverseLauncher public immutable launcher;
    IERC20 public immutable upt;
    IERC20 public immutable memecoin;
    IERC20 public immutable liquidProof;
    uint256 public immutable verseId;
    bool public sawPolDuringRefund;

    constructor(MemeverseLauncher launcher_, IERC20 upt_, IERC20 memecoin_, IERC20 liquidProof_, uint256 verseId_) {
        launcher = launcher_;
        upt = upt_;
        memecoin = memecoin_;
        liquidProof = liquidProof_;
        verseId = verseId_;
    }

    /// @notice Grants the launcher unlimited approval over the observer's test assets.
    /// @dev Used before invoking mint flows that pull UPT and memecoin from this helper.
    function approveLauncher() external {
        upt.approve(address(launcher), type(uint256).max);
        memecoin.approve(address(launcher), type(uint256).max);
    }

    /// @notice Forwards a `mintPOLToken` call through the observer contract.
    /// @dev Lets the test observe whether POL exists before refund callbacks fire.
    /// @param amountInUPTDesired Desired UPT spend.
    /// @param amountInMemecoinDesired Desired memecoin spend.
    /// @param amountInUPTMin Minimum accepted UPT spend.
    /// @param amountInMemecoinMin Minimum accepted memecoin spend.
    /// @param amountOutDesired Desired POL output.
    /// @param deadline Latest valid execution timestamp.
    /// @return amountInUPT Actual UPT spent.
    /// @return amountInMemecoin Actual memecoin spent.
    /// @return amountOut Actual POL minted.
    function executeMintPOLToken(
        uint256 amountInUPTDesired,
        uint256 amountInMemecoinDesired,
        uint256 amountInUPTMin,
        uint256 amountInMemecoinMin,
        uint256 amountOutDesired,
        uint256 deadline
    ) external returns (uint256 amountInUPT, uint256 amountInMemecoin, uint256 amountOut) {
        return launcher.mintPOLToken(
            verseId,
            amountInUPTDesired,
            amountInMemecoinDesired,
            amountInUPTMin,
            amountInMemecoinMin,
            amountOutDesired,
            deadline
        );
    }

    /// @notice Observes the refund callback and records whether POL had already been minted.
    /// @dev Reverts unless the callback came from the memecoin refund token and POL is already present.
    function onRefundCallback() external override {
        require(msg.sender == address(memecoin), "unexpected callback token");
        sawPolDuringRefund = liquidProof.balanceOf(address(this)) != 0;
        require(sawPolDuringRefund, "POL not minted before refund");
    }
}

contract MockPredictOnlyProxyDeployer {
    address public immutable predictedYieldVault;
    address public immutable predictedGovernor;
    address public immutable predictedIncentivizer;

    constructor(address yieldVault, address governor, address incentivizer) {
        predictedYieldVault = yieldVault;
        predictedGovernor = governor;
        predictedIncentivizer = incentivizer;
    }

    /// @notice Returns the mocked predicted yield vault address.
    /// @dev Ignores the verse id because this mock always returns a fixed address.
    /// @param uniqueId Unused mock verse id.
    /// @return yieldVault The mocked predicted yield vault address.
    function predictYieldVaultAddress(uint256 uniqueId) external view returns (address) {
        uniqueId;
        return predictedYieldVault;
    }

    /// @notice Returns the mocked predicted governor and incentivizer addresses.
    /// @dev Ignores the verse id because this mock always returns fixed addresses.
    /// @param uniqueId Unused mock verse id.
    /// @return governor The mocked governor address.
    /// @return incentivizer The mocked incentivizer address.
    function computeGovernorAndIncentivizerAddress(uint256 uniqueId)
        external
        view
        returns (address governor, address incentivizer)
    {
        uniqueId;
        return (predictedGovernor, predictedIncentivizer);
    }
}

contract MockOFTDispatcher {
    uint256 public composeCallCount;
    address public lastToken;
    bytes public lastMessage;

    /// @notice Records a mocked compose dispatch.
    /// @dev Stores the last token and payload for launcher fee-distribution assertions.
    /// @param _from Token address associated with the compose message.
    /// @param _guid Unused mock compose guid.
    /// @param _message Mock compose payload.
    /// @param _executor Unused mock executor address.
    /// @param _extraData Unused mock extra data.
    function lzCompose(
        address _from,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) external payable {
        _guid;
        _executor;
        _extraData;
        composeCallCount++;
        lastToken = _from;
        lastMessage = _message;
    }
}

contract MockLzEndpointRegistry {
    mapping(uint32 chainId => uint32 endpointId) public lzEndpointIdOfChain;

    /// @notice Set endpoint.
    /// @dev Mirrors the registry setter so tests can control chain/endpoint mapping.
    /// @param chainId See implementation.
    /// @param endpointId See implementation.
    function setEndpoint(uint32 chainId, uint32 endpointId) external {
        lzEndpointIdOfChain[chainId] = endpointId;
    }
}

contract MockOFTToken is MockERC20, IOFT {
    MessagingFee internal nextQuoteFee;
    uint32 public lastSendDstEid;
    address public lastRefundAddress;
    uint256 public lastNativeFeePaid;
    uint256 public sendCallCount;

    constructor(string memory name_, string memory symbol_) MockERC20(name_, symbol_, 18) {}

    /// @notice Set quote fee.
    /// @dev Stores the per-chain fee used by remote quote tests.
    /// @param nativeFee See implementation.
    function setQuoteFee(uint256 nativeFee) external {
        nextQuoteFee = MessagingFee({nativeFee: nativeFee, lzTokenFee: 0});
    }

    /// @notice Oft version.
    /// @dev Returns the IOFT interface id and mock version used by the dispatcher.
    /// @return interfaceId See implementation.
    /// @return version See implementation.
    function oftVersion() external pure returns (bytes4 interfaceId, uint64 version) {
        return (type(IOFT).interfaceId, 1);
    }

    /// @notice Token.
    /// @dev Always returns `address(this)` because this mock represents that token.
    /// @return See implementation.
    function token() external view returns (address) {
        return address(this);
    }

    /// @notice Approval required.
    /// @dev Matches the IOFT interface by allowing immediate approval.
    /// @return See implementation.
    function approvalRequired() external pure returns (bool) {
        return false;
    }

    /// @notice Shared decimals.
    /// @dev Signals the decimals that accompany messaging fees.
    /// @return See implementation.
    function sharedDecimals() external pure returns (uint8) {
        return 6;
    }

    /// @notice Quote oft.
    /// @dev Present to satisfy the IOFT interface but left unused in these tests.
    /// @return See implementation.
    function quoteOFT(SendParam calldata)
        external
        pure
        returns (OFTLimit memory, OFTFeeDetail[] memory, OFTReceipt memory)
    {
        revert("unused");
    }

    /// @notice Quote send.
    /// @dev Returns the previously stored messaging fee for the requested payload.
    /// @param sendParam See implementation.
    /// @param payInLzToken See implementation.
    /// @return fee See implementation.
    function quoteSend(SendParam calldata sendParam, bool payInLzToken)
        external
        view
        returns (MessagingFee memory fee)
    {
        sendParam;
        payInLzToken;
        fee = nextQuoteFee;
    }

    /// @notice Send.
    /// @dev Records the last dispatch payload and returns deterministic receipts.
    /// @param sendParam See implementation.
    /// @param fee See implementation.
    /// @param refundAddress See implementation.
    /// @return receipt See implementation.
    /// @return oftReceipt See implementation.
    function send(SendParam calldata sendParam, MessagingFee calldata fee, address refundAddress)
        external
        payable
        returns (MessagingReceipt memory receipt, OFTReceipt memory oftReceipt)
    {
        lastSendDstEid = sendParam.dstEid;
        lastRefundAddress = refundAddress;
        lastNativeFeePaid = msg.value;
        sendCallCount++;

        receipt = MessagingReceipt({guid: bytes32("oft-guid"), nonce: 1, fee: fee});
        oftReceipt = OFTReceipt({amountSentLD: sendParam.amountLD, amountReceivedLD: sendParam.amountLD});
    }
}

contract TestableMemeverseLauncher is MemeverseLauncher {
    constructor(
        address _owner,
        address _localLzEndpoint,
        address _memeverseRegistrar,
        address _memeverseProxyDeployer,
        address _yieldDispatcher,
        address _lzEndpointRegistry,
        uint256 _executorRewardRate,
        uint128 _oftReceiveGasLimit,
        uint128 _yieldDispatcherGasLimit,
        uint256 _preorderCapRatio,
        uint256 _preorderVestingDuration
    )
        MemeverseLauncher(
            _owner,
            _localLzEndpoint,
            _memeverseRegistrar,
            _memeverseProxyDeployer,
            _yieldDispatcher,
            _lzEndpointRegistry,
            _executorRewardRate,
            _oftReceiveGasLimit,
            _yieldDispatcherGasLimit,
            _preorderCapRatio,
            _preorderVestingDuration
        )
    {}

    /// @notice Stores mock memeverse state for a verse id.
    /// @dev Exposes direct storage writes needed by unit tests.
    /// @param verseId Verse id whose state should be set.
    /// @param verse Mock memeverse state to store.
    function setMemeverseForTest(uint256 verseId, Memeverse memory verse) external {
        memeverses[verseId] = verse;
    }

    /// @notice Stores mock genesis fund totals for a verse id.
    /// @dev Lets tests control redemption share math directly.
    /// @param verseId Verse id whose genesis totals should be set.
    /// @param totalMemecoinFunds Mock memecoin-side genesis total.
    /// @param totalPolFunds Mock liquid-proof-side genesis total.
    function setGenesisFundForTest(uint256 verseId, uint128 totalMemecoinFunds, uint128 totalPolFunds) external {
        genesisFunds[verseId] = GenesisFund({totalMemecoinFunds: totalMemecoinFunds, totalPolFunds: totalPolFunds});
    }

    /// @notice Stores mock user genesis data for a verse id.
    /// @dev Lets tests control redemption eligibility flags directly.
    /// @param verseId Verse id whose user state should be set.
    /// @param account Account whose genesis data should be set.
    /// @param genesisFund Mock contributed genesis amount.
    /// @param isRefunded Mock refunded flag.
    /// @param isClaimed Mock claimed flag.
    /// @param isRedeemed Mock redeemed flag.
    function setUserGenesisDataForTest(
        uint256 verseId,
        address account,
        uint256 genesisFund,
        bool isRefunded,
        bool isClaimed,
        bool isRedeemed
    ) external {
        userGenesisData[verseId][account] = GenesisData({
            genesisFund: genesisFund, isRefunded: isRefunded, isClaimed: isClaimed, isRedeemed: isRedeemed
        });
    }

    /// @notice Stores mock user preorder data for a verse id.
    /// @dev Lets tests control preorder eligibility flags directly.
    /// @param verseId Verse id whose user state should be set.
    /// @param account Account whose preorder data should be set.
    /// @param funds Mock contributed preorder amount.
    /// @param claimedMemecoin Mock claimed preorder memecoin amount.
    /// @param isRefunded Mock refunded flag.
    function setUserPreorderDataForTest(
        uint256 verseId,
        address account,
        uint256 funds,
        uint256 claimedMemecoin,
        bool isRefunded
    ) external {
        userPreorderData[verseId][account] = PreorderData({
            funds: funds, claimedMemecoin: claimedMemecoin, isRefunded: isRefunded
        });
    }

    function getPreorderStateForTest(uint256 verseId)
        external
        view
        returns (uint256 totalFunds, uint256 settledMemecoin, uint40 settlementTimestamp)
    {
        PreorderState storage preorderState = preorderStates[verseId];
        return (preorderState.totalFunds, preorderState.settledMemecoin, preorderState.settlementTimestamp);
    }

    /// @notice Stores mock total POL liquidity for a verse id.
    /// @dev Used to drive POL LP redemption share math in tests.
    /// @param verseId Verse id whose total POL liquidity should be set.
    /// @param amount Mock total POL liquidity amount.
    function setTotalPolLiquidityForTest(uint256 verseId, uint256 amount) external {
        totalPolLiquidity[verseId] = amount;
    }

    /// @notice Stores mock total claimable POL for a verse id.
    /// @dev Used to drive POL claim math directly in tests.
    /// @param verseId Verse id whose total claimable POL should be set.
    /// @param amount Mock total claimable POL amount.
    function setTotalClaimablePOLForTest(uint256 verseId, uint256 amount) external {
        totalClaimablePOL[verseId] = amount;
    }

    /// @notice Stores mock pol to verse-id state for a verse.
    /// @dev Exposes the symmetric swap-gate index to unit tests without going through full registration.
    /// @param liquidProofAddress Pol token address whose verse id should be set.
    /// @param verseId Verse id to associate with the pol token.
    function setVerseIdByPolForTest(address liquidProofAddress, uint256 verseId) external {
        polToIds[liquidProofAddress] = verseId;
    }
}

contract MemeverseLauncherLifecycleTest is Test {
    using PoolIdLibrary for PoolKey;

    TestableMemeverseLauncher internal launcher;
    MockSwapRouter internal router;
    MockOFTDispatcher internal dispatcher;
    MockPredictOnlyProxyDeployer internal proxyDeployer;
    MockLzEndpointRegistry internal registry;
    MockERC20 internal upt;
    MockERC20 internal memecoin;
    MockLiquidProof internal liquidProof;

    address internal constant REWARD_RECEIVER = address(0xBEEF);
    address internal constant ALICE = address(0xA11CE);

    function _readPublicSwapResumeTime(PoolKey memory key) internal view returns (bool ok, uint40 resumeTime) {
        address hookAddress = address(IMemeverseSwapRouter(address(router)).hook());
        (bool success, bytes memory data) =
            hookAddress.staticcall(abi.encodeWithSignature("publicSwapResumeTime(bytes32)", key.toId()));
        if (!success || data.length != 32) return (false, 0);
        return (true, abi.decode(data, (uint40)));
    }

    /// @notice Deploys the launcher test harness and supporting mocks.
    /// @dev Wires the launcher to the mock router and mock dispatcher.
    function setUp() external {
        launcher = new TestableMemeverseLauncher(
            address(this),
            address(0x1),
            address(0x2),
            address(0x3),
            address(0x4),
            address(0x5),
            25,
            115_000,
            135_000,
            2_500,
            7 days
        );
        router = new MockSwapRouter(address(launcher));
        dispatcher = new MockOFTDispatcher();
        upt = new MockERC20("UPT", "UPT", 18);
        memecoin = new MockERC20("MEME", "MEME", 18);
        liquidProof = new MockLiquidProof();
        proxyDeployer = new MockPredictOnlyProxyDeployer(address(0xD00D), address(0xCAFE), address(0xF00D));
        registry = new MockLzEndpointRegistry();

        launcher.setMemeverseUniswapHook(address(router.hook()));
        launcher.setMemeverseSwapRouter(address(router));
        launcher.setYieldDispatcher(address(dispatcher));
        launcher.setMemeverseProxyDeployer(address(proxyDeployer));
        launcher.setLzEndpointRegistry(address(registry));
    }

    /// @notice Seeds the launcher state with a verse locked for staking.
    /// @dev Populates the necessary UPT/memecoin/liquid-proof pointers for locking tests.
    function _setLockedVerse(uint256 verseId) internal {
        IMemeverseLauncher.Memeverse memory verse;
        verse.UPT = address(upt);
        verse.memecoin = address(memecoin);
        verse.pol = address(liquidProof);
        verse.governor = address(0xCAFE);
        verse.yieldVault = address(0xD00D);
        verse.currentStage = IMemeverseLauncher.Stage.Locked;
        verse.omnichainIds = new uint32[](1);
        verse.omnichainIds[0] = uint32(block.chainid);
        launcher.setMemeverseForTest(verseId, verse);
    }

    /// @notice Transitions a seeded verse from Locked to Unlocked.
    /// @dev Reuses the locked verse fixture and flips the stage flag.
    function _setUnlockedVerse(uint256 verseId) internal {
        _setLockedVerse(verseId);
        IMemeverseLauncher.Memeverse memory verse = launcher.getMemeverseByVerseId(verseId);
        verse.currentStage = IMemeverseLauncher.Stage.Unlocked;
        launcher.setMemeverseForTest(verseId, verse);
    }

    /// @notice Seeds a verse that is currently in the Genesis stage.
    /// @dev Controls flashGenesis, endTime, and omnichain ids for change-stage tests.
    function _setGenesisVerse(uint256 verseId, bool flashGenesis, uint128 endTime) internal {
        _setGenesisVerseWithAssets(
            verseId, address(upt), address(memecoin), address(liquidProof), flashGenesis, endTime
        );
    }

    function _setGenesisVerseWithAssets(
        uint256 verseId,
        address uptAddress,
        address memecoinAddress,
        address polAddress,
        bool flashGenesis,
        uint128 endTime
    ) internal {
        IMemeverseLauncher.Memeverse memory verse;
        verse.UPT = uptAddress;
        verse.memecoin = memecoinAddress;
        verse.pol = polAddress;
        verse.currentStage = IMemeverseLauncher.Stage.Genesis;
        verse.endTime = endTime;
        verse.flashGenesis = flashGenesis;
        verse.omnichainIds = new uint32[](1);
        verse.omnichainIds[0] = uint32(block.chainid + 1);
        launcher.setMemeverseForTest(verseId, verse);
    }

    function _launchSettlementLimit(bool zeroForOne) internal pure returns (uint160) {
        return zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;
    }

    function _deployTokenSortedRelativeTo(address referenceToken, bool sortBefore) internal returns (MockERC20 token) {
        for (uint256 i = 0; i < 32; ++i) {
            token = new MockERC20("UPT-LATE", "UPTL", 18);
            if ((address(token) < referenceToken) == sortBefore) {
                return token;
            }
        }
        revert("failed to deploy ordered token");
    }

    /// @notice Approves the launcher to pull mint inputs for a user.
    /// @dev Centralizes the approval pattern used by mintPOLToken scenarios.
    function _approveMintInputs(address user) internal {
        vm.startPrank(user);
        upt.approve(address(launcher), type(uint256).max);
        memecoin.approve(address(launcher), type(uint256).max);
        vm.stopPrank();
    }

    /// @notice Verifies preview fee mapping preserves token ordering for both pools.
    /// @dev Ensures the fee preview rearranges router outputs into semantic memecoin/UPT names.
    /// @dev Ensures the launcher maps router fee0/fee1 outputs back to semantic token names.
    function testPreviewGenesisMakerFees_MapsFeesCorrectly() external {
        uint256 verseId = 1;
        _setLockedVerse(verseId);

        router.setQuote(address(memecoin), address(upt), address(launcher), 11 ether, 22 ether);
        router.setQuote(address(liquidProof), address(upt), address(launcher), 33 ether, 44 ether);

        (uint256 uptFee, uint256 memecoinFee) = launcher.previewGenesisMakerFees(verseId);

        assertEq(memecoinFee, 22 ether, "memecoin fee");
        assertEq(uptFee, 44 ether, "upt fee");
    }

    /// @notice Verifies previewing fees reverts before the locked stage.
    /// @dev Guards the launcher from previewing fees until after the locked-stage entry.
    /// @dev The launcher must not preview LP fees during genesis.
    function testPreviewGenesisMakerFees_RevertsWhenNotLocked() external {
        uint256 verseId = 1;
        IMemeverseLauncher.Memeverse memory verse;
        verse.UPT = address(upt);
        verse.memecoin = address(memecoin);
        verse.pol = address(liquidProof);
        verse.currentStage = IMemeverseLauncher.Stage.Genesis;
        launcher.setMemeverseForTest(verseId, verse);

        vm.expectRevert(IMemeverseLauncher.NotReachedLockedStage.selector);
        launcher.previewGenesisMakerFees(verseId);
    }

    /// @notice Test claimable poltoken returns zero when already claimed.
    /// @dev Confirms the claimable view respects the `isClaimed` flag and returns zero.
    function testClaimablePOLToken_ReturnsZeroWhenAlreadyClaimed() external {
        uint256 verseId = 1;
        _setLockedVerse(verseId);
        launcher.setGenesisFundForTest(verseId, 90 ether, 30 ether);
        launcher.setUserGenesisDataForTest(verseId, ALICE, 24 ether, false, true, false);
        launcher.setTotalClaimablePOLForTest(verseId, 60 ether);

        vm.prank(ALICE);
        uint256 amount = launcher.claimablePOLToken(verseId);

        assertEq(amount, 0);
    }

    /// @notice Test quote distribution lz fee returns zero for local governance chain.
    /// @dev Verifies same-chain verses do not quote any LayerZero fee.
    function testQuoteDistributionLzFee_ReturnsZeroForLocalGovernanceChain() external {
        uint256 verseId = 1;
        _setLockedVerse(verseId);

        uint256 fee = launcher.quoteDistributionLzFee(verseId);

        assertEq(fee, 0);
    }

    /// @notice Test quote distribution lz fee quotes remote gov and memecoin fees.
    /// @dev Ensures remote verses aggregate the quote fees plus LayerZero bridging costs.
    function testQuoteDistributionLzFee_QuotesRemoteGovAndMemecoinFees() external {
        uint256 verseId = 1;
        MockOFTToken remoteUpt = new MockOFTToken("UPT", "UPT");
        MockOFTToken remoteMemecoin = new MockOFTToken("MEME", "MEME");
        IMemeverseLauncher.Memeverse memory verse;
        verse.UPT = address(remoteUpt);
        verse.memecoin = address(remoteMemecoin);
        verse.pol = address(liquidProof);
        verse.governor = address(0xCAFE);
        verse.yieldVault = address(0xD00D);
        verse.currentStage = IMemeverseLauncher.Stage.Locked;
        verse.omnichainIds = new uint32[](1);
        verse.omnichainIds[0] = 202;
        launcher.setMemeverseForTest(verseId, verse);
        registry.setEndpoint(202, 302);

        router.setPreviewQuote(address(remoteMemecoin), address(remoteUpt), address(launcher), 9 ether, 4 ether);
        router.setPreviewQuote(address(liquidProof), address(remoteUpt), address(launcher), 0, 6 ether);
        remoteUpt.setQuoteFee(0.15 ether);
        remoteMemecoin.setQuoteFee(0.25 ether);

        uint256 fee = launcher.quoteDistributionLzFee(verseId);

        assertEq(fee, 0.4 ether);
    }

    /// @notice Test quote distribution lz fee quotes only gov fee when memecoin fee is zero.
    /// @dev Confirms remote LZ quoting still works when the memecoin fee is zero.
    function testQuoteDistributionLzFee_QuotesOnlyGovFeeWhenMemecoinFeeIsZero() external {
        uint256 verseId = 18;
        MockOFTToken remoteUpt = new MockOFTToken("UPT", "UPT");
        MockOFTToken remoteMemecoin = new MockOFTToken("MEME", "MEME");
        IMemeverseLauncher.Memeverse memory verse;
        verse.UPT = address(remoteUpt);
        verse.memecoin = address(remoteMemecoin);
        verse.pol = address(liquidProof);
        verse.governor = address(0xCAFE);
        verse.yieldVault = address(0xD00D);
        verse.currentStage = IMemeverseLauncher.Stage.Locked;
        verse.omnichainIds = new uint32[](1);
        verse.omnichainIds[0] = 202;
        launcher.setMemeverseForTest(verseId, verse);
        registry.setEndpoint(202, 302);

        router.setPreviewQuote(address(remoteMemecoin), address(remoteUpt), address(launcher), 9 ether, 0);
        router.setPreviewQuote(address(liquidProof), address(remoteUpt), address(launcher), 0, 0);
        remoteUpt.setQuoteFee(0.15 ether);

        uint256 fee = launcher.quoteDistributionLzFee(verseId);

        assertEq(fee, 0.15 ether);
    }

    /// @notice Test quote distribution lz fee quotes only memecoin fee when gov fee is zero.
    /// @dev Covers the remote path where the governance fee is absent but the memecoin fee remains.
    function testQuoteDistributionLzFee_QuotesOnlyMemecoinFeeWhenGovFeeIsZero() external {
        uint256 verseId = 19;
        MockOFTToken remoteUpt = new MockOFTToken("UPT", "UPT");
        MockOFTToken remoteMemecoin = new MockOFTToken("MEME", "MEME");
        IMemeverseLauncher.Memeverse memory verse;
        verse.UPT = address(remoteUpt);
        verse.memecoin = address(remoteMemecoin);
        verse.pol = address(liquidProof);
        verse.governor = address(0xCAFE);
        verse.yieldVault = address(0xD00D);
        verse.currentStage = IMemeverseLauncher.Stage.Locked;
        verse.omnichainIds = new uint32[](1);
        verse.omnichainIds[0] = 202;
        launcher.setMemeverseForTest(verseId, verse);
        registry.setEndpoint(202, 302);

        router.setPreviewQuote(address(remoteMemecoin), address(remoteUpt), address(launcher), 0, 5 ether);
        router.setPreviewQuote(address(liquidProof), address(remoteUpt), address(launcher), 0, 0);
        remoteMemecoin.setQuoteFee(0.25 ether);

        uint256 fee = launcher.quoteDistributionLzFee(verseId);

        assertEq(fee, 0.25 ether);
    }

    /// @notice Verifies fee redemption reverts before the locked stage.
    /// @dev Guarantees redeemAndDistributeFees cannot run until the locked stage is reached.
    /// @dev The launcher must not claim or distribute fees during genesis.
    function testRedeemAndDistributeFees_RevertsWhenNotLocked() external {
        uint256 verseId = 1;
        _setGenesisVerse(verseId, false, uint128(block.timestamp + 1 days));

        vm.expectRevert(IMemeverseLauncher.NotReachedLockedStage.selector);
        launcher.redeemAndDistributeFees(verseId, REWARD_RECEIVER);
    }

    /// @notice Verifies expired Genesis moves to Refund when minimum funding was never met.
    /// @dev Captures the stage-transition behavior that reroutes undersubscribed Genesis to Refund.
    function testChangeStage_WhenGenesisEndedWithoutMinimumFund_MovesToRefund() external {
        uint256 verseId = 7;
        uint128 endTime = uint128(block.timestamp + 1);
        _setGenesisVerse(verseId, false, endTime);
        launcher.setFundMetaData(address(upt), 100 ether, 4);
        launcher.setGenesisFundForTest(verseId, 30 ether, 10 ether);
        vm.warp(endTime + 1);

        IMemeverseLauncher.Stage stage = launcher.changeStage(verseId);

        assertEq(uint256(stage), uint256(IMemeverseLauncher.Stage.Refund), "returned stage");
        assertEq(uint256(launcher.getStageByVerseId(verseId)), uint256(IMemeverseLauncher.Stage.Refund), "stored stage");
    }

    /// @notice Verifies flashGenesis can lock early once the minimum funding target is met.
    /// @dev Confirms the flash Genesis branch bypasses endTime when the funding target is satisfied.
    function testChangeStage_WhenFlashGenesisAndMinimumFundMet_MovesToLocked() external {
        uint256 verseId = 8;
        _setGenesisVerse(verseId, true, uint128(block.timestamp + 1 days));
        launcher.setFundMetaData(address(upt), 100 ether, 4);
        launcher.setGenesisFundForTest(verseId, 90 ether, 30 ether);
        router.setAddLiquidityResult(address(memecoin), address(upt), 90 ether, 0, 0);
        router.setAddLiquidityResult(address(liquidProof), address(upt), 30 ether, 0, 0);

        IMemeverseLauncher.Stage stage = launcher.changeStage(verseId);

        assertEq(uint256(stage), uint256(IMemeverseLauncher.Stage.Locked), "returned stage");
        assertEq(uint256(launcher.getStageByVerseId(verseId)), uint256(IMemeverseLauncher.Stage.Locked), "stored stage");
    }

    /// @notice Verifies successful Genesis settlement executes the launch preorder swap and unlocks preorder memecoin linearly.
    /// @dev Covers the new launcher-managed preorder settlement path and linear unlock math.
    function testChangeStage_WhenGenesisSucceedsWithPreorder_SettlesAndUnlocksLinearly() external {
        uint256 verseId = 22;
        _setGenesisVerse(verseId, true, uint128(block.timestamp + 1 days));
        launcher.setFundMetaData(address(upt), 100 ether, 4);
        launcher.setGenesisFundForTest(verseId, 90 ether, 30 ether);
        router.setAddLiquidityResult(address(memecoin), address(upt), 90 ether, 0, 0);
        router.setAddLiquidityResult(address(liquidProof), address(upt), 30 ether, 0, 0);
        router.setLaunchSwapResult(address(upt), address(memecoin), 10 ether, 60 ether);

        upt.mint(address(this), 10 ether);
        upt.approve(address(launcher), type(uint256).max);
        launcher.preorder(verseId, 10 ether, ALICE);

        IMemeverseLauncher.Stage stage = launcher.changeStage(verseId);

        assertEq(uint256(stage), uint256(IMemeverseLauncher.Stage.Locked), "returned stage");

        vm.prank(ALICE);
        assertEq(launcher.claimablePreorderMemecoin(verseId), 0, "initial claimable");

        vm.warp(block.timestamp + 3 days + 12 hours);
        vm.prank(ALICE);
        assertEq(launcher.claimablePreorderMemecoin(verseId), 30 ether, "half unlocked");

        vm.warp(block.timestamp + 3 days + 12 hours + 1);
        vm.prank(ALICE);
        uint256 claimedAmount = launcher.claimUnlockedPreorderMemecoin(verseId);
        assertEq(claimedAmount, 60 ether, "claimed amount");
        assertEq(memecoin.balanceOf(ALICE), 60 ether, "alice memecoin");
    }

    function testChangeStage_WhenPreorderSettlementZeroForOne_UsesMinSqrtPriceBoundary() external {
        uint256 verseId = 23;
        _setGenesisVerse(verseId, true, uint128(block.timestamp + 1 days));
        launcher.setFundMetaData(address(upt), 100 ether, 4);
        launcher.setGenesisFundForTest(verseId, 90 ether, 30 ether);
        router.setAddLiquidityResult(address(memecoin), address(upt), 90 ether, 0, 0);
        router.setAddLiquidityResult(address(liquidProof), address(upt), 30 ether, 0, 0);
        router.setLaunchSwapResult(address(upt), address(memecoin), 10 ether, 60 ether);

        bool zeroForOne = address(upt) < address(memecoin);
        assertTrue(zeroForOne, "fixture requires UPT as currency0");

        MockLaunchSettlementHookForLauncherTest settlementHook =
            MockLaunchSettlementHookForLauncherTest(address(router.hook()));
        uint160 expectedLimit = _launchSettlementLimit(true);
        settlementHook.setExpectedLaunchSqrtPriceLimit(true, expectedLimit);

        upt.mint(address(this), 10 ether);
        upt.approve(address(launcher), type(uint256).max);
        launcher.preorder(verseId, 10 ether, ALICE);

        IMemeverseLauncher.Stage stage = launcher.changeStage(verseId);

        assertEq(uint256(stage), uint256(IMemeverseLauncher.Stage.Locked), "returned stage");
        assertTrue(settlementHook.lastSettlementZeroForOne(), "zeroForOne");
        assertEq(settlementHook.lastSettlementSqrtPriceLimitX96(), expectedLimit, "sqrt price limit");
        assertEq(settlementHook.settlementCallCount(), 1, "settlement calls");
    }

    function testChangeStage_WhenPreorderSettlementOneForZero_UsesMaxSqrtPriceBoundary() external {
        uint256 verseId = 24;
        MockERC20 laterUpt = _deployTokenSortedRelativeTo(address(memecoin), false);
        _setGenesisVerseWithAssets(
            verseId, address(laterUpt), address(memecoin), address(liquidProof), true, uint128(block.timestamp + 1 days)
        );
        launcher.setFundMetaData(address(laterUpt), 100 ether, 4);
        launcher.setGenesisFundForTest(verseId, 90 ether, 30 ether);
        router.setAddLiquidityResult(address(memecoin), address(laterUpt), 90 ether, 0, 0);
        router.setAddLiquidityResult(address(liquidProof), address(laterUpt), 30 ether, 0, 0);
        router.setLaunchSwapResult(address(laterUpt), address(memecoin), 10 ether, 60 ether);

        bool zeroForOne = address(laterUpt) < address(memecoin);
        assertFalse(zeroForOne, "fixture requires UPT as currency1");

        MockLaunchSettlementHookForLauncherTest settlementHook =
            MockLaunchSettlementHookForLauncherTest(address(router.hook()));
        uint160 expectedLimit = _launchSettlementLimit(false);
        settlementHook.setExpectedLaunchSqrtPriceLimit(false, expectedLimit);

        laterUpt.mint(address(this), 10 ether);
        laterUpt.approve(address(launcher), type(uint256).max);
        launcher.preorder(verseId, 10 ether, ALICE);

        IMemeverseLauncher.Stage stage = launcher.changeStage(verseId);

        assertEq(uint256(stage), uint256(IMemeverseLauncher.Stage.Locked), "returned stage");
        assertFalse(settlementHook.lastSettlementZeroForOne(), "zeroForOne");
        assertEq(settlementHook.lastSettlementSqrtPriceLimitX96(), expectedLimit, "sqrt price limit");
        assertEq(settlementHook.settlementCallCount(), 1, "settlement calls");
    }

    function testChangeStage_WhenLaunchSettlementReverts_RevertsAtomically() external {
        uint256 verseId = 25;
        _setGenesisVerse(verseId, true, uint128(block.timestamp + 1 days));
        launcher.setFundMetaData(address(upt), 100 ether, 4);
        launcher.setGenesisFundForTest(verseId, 90 ether, 30 ether);
        router.setAddLiquidityResult(address(memecoin), address(upt), 90 ether, 0, 0);
        router.setAddLiquidityResult(address(liquidProof), address(upt), 30 ether, 0, 0);

        MockLaunchSettlementHookForLauncherTest settlementHook =
            MockLaunchSettlementHookForLauncherTest(address(router.hook()));
        settlementHook.setLaunchSettlementRevert("mock launch settlement revert");

        upt.mint(address(this), 10 ether);
        upt.approve(address(launcher), type(uint256).max);
        launcher.preorder(verseId, 10 ether, ALICE);

        (uint256 totalFundsBefore, uint256 settledMemecoinBefore, uint40 settlementTimestampBefore) =
            launcher.getPreorderStateForTest(verseId);
        assertEq(totalFundsBefore, 10 ether, "preorder total funds before");
        assertEq(settledMemecoinBefore, 0, "settled memecoin before");
        assertEq(settlementTimestampBefore, 0, "settlement timestamp before");

        vm.expectRevert(bytes("mock launch settlement revert"));
        launcher.changeStage(verseId);

        assertEq(uint256(launcher.getStageByVerseId(verseId)), uint256(IMemeverseLauncher.Stage.Genesis), "stage");

        (uint256 totalFundsAfter, uint256 settledMemecoinAfter, uint40 settlementTimestampAfter) =
            launcher.getPreorderStateForTest(verseId);
        assertEq(totalFundsAfter, 10 ether, "preorder total funds after");
        assertEq(settledMemecoinAfter, 0, "settled memecoin after");
        assertEq(settlementTimestampAfter, 0, "settlement timestamp after");
    }

    /// @notice Verifies non-flash Genesis cannot lock early even if the minimum funding target is met.
    /// @dev Preserves the requirement that non-flash launches wait for endTime expiry before locking.
    function testChangeStage_WhenNotFlashGenesisBeforeEnd_Reverts() external {
        uint256 verseId = 9;
        uint128 endTime = uint128(block.timestamp + 1 days);
        _setGenesisVerse(verseId, false, endTime);
        launcher.setFundMetaData(address(upt), 100 ether, 4);
        launcher.setGenesisFundForTest(verseId, 90 ether, 30 ether);

        vm.expectRevert(abi.encodeWithSelector(IMemeverseLauncher.StillInGenesisStage.selector, uint256(endTime)));
        launcher.changeStage(verseId);
    }

    /// @notice Test change stage reverts at final stages.
    /// @dev Ensures the launcher rejects stage transitions once a verse reaches a final stage.
    function testChangeStage_RevertsAtFinalStages() external {
        uint256 verseId = 10;
        IMemeverseLauncher.Memeverse memory verse;
        verse.memecoin = address(memecoin);
        verse.currentStage = IMemeverseLauncher.Stage.Refund;
        launcher.setMemeverseForTest(verseId, verse);

        vm.expectRevert(IMemeverseLauncher.ReachedFinalStage.selector);
        launcher.changeStage(verseId);
    }

    /// @notice Test change stage locked before unlock time keeps stage locked.
    /// @dev Keeps the locked state until the unlockTime timestamp elapses.
    function testChangeStage_LockedBeforeUnlockTimeKeepsStageLocked() external {
        uint256 verseId = 14;
        _setLockedVerse(verseId);
        IMemeverseLauncher.Memeverse memory verse = launcher.getMemeverseByVerseId(verseId);
        verse.unlockTime = uint128(block.timestamp + 1 days);
        launcher.setMemeverseForTest(verseId, verse);

        IMemeverseLauncher.Stage stage = launcher.changeStage(verseId);

        assertEq(uint256(stage), uint256(IMemeverseLauncher.Stage.Locked));
        assertEq(uint256(launcher.getStageByVerseId(verseId)), uint256(IMemeverseLauncher.Stage.Locked));
    }

    /// @notice Test change stage locked after unlock time moves to unlocked.
    /// @dev Releases the lock once unlockTime has passed.
    function testChangeStage_LockedAfterUnlockTimeMovesToUnlocked() external {
        uint256 verseId = 20;
        _setLockedVerse(verseId);
        IMemeverseLauncher.Memeverse memory verse = launcher.getMemeverseByVerseId(verseId);
        verse.unlockTime = uint128(block.timestamp - 1);
        launcher.setMemeverseForTest(verseId, verse);

        IMemeverseLauncher.Stage stage = launcher.changeStage(verseId);

        assertEq(uint256(stage), uint256(IMemeverseLauncher.Stage.Unlocked));
        assertEq(uint256(launcher.getStageByVerseId(verseId)), uint256(IMemeverseLauncher.Stage.Unlocked));
    }

    /// @notice Verifies entering `Unlocked` snapshots pool resume times onto the hook with the fixed 24 hour window.
    /// @dev The protection window is now a constant product rule rather than a mutable config surface.
    function testChangeStage_LockedAfterUnlockSnapshotsHookResumeTimes() external {
        uint256 verseId = 24;
        _setLockedVerse(verseId);
        IMemeverseLauncher.Memeverse memory verse = launcher.getMemeverseByVerseId(verseId);
        verse.unlockTime = uint128(block.timestamp - 1);
        launcher.setMemeverseForTest(verseId, verse);

        PoolKey memory memecoinKey = router.getHookPoolKey(address(memecoin), address(upt));
        PoolKey memory polKey = router.getHookPoolKey(address(liquidProof), address(upt));

        // Unlocking should snapshot the same fixed protection window onto both launcher-managed pools.
        launcher.changeStage(verseId);

        (bool memecoinResumeOk, uint40 memecoinResumeTime) = _readPublicSwapResumeTime(memecoinKey);
        (bool polResumeOk, uint40 polResumeTime) = _readPublicSwapResumeTime(polKey);
        assertTrue(memecoinResumeOk, "memecoin resume getter missing");
        assertTrue(polResumeOk, "pol resume getter missing");
        assertEq(memecoinResumeTime, uint40(block.timestamp + 24 hours), "memecoin resume time");
        assertEq(polResumeTime, uint40(block.timestamp + 24 hours), "pol resume time");
    }

    /// @notice Verifies unlock protection no longer depends on the router's pool-key helper after router rebinding.
    /// @dev Rebinding to a router that shares the same hook but has a broken helper must still protect the live pool.
    function testChangeStage_LockedAfterUnlockDoesNotDependOnRouterPoolKeyHelper() external {
        uint256 verseId = 27;
        _setLockedVerse(verseId);
        IMemeverseLauncher.Memeverse memory verse = launcher.getMemeverseByVerseId(verseId);
        verse.unlockTime = uint128(block.timestamp - 1);
        launcher.setMemeverseForTest(verseId, verse);

        PoolKey memory memecoinKey = router.getHookPoolKey(address(memecoin), address(upt));
        address sharedHook = address(router.hook());
        launcher.setMemeverseSwapRouter(address(new MockSwapRouterWithBrokenPoolKey(sharedHook)));

        launcher.changeStage(verseId);

        (bool memecoinResumeOk, uint40 memecoinResumeTime) = _readPublicSwapResumeTime(memecoinKey);
        assertTrue(memecoinResumeOk, "memecoin resume getter missing");
        assertEq(memecoinResumeTime, uint40(block.timestamp + 24 hours), "memecoin resume time");
    }

    /// @notice Test refund reverts when stage or user state invalid.
    /// @dev Guards refund access when the verse stage or user flags forbid it.
    function testRefund_RevertsWhenStageOrUserStateInvalid() external {
        uint256 verseId = 11;
        _setLockedVerse(verseId);

        vm.expectRevert(IMemeverseLauncher.NotRefundStage.selector);
        launcher.refund(verseId);

        IMemeverseLauncher.Memeverse memory verse = launcher.getMemeverseByVerseId(verseId);
        verse.currentStage = IMemeverseLauncher.Stage.Refund;
        launcher.setMemeverseForTest(verseId, verse);

        vm.prank(ALICE);
        vm.expectRevert(IMemeverseLauncher.InvalidRefund.selector);
        launcher.refund(verseId);
    }

    /// @notice Test refund preorder reverts when stage or user state invalid.
    /// @dev Ensures preorder refunds only run during the refund stage with valid user state.
    function testRefundPreorder_RevertsWhenStageOrUserStateInvalid() external {
        uint256 verseId = 21;
        _setLockedVerse(verseId);

        vm.expectRevert(IMemeverseLauncher.NotRefundStage.selector);
        launcher.refundPreorder(verseId);

        IMemeverseLauncher.Memeverse memory verse = launcher.getMemeverseByVerseId(verseId);
        verse.currentStage = IMemeverseLauncher.Stage.Refund;
        launcher.setMemeverseForTest(verseId, verse);

        vm.prank(ALICE);
        vm.expectRevert();
        launcher.refundPreorder(verseId);
    }

    /// @notice Verifies refund preorder returns funds and marks the user as refunded.
    /// @dev Covers the successful preorder refund path, asserting balances and flags.
    function testRefundPreorder_TransfersFundsAndMarksRefunded() external {
        uint256 verseId = 23;
        _setLockedVerse(verseId);
        IMemeverseLauncher.Memeverse memory verse = launcher.getMemeverseByVerseId(verseId);
        verse.currentStage = IMemeverseLauncher.Stage.Refund;
        launcher.setMemeverseForTest(verseId, verse);
        launcher.setUserPreorderDataForTest(verseId, ALICE, 5 ether, 0, false);
        upt.mint(address(launcher), 5 ether);

        vm.prank(ALICE);
        uint256 refunded = launcher.refundPreorder(verseId);

        (uint256 funds, uint256 claimedMemecoin, bool isRefunded) = launcher.userPreorderData(verseId, ALICE);
        assertEq(refunded, 5 ether, "refunded");
        assertEq(funds, 5 ether, "funds");
        assertEq(claimedMemecoin, 0, "claimed");
        assertTrue(isRefunded, "isRefunded");
        assertEq(upt.balanceOf(ALICE), 5 ether, "alice upt");
    }

    /// @notice Verifies POL cannot be claimed twice for the same genesis contribution.
    /// @dev Guards double-claim attempts by checking `isClaimed`.
    function testClaimPOLToken_RevertsWhenAlreadyClaimed() external {
        uint256 verseId = 1;
        _setLockedVerse(verseId);
        launcher.setGenesisFundForTest(verseId, 90 ether, 30 ether);
        launcher.setUserGenesisDataForTest(verseId, ALICE, 24 ether, false, false, false);
        launcher.setTotalClaimablePOLForTest(verseId, 60 ether);
        liquidProof.mint(address(launcher), 60 ether);

        vm.prank(ALICE);
        uint256 amount = launcher.claimPOLToken(verseId);
        assertEq(amount, 12 ether, "claimed amount");

        vm.prank(ALICE);
        vm.expectRevert(IMemeverseLauncher.NoPOLAvailable.selector);
        launcher.claimPOLToken(verseId);
    }

    /// @notice Verifies fee redemption returns zero values when no fees are claimable.
    /// @dev Confirms the early-return path short-circuits without dispatching or mutating balances.
    function testRedeemAndDistributeFees_ReturnsZeroWhenNoFees() external {
        uint256 verseId = 1;
        _setLockedVerse(verseId);

        (uint256 govFee, uint256 memecoinFee, uint256 liquidProofFee, uint256 executorReward) =
            launcher.redeemAndDistributeFees(verseId, REWARD_RECEIVER);

        assertEq(govFee, 0, "govFee");
        assertEq(memecoinFee, 0, "memecoinFee");
        assertEq(liquidProofFee, 0, "liquidProofFee");
        assertEq(executorReward, 0, "executorReward");
    }

    /// @notice Test redeem and distribute fees remote path checks lz fee and sends oft.
    /// @dev Validates the remote dispatch branch requires the exact LayerZero fee and calls `send`.
    function testRedeemAndDistributeFees_RemotePathChecksLzFeeAndSendsOFT() external {
        uint256 verseId = 2;
        MockOFTToken remoteUpt = new MockOFTToken("UPT", "UPT");
        MockOFTToken remoteMemecoin = new MockOFTToken("MEME", "MEME");
        IMemeverseLauncher.Memeverse memory verse;
        verse.UPT = address(remoteUpt);
        verse.memecoin = address(remoteMemecoin);
        verse.pol = address(liquidProof);
        verse.governor = address(0xCAFE);
        verse.yieldVault = address(0xD00D);
        verse.currentStage = IMemeverseLauncher.Stage.Locked;
        verse.omnichainIds = new uint32[](1);
        verse.omnichainIds[0] = 202;
        launcher.setMemeverseForTest(verseId, verse);
        registry.setEndpoint(202, 302);

        router.setClaimQuote(address(remoteMemecoin), address(remoteUpt), address(launcher), 9 ether, 4 ether);
        router.setClaimQuote(address(liquidProof), address(remoteUpt), address(launcher), 0, 6 ether);
        remoteUpt.setQuoteFee(0.15 ether);
        remoteMemecoin.setQuoteFee(0.25 ether);

        remoteUpt.mint(address(launcher), 100 ether);
        remoteMemecoin.mint(address(launcher), 100 ether);

        vm.expectRevert(abi.encodeWithSelector(IMemeverseLauncher.InvalidLzFee.selector, 0.4 ether, 0));
        launcher.redeemAndDistributeFees(verseId, REWARD_RECEIVER);

        launcher.redeemAndDistributeFees{value: 0.4 ether}(verseId, REWARD_RECEIVER);

        assertEq(remoteUpt.sendCallCount(), 1);
        assertEq(remoteMemecoin.sendCallCount(), 1);
        assertEq(remoteUpt.lastSendDstEid(), 302);
        assertEq(remoteMemecoin.lastSendDstEid(), 302);
        assertEq(remoteUpt.lastNativeFeePaid(), 0.15 ether);
        assertEq(remoteMemecoin.lastNativeFeePaid(), 0.25 ether);
    }

    /// @notice Verifies remote fee redemption rejects overpayment instead of trapping extra ETH in the launcher.
    /// @dev Requires the caller to provide the exact quoted LayerZero fee and reject overpayments.
    function testRedeemAndDistributeFees_RemotePathRevertsWhenLzFeeIsNotExact() external {
        uint256 verseId = 24;
        MockOFTToken remoteUpt = new MockOFTToken("UPT", "UPT");
        MockOFTToken remoteMemecoin = new MockOFTToken("MEME", "MEME");
        IMemeverseLauncher.Memeverse memory verse;
        verse.UPT = address(remoteUpt);
        verse.memecoin = address(remoteMemecoin);
        verse.pol = address(liquidProof);
        verse.governor = address(0xCAFE);
        verse.yieldVault = address(0xD00D);
        verse.currentStage = IMemeverseLauncher.Stage.Locked;
        verse.omnichainIds = new uint32[](1);
        verse.omnichainIds[0] = 202;
        launcher.setMemeverseForTest(verseId, verse);
        registry.setEndpoint(202, 302);

        router.setClaimQuote(address(remoteMemecoin), address(remoteUpt), address(launcher), 9 ether, 4 ether);
        router.setClaimQuote(address(liquidProof), address(remoteUpt), address(launcher), 0, 6 ether);
        remoteUpt.setQuoteFee(0.15 ether);
        remoteMemecoin.setQuoteFee(0.25 ether);
        remoteUpt.mint(address(launcher), 100 ether);
        remoteMemecoin.mint(address(launcher), 100 ether);

        vm.expectRevert(abi.encodeWithSelector(IMemeverseLauncher.InvalidLzFee.selector, 0.4 ether, 0.41 ether));
        launcher.redeemAndDistributeFees{value: 0.41 ether}(verseId, REWARD_RECEIVER);
    }

    /// @notice Test redeem and distribute fees remote path only gov fee skips memecoin send.
    /// @dev Ensures memecoin dispatch is skipped when its quote is zero in the remote path.
    function testRedeemAndDistributeFees_RemotePathOnlyGovFeeSkipsMemecoinSend() external {
        uint256 verseId = 21;
        MockOFTToken remoteUpt = new MockOFTToken("UPT", "UPT");
        MockOFTToken remoteMemecoin = new MockOFTToken("MEME", "MEME");
        IMemeverseLauncher.Memeverse memory verse;
        verse.UPT = address(remoteUpt);
        verse.memecoin = address(remoteMemecoin);
        verse.pol = address(liquidProof);
        verse.governor = address(0xCAFE);
        verse.yieldVault = address(0xD00D);
        verse.currentStage = IMemeverseLauncher.Stage.Locked;
        verse.omnichainIds = new uint32[](1);
        verse.omnichainIds[0] = 202;
        launcher.setMemeverseForTest(verseId, verse);
        registry.setEndpoint(202, 302);

        router.setClaimQuote(address(remoteMemecoin), address(remoteUpt), address(launcher), 9 ether, 0);
        router.setClaimQuote(address(liquidProof), address(remoteUpt), address(launcher), 0, 0);
        remoteUpt.setQuoteFee(0.15 ether);
        remoteUpt.mint(address(launcher), 100 ether);

        launcher.redeemAndDistributeFees{value: 0.15 ether}(verseId, REWARD_RECEIVER);

        assertEq(remoteUpt.sendCallCount(), 1);
        assertEq(remoteMemecoin.sendCallCount(), 0);
    }

    /// @notice Test redeem and distribute fees remote path only memecoin fee skips gov send.
    /// @dev Ensures governance dispatch is skipped when its quote is zero in the remote path.
    function testRedeemAndDistributeFees_RemotePathOnlyMemecoinFeeSkipsGovSend() external {
        uint256 verseId = 22;
        MockOFTToken remoteUpt = new MockOFTToken("UPT", "UPT");
        MockOFTToken remoteMemecoin = new MockOFTToken("MEME", "MEME");
        IMemeverseLauncher.Memeverse memory verse;
        verse.UPT = address(remoteUpt);
        verse.memecoin = address(remoteMemecoin);
        verse.pol = address(liquidProof);
        verse.governor = address(0xCAFE);
        verse.yieldVault = address(0xD00D);
        verse.currentStage = IMemeverseLauncher.Stage.Locked;
        verse.omnichainIds = new uint32[](1);
        verse.omnichainIds[0] = 202;
        launcher.setMemeverseForTest(verseId, verse);
        registry.setEndpoint(202, 302);

        router.setClaimQuote(address(remoteMemecoin), address(remoteUpt), address(launcher), 0, 5 ether);
        router.setClaimQuote(address(liquidProof), address(remoteUpt), address(launcher), 0, 0);
        remoteMemecoin.setQuoteFee(0.25 ether);
        remoteMemecoin.mint(address(launcher), 100 ether);

        launcher.redeemAndDistributeFees{value: 0.25 ether}(verseId, REWARD_RECEIVER);

        assertEq(remoteUpt.sendCallCount(), 0);
        assertEq(remoteMemecoin.sendCallCount(), 1);
    }

    /// @notice Test redeem and distribute fees local path with only gov fee skips memecoin dispatch.
    /// @dev Confirms the local path keeps dispatcher fees aligned with the available memecoin/governance splits.
    function testRedeemAndDistributeFees_LocalPathWithOnlyGovFeeSkipsMemecoinDispatch() external {
        uint256 verseId = 15;
        _setLockedVerse(verseId);

        router.setClaimQuote(address(memecoin), address(upt), address(launcher), 9 ether, 0);
        router.setClaimQuote(address(liquidProof), address(upt), address(launcher), 0, 0);

        (uint256 govFee, uint256 memecoinFee,, uint256 executorReward) =
            launcher.redeemAndDistributeFees(verseId, REWARD_RECEIVER);

        assertGt(govFee, 0);
        assertEq(memecoinFee, 0);
        assertGt(executorReward, 0);
        assertEq(dispatcher.composeCallCount(), 1);
        assertEq(dispatcher.lastToken(), address(upt));
    }

    /// @notice Verifies local fee redemption rejects accidental native value.
    /// @dev Prevents stray ETH from being trapped in the launcher on same-chain paths.
    function testRedeemAndDistributeFees_LocalPathRevertsWhenMsgValueProvided() external {
        uint256 verseId = 25;
        _setLockedVerse(verseId);

        router.setClaimQuote(address(memecoin), address(upt), address(launcher), 9 ether, 0);
        router.setClaimQuote(address(liquidProof), address(upt), address(launcher), 0, 0);

        vm.expectRevert(abi.encodeWithSelector(IMemeverseLauncher.InvalidLzFee.selector, 0, 1));
        launcher.redeemAndDistributeFees{value: 1}(verseId, REWARD_RECEIVER);
    }

    /// @notice Test redeem and distribute fees local path with only memecoin fee skips gov dispatch.
    /// @dev Verifies executor rewards and gov dispatch are zero when only memecoin fees exist locally.
    function testRedeemAndDistributeFees_LocalPathWithOnlyMemecoinFeeSkipsGovDispatch() external {
        uint256 verseId = 16;
        _setLockedVerse(verseId);
        launcher.setExecutorRewardRate(0);

        router.setClaimQuote(address(memecoin), address(upt), address(launcher), 0, 5 ether);
        router.setClaimQuote(address(liquidProof), address(upt), address(launcher), 0, 0);

        (uint256 govFee, uint256 memecoinFee,, uint256 executorReward) =
            launcher.redeemAndDistributeFees(verseId, REWARD_RECEIVER);

        assertEq(govFee, 0);
        assertEq(memecoinFee, 5 ether);
        assertEq(executorReward, 0);
        assertEq(dispatcher.composeCallCount(), 1);
        assertEq(dispatcher.lastToken(), address(memecoin));
    }

    /// @notice Verifies same-chain fee redemption claims, burns, and dispatches the expected assets.
    /// @dev Covers the restored fee distribution flow through the mock dispatcher and validates all transfers.
    function testRedeemAndDistributeFees_SameChainClaimsAndDistributesFees() external {
        uint256 verseId = 1;
        _setLockedVerse(verseId);

        router.setClaimQuote(address(memecoin), address(upt), address(launcher), 20 ether, 7 ether);
        router.setClaimQuote(address(liquidProof), address(upt), address(launcher), 12 ether, 5 ether);

        (uint256 govFee, uint256 memecoinFee, uint256 liquidProofFee, uint256 executorReward) =
            launcher.redeemAndDistributeFees(verseId, REWARD_RECEIVER);

        assertEq(memecoinFee, 7 ether, "memecoin fee");
        assertEq(liquidProofFee, 5 ether, "liquid proof fee");
        assertEq(executorReward, 0.08 ether, "executor reward");
        assertEq(govFee, 31.92 ether, "gov fee");

        assertEq(upt.balanceOf(REWARD_RECEIVER), executorReward, "reward receiver UPT");
        assertEq(upt.balanceOf(address(dispatcher)), govFee, "dispatcher UPT");
        assertEq(memecoin.balanceOf(address(dispatcher)), memecoinFee, "dispatcher memecoin");
        assertEq(liquidProof.burnedAmount(), liquidProofFee, "burned liquid proof");
        assertEq(dispatcher.composeCallCount(), 2, "compose call count");
        assertEq(upt.balanceOf(address(launcher)), 0, "launcher UPT");
        assertEq(memecoin.balanceOf(address(launcher)), 0, "launcher memecoin");
        assertEq(liquidProof.balanceOf(address(launcher)), 0, "launcher liquid proof");
    }

    /// @notice Verifies preview fee mapping matches actual redemption fee mapping.
    /// @dev Prevents preview and claim flows from drifting on token ordering.
    function testPreviewAndRedeemShareTheSameFeeMapping() external {
        uint256 verseId = 1;
        _setLockedVerse(verseId);

        router.setPreviewQuote(address(memecoin), address(upt), address(launcher), 9 ether, 4 ether);
        router.setPreviewQuote(address(liquidProof), address(upt), address(launcher), 13 ether, 6 ether);
        router.setClaimQuote(address(memecoin), address(upt), address(launcher), 9 ether, 4 ether);
        router.setClaimQuote(address(liquidProof), address(upt), address(launcher), 13 ether, 6 ether);

        (uint256 previewUptFee, uint256 previewMemecoinFee) = launcher.previewGenesisMakerFees(verseId);
        (uint256 govFee, uint256 memecoinFee,, uint256 executorReward) =
            launcher.redeemAndDistributeFees(verseId, REWARD_RECEIVER);

        assertEq(previewMemecoinFee, memecoinFee, "memecoin mapping");
        assertEq(previewUptFee, govFee + executorReward, "UPT mapping");
    }

    /// @notice Verifies memecoin LP redemption rejects zero POL input.
    /// @dev Confirms the restored zero-input guard is active.
    function testRedeemMemecoinLiquidity_RevertsOnZeroInput() external {
        uint256 verseId = 1;
        _setUnlockedVerse(verseId);

        vm.expectRevert(IMemeverseLauncher.ZeroInput.selector);
        launcher.redeemMemecoinLiquidity(verseId, 0);
    }

    /// @notice Verifies memecoin LP redemption rejects non-unlocked verses.
    /// @dev Confirms the restored stage guard is active for memecoin LP claims.
    function testRedeemMemecoinLiquidity_RevertsWhenNotUnlocked() external {
        uint256 verseId = 1;
        _setLockedVerse(verseId);

        vm.expectRevert(IMemeverseLauncher.NotUnlockedStage.selector);
        launcher.redeemMemecoinLiquidity(verseId, 1 ether);
    }

    /// @notice Verifies memecoin LP redemption burns POL and transfers pair LP shares.
    /// @dev Covers the restored router-based pair LP lookup in the happy path.
    function testRedeemMemecoinLiquidity_BurnsPOLAndTransfersMemecoinLp() external {
        uint256 verseId = 1;
        _setUnlockedVerse(verseId);

        MockERC20 memecoinLp = new MockERC20("MEME-LP", "MEME-LP", 18);
        router.setLpToken(address(memecoin), address(upt), address(memecoinLp));
        memecoinLp.mint(address(launcher), 10 ether);
        liquidProof.mint(ALICE, 10 ether);

        vm.prank(ALICE);
        uint256 amountInLP = launcher.redeemMemecoinLiquidity(verseId, 4 ether);

        assertEq(amountInLP, 4 ether, "lp amount");
        assertEq(liquidProof.burnedAmount(), 4 ether, "burned pol");
        assertEq(liquidProof.balanceOf(ALICE), 6 ether, "alice pol balance");
        assertEq(memecoinLp.balanceOf(ALICE), 4 ether, "alice memecoin lp");
        assertEq(memecoinLp.balanceOf(address(launcher)), 6 ether, "launcher memecoin lp");
    }

    /// @notice Verifies memecoin LP redemption stays available during the post-unlock protection window.
    /// @dev Protection-window config should only gate public swaps, not unlocked liquidity redemption.
    function testRedeemMemecoinLiquidity_AllowsDuringPostUnlockProtectionWindow() external {
        uint256 verseId = 21;
        _setUnlockedVerse(verseId);
        IMemeverseLauncher.Memeverse memory verse = launcher.getMemeverseByVerseId(verseId);
        verse.unlockTime = uint128(block.timestamp);
        launcher.setMemeverseForTest(verseId, verse);

        MockERC20 memecoinLp = new MockERC20("MEME-LP", "MEME-LP", 18);
        router.setLpToken(address(memecoin), address(upt), address(memecoinLp));
        memecoinLp.mint(address(launcher), 10 ether);
        liquidProof.mint(ALICE, 10 ether);

        vm.prank(ALICE);
        uint256 amountInLP = launcher.redeemMemecoinLiquidity(verseId, 4 ether);

        assertEq(amountInLP, 4 ether, "lp amount");
        assertEq(memecoinLp.balanceOf(ALICE), 4 ether, "alice memecoin lp");
    }

    /// @notice Test redeem memecoin liquidity reverts when launcher lp balance insufficient.
    /// @dev Ensures the contract only transfers LP when it holds enough balance.
    function testRedeemMemecoinLiquidity_RevertsWhenLauncherLpBalanceInsufficient() external {
        uint256 verseId = 12;
        _setUnlockedVerse(verseId);

        MockERC20 memecoinLp = new MockERC20("MEME-LP", "MEME-LP", 18);
        router.setLpToken(address(memecoin), address(upt), address(memecoinLp));
        liquidProof.mint(ALICE, 10 ether);

        vm.prank(ALICE);
        vm.expectRevert(IMemeverseLauncher.InsufficientLPBalance.selector);
        launcher.redeemMemecoinLiquidity(verseId, 4 ether);
    }

    /// @notice Verifies POL LP redemption rejects non-unlocked verses.
    /// @dev Confirms the restored stage guard is active for genesis-share redemption.
    function testRedeemPolLiquidity_RevertsWhenNotUnlocked() external {
        uint256 verseId = 1;
        _setLockedVerse(verseId);
        launcher.setUserGenesisDataForTest(verseId, ALICE, 1 ether, false, false, false);

        vm.prank(ALICE);
        vm.expectRevert(IMemeverseLauncher.NotUnlockedStage.selector);
        launcher.redeemPolLiquidity(verseId);
    }

    /// @notice Verifies POL LP redemption rejects accounts that already redeemed.
    /// @dev Confirms the single-claim protection is preserved for each genesis share.
    function testRedeemPolLiquidity_RevertsWhenAlreadyRedeemed() external {
        uint256 verseId = 1;
        _setUnlockedVerse(verseId);
        launcher.setUserGenesisDataForTest(verseId, ALICE, 1 ether, false, false, true);

        vm.prank(ALICE);
        vm.expectRevert(IMemeverseLauncher.InvalidRedeem.selector);
        launcher.redeemPolLiquidity(verseId);
    }

    /// @notice Verifies POL LP redemption transfers the caller's genesis share of POL LP.
    /// @dev Covers router-based LP lookup and redeemed-flag mutation in the happy path.
    function testRedeemPolLiquidity_TransfersPolLpByGenesisShare() external {
        uint256 verseId = 1;
        _setUnlockedVerse(verseId);

        MockERC20 polLp = new MockERC20("POL-LP", "POL-LP", 18);
        router.setLpToken(address(liquidProof), address(upt), address(polLp));
        polLp.mint(address(launcher), 60 ether);
        launcher.setGenesisFundForTest(verseId, 90 ether, 30 ether);
        launcher.setUserGenesisDataForTest(verseId, ALICE, 24 ether, false, false, false);
        launcher.setTotalPolLiquidityForTest(verseId, 60 ether);

        vm.prank(ALICE);
        uint256 amountInLP = launcher.redeemPolLiquidity(verseId);

        (, bool isRefunded, bool isClaimed, bool isRedeemed) = launcher.userGenesisData(verseId, ALICE);
        assertEq(amountInLP, 12 ether, "lp amount");
        assertEq(polLp.balanceOf(ALICE), 12 ether, "alice pol lp");
        assertEq(polLp.balanceOf(address(launcher)), 48 ether, "launcher pol lp");
        assertFalse(isRefunded, "is refunded");
        assertFalse(isClaimed, "is claimed");
        assertTrue(isRedeemed, "is redeemed");
    }

    /// @notice Verifies POL LP redemption stays available during the post-unlock protection window.
    /// @dev The protection window must not re-lock genesis liquidity that is already in `Stage.Unlocked`.
    function testRedeemPolLiquidity_AllowsDuringPostUnlockProtectionWindow() external {
        uint256 verseId = 22;
        _setUnlockedVerse(verseId);
        IMemeverseLauncher.Memeverse memory verse = launcher.getMemeverseByVerseId(verseId);
        verse.unlockTime = uint128(block.timestamp);
        launcher.setMemeverseForTest(verseId, verse);

        MockERC20 polLp = new MockERC20("POL-LP", "POL-LP", 18);
        router.setLpToken(address(liquidProof), address(upt), address(polLp));
        polLp.mint(address(launcher), 60 ether);
        launcher.setGenesisFundForTest(verseId, 90 ether, 30 ether);
        launcher.setUserGenesisDataForTest(verseId, ALICE, 24 ether, false, false, false);
        launcher.setTotalPolLiquidityForTest(verseId, 60 ether);

        vm.prank(ALICE);
        uint256 amountInLP = launcher.redeemPolLiquidity(verseId);

        assertEq(amountInLP, 12 ether, "lp amount");
        assertEq(polLp.balanceOf(ALICE), 12 ether, "alice pol lp");
    }

    /// @notice Test redeem pol liquidity reverts when launcher lp balance insufficient.
    /// @dev Ensures the PoL LP redemption guard fires when the contract lacks enough LP tokens.
    function testRedeemPolLiquidity_RevertsWhenLauncherLpBalanceInsufficient() external {
        uint256 verseId = 13;
        _setUnlockedVerse(verseId);

        MockERC20 polLp = new MockERC20("POL-LP", "POL-LP", 18);
        router.setLpToken(address(liquidProof), address(upt), address(polLp));
        launcher.setGenesisFundForTest(verseId, 90 ether, 30 ether);
        launcher.setUserGenesisDataForTest(verseId, ALICE, 24 ether, false, false, false);
        launcher.setTotalPolLiquidityForTest(verseId, 60 ether);

        vm.prank(ALICE);
        vm.expectRevert(IMemeverseLauncher.InsufficientLPBalance.selector);
        launcher.redeemPolLiquidity(verseId);
    }

    /// @notice Verifies mintPOLToken rejects zero input budgets.
    /// @dev Confirms zero-input guard prevents meaningless mint transactions.
    /// @dev Confirms the restored zero-input guard is active.
    function testMintPOLToken_RevertsOnZeroInput() external {
        uint256 verseId = 1;
        _setLockedVerse(verseId);

        vm.expectRevert(IMemeverseLauncher.ZeroInput.selector);
        launcher.mintPOLToken(verseId, 0, 1 ether, 0, 0, 0, block.timestamp);
    }

    /// @notice Verifies mintPOLToken rejects verses before the locked stage.
    /// @dev Confirms the stage guard blocks minting during Genesis or Refund.
    /// @dev Confirms the restored stage guard is active.
    function testMintPOLToken_RevertsWhenBeforeLocked() external {
        uint256 verseId = 1;
        IMemeverseLauncher.Memeverse memory verse;
        verse.currentStage = IMemeverseLauncher.Stage.Genesis;
        verse.UPT = address(upt);
        verse.memecoin = address(memecoin);
        launcher.setMemeverseForTest(verseId, verse);

        vm.expectRevert(IMemeverseLauncher.NotReachedLockedStage.selector);
        launcher.mintPOLToken(verseId, 1 ether, 1 ether, 0, 0, 0, block.timestamp);
    }

    /// @notice Verifies lifecycle entrypoints reject non-existent non-zero verse ids.
    /// @dev Prevents default-slot stage errors from leaking through state-changing APIs.
    function testLifecycleEntryPoints_RevertWhenVerseIdNotRegistered() external {
        uint256 invalidVerseId = 999;

        vm.expectRevert(IMemeverseLauncher.InvalidVerseId.selector);
        launcher.refund(invalidVerseId);

        vm.expectRevert(IMemeverseLauncher.InvalidVerseId.selector);
        launcher.refundPreorder(invalidVerseId);

        vm.expectRevert(IMemeverseLauncher.InvalidVerseId.selector);
        launcher.claimPOLToken(invalidVerseId);

        vm.expectRevert(IMemeverseLauncher.InvalidVerseId.selector);
        launcher.claimUnlockedPreorderMemecoin(invalidVerseId);

        vm.expectRevert(IMemeverseLauncher.InvalidVerseId.selector);
        launcher.redeemAndDistributeFees(invalidVerseId, REWARD_RECEIVER);

        vm.expectRevert(IMemeverseLauncher.InvalidVerseId.selector);
        launcher.redeemMemecoinLiquidity(invalidVerseId, 1 ether);

        vm.expectRevert(IMemeverseLauncher.InvalidVerseId.selector);
        launcher.redeemPolLiquidity(invalidVerseId);

        vm.expectRevert(IMemeverseLauncher.InvalidVerseId.selector);
        launcher.mintPOLToken(invalidVerseId, 1 ether, 1 ether, 0, 0, 0, block.timestamp);
    }

    /// @notice Verifies automatic liquidity minting refunds unused inputs and mints matching POL.
    /// @dev Covers the `amountOutDesired == 0` router path to ensure refunds happen before LP minting.
    function testMintPOLToken_WithAutoLiquidity_RefundsUnusedInputsAndMintsPol() external {
        uint256 verseId = 1;
        _setLockedVerse(verseId);

        MockERC20 memecoinLp = new MockERC20("MEME-LP", "MEME-LP", 18);
        router.setLpToken(address(memecoin), address(upt), address(memecoinLp));
        router.setAddLiquidityResult(address(upt), address(memecoin), 8 ether, 6 ether, 10 ether);

        upt.mint(ALICE, 9 ether);
        memecoin.mint(ALICE, 13 ether);
        _approveMintInputs(ALICE);

        vm.prank(ALICE);
        (uint256 amountInUPT, uint256 amountInMemecoin, uint256 amountOut) =
            launcher.mintPOLToken(verseId, 9 ether, 13 ether, 5 ether, 8 ether, 0, block.timestamp);

        assertEq(amountInUPT, 6 ether, "upt used");
        assertEq(amountInMemecoin, 10 ether, "memecoin used");
        assertEq(amountOut, 8 ether, "pol out");
        assertEq(upt.balanceOf(ALICE), 3 ether, "upt refund");
        assertEq(memecoin.balanceOf(ALICE), 3 ether, "memecoin refund");
        assertEq(liquidProof.balanceOf(ALICE), 8 ether, "alice pol");
        assertEq(memecoinLp.balanceOf(address(launcher)), 8 ether, "launcher lp");
    }

    /// @notice Verifies POL is minted before refund callbacks during auto-liquidity minting.
    /// @dev Uses a callback token to assert CEI ordering at refund time.
    function testMintPOLToken_WithAutoLiquidity_MintsPolBeforeRefundCallback() external {
        uint256 verseId = 1;
        RefundCallbackToken callbackMemecoin = new RefundCallbackToken("MEME", "MEME");
        memecoin = callbackMemecoin;
        _setLockedVerse(verseId);

        MockERC20 memecoinLp = new MockERC20("MEME-LP", "MEME-LP", 18);
        router.setLpToken(address(memecoin), address(upt), address(memecoinLp));
        router.setAddLiquidityResult(address(upt), address(memecoin), 8 ether, 6 ether, 10 ether);

        MintPolRefundObserver observer = new MintPolRefundObserver(
            launcher, IERC20(address(upt)), IERC20(address(memecoin)), IERC20(address(liquidProof)), verseId
        );
        callbackMemecoin.setCallbackTarget(address(observer));

        upt.mint(address(observer), 9 ether);
        memecoin.mint(address(observer), 13 ether);
        observer.approveLauncher();

        (uint256 amountInUPT, uint256 amountInMemecoin, uint256 amountOut) =
            observer.executeMintPOLToken(9 ether, 13 ether, 5 ether, 8 ether, 0, block.timestamp);

        assertEq(amountInUPT, 6 ether, "upt used");
        assertEq(amountInMemecoin, 10 ether, "memecoin used");
        assertEq(amountOut, 8 ether, "pol out");
        assertTrue(observer.sawPolDuringRefund(), "refund callback should observe minted POL");
        assertEq(liquidProof.balanceOf(address(observer)), 8 ether, "observer pol");
    }

    /// @notice Verifies exact-liquidity minting uses the detailed add-liquidity path and mints the requested POL.
    /// @dev Covers the `amountOutDesired != 0` launcher path without relying on padded quote amounts as a hard gate.
    function testMintPOLToken_WithExactLiquidity_UsesDetailedAddLiquidityAndMintsRequestedPol() external {
        uint256 verseId = 1;
        _setLockedVerse(verseId);

        MockERC20 memecoinLp = new MockERC20("MEME-LP", "MEME-LP", 18);
        router.setLpToken(address(memecoin), address(upt), address(memecoinLp));
        router.setExactQuoteAmountsForLiquidity(address(upt), address(memecoin), 5 ether, 10 ether, 12 ether);
        router.setAddLiquidityResult(address(upt), address(memecoin), 5 ether, 7 ether, 9 ether);

        upt.mint(ALICE, 10 ether);
        memecoin.mint(ALICE, 12 ether);
        _approveMintInputs(ALICE);

        vm.prank(ALICE);
        (uint256 amountInUPT, uint256 amountInMemecoin, uint256 amountOut) =
            launcher.mintPOLToken(verseId, 10 ether, 12 ether, 0, 0, 5 ether, block.timestamp);

        assertEq(amountInUPT, 7 ether, "upt used");
        assertEq(amountInMemecoin, 9 ether, "memecoin used");
        assertEq(amountOut, 5 ether, "pol out");
        assertEq(upt.balanceOf(ALICE), 3 ether, "upt refund");
        assertEq(memecoin.balanceOf(ALICE), 3 ether, "memecoin refund");
        assertEq(liquidProof.balanceOf(ALICE), 5 ether, "alice pol");
        assertEq(memecoinLp.balanceOf(address(launcher)), 5 ether, "launcher lp");
        assertEq(router.addLiquidityDetailedCallCount(), 1, "detailed addLiquidity used");
    }

    /// @notice Verifies exact-liquidity minting fails closed when budgets cannot mint the requested POL amount.
    /// @dev Confirms the launcher no longer treats a padded quote as a hard budget gate and instead checks actual output.
    function testMintPOLToken_WithExactLiquidity_RevertsWhenDetailedLiquidityUnderMints() external {
        uint256 verseId = 1;
        _setLockedVerse(verseId);

        router.setExactQuoteAmountsForLiquidity(address(upt), address(memecoin), 5 ether, 10 ether, 12 ether);
        upt.mint(ALICE, 10 ether);
        memecoin.mint(ALICE, 12 ether);
        _approveMintInputs(ALICE);
        router.setAddLiquidityResult(address(upt), address(memecoin), 4 ether, 7 ether, 9 ether);

        vm.prank(ALICE);
        vm.expectRevert(IMemeverseUniswapHook.TooMuchSlippage.selector);
        launcher.mintPOLToken(verseId, 10 ether, 12 ether, 0, 0, 5 ether, block.timestamp);
    }

    /// @notice Test mint poltoken with exact liquidity no refund path.
    /// @dev Ensures no refund is issued when exact liquidity formulas match the requested output.
    function testMintPOLToken_WithExactLiquidity_NoRefundPath() external {
        uint256 verseId = 17;
        _setLockedVerse(verseId);

        MockERC20 memecoinLp = new MockERC20("MEME-LP", "MEME-LP", 18);
        router.setLpToken(address(memecoin), address(upt), address(memecoinLp));
        router.setExactQuoteAmountsForLiquidity(address(upt), address(memecoin), 5 ether, 10 ether, 12 ether);
        router.setAddLiquidityResult(address(upt), address(memecoin), 5 ether, 10 ether, 12 ether);

        upt.mint(ALICE, 10 ether);
        memecoin.mint(ALICE, 12 ether);
        _approveMintInputs(ALICE);

        vm.prank(ALICE);
        (uint256 amountInUPT, uint256 amountInMemecoin, uint256 amountOut) =
            launcher.mintPOLToken(verseId, 10 ether, 12 ether, 0, 0, 5 ether, block.timestamp);

        assertEq(amountInUPT, 10 ether);
        assertEq(amountInMemecoin, 12 ether);
        assertEq(amountOut, 5 ether);
        assertEq(upt.balanceOf(ALICE), 0);
        assertEq(memecoin.balanceOf(ALICE), 0);
    }

    /// @notice Verifies exact-liquidity minting uses the exact quote path even when the padded quote exceeds budget.
    /// @dev Proves `quoteAmountsForLiquidity(...)` no longer blocks exact-liquidity mints when `quoteExact...` fits.
    function testMintPOLToken_WithExactLiquidity_IgnoresPaddedQuoteBudgetOverrun() external {
        uint256 verseId = 19;
        _setLockedVerse(verseId);

        MockERC20 memecoinLp = new MockERC20("MEME-LP", "MEME-LP", 18);
        router.setLpToken(address(memecoin), address(upt), address(memecoinLp));
        router.setQuoteAmountsForLiquidity(address(upt), address(memecoin), 5 ether, 11 ether, 13 ether);
        router.setExactQuoteAmountsForLiquidity(address(upt), address(memecoin), 5 ether, 10 ether, 12 ether);
        router.setAddLiquidityResult(address(upt), address(memecoin), 5 ether, 10 ether, 12 ether);

        upt.mint(ALICE, 10 ether);
        memecoin.mint(ALICE, 12 ether);
        _approveMintInputs(ALICE);

        vm.prank(ALICE);
        (uint256 amountInUPT, uint256 amountInMemecoin, uint256 amountOut) =
            launcher.mintPOLToken(verseId, 10 ether, 12 ether, 0, 0, 5 ether, block.timestamp);

        assertEq(amountInUPT, 10 ether, "exact UPT used");
        assertEq(amountInMemecoin, 12 ether, "exact memecoin used");
        assertEq(amountOut, 5 ether, "requested liquidity minted");
        assertEq(liquidProof.balanceOf(ALICE), 5 ether, "alice pol");
        assertEq(memecoinLp.balanceOf(address(launcher)), 5 ether, "launcher lp");
        assertEq(router.addLiquidityDetailedCallCount(), 1, "detailed addLiquidity used");
    }

    /// @notice Verifies only the owner can sweep native dust from the launcher.
    /// @dev Exposes the regression where any caller could drain the contract's native balance.
    function testRemoveGasDust_RevertsWhenCallerIsNotOwner() external {
        vm.deal(address(launcher), 1 ether);

        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, ALICE));
        launcher.removeGasDust(ALICE);
    }
}
