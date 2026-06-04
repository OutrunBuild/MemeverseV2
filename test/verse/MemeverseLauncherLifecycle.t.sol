// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
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
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta, toBalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";

import {MemeverseLauncher} from "../../src/verse/MemeverseLauncher.sol";
import {MemeverseLauncherTestBase} from "./helpers/MemeverseLauncherTestBase.sol";
import {IMemeverseLauncher} from "../../src/verse/interfaces/IMemeverseLauncher.sol";
import {IMemeverseOFTEnum} from "../../src/common/types/IMemeverseOFTEnum.sol";
import {IPOLend} from "../../src/polend/interfaces/IPOLend.sol";
import {IPOLSplitter} from "../../src/polend/interfaces/IPOLSplitter.sol";
import {IMemeverseSwapRouter} from "../../src/swap/interfaces/IMemeverseSwapRouter.sol";
import {IMemeverseUniswapHook} from "../../src/swap/interfaces/IMemeverseUniswapHook.sol";

interface IRefundCallbackObserver {
    /// @notice Handles the token refund callback emitted by the test refund token.
    /// @dev Used to assert CEI ordering during refund-sensitive launcher flows.
    function onRefundCallback() external;
}

interface IClaimNormalFeesReentryObserver {
    function onRedeemPTCallback() external;
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
    address internal initializer;
    bool internal enforceExpectedSqrtPriceLimitX96;
    bool internal revertLaunchSettlement;
    string internal launchSettlementRevertReason;
    bool internal lastLaunchSettlementZeroForOne;
    uint160 internal lastLaunchSettlementSqrtPriceLimitX96;
    uint256 internal launchSettlementCallCount;

    constructor(address boundLauncher_, address initializer_) {
        boundLauncher = boundLauncher_;
        initializer = initializer_;
    }

    function launcher() external view returns (address launcher_) {
        return boundLauncher;
    }

    function poolInitializer() external view returns (address initializer_) {
        return initializer;
    }

    function setPoolInitializer(address initializer_) external {
        initializer = initializer_;
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

    // Boundary note:
    // removeLiquidity fixtures below only prove launcher-side forwarding for lifecycle tests.
    // They do not prove real router/hook settlement semantics.

    struct Quote {
        uint256 fee0;
        uint256 fee1;
    }

    struct AddLiquidityResult {
        uint128 liquidity;
        uint256 amount0Used;
        uint256 amount1Used;
    }

    struct RemoveLiquidityResult {
        uint256 amount0Out;
        uint256 amount1Out;
    }

    mapping(bytes32 => Quote) internal previewQuotes;
    mapping(bytes32 => Quote) internal claimQuotes;
    mapping(bytes32 => address) internal lpTokens;
    mapping(bytes32 => AddLiquidityResult) internal addLiquidityResults;
    mapping(bytes32 => RemoveLiquidityResult) internal removeLiquidityResults;
    mapping(bytes32 => uint128) internal lastRemoveLiquidity;
    mapping(bytes32 => uint256) internal paddedLiquidityQuoteAmountA;
    mapping(bytes32 => uint256) internal paddedLiquidityQuoteAmountB;
    mapping(bytes32 => uint256) internal exactLiquidityQuoteAmountA;
    mapping(bytes32 => uint256) internal exactLiquidityQuoteAmountB;
    MockLaunchSettlementHookForLauncherTest internal immutable settlementHook;
    uint256 internal addLiquidityCallCount_;
    uint256 internal addLiquidityDetailedCallCount_;
    uint256 internal createPoolAndAddLiquidityCallCount_;
    address internal reenterLauncher;
    uint256 internal reenterVerseId;
    bool public reentryAttempted;
    bool public reentrySucceeded;
    bool internal revertNextRemoveLiquidity;

    constructor(address launcher_) {
        settlementHook = new MockLaunchSettlementHookForLauncherTest(launcher_, address(this));
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

    function createPoolAndAddLiquidityCallCount() external view returns (uint256 count) {
        return createPoolAndAddLiquidityCallCount_;
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

    function setRemoveLiquidityResult(address tokenA, address tokenB, uint256 amountAOut, uint256 amountBOut) external {
        (uint256 amount0Out, uint256 amount1Out) = _normalizePairAmounts(tokenA, tokenB, amountAOut, amountBOut);
        removeLiquidityResults[_pairKey(tokenA, tokenB)] =
            RemoveLiquidityResult({amount0Out: amount0Out, amount1Out: amount1Out});
    }

    function setRedeemReentry(address launcher, uint256 verseId) external {
        reenterLauncher = launcher;
        reenterVerseId = verseId;
        reentryAttempted = false;
        reentrySucceeded = false;
    }

    function setRevertNextRemoveLiquidity() external {
        revertNextRemoveLiquidity = true;
    }

    function clearRevertNextRemoveLiquidity() external {
        revertNextRemoveLiquidity = false;
    }

    function redeemAuxiliary(address launcher, uint256 verseId)
        external
        returns (uint256 polAmount, uint256 ptAmount, uint256 uAssetAmount)
    {
        return IMemeverseLauncher(launcher).redeemAuxiliaryLiquidity(verseId);
    }

    function lastRemoveLiquidityAmount(address tokenA, address tokenB) external view returns (uint128 liquidity) {
        return lastRemoveLiquidity[_pairKey(tokenA, tokenB)];
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
    /// @return amountAUsed Mock spend for `tokenA`.
    /// @return amountBUsed Mock spend for `tokenB`.
    function createPoolAndAddLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint160 startPrice,
        address recipient,
        uint256 deadline
    ) external returns (uint128 liquidity, PoolKey memory poolKey, uint256 amountAUsed, uint256 amountBUsed) {
        startPrice;
        deadline;

        createPoolAndAddLiquidityCallCount_++;
        poolKey = this.getHookPoolKey(tokenA, tokenB);
        AddLiquidityResult memory result = addLiquidityResults[_pairKey(tokenA, tokenB)];
        (amountAUsed, amountBUsed) =
            tokenA < tokenB ? (result.amount0Used, result.amount1Used) : (result.amount1Used, result.amount0Used);
        if (amountAUsed == 0 && amountBUsed == 0) {
            amountAUsed = amountADesired;
            amountBUsed = amountBDesired;
        }
        address liquidityToken = lpTokens[_pairKey(tokenA, tokenB)];
        if (result.liquidity != 0 && liquidityToken != address(0)) {
            MockERC20(liquidityToken).mint(recipient, result.liquidity);
        }
        return (result.liquidity, poolKey, amountAUsed, amountBUsed);
    }

    function removeLiquidity(
        Currency currency0,
        Currency currency1,
        uint128 liquidity,
        uint256 amount0Min,
        uint256 amount1Min,
        address to,
        uint256 deadline
    ) external returns (BalanceDelta delta) {
        amount0Min;
        amount1Min;
        deadline;

        address token0 = Currency.unwrap(currency0);
        address token1 = Currency.unwrap(currency1);
        lastRemoveLiquidity[_pairKey(token0, token1)] = liquidity;
        if (revertNextRemoveLiquidity) {
            revertNextRemoveLiquidity = false;
            revert("mock removeLiquidity revert");
        }
        if (reenterLauncher != address(0) && !reentryAttempted) {
            reentryAttempted = true;
            try IMemeverseLauncher(reenterLauncher).redeemAuxiliaryLiquidity(reenterVerseId) returns (
                uint256, uint256, uint256
            ) {
                reentrySucceeded = true;
            } catch {}
        }
        address liquidityToken = lpTokens[_pairKey(token0, token1)];
        if (liquidityToken != address(0) && liquidity != 0) {
            IERC20(liquidityToken).safeTransferFrom(msg.sender, address(this), liquidity);
        }

        RemoveLiquidityResult memory result = removeLiquidityResults[_pairKey(token0, token1)];
        if (result.amount0Out != 0) MockERC20(token0).mint(to, result.amount0Out);
        if (result.amount1Out != 0) MockERC20(token1).mint(to, result.amount1Out);
        return toBalanceDelta(int128(uint128(result.amount0Out)), int128(uint128(result.amount1Out)));
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
    IERC20 public immutable uAsset;
    IERC20 public immutable memecoin;
    IERC20 public immutable liquidProof;
    uint256 public immutable verseId;
    bool public sawPolDuringRefund;

    constructor(MemeverseLauncher launcher_, IERC20 uAsset_, IERC20 memecoin_, IERC20 liquidProof_, uint256 verseId_) {
        launcher = launcher_;
        uAsset = uAsset_;
        memecoin = memecoin_;
        liquidProof = liquidProof_;
        verseId = verseId_;
    }

    /// @notice Grants the launcher unlimited approval over the observer's test assets.
    /// @dev Used before invoking mint flows that pull uAsset and memecoin from this helper.
    function approveLauncher() external {
        uAsset.approve(address(launcher), type(uint256).max);
        memecoin.approve(address(launcher), type(uint256).max);
    }

    /// @notice Forwards a `mintPOLToken` call through the observer contract.
    /// @dev Lets the test observe whether POL exists before refund callbacks fire.
    /// @param amountInUAssetDesired Desired uAsset spend.
    /// @param amountInMemecoinDesired Desired memecoin spend.
    /// @param amountInUAssetMin Minimum accepted uAsset spend.
    /// @param amountInMemecoinMin Minimum accepted memecoin spend.
    /// @param amountOutDesired Desired POL output.
    /// @param deadline Latest valid execution timestamp.
    /// @return amountInUAsset Actual uAsset spent.
    /// @return amountInMemecoin Actual memecoin spent.
    /// @return amountOut Actual POL minted.
    function executeMintPOLToken(
        uint256 amountInUAssetDesired,
        uint256 amountInMemecoinDesired,
        uint256 amountInUAssetMin,
        uint256 amountInMemecoinMin,
        uint256 amountOutDesired,
        uint256 deadline
    ) external returns (uint256 amountInUAsset, uint256 amountInMemecoin, uint256 amountOut) {
        return launcher.mintPOLToken(
            verseId,
            amountInUAssetDesired,
            amountInMemecoinDesired,
            amountInUAssetMin,
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

contract MockPOLendForLifecycle {
    uint256 internal totalLeveragedDebt_;
    uint256 internal totalLeveragedInterest_;
    uint256 internal totalLeveragedYT_;
    address internal uAsset_;
    address internal pt_;
    address internal yt_;
    uint8 internal state_;
    address internal settlementLauncher_;
    bool internal settleAuxiliaryOnGlobalSettlement_;
    uint256 public preRedeemPTFeeCallCount;
    uint256 public lastPreRedeemPTFeeVerseId;
    uint256 public lastPreRedeemPTFeeAmount;
    address public lastPreRedeemPTFeeMintTo;
    address public lastFundSettlementDustReserveUAsset;
    uint256 public lastFundSettlementDustReserveAmount;
    uint256 internal preRedeemPTFeeBacking_;
    bool internal hasPreRedeemPTFeeBacking_;

    function setTotalLeveragedDebt(uint256 verseId, uint256 amount) external {
        verseId;
        totalLeveragedDebt_ = amount;
    }

    function setTotalLeveragedInterest(uint256 verseId, uint256 amount) external {
        verseId;
        totalLeveragedInterest_ = amount;
    }

    function setLendMarket(address pt, address yt) external {
        pt_ = pt;
        yt_ = yt;
    }

    function setLendMarketUAsset(address uAsset) external {
        uAsset_ = uAsset;
    }

    function registerLendMarket(uint256) external {}

    function getTotalLeveragedDebt(uint256) external view returns (uint256) {
        return totalLeveragedDebt_;
    }

    function getTotalLeveragedInterest(uint256) external view returns (uint256) {
        return totalLeveragedInterest_;
    }

    function getUserLeveragedDebt(uint256, address user) external pure returns (uint256) {
        if (user == address(0)) revert IPOLend.ZeroInput();
        return 0;
    }

    function getTotalDebtByUAsset(address uAsset) external view returns (uint256) {
        if (uAsset == address(0)) revert IPOLend.ZeroInput();
        return uAsset == uAsset_ ? totalLeveragedDebt_ : 0;
    }

    function settlementDustStates(address) external pure returns (uint128 reserve, uint128 maxReserve) {
        return (0, 0);
    }

    function fundSettlementDustReserve(address uAsset, uint256 amount) external {
        lastFundSettlementDustReserveUAsset = uAsset;
        lastFundSettlementDustReserveAmount = amount;
    }

    function getLeveragedDebtInfo(uint256) external view returns (IPOLend.LeveragedDebtInfo memory info) {
        info.totalLeveragedInterest = totalLeveragedInterest_;
        info.totalLeveragedDebt = totalLeveragedDebt_;
    }

    function getLendMarket(uint256) external view returns (IPOLend.LendMarket memory market) {
        market.yt = yt_;
        market.totalLeveragedInterest = totalLeveragedInterest_;
        market.totalLeveragedYT = totalLeveragedYT_;
        market.state = IPOLend.MarketState(state_);
        market.uAsset = uAsset_;
    }

    function finalizeLeveragedGenesis(uint256 verseId) external {
        verseId;
        state_ = 2;
    }

    function recordLeveragedYT(uint256 verseId, address yt, uint256 totalLeveragedYT) external {
        verseId;
        yt_ = yt;
        totalLeveragedYT_ = totalLeveragedYT;
    }

    function markRefundable(uint256 verseId) external {
        verseId;
        state_ = 4;
    }

    function setPreRedeemPTFeeBacking(uint256 backing) external {
        preRedeemPTFeeBacking_ = backing;
        hasPreRedeemPTFeeBacking_ = true;
    }

    function setSettleAuxiliaryOnGlobalSettlement(address launcher, bool enabled) external {
        settlementLauncher_ = launcher;
        settleAuxiliaryOnGlobalSettlement_ = enabled;
    }

    function executeGlobalSettlement(uint256 verseId) external {
        state_ = 3;
        if (settleAuxiliaryOnGlobalSettlement_) {
            IMemeverseLauncher(settlementLauncher_).settleLeveragedAuxiliaryLiquidity(verseId);
        }
    }

    function preRedeemPTFee(uint256 verseId, uint256 ptAmount, address mintTo)
        external
        returns (uint256 uAssetBacking)
    {
        preRedeemPTFeeCallCount++;
        lastPreRedeemPTFeeVerseId = verseId;
        lastPreRedeemPTFeeAmount = ptAmount;
        lastPreRedeemPTFeeMintTo = mintTo;

        uAssetBacking = hasPreRedeemPTFeeBacking_ ? preRedeemPTFeeBacking_ : ptAmount;
        if (ptAmount != 0 && uAssetBacking == 0) revert IPOLend.InvalidClaim();
        address uAsset = uAsset_;
        if (uAsset == address(0)) uAsset = IMemeverseLauncher(msg.sender).getMemeverseByVerseId(verseId).uAsset;
        MockERC20(uAsset).mint(mintTo, uAssetBacking);
    }

    function burnPreRedeemedBacking(uint256, uint256) external {}
}

contract RedeemMemecoinLiquidityReenterer {
    bool public reentryAttempted;
    bool public reentrySucceeded;
    bytes public lastRevertData;

    function redeemDuringSettlement(IMemeverseLauncher launcher, uint256 verseId, uint256 amountInPOL) external {
        reentryAttempted = true;
        delete lastRevertData;
        try launcher.redeemMemecoinLiquidity(verseId, amountInPOL, false) returns (uint256) {
            reentrySucceeded = true;
        } catch (bytes memory reason) {
            lastRevertData = reason;
        }
    }
}

contract ClaimNormalFeesReenterer is IClaimNormalFeesReentryObserver {
    MemeverseLauncher public immutable launcher;
    IERC20 public immutable uAsset;
    IERC20 public immutable pt;
    uint256 public immutable verseId;
    bool public reentryAttempted;
    bool public reentrySucceeded;
    bytes public lastRevertData;

    constructor(MemeverseLauncher launcher_, IERC20 uAsset_, IERC20 pt_, uint256 verseId_) {
        launcher = launcher_;
        uAsset = uAsset_;
        pt = pt_;
        verseId = verseId_;
    }

    function claimNormalFees() external returns (uint256 uAssetAmount, uint256 ptAmount) {
        return launcher.claimNormalFees(verseId);
    }

    function claimNormalYT() external returns (uint256 amount) {
        return launcher.claimNormalYT(verseId);
    }

    function redeemAuxiliaryLiquidity() external returns (uint256 polAmount, uint256 ptAmount, uint256 uAssetAmount) {
        return launcher.redeemAuxiliaryLiquidity(verseId);
    }

    function onRedeemPTCallback() external override {
        reentryAttempted = true;
        delete lastRevertData;
        try launcher.claimNormalFees(verseId) returns (uint256, uint256) {
            reentrySucceeded = true;
        } catch (bytes memory reason) {
            lastRevertData = reason;
        }
    }

    function onRedeemPTClaimNormalYTCallback() external {
        reentryAttempted = true;
        delete lastRevertData;
        try launcher.claimNormalYT(verseId) returns (uint256) {
            reentrySucceeded = true;
        } catch (bytes memory reason) {
            lastRevertData = reason;
        }
    }

    function onRedeemPTRedeemAuxiliaryLiquidityCallback() external {
        reentryAttempted = true;
        delete lastRevertData;
        try launcher.redeemAuxiliaryLiquidity(verseId) returns (uint256, uint256, uint256) {
            reentrySucceeded = true;
        } catch (bytes memory reason) {
            lastRevertData = reason;
        }
    }
}

contract MockPOLSplitterForLifecycle {
    address internal immutable pt;
    address internal immutable yt;
    uint256 public initializeVerseCallCount;
    uint256 public bridgeRedeemCallCount;
    uint256 public lastBridgeRedeemVerseId;
    uint256 public lastBridgeRedeemPTAmount;
    uint256 public redeemPTCallCount;
    uint256 public lastRedeemPTVerseId;
    uint256 public lastRedeemPTAmount;
    address public lastRedeemPTTo;
    address internal reenterLauncher;
    uint256 internal reenterVerseId;
    bool public reentryAttempted;
    bool public reentrySucceeded;
    bool public initializeReentryAttempted;
    bool public initializeGenesisSucceeded;
    bool public initializePreorderSucceeded;
    IMemeverseLauncher.Stage public initializeObservedStage;
    address internal memecoinLiquidityReenterer;
    uint256 internal reenterMemecoinLiquidityAmount;
    address internal claimNormalFeesReenterer;
    uint8 internal claimNormalFeesReentryMode;
    bool internal settled;
    uint256 internal previewPTToUAssetResult;
    bool internal hasPreviewPTToUAssetResult;
    uint256 internal previewPTToUAssetNumerator;
    uint256 internal previewPTToUAssetDenominator;
    mapping(uint256 => uint256) internal ptBackingNumerators;
    mapping(uint256 => uint256) internal ptBackingDenominators;

    constructor(address pt_, address yt_) {
        pt = pt_;
        yt = yt_;
    }

    function initializeVerse(uint256 verseId, address, address, address, string calldata, string calldata)
        external
        returns (address, address)
    {
        initializeVerseCallCount++;
        if (reenterLauncher != address(0) && reenterVerseId == verseId && !initializeReentryAttempted) {
            initializeReentryAttempted = true;
            IMemeverseLauncher launcher = IMemeverseLauncher(reenterLauncher);
            initializeObservedStage = launcher.getStageByVerseId(verseId);
            try launcher.genesis(verseId, 1, address(this)) {
                initializeGenesisSucceeded = true;
            } catch {}
            try launcher.preorder(verseId, 1, address(this)) {
                initializePreorderSucceeded = true;
            } catch {}
        }
        return (pt, yt);
    }

    function splitInfos(uint256)
        external
        view
        returns (address, address, address, address, address, uint256, uint256, uint256, uint256, uint256, bool)
    {
        return (pt, yt, address(0), address(0), address(0), 0, 0, 0, 0, 0, settled);
    }

    function getPT(uint256) external view returns (address) {
        return pt;
    }

    function getYT(uint256) external view returns (address) {
        return yt;
    }

    function getMemecoin(uint256) external pure returns (address) {
        return address(0);
    }

    function getPTAndYT(uint256) external view returns (address, address) {
        return (pt, yt);
    }

    function getPTSettlementState(uint256) external view returns (address, bool) {
        return (pt, settled);
    }

    function setSettled(bool settled_) external {
        settled = settled_;
    }

    function setPreviewPTToUAssetResult(uint256 result) external {
        previewPTToUAssetResult = result;
        hasPreviewPTToUAssetResult = true;
    }

    function setPreviewPTToUAssetRatio(uint256 numerator, uint256 denominator) external {
        require(denominator != 0, "zero denominator");
        previewPTToUAssetNumerator = numerator;
        previewPTToUAssetDenominator = denominator;
        hasPreviewPTToUAssetResult = false;
    }

    function setInitializeVerseReentry(address launcher, uint256 verseId) external {
        reenterLauncher = launcher;
        reenterVerseId = verseId;
        initializeReentryAttempted = false;
        initializeGenesisSucceeded = false;
        initializePreorderSucceeded = false;
        initializeObservedStage = IMemeverseLauncher.Stage.Genesis;
    }

    function split(uint256, uint256 polAmount) external returns (uint256 ptAmount, uint256 ytAmount) {
        MockERC20(pt).mint(msg.sender, polAmount);
        MockERC20(yt).mint(msg.sender, polAmount);
        return (polAmount, polAmount);
    }

    function recordPTBackingRatio(uint256 verseId, uint256 numerator, uint256 denominator) external {
        ptBackingNumerators[verseId] = numerator;
        ptBackingDenominators[verseId] = denominator;
    }

    function setSettleReentry(address launcher, uint256 verseId) external {
        reenterLauncher = launcher;
        reenterVerseId = verseId;
        memecoinLiquidityReenterer = address(0);
        reenterMemecoinLiquidityAmount = 0;
        reentryAttempted = false;
        reentrySucceeded = false;
        initializeReentryAttempted = false;
        initializeGenesisSucceeded = false;
        initializePreorderSucceeded = false;
        initializeObservedStage = IMemeverseLauncher.Stage.Genesis;
    }

    function setSettleMemecoinLiquidityReentry(
        address reenterer,
        address launcher,
        uint256 verseId,
        uint256 amountInPOL
    ) external {
        reenterLauncher = launcher;
        reenterVerseId = verseId;
        memecoinLiquidityReenterer = reenterer;
        reenterMemecoinLiquidityAmount = amountInPOL;
        reentryAttempted = false;
        reentrySucceeded = false;
        initializeReentryAttempted = false;
        initializeGenesisSucceeded = false;
        initializePreorderSucceeded = false;
        initializeObservedStage = IMemeverseLauncher.Stage.Genesis;
    }

    function setClaimNormalFeesReentry(address reenterer) external {
        claimNormalFeesReenterer = reenterer;
        claimNormalFeesReentryMode = 1;
    }

    function setClaimNormalFeesReentryMode(address reenterer, uint8 mode) external {
        claimNormalFeesReenterer = reenterer;
        claimNormalFeesReentryMode = mode;
    }

    function settle(uint256) external returns (uint256 settlementUAsset, uint256 settlementMemecoin) {
        if (reenterLauncher != address(0) && !reentryAttempted) {
            reentryAttempted = true;
            if (memecoinLiquidityReenterer != address(0)) {
                RedeemMemecoinLiquidityReenterer(memecoinLiquidityReenterer)
                    .redeemDuringSettlement(
                        IMemeverseLauncher(reenterLauncher), reenterVerseId, reenterMemecoinLiquidityAmount
                    );
            } else {
                try IMemeverseLauncher(reenterLauncher).redeemAuxiliaryLiquidity(reenterVerseId) returns (
                    uint256, uint256, uint256
                ) {
                    reentrySucceeded = true;
                } catch {}
            }
        }
        return (0, 0);
    }

    function merge(uint256, uint256) external pure returns (uint256) {
        revert("unused");
    }

    function preRedeemPTFee(uint256, uint256) external pure returns (uint256 uAssetBacking) {
        return 0;
    }

    function redeemPT(uint256 verseId, uint256 ptAmount, address to) external returns (uint256 uAssetAmount) {
        redeemPTCallCount++;
        lastRedeemPTVerseId = verseId;
        lastRedeemPTAmount = ptAmount;
        lastRedeemPTTo = to;
        uAssetAmount = _previewPTToUAsset(verseId, ptAmount);
        if (uAssetAmount == 0) revert IPOLSplitter.InvalidClaim();
        MockERC20(pt).burn(msg.sender, ptAmount);
        address uAsset = IMemeverseLauncher(msg.sender).getMemeverseByVerseId(verseId).uAsset;
        MockERC20(uAsset).mint(to, uAssetAmount);
        if (claimNormalFeesReenterer != address(0) && to == claimNormalFeesReenterer) {
            if (claimNormalFeesReentryMode == 2) {
                ClaimNormalFeesReenterer(claimNormalFeesReenterer).onRedeemPTClaimNormalYTCallback();
            } else if (claimNormalFeesReentryMode == 3) {
                ClaimNormalFeesReenterer(claimNormalFeesReenterer).onRedeemPTRedeemAuxiliaryLiquidityCallback();
            } else {
                IClaimNormalFeesReentryObserver(claimNormalFeesReenterer).onRedeemPTCallback();
            }
        }
        return uAssetAmount;
    }

    function redeemYT(uint256, uint256, address) external pure returns (uint256, uint256) {
        revert("unused");
    }

    function previewRedeemYTUAsset(uint256, uint256) external pure returns (uint256 uAssetAmount) {
        return 0;
    }

    function previewPTToUAsset(uint256 verseId, uint256 ptAmount) external view returns (uint256 uAssetAmount) {
        return _previewPTToUAsset(verseId, ptAmount);
    }

    function _previewPTToUAsset(uint256 verseId, uint256 ptAmount) internal view returns (uint256 uAssetAmount) {
        if (hasPreviewPTToUAssetResult) return previewPTToUAssetResult;
        if (previewPTToUAssetDenominator != 0) {
            return FullMath.mulDiv(ptAmount, previewPTToUAssetNumerator, previewPTToUAssetDenominator);
        }
        if (ptBackingDenominators[verseId] != 0) {
            return FullMath.mulDiv(ptAmount, ptBackingNumerators[verseId], ptBackingDenominators[verseId]);
        }
        return ptAmount;
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
    bool internal quoteAmountAsFee;
    uint32 public lastSendDstEid;
    address public lastRefundAddress;
    uint256 public lastNativeFeePaid;
    uint256 public lastSendAmountLD;
    uint256 public sendCallCount;

    constructor(string memory name_, string memory symbol_) MockERC20(name_, symbol_, 18) {}

    /// @notice Set quote fee.
    /// @dev Stores the per-chain fee used by remote quote tests.
    /// @param nativeFee See implementation.
    function setQuoteFee(uint256 nativeFee) external {
        nextQuoteFee = MessagingFee({nativeFee: nativeFee, lzTokenFee: 0});
    }

    function setQuoteAmountAsFee(bool enabled) external {
        quoteAmountAsFee = enabled;
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
        payInLzToken;
        if (quoteAmountAsFee) return MessagingFee({nativeFee: sendParam.amountLD, lzTokenFee: 0});
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
        lastSendAmountLD = sendParam.amountLD;
        sendCallCount++;

        receipt = MessagingReceipt({guid: bytes32("oft-guid"), nonce: 1, fee: fee});
        oftReceipt = OFTReceipt({amountSentLD: sendParam.amountLD, amountReceivedLD: sendParam.amountLD});
    }
}

contract TestableMemeverseLauncher is MemeverseLauncherTestBase {
    /// @notice Stores mock memeverse state for a verse id.
    /// @dev Exposes direct storage writes needed by unit tests.
    /// @param verseId Verse id whose state should be set.
    /// @param verse Mock memeverse state to store.
    function setMemeverseForTest(uint256 verseId, Memeverse memory verse) external {
        _testStorage().memeverses[verseId] = verse;
    }

    /// @notice Stores mock genesis fund totals for a verse id.
    /// @dev Lets tests control redemption share math directly.
    function setGenesisFundForTest(uint256 verseId, uint256 _totalNormalFunds) external {
        _testStorage().totalNormalFunds[verseId] = _totalNormalFunds;
    }

    /// @notice Stores mock user genesis data for a verse id.
    /// @dev Lets tests control redemption eligibility flags directly.
    /// @param verseId Verse id whose user state should be set.
    /// @param account Account whose genesis data should be set.
    /// @param genesisFund Mock contributed genesis amount.
    /// @param isRefunded Mock refunded flag.
    /// @param isRedeemed Mock redeemed flag.
    function setUserGenesisDataForTest(
        uint256 verseId,
        address account,
        uint256 genesisFund,
        bool isRefunded,
        bool isRedeemed
    ) external {
        _testStorage().userGenesisData[verseId][account] =
            GenesisData({genesisFund: genesisFund, isRefunded: isRefunded, isRedeemed: isRedeemed});
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
        _testStorage().userPreorderData[verseId][account] = PreorderData({
            funds: funds, claimedMemecoin: claimedMemecoin, isRefunded: isRefunded
        });
    }

    function setTotalNormalClaimableYTForTest(uint256 verseId, uint256 amount) external {
        _testStorage().totalNormalClaimableYT[verseId] = amount;
    }

    function setAuxiliaryLiquiditiesForTest(
        uint256 verseId,
        uint256 polUAssetLpAmount,
        uint256 ptUAssetLpAmount,
        uint256 ptPolLpAmount
    ) external {
        _testStorage().auxiliaryLiquidities[verseId] = AuxiliaryLiquidity({
            polUAssetLpAmount: polUAssetLpAmount, ptUAssetLpAmount: ptUAssetLpAmount, ptPolLpAmount: ptPolLpAmount
        });
    }

    function setBootstrapResidualClaimsForTest(
        uint256 verseId,
        uint256 normalResidualPOL,
        uint256 normalResidualPT,
        uint256 leveragedResidualPOL,
        uint256 leveragedResidualPT
    ) external {
        _testStorage().bootstrapResidualClaims[verseId] = BootstrapResidualClaims({
            normalResidualPOL: normalResidualPOL,
            normalResidualPT: normalResidualPT,
            leveragedResidualPOL: leveragedResidualPOL,
            leveragedResidualPT: leveragedResidualPT
        });
    }

    function setPendingAuxiliaryGovFeeForTest(uint256 verseId, uint256 pendingUAssetFee, uint256 pendingPTFee)
        external
    {
        _testStorage().pendingAuxiliaryGovFeeStates[verseId] =
            PendingAuxiliaryGovFeeState({pendingUAssetFee: pendingUAssetFee, pendingPTFee: pendingPTFee});
    }

    function setNormalFeeStateForTest(uint256 verseId, uint256 accUAssetFee, uint256 accPTFee) external {
        _testStorage().normalFeeStates[verseId] = NormalFeeState({accUAssetFee: accUAssetFee, accPTFee: accPTFee});
    }

    /// @notice Stores mock pol to verse-id state for a verse.
    /// @dev Exposes the symmetric swap-gate index to unit tests without going through full registration.
    /// @param liquidProofAddress Pol token address whose verse id should be set.
    /// @param verseId Verse id to associate with the pol token.
    function setVerseIdByPolForTest(address liquidProofAddress, uint256 verseId) external {
        _testStorage().polToIds[liquidProofAddress] = verseId;
    }
}

contract TestableMemeverseLauncherFactory {
    function deploy(
        address _owner,
        address _localLzEndpoint,
        address _memeverseRegistrar,
        address _memeverseProxyDeployer,
        address _yieldDispatcher,
        address _lzEndpointRegistry,
        address _polend,
        address _polSplitter,
        uint256 _executorRewardRate,
        uint128 _oftReceiveGasLimit,
        uint128 _yieldDispatcherGasLimit,
        uint256 _preorderCapRatio,
        uint256 _preorderVestingDuration
    ) external returns (TestableMemeverseLauncher) {
        TestableMemeverseLauncher implementation = new TestableMemeverseLauncher();
        bytes memory data = abi.encodeCall(
            MemeverseLauncher.initialize,
            (
                _owner,
                _localLzEndpoint,
                _memeverseRegistrar,
                _memeverseProxyDeployer,
                _yieldDispatcher,
                _lzEndpointRegistry,
                _polend,
                _polSplitter,
                _executorRewardRate,
                _oftReceiveGasLimit,
                _yieldDispatcherGasLimit,
                _preorderCapRatio,
                _preorderVestingDuration
            )
        );
        return TestableMemeverseLauncher(address(new ERC1967Proxy(address(implementation), data)));
    }
}

contract MemeverseLauncherLifecycleTest is Test {
    using PoolIdLibrary for PoolKey;

    event RefundPreorder(uint256 indexed verseId, address indexed receiver, uint256 refundAmount);
    event ClaimNormalFees(uint256 indexed verseId, address indexed receiver, uint256 uAssetAmount, uint256 ptAmount);

    TestableMemeverseLauncher internal launcher;
    MockSwapRouter internal router;
    MockOFTDispatcher internal dispatcher;
    MockPredictOnlyProxyDeployer internal proxyDeployer;
    MockPOLendForLifecycle internal polend;
    MockPOLSplitterForLifecycle internal splitter;
    MockLzEndpointRegistry internal registry;
    MockERC20 internal uAsset;
    MockERC20 internal memecoin;
    MockLiquidProof internal liquidProof;
    MockERC20 internal pt;
    MockERC20 internal yt;
    MockERC20 internal polUAssetLp;
    MockERC20 internal ptUAssetLp;
    MockERC20 internal ptPolLp;

    address internal constant REWARD_RECEIVER = address(0xBEEF);
    address internal constant ALICE = address(0xA11CE);

    function _readPublicSwapResumeTime(PoolKey memory key) internal view returns (bool ok, uint40 resumeTime) {
        address hookAddress = address(IMemeverseSwapRouter(address(router)).hook());
        (bool success, bytes memory data) =
            hookAddress.staticcall(abi.encodeWithSignature("publicSwapResumeTime(bytes32)", key.toId()));
        if (!success || data.length != 32) return (false, 0);
        return (true, abi.decode(data, (uint40)));
    }

    function _assertProtectionWindow(PoolKey memory key, uint40 resumeTime, string memory label) internal view {
        (bool resumeOk, uint40 storedResumeTime) = _readPublicSwapResumeTime(key);
        assertTrue(resumeOk, string.concat(label, " resume getter missing"));
        assertEq(storedResumeTime, resumeTime, string.concat(label, " resumeTime"));
    }

    /// @notice Deploys the launcher test harness and supporting mocks.
    /// @dev Wires the launcher to the mock router and mock dispatcher.
    function setUp() external {
        dispatcher = new MockOFTDispatcher();
        uAsset = new MockERC20("UASSET", "UASSET", 18);
        memecoin = new MockERC20("MEME", "MEME", 18);
        liquidProof = new MockLiquidProof();
        pt = new MockERC20("PT", "PT", 18);
        yt = new MockERC20("YT", "YT", 18);
        polUAssetLp = new MockERC20("POL-UASSET-LP", "POL-UASSET-LP", 18);
        ptUAssetLp = new MockERC20("PT-UASSET-LP", "PT-UASSET-LP", 18);
        ptPolLp = new MockERC20("PT-POL-LP", "PT-POL-LP", 18);
        proxyDeployer = new MockPredictOnlyProxyDeployer(address(0xD00D), address(0xCAFE), address(0xF00D));
        polend = new MockPOLendForLifecycle();
        splitter = new MockPOLSplitterForLifecycle(address(pt), address(yt));
        registry = new MockLzEndpointRegistry();
        launcher = (new TestableMemeverseLauncherFactory())
        .deploy(
            address(this),
            address(0x1),
            address(0x2),
            address(0x3),
            address(0x4),
            address(0x5),
            address(polend),
            address(splitter),
            25,
            115_000,
            135_000,
            2_500,
            7 days
        );
        router = new MockSwapRouter(address(launcher));

        launcher.setMemeverseUniswapHook(address(router.hook()));
        launcher.setMemeverseSwapRouter(address(router));
        launcher.setYieldDispatcher(address(dispatcher));
        launcher.setMemeverseProxyDeployer(address(proxyDeployer));
        launcher.setLzEndpointRegistry(address(registry));
        polend.setLendMarket(address(pt), address(yt));
        router.setLpToken(address(liquidProof), address(uAsset), address(polUAssetLp));
        router.setLpToken(address(pt), address(uAsset), address(ptUAssetLp));
        router.setLpToken(address(pt), address(liquidProof), address(ptPolLp));
    }

    /// @notice Seeds the launcher state with a verse locked for staking.
    /// @dev Populates the necessary uAsset/memecoin/liquid-proof pointers for locking tests.
    function _setLockedVerse(uint256 verseId) internal {
        IMemeverseLauncher.Memeverse memory verse;
        verse.uAsset = address(uAsset);
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
            verseId, address(uAsset), address(memecoin), address(liquidProof), flashGenesis, endTime
        );
    }

    function _setGenesisVerseWithAssets(
        uint256 verseId,
        address uAssetAddress,
        address memecoinAddress,
        address polAddress,
        bool flashGenesis,
        uint128 endTime
    ) internal {
        IMemeverseLauncher.Memeverse memory verse;
        verse.uAsset = uAssetAddress;
        verse.memecoin = memecoinAddress;
        verse.pol = polAddress;
        verse.currentStage = IMemeverseLauncher.Stage.Genesis;
        verse.endTime = endTime;
        verse.flashGenesis = flashGenesis;
        verse.omnichainIds = new uint32[](1);
        verse.omnichainIds[0] = uint32(block.chainid + 1);
        launcher.setMemeverseForTest(verseId, verse);
    }

    /// @notice Approves the launcher to pull mint inputs for a user.
    /// @dev Centralizes the approval pattern used by mintPOLToken scenarios.
    function _approveMintInputs(address user) internal {
        vm.startPrank(user);
        uAsset.approve(address(launcher), type(uint256).max);
        memecoin.approve(address(launcher), type(uint256).max);
        vm.stopPrank();
    }

    function _setSemanticPreviewQuote(address tokenA, address tokenB, uint256 tokenAFee, uint256 tokenBFee) internal {
        (uint256 fee0, uint256 fee1) = tokenA < tokenB ? (tokenAFee, tokenBFee) : (tokenBFee, tokenAFee);
        router.setPreviewQuote(tokenA, tokenB, address(launcher), fee0, fee1);
    }

    /// @notice Verifies preview fee mapping preserves token ordering for both pools.
    /// @dev Ensures the fee preview rearranges router outputs into semantic memecoin/uAsset names.
    /// @dev Ensures the launcher maps router fee0/fee1 outputs back to semantic token names.
    function testPreviewGenesisMakerFees_MapsFeesCorrectly() external {
        uint256 verseId = 1;
        _setLockedVerse(verseId);

        router.setQuote(address(memecoin), address(uAsset), address(launcher), 11 ether, 22 ether);
        router.setQuote(address(liquidProof), address(uAsset), address(launcher), 33 ether, 44 ether);

        (uint256 uAssetFee, uint256 memecoinFee) = launcher.previewGenesisMakerFees(verseId);

        assertEq(memecoinFee, 22 ether, "memecoin fee");
        assertEq(uAssetFee, 44 ether, "uAsset fee");
    }

    function testPreviewGenesisMakerFees_IncludesAuxiliaryGovFeesFromPTPools() external {
        uint256 verseId = 1;
        _setLockedVerse(verseId);
        launcher.setGenesisFundForTest(verseId, 100 ether);
        polend.setTotalLeveragedDebt(verseId, 40 ether);

        _setSemanticPreviewQuote(address(memecoin), address(uAsset), 3 ether, 7 ether);
        _setSemanticPreviewQuote(address(liquidProof), address(uAsset), 5 ether, 14 ether);
        _setSemanticPreviewQuote(address(pt), address(uAsset), 28 ether, 21 ether);
        _setSemanticPreviewQuote(address(pt), address(liquidProof), 14 ether, 35 ether);

        (uint256 uAssetFee, uint256 memecoinFee) = launcher.previewGenesisMakerFees(verseId);

        assertEq(memecoinFee, 3 ether, "memecoin fee");
        assertEq(uAssetFee, 29 ether, "uAsset fee includes auxiliary gov share");
    }

    function testPreviewGenesisMakerFees_PostUnlockConvertsAuxiliaryGovPTFee() external {
        uint256 verseId = 32;
        _setUnlockedVerse(verseId);
        launcher.setGenesisFundForTest(verseId, 100 ether);
        polend.setTotalLeveragedDebt(verseId, 40 ether);
        splitter.setPreviewPTToUAssetResult(2 ether);

        _setSemanticPreviewQuote(address(memecoin), address(uAsset), 3 ether, 7 ether);
        _setSemanticPreviewQuote(address(liquidProof), address(uAsset), 0, 0);
        _setSemanticPreviewQuote(address(pt), address(uAsset), 14 ether, 0);
        _setSemanticPreviewQuote(address(pt), address(liquidProof), 0, 0);

        (uint256 uAssetFee, uint256 memecoinFee) = launcher.previewGenesisMakerFees(verseId);

        assertEq(memecoinFee, 3 ether, "memecoin fee");
        assertEq(uAssetFee, 9 ether, "uAsset fee includes converted PT backing");
    }

    function testPreviewGenesisMakerFees_PostUnlockIncludesPendingAuxiliaryGovFees() external {
        uint256 verseId = 35;
        _setUnlockedVerse(verseId);
        launcher.setPendingAuxiliaryGovFeeForTest(verseId, 3 ether, 14 ether);
        splitter.setPreviewPTToUAssetResult(2 ether);

        _setSemanticPreviewQuote(address(memecoin), address(uAsset), 0, 0);
        _setSemanticPreviewQuote(address(liquidProof), address(uAsset), 0, 0);
        _setSemanticPreviewQuote(address(pt), address(uAsset), 0, 0);
        _setSemanticPreviewQuote(address(pt), address(liquidProof), 0, 0);

        (uint256 uAssetFee, uint256 memecoinFee) = launcher.previewGenesisMakerFees(verseId);

        assertEq(memecoinFee, 0, "memecoin fee");
        assertEq(uAssetFee, 5 ether, "uAsset fee includes pending auxiliary gov fees");
    }

    /// @notice Verifies previewing fees reverts before the locked stage.
    /// @dev Guards the launcher from previewing fees until after the locked-stage entry.
    /// @dev The launcher must not preview LP fees during genesis.
    function testPreviewGenesisMakerFees_RevertsWhenNotLocked() external {
        uint256 verseId = 1;
        IMemeverseLauncher.Memeverse memory verse;
        verse.uAsset = address(uAsset);
        verse.memecoin = address(memecoin);
        verse.pol = address(liquidProof);
        verse.currentStage = IMemeverseLauncher.Stage.Genesis;
        launcher.setMemeverseForTest(verseId, verse);

        vm.expectRevert(IMemeverseLauncher.NotReachedLockedStage.selector);
        launcher.previewGenesisMakerFees(verseId);
    }

    /// @notice Verifies normal YT can be claimed exactly once after the verse is locked.
    /// @dev Covers proportional YT distribution for normal genesis contributors.
    function testClaimNormalYT_SucceedsOnceAtLocked() external {
        uint256 verseId = 1;
        _setLockedVerse(verseId);
        launcher.setGenesisFundForTest(verseId, 120 ether);
        launcher.setUserGenesisDataForTest(verseId, ALICE, 24 ether, false, false);
        launcher.setTotalNormalClaimableYTForTest(verseId, 60 ether);
        yt.mint(address(launcher), 60 ether);

        vm.prank(ALICE);
        uint256 amount = launcher.claimNormalYT(verseId);

        assertEq(amount, 12 ether, "claimed amount");
        assertEq(yt.balanceOf(ALICE), 12 ether, "alice yt");

        vm.prank(ALICE);
        vm.expectRevert(IMemeverseLauncher.InvalidClaim.selector);
        launcher.claimNormalYT(verseId);
    }

    function testClaimNormalYT_AllowsZeroFloorDustClaimOnce() external {
        uint256 verseId = 1;
        _setLockedVerse(verseId);
        launcher.setGenesisFundForTest(verseId, 100 ether);
        launcher.setUserGenesisDataForTest(verseId, ALICE, 1, false, false);
        launcher.setTotalNormalClaimableYTForTest(verseId, 1);
        yt.mint(address(launcher), 1);

        vm.prank(ALICE);
        uint256 amount = launcher.claimNormalYT(verseId);

        assertEq(amount, 0, "claimed amount");
        assertEq(yt.balanceOf(ALICE), 0, "alice yt");

        vm.prank(ALICE);
        vm.expectRevert(IMemeverseLauncher.InvalidClaim.selector);
        launcher.claimNormalYT(verseId);
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
        MockOFTToken remoteUAsset = new MockOFTToken("UASSET", "UASSET");
        MockOFTToken remoteMemecoin = new MockOFTToken("MEME", "MEME");
        IMemeverseLauncher.Memeverse memory verse;
        verse.uAsset = address(remoteUAsset);
        verse.memecoin = address(remoteMemecoin);
        verse.pol = address(liquidProof);
        verse.governor = address(0xCAFE);
        verse.yieldVault = address(0xD00D);
        verse.currentStage = IMemeverseLauncher.Stage.Locked;
        verse.omnichainIds = new uint32[](1);
        verse.omnichainIds[0] = 202;
        launcher.setMemeverseForTest(verseId, verse);
        registry.setEndpoint(202, 302);

        router.setPreviewQuote(address(remoteMemecoin), address(remoteUAsset), address(launcher), 9 ether, 4 ether);
        router.setPreviewQuote(address(liquidProof), address(remoteUAsset), address(launcher), 0, 6 ether);
        remoteUAsset.setQuoteFee(0.15 ether);
        remoteMemecoin.setQuoteFee(0.25 ether);

        uint256 fee = launcher.quoteDistributionLzFee(verseId);

        assertEq(fee, 0.4 ether);
    }

    /// @notice Test quote distribution lz fee quotes only gov fee when memecoin fee is zero.
    /// @dev Confirms remote LZ quoting still works when the memecoin fee is zero.
    function testQuoteDistributionLzFee_QuotesOnlyGovFeeWhenMemecoinFeeIsZero() external {
        uint256 verseId = 18;
        MockOFTToken remoteUAsset = new MockOFTToken("UASSET", "UASSET");
        MockOFTToken remoteMemecoin = new MockOFTToken("MEME", "MEME");
        IMemeverseLauncher.Memeverse memory verse;
        verse.uAsset = address(remoteUAsset);
        verse.memecoin = address(remoteMemecoin);
        verse.pol = address(liquidProof);
        verse.governor = address(0xCAFE);
        verse.yieldVault = address(0xD00D);
        verse.currentStage = IMemeverseLauncher.Stage.Locked;
        verse.omnichainIds = new uint32[](1);
        verse.omnichainIds[0] = 202;
        launcher.setMemeverseForTest(verseId, verse);
        registry.setEndpoint(202, 302);

        if (address(remoteMemecoin) < address(remoteUAsset)) {
            router.setPreviewQuote(address(remoteMemecoin), address(remoteUAsset), address(launcher), 0, 9 ether);
        } else {
            router.setPreviewQuote(address(remoteMemecoin), address(remoteUAsset), address(launcher), 9 ether, 0);
        }
        router.setPreviewQuote(address(liquidProof), address(remoteUAsset), address(launcher), 0, 0);
        remoteUAsset.setQuoteFee(0.15 ether);

        uint256 fee = launcher.quoteDistributionLzFee(verseId);

        assertEq(fee, 0.15 ether);
    }

    /// @notice Test quote distribution lz fee quotes only memecoin fee when gov fee is zero.
    /// @dev Covers the remote path where the governance fee is absent but the memecoin fee remains.
    function testQuoteDistributionLzFee_QuotesOnlyMemecoinFeeWhenGovFeeIsZero() external {
        uint256 verseId = 19;
        MockOFTToken remoteUAsset = new MockOFTToken("UASSET", "UASSET");
        MockOFTToken remoteMemecoin = new MockOFTToken("MEME", "MEME");
        IMemeverseLauncher.Memeverse memory verse;
        verse.uAsset = address(remoteUAsset);
        verse.memecoin = address(remoteMemecoin);
        verse.pol = address(liquidProof);
        verse.governor = address(0xCAFE);
        verse.yieldVault = address(0xD00D);
        verse.currentStage = IMemeverseLauncher.Stage.Locked;
        verse.omnichainIds = new uint32[](1);
        verse.omnichainIds[0] = 202;
        launcher.setMemeverseForTest(verseId, verse);
        registry.setEndpoint(202, 302);

        if (address(remoteMemecoin) < address(remoteUAsset)) {
            router.setPreviewQuote(address(remoteMemecoin), address(remoteUAsset), address(launcher), 5 ether, 0);
        } else {
            router.setPreviewQuote(address(remoteMemecoin), address(remoteUAsset), address(launcher), 0, 5 ether);
        }
        router.setPreviewQuote(address(liquidProof), address(remoteUAsset), address(launcher), 0, 0);
        remoteMemecoin.setQuoteFee(0.25 ether);

        uint256 fee = launcher.quoteDistributionLzFee(verseId);

        assertEq(fee, 0.25 ether);
    }

    /// @notice Verifies remote gov-fee quoting stays overflow-safe for large claimable uAsset fees.
    /// @dev Guards against intermediate multiplication overflow when splitting executor reward from the main uAsset fee.
    function testQuoteDistributionLzFee_UsesFullPrecisionForLargeUAssetFee() external {
        uint256 verseId = 25;
        uint256 rewardRate = 9999;
        uint256 largeFee = type(uint256).max / rewardRate + 1;
        MockOFTToken remoteUAsset = new MockOFTToken("UASSET", "UASSET");
        MockOFTToken remoteMemecoin = new MockOFTToken("MEME", "MEME");
        IMemeverseLauncher.Memeverse memory verse;
        verse.uAsset = address(remoteUAsset);
        verse.memecoin = address(remoteMemecoin);
        verse.pol = address(liquidProof);
        verse.governor = address(0xCAFE);
        verse.yieldVault = address(0xD00D);
        verse.currentStage = IMemeverseLauncher.Stage.Locked;
        verse.omnichainIds = new uint32[](1);
        verse.omnichainIds[0] = 202;
        launcher.setMemeverseForTest(verseId, verse);
        registry.setEndpoint(202, 302);
        launcher.setExecutorRewardRate(rewardRate);

        if (address(remoteMemecoin) < address(remoteUAsset)) {
            router.setPreviewQuote(address(remoteMemecoin), address(remoteUAsset), address(launcher), 0, largeFee);
        } else {
            router.setPreviewQuote(address(remoteMemecoin), address(remoteUAsset), address(launcher), largeFee, 0);
        }
        router.setPreviewQuote(address(liquidProof), address(remoteUAsset), address(launcher), 0, 0);
        remoteUAsset.setQuoteAmountAsFee(true);

        uint256 expectedExecutorReward = FullMath.mulDiv(largeFee, rewardRate, 10_000);
        uint256 expectedGovFee = largeFee - expectedExecutorReward;

        uint256 fee = launcher.quoteDistributionLzFee(verseId);

        assertEq(fee, expectedGovFee);
    }

    /// @notice Test quote distribution lz fee quotes remote gov fee when only PT fee is bridged as uAsset.
    /// @dev Ensures remote PT fees still reserve a uAsset OFT send quote after the bridge-redemption rewrite.
    function testQuoteDistributionLzFee_QuotesRemoteGovFeeWhenOnlyPTFeeExists() external {
        uint256 verseId = 20;
        MockOFTToken remoteUAsset = new MockOFTToken("UASSET", "UASSET");
        MockOFTToken remoteMemecoin = new MockOFTToken("MEME", "MEME");
        IMemeverseLauncher.Memeverse memory verse;
        verse.uAsset = address(remoteUAsset);
        verse.memecoin = address(remoteMemecoin);
        verse.pol = address(liquidProof);
        verse.governor = address(0xCAFE);
        verse.yieldVault = address(0xD00D);
        verse.currentStage = IMemeverseLauncher.Stage.Locked;
        verse.omnichainIds = new uint32[](1);
        verse.omnichainIds[0] = 202;
        launcher.setMemeverseForTest(verseId, verse);
        launcher.setGenesisFundForTest(verseId, 100 ether);
        polend.setTotalLeveragedDebt(verseId, 40 ether);
        polend.setPreRedeemPTFeeBacking(2 ether);
        registry.setEndpoint(202, 302);

        router.setPreviewQuote(address(remoteMemecoin), address(remoteUAsset), address(launcher), 0, 0);
        router.setPreviewQuote(address(liquidProof), address(remoteUAsset), address(launcher), 0, 0);
        if (address(pt) < address(remoteUAsset)) {
            router.setPreviewQuote(address(pt), address(remoteUAsset), address(launcher), 14 ether, 0);
        } else {
            router.setPreviewQuote(address(pt), address(remoteUAsset), address(launcher), 0, 14 ether);
        }
        router.setPreviewQuote(address(pt), address(liquidProof), address(launcher), 0, 0);
        remoteUAsset.setQuoteFee(0.15 ether);

        uint256 fee = launcher.quoteDistributionLzFee(verseId);

        assertEq(fee, 0.15 ether);
    }

    /// @notice Verifies remote quote still charges for pending gov fees captured at unlock.
    /// @dev Historical auxiliary fees claimed during `Locked -> Unlocked` must still reserve a uAsset send.
    function testQuoteDistributionLzFee_QuotesPendingAuxiliaryGovFeesAfterUnlock() external {
        uint256 verseId = 29;
        MockOFTToken remoteUAsset = new MockOFTToken("UASSET", "UASSET");
        MockOFTToken remoteMemecoin = new MockOFTToken("MEME", "MEME");
        IMemeverseLauncher.Memeverse memory verse;
        verse.uAsset = address(remoteUAsset);
        verse.memecoin = address(remoteMemecoin);
        verse.pol = address(liquidProof);
        verse.governor = address(0xCAFE);
        verse.yieldVault = address(0xD00D);
        verse.currentStage = IMemeverseLauncher.Stage.Locked;
        verse.unlockTime = uint128(block.timestamp - 1);
        verse.omnichainIds = new uint32[](1);
        verse.omnichainIds[0] = 202;
        launcher.setMemeverseForTest(verseId, verse);
        launcher.setGenesisFundForTest(verseId, 100 ether);
        polend.setTotalLeveragedDebt(verseId, 40 ether);
        polend.setPreRedeemPTFeeBacking(2 ether);
        registry.setEndpoint(202, 302);

        router.setClaimQuote(address(remoteMemecoin), address(remoteUAsset), address(launcher), 0, 0);
        if (address(liquidProof) < address(remoteUAsset)) {
            router.setClaimQuote(address(liquidProof), address(remoteUAsset), address(launcher), 0, 6 ether);
        } else {
            router.setClaimQuote(address(liquidProof), address(remoteUAsset), address(launcher), 6 ether, 0);
        }
        router.setClaimQuote(address(pt), address(remoteUAsset), address(launcher), 0, 0);
        router.setClaimQuote(address(pt), address(liquidProof), address(launcher), 0, 0);

        router.setPreviewQuote(address(remoteMemecoin), address(remoteUAsset), address(launcher), 0, 0);
        router.setPreviewQuote(address(liquidProof), address(remoteUAsset), address(launcher), 0, 0);
        router.setPreviewQuote(address(pt), address(remoteUAsset), address(launcher), 0, 0);
        router.setPreviewQuote(address(pt), address(liquidProof), address(launcher), 0, 0);
        remoteUAsset.setQuoteFee(0.15 ether);

        launcher.changeStage(verseId);
        (uint256 pendingUAssetFee, uint256 pendingPTFee) = launcher.pendingAuxiliaryGovFeeStates(verseId);
        assertGt(pendingUAssetFee + pendingPTFee, 0, "pending auxiliary gov fee captured");

        uint256 fee = launcher.quoteDistributionLzFee(verseId);
        assertEq(fee, 0.15 ether, "pending auxiliary fee still quoted");
    }

    function testQuoteDistributionLzFee_PostUnlockUsesConvertedPendingPTFee() external {
        uint256 verseId = 33;
        MockOFTToken remoteUAsset = new MockOFTToken("UASSET", "UASSET");
        MockOFTToken remoteMemecoin = new MockOFTToken("MEME", "MEME");
        IMemeverseLauncher.Memeverse memory verse;
        verse.uAsset = address(remoteUAsset);
        verse.memecoin = address(remoteMemecoin);
        verse.pol = address(liquidProof);
        verse.governor = address(0xCAFE);
        verse.yieldVault = address(0xD00D);
        verse.currentStage = IMemeverseLauncher.Stage.Unlocked;
        verse.omnichainIds = new uint32[](1);
        verse.omnichainIds[0] = 202;
        launcher.setMemeverseForTest(verseId, verse);
        launcher.setPendingAuxiliaryGovFeeForTest(verseId, 0, 14 ether);
        splitter.setPreviewPTToUAssetResult(2 ether);
        registry.setEndpoint(202, 302);

        router.setPreviewQuote(address(remoteMemecoin), address(remoteUAsset), address(launcher), 0, 0);
        router.setPreviewQuote(address(liquidProof), address(remoteUAsset), address(launcher), 0, 0);
        router.setPreviewQuote(address(pt), address(remoteUAsset), address(launcher), 0, 0);
        router.setPreviewQuote(address(pt), address(liquidProof), address(launcher), 0, 0);
        remoteUAsset.setQuoteAmountAsFee(true);

        uint256 fee = launcher.quoteDistributionLzFee(verseId);

        assertEq(fee, 2 ether, "quoted converted pending backing");
    }

    function testQuoteDistributionLzFee_PostUnlockUsesConvertedCurrentPTFee() external {
        uint256 verseId = 34;
        MockOFTToken remoteUAsset = new MockOFTToken("UASSET", "UASSET");
        MockOFTToken remoteMemecoin = new MockOFTToken("MEME", "MEME");
        IMemeverseLauncher.Memeverse memory verse;
        verse.uAsset = address(remoteUAsset);
        verse.memecoin = address(remoteMemecoin);
        verse.pol = address(liquidProof);
        verse.governor = address(0xCAFE);
        verse.yieldVault = address(0xD00D);
        verse.currentStage = IMemeverseLauncher.Stage.Unlocked;
        verse.omnichainIds = new uint32[](1);
        verse.omnichainIds[0] = 202;
        launcher.setMemeverseForTest(verseId, verse);
        launcher.setGenesisFundForTest(verseId, 100 ether);
        polend.setTotalLeveragedDebt(verseId, 40 ether);
        splitter.setPreviewPTToUAssetResult(2 ether);
        registry.setEndpoint(202, 302);

        router.setPreviewQuote(address(remoteMemecoin), address(remoteUAsset), address(launcher), 0, 0);
        router.setPreviewQuote(address(liquidProof), address(remoteUAsset), address(launcher), 0, 0);
        if (address(pt) < address(remoteUAsset)) {
            router.setPreviewQuote(address(pt), address(remoteUAsset), address(launcher), 14 ether, 0);
        } else {
            router.setPreviewQuote(address(pt), address(remoteUAsset), address(launcher), 0, 14 ether);
        }
        router.setPreviewQuote(address(pt), address(liquidProof), address(launcher), 0, 0);
        remoteUAsset.setQuoteAmountAsFee(true);

        uint256 fee = launcher.quoteDistributionLzFee(verseId);

        assertEq(fee, 2 ether, "quoted converted current backing");
    }

    function testQuoteDistributionLzFee_MergesPendingAndCurrentPTBeforeConversion() external {
        uint256 verseId = 36;
        MockOFTToken remoteUAsset = new MockOFTToken("UASSET", "UASSET");
        MockOFTToken remoteMemecoin = new MockOFTToken("MEME", "MEME");
        IMemeverseLauncher.Memeverse memory verse;
        verse.uAsset = address(remoteUAsset);
        verse.memecoin = address(remoteMemecoin);
        verse.pol = address(liquidProof);
        verse.governor = address(0xCAFE);
        verse.yieldVault = address(0xD00D);
        verse.currentStage = IMemeverseLauncher.Stage.Unlocked;
        verse.omnichainIds = new uint32[](1);
        verse.omnichainIds[0] = 202;
        launcher.setMemeverseForTest(verseId, verse);
        launcher.setPendingAuxiliaryGovFeeForTest(verseId, 0, 1);
        splitter.setPreviewPTToUAssetRatio(1, 2);
        registry.setEndpoint(202, 302);

        router.setPreviewQuote(address(remoteMemecoin), address(remoteUAsset), address(launcher), 0, 0);
        router.setPreviewQuote(address(liquidProof), address(remoteUAsset), address(launcher), 0, 0);
        _setSemanticPreviewQuote(address(pt), address(remoteUAsset), 1, 0);
        router.setPreviewQuote(address(pt), address(liquidProof), address(launcher), 0, 0);
        remoteUAsset.setQuoteAmountAsFee(true);

        uint256 fee = launcher.quoteDistributionLzFee(verseId);

        assertEq(fee, 1, "quoted merged converted backing");
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
        launcher.setFundMetaData(address(uAsset), 10 ether, 4);
        launcher.setGenesisFundForTest(verseId, 4 ether);
        vm.warp(endTime + 1);

        IMemeverseLauncher.Stage stage = launcher.changeStage(verseId);

        assertEq(uint256(stage), uint256(IMemeverseLauncher.Stage.Refund), "returned stage");
        assertEq(uint256(launcher.getStageByVerseId(verseId)), uint256(IMemeverseLauncher.Stage.Refund), "stored stage");
    }

    function testChangeStage_WhenPausedGenesisEndedWithoutMinimumFund_MovesToRefund() external {
        uint256 verseId = 31;
        uint128 endTime = uint128(block.timestamp + 1);
        _setGenesisVerse(verseId, false, endTime);
        launcher.setFundMetaData(address(uAsset), 10 ether, 4);
        launcher.setGenesisFundForTest(verseId, 4 ether);
        vm.warp(endTime + 1);
        launcher.pause();

        IMemeverseLauncher.Stage stage = launcher.changeStage(verseId);

        assertEq(uint256(stage), uint256(IMemeverseLauncher.Stage.Refund), "returned stage");
        assertEq(uint256(launcher.getStageByVerseId(verseId)), uint256(IMemeverseLauncher.Stage.Refund), "stored stage");
    }

    /// @notice Verifies flashGenesis can lock early once the minimum funding target is met.
    /// @dev Confirms the flash Genesis branch bypasses endTime when the funding target is satisfied.
    function testChangeStage_WhenFlashGenesisAndMinimumFundMet_MovesToLocked() external {
        uint256 verseId = 8;
        _setGenesisVerse(verseId, true, uint128(block.timestamp + 1 days));
        launcher.setFundMetaData(address(uAsset), 10 ether, 4);
        launcher.setGenesisFundForTest(verseId, 120 ether);
        router.setAddLiquidityResult(address(memecoin), address(uAsset), 90 ether, 0, 0);
        router.setAddLiquidityResult(address(liquidProof), address(uAsset), 30 ether, 0, 0);

        IMemeverseLauncher.Stage stage = launcher.changeStage(verseId);

        assertEq(uint256(stage), uint256(IMemeverseLauncher.Stage.Locked), "returned stage");
        assertEq(uint256(launcher.getStageByVerseId(verseId)), uint256(IMemeverseLauncher.Stage.Locked), "stored stage");
    }

    function testChangeStage_WhenGenesisDeploymentReentersGenesisOrPreorder_SeesLockedStage() external {
        uint256 verseId = 30;
        _setGenesisVerse(verseId, true, uint128(block.timestamp + 1 days));
        launcher.setFundMetaData(address(uAsset), 10 ether, 4);
        launcher.setGenesisFundForTest(verseId, 120 ether);
        router.setAddLiquidityResult(address(memecoin), address(uAsset), 90 ether, 0, 0);
        router.setAddLiquidityResult(address(liquidProof), address(uAsset), 30 ether, 0, 0);
        splitter.setInitializeVerseReentry(address(launcher), verseId);

        IMemeverseLauncher.Stage stage = launcher.changeStage(verseId);

        assertEq(uint256(stage), uint256(IMemeverseLauncher.Stage.Locked), "returned stage");
        assertTrue(splitter.initializeReentryAttempted(), "reentry attempted");
        assertEq(uint256(splitter.initializeObservedStage()), uint256(IMemeverseLauncher.Stage.Locked), "reentry stage");
        assertFalse(splitter.initializeGenesisSucceeded(), "genesis reentry");
        assertFalse(splitter.initializePreorderSucceeded(), "preorder reentry");
    }

    function testExecuteLaunchSettlement_SplitsBootstrapResidualPOLAndPTByFundingShare() external {
        uint256 verseId = 33;
        _setGenesisVerse(verseId, true, uint128(block.timestamp + 1 days));
        launcher.setFundMetaData(address(uAsset), 10 ether, 4);
        launcher.setGenesisFundForTest(verseId, 100 ether);
        polend.setTotalLeveragedInterest(verseId, 10 ether);
        polend.setTotalLeveragedDebt(verseId, 100 ether);
        router.setAddLiquidityResult(address(memecoin), address(uAsset), 140 ether, 560 ether, 140 ether);
        router.setAddLiquidityResult(address(liquidProof), address(uAsset), 40 ether, 35 ether, 35 ether);
        router.setAddLiquidityResult(address(pt), address(uAsset), 20 ether, 10 ether, 10 ether);
        router.setAddLiquidityResult(address(pt), address(liquidProof), 40 ether, 35 ether, 35 ether);

        launcher.changeStage(verseId);

        (
            uint256 normalResidualPOL,
            uint256 normalResidualPT,
            uint256 leveragedResidualPOL,
            uint256 leveragedResidualPT
        ) = launcher.bootstrapResidualClaims(verseId);
        assertEq(normalResidualPOL, 5 ether, "normal pol residual");
        assertEq(leveragedResidualPOL, 5 ether, "leveraged pol residual");
        assertEq(normalResidualPT, 15 ether / 2, "normal pt residual");
        assertEq(leveragedResidualPT, 15 ether / 2, "leveraged pt residual");

        IMemeverseLauncher.Memeverse memory verse = launcher.getMemeverseByVerseId(verseId);
        verse.unlockTime = uint128(block.timestamp);
        launcher.setMemeverseForTest(verseId, verse);
        router.setRemoveLiquidityResult(address(liquidProof), address(uAsset), 1 ether, 2 ether);
        router.setRemoveLiquidityResult(address(pt), address(uAsset), 3 ether, 4 ether);
        router.setRemoveLiquidityResult(address(pt), address(liquidProof), 5 ether, 6 ether);
        polend.setSettleAuxiliaryOnGlobalSettlement(address(launcher), true);
        uint256 polendPOLBefore = liquidProof.balanceOf(address(polend));
        uint256 polendPTBefore = pt.balanceOf(address(polend));

        vm.warp(block.timestamp + 1);
        assertEq(uint256(launcher.changeStage(verseId)), uint256(IMemeverseLauncher.Stage.Unlocked), "unlocked");

        assertEq(liquidProof.balanceOf(address(polend)) - polendPOLBefore, 12 ether, "settled pol plus residual");
        assertEq(
            pt.balanceOf(address(polend)) - polendPTBefore, 4 ether + 6 ether + 15 ether / 2, "settled pt plus residual"
        );
        (,, leveragedResidualPOL, leveragedResidualPT) = launcher.bootstrapResidualClaims(verseId);
        assertEq(leveragedResidualPOL, 0, "leveraged pol cleared");
        assertEq(leveragedResidualPT, 0, "leveraged pt cleared");
    }

    function testExecuteLaunchSettlement_FundsUnusedBootstrapUAssetAfterAcceptedBootstrapDust() external {
        uint256 verseId = 34;
        _setGenesisVerse(verseId, true, uint128(block.timestamp + 1 days));
        launcher.setFundMetaData(address(uAsset), 10 ether, 4);
        launcher.setGenesisFundForTest(verseId, 120 ether);
        router.setAddLiquidityResult(address(memecoin), address(uAsset), 140 ether, 0, 0);
        router.setAddLiquidityResult(address(liquidProof), address(uAsset), 40 ether, 20 ether, 10 ether);
        router.setAddLiquidityResult(address(pt), address(uAsset), 20 ether, 10 ether, 5 ether);
        router.setAddLiquidityResult(address(pt), address(liquidProof), 40 ether, 40 ether, 40 ether);

        launcher.changeStage(verseId);

        assertEq(polend.lastFundSettlementDustReserveUAsset(), address(uAsset), "reserve uAsset");
        assertEq(polend.lastFundSettlementDustReserveAmount(), 21 ether, "unused uAsset");
    }

    function testPureLeveragedGenesis_LaunchesAndAllocatesAuxiliaryLiquidityToLeveragedSide() external {
        uint256 verseId = 32;
        uint128 endTime = uint128(block.timestamp + 1 days);
        _setGenesisVerse(verseId, false, endTime);
        launcher.setFundMetaData(address(uAsset), 10 ether, 4);
        polend.setTotalLeveragedInterest(verseId, 10 ether);
        polend.setTotalLeveragedDebt(verseId, 100 ether);
        router.setAddLiquidityResult(address(memecoin), address(uAsset), 140 ether, 0, 0);
        router.setAddLiquidityResult(address(liquidProof), address(uAsset), 60 ether, 0, 0);
        router.setAddLiquidityResult(address(pt), address(uAsset), 30 ether, 0, 0);
        router.setAddLiquidityResult(address(pt), address(liquidProof), 90 ether, 0, 0);

        vm.warp(endTime + 1);
        IMemeverseLauncher.Stage stage = launcher.changeStage(verseId);

        assertEq(uint256(stage), uint256(IMemeverseLauncher.Stage.Locked), "returned stage");
        assertEq(uint256(launcher.getStageByVerseId(verseId)), uint256(IMemeverseLauncher.Stage.Locked), "stored stage");
        assertEq(launcher.totalNormalFunds(verseId), 0, "normal funds");
        assertEq(launcher.totalNormalClaimableYT(verseId), 0, "normal yt");
        IPOLend.LendMarket memory market = polend.getLendMarket(verseId);
        assertGt(market.totalLeveragedYT, 0, "leveraged yt");

        IMemeverseLauncher.Memeverse memory verse = launcher.getMemeverseByVerseId(verseId);
        verse.unlockTime = uint128(block.timestamp);
        launcher.setMemeverseForTest(verseId, verse);
        router.setRemoveLiquidityResult(address(liquidProof), address(uAsset), 30 ether, 15 ether);
        router.setRemoveLiquidityResult(address(pt), address(uAsset), 12 ether, 6 ether);
        router.setRemoveLiquidityResult(address(pt), address(liquidProof), 20 ether, 10 ether);
        polend.setSettleAuxiliaryOnGlobalSettlement(address(launcher), true);
        uint256 polendPolBefore = liquidProof.balanceOf(address(polend));
        uint256 polendPtBefore = pt.balanceOf(address(polend));
        uint256 polendUAssetBefore = uAsset.balanceOf(address(polend));

        vm.warp(block.timestamp + 1);
        assertEq(uint256(launcher.changeStage(verseId)), uint256(IMemeverseLauncher.Stage.Unlocked), "unlocked");

        (uint256 remainingPolUAssetLp, uint256 remainingPtUAssetLp, uint256 remainingPtPolLp) =
            launcher.auxiliaryLiquidities(verseId);
        assertEq(remainingPolUAssetLp, 0, "remaining pol/uAsset");
        assertEq(remainingPtUAssetLp, 0, "remaining pt/uAsset");
        assertEq(remainingPtPolLp, 0, "remaining pt/pol");
        assertEq(
            uint256(router.lastRemoveLiquidityAmount(address(liquidProof), address(uAsset))),
            60 ether,
            "removed pol/uAsset"
        );
        assertEq(uint256(router.lastRemoveLiquidityAmount(address(pt), address(uAsset))), 30 ether, "removed pt/uAsset");
        assertEq(
            uint256(router.lastRemoveLiquidityAmount(address(pt), address(liquidProof))), 90 ether, "removed pt/pol"
        );
        assertEq(liquidProof.balanceOf(address(polend)) - polendPolBefore, 35 ether, "polend pol");
        assertEq(pt.balanceOf(address(polend)) - polendPtBefore, 16 ether, "polend pt");
        assertEq(uAsset.balanceOf(address(polend)) - polendUAssetBefore, 42 ether, "polend uAsset");

        assertEq(launcher.totalNormalFunds(verseId), 0, "normal funds before redeem");
        vm.prank(ALICE);
        vm.expectRevert(IMemeverseLauncher.InvalidClaim.selector);
        launcher.redeemAuxiliaryLiquidity(verseId);
    }

    function testPureLeveragedGenesis_WhenOnlyDebtMeetsMinimum_MovesToRefund() external {
        uint256 verseId = 33;
        uint128 endTime = uint128(block.timestamp + 1 days);
        _setGenesisVerse(verseId, false, endTime);
        launcher.setFundMetaData(address(uAsset), 10 ether, 4);
        polend.setTotalLeveragedInterest(verseId, 9 ether);
        polend.setTotalLeveragedDebt(verseId, 100 ether);

        vm.warp(endTime + 1);
        IMemeverseLauncher.Stage stage = launcher.changeStage(verseId);

        assertEq(uint256(stage), uint256(IMemeverseLauncher.Stage.Refund), "returned stage");
        assertEq(uint256(launcher.getStageByVerseId(verseId)), uint256(IMemeverseLauncher.Stage.Refund), "stored stage");
        assertEq(launcher.totalNormalFunds(verseId), 0, "normal funds");
        assertEq(launcher.totalNormalClaimableYT(verseId), 0, "normal yt");
        IPOLend.LendMarket memory market = polend.getLendMarket(verseId);
        assertEq(market.totalLeveragedYT, 0, "leveraged yt");
    }

    /// @notice Verifies Locked entry protects the four launcher-managed pools until actual unlock.
    function testChangeStage_WhenGenesisMovesToLocked_DoesNotSetProtectionWindow() external {
        uint256 verseId = 28;
        uint40 unlockTime = uint40(block.timestamp + 3 days);
        _setGenesisVerse(verseId, true, uint128(block.timestamp + 1 days));
        IMemeverseLauncher.Memeverse memory verse = launcher.getMemeverseByVerseId(verseId);
        verse.unlockTime = unlockTime;
        launcher.setMemeverseForTest(verseId, verse);

        launcher.setFundMetaData(address(uAsset), 10 ether, 4);
        launcher.setGenesisFundForTest(verseId, 120 ether);
        router.setAddLiquidityResult(address(memecoin), address(uAsset), 90 ether, 0, 0);
        router.setAddLiquidityResult(address(liquidProof), address(uAsset), 30 ether, 0, 0);

        PoolKey memory memecoinKey = router.getHookPoolKey(address(memecoin), address(uAsset));
        PoolKey memory polKey = router.getHookPoolKey(address(liquidProof), address(uAsset));

        IMemeverseLauncher.Stage stage = launcher.changeStage(verseId);

        assertEq(uint256(stage), uint256(IMemeverseLauncher.Stage.Locked), "returned stage");
        _assertProtectionWindow(memecoinKey, 0, "memecoin/uAsset");
        _assertProtectionWindow(polKey, 0, "POL/uAsset");
    }

    function testChangeStage_WhenLaunchSettlementConfigDrifts_RevertsBeforeCreatingPool() external {
        uint256 verseId = 34;
        _setGenesisVerse(verseId, true, uint128(block.timestamp + 1 days));
        launcher.setFundMetaData(address(uAsset), 10 ether, 4);
        launcher.setGenesisFundForTest(verseId, 120 ether);
        router.setAddLiquidityResult(address(memecoin), address(uAsset), 90 ether, 0, 0);
        router.setAddLiquidityResult(address(liquidProof), address(uAsset), 30 ether, 0, 0);

        MockLaunchSettlementHookForLauncherTest settlementHook =
            MockLaunchSettlementHookForLauncherTest(address(router.hook()));
        settlementHook.setPoolInitializer(address(0xBAD));

        vm.expectRevert(IMemeverseLauncher.InvalidLaunchSettlementConfig.selector);
        launcher.changeStage(verseId);

        assertEq(uint256(launcher.getStageByVerseId(verseId)), uint256(IMemeverseLauncher.Stage.Genesis), "stage");
        assertEq(router.createPoolAndAddLiquidityCallCount(), 0, "pool create calls");
    }

    /// @notice Verifies successful Genesis settlement executes the launch preorder swap and unlocks preorder memecoin linearly.
    /// @dev Covers the new launcher-managed preorder settlement path and linear unlock math.
    function testChangeStage_WhenGenesisSucceedsWithPreorder_SettlesAndUnlocksLinearly() external {
        uint256 verseId = 22;
        _setGenesisVerse(verseId, true, uint128(block.timestamp + 1 days));
        launcher.setFundMetaData(address(uAsset), 10 ether, 4);
        launcher.setGenesisFundForTest(verseId, 120 ether);
        router.setAddLiquidityResult(address(memecoin), address(uAsset), 90 ether, 0, 0);
        router.setAddLiquidityResult(address(liquidProof), address(uAsset), 30 ether, 0, 0);
        router.setLaunchSwapResult(address(uAsset), address(memecoin), 10 ether, 60 ether);

        uAsset.mint(address(this), 10 ether);
        uAsset.approve(address(launcher), type(uint256).max);
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

    function testChangeStage_PreorderSettlement_UsesCorrectSqrtPriceBoundary() external {
        uint256 verseId = 23;
        _setGenesisVerse(verseId, true, uint128(block.timestamp + 1 days));
        launcher.setFundMetaData(address(uAsset), 10 ether, 4);
        launcher.setGenesisFundForTest(verseId, 120 ether);
        router.setAddLiquidityResult(address(memecoin), address(uAsset), 90 ether, 0, 0);
        router.setAddLiquidityResult(address(liquidProof), address(uAsset), 30 ether, 0, 0);
        router.setLaunchSwapResult(address(uAsset), address(memecoin), 10 ether, 60 ether);

        bool zeroForOne = address(uAsset) < address(memecoin);
        uint160 expectedLimit = zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;

        MockLaunchSettlementHookForLauncherTest settlementHook =
            MockLaunchSettlementHookForLauncherTest(address(router.hook()));
        settlementHook.setExpectedLaunchSqrtPriceLimit(zeroForOne, expectedLimit);

        uAsset.mint(address(this), 10 ether);
        uAsset.approve(address(launcher), type(uint256).max);
        launcher.preorder(verseId, 10 ether, ALICE);

        IMemeverseLauncher.Stage stage = launcher.changeStage(verseId);

        assertEq(uint256(stage), uint256(IMemeverseLauncher.Stage.Locked), "returned stage");
        assertEq(settlementHook.lastSettlementZeroForOne(), zeroForOne, "zeroForOne");
        assertEq(settlementHook.lastSettlementSqrtPriceLimitX96(), expectedLimit, "sqrt price limit");
        assertEq(settlementHook.settlementCallCount(), 1, "settlement calls");
    }

    function testChangeStage_WhenLaunchSettlementReverts_RevertsAtomically() external {
        uint256 verseId = 25;
        _setGenesisVerse(verseId, true, uint128(block.timestamp + 1 days));
        launcher.setFundMetaData(address(uAsset), 10 ether, 4);
        launcher.setGenesisFundForTest(verseId, 120 ether);
        router.setAddLiquidityResult(address(memecoin), address(uAsset), 90 ether, 0, 0);
        router.setAddLiquidityResult(address(liquidProof), address(uAsset), 30 ether, 0, 0);

        MockLaunchSettlementHookForLauncherTest settlementHook =
            MockLaunchSettlementHookForLauncherTest(address(router.hook()));
        settlementHook.setLaunchSettlementRevert("mock launch settlement revert");

        uAsset.mint(address(this), 10 ether);
        uAsset.approve(address(launcher), type(uint256).max);
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
        launcher.setFundMetaData(address(uAsset), 10 ether, 4);
        launcher.setGenesisFundForTest(verseId, 120 ether);

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

    function testChangeStage_AllowsAuxiliaryRedeemDuringUnlockSettlement() external {
        uint256 verseId = 29;
        _setLockedVerse(verseId);
        IMemeverseLauncher.Memeverse memory verse = launcher.getMemeverseByVerseId(verseId);
        verse.unlockTime = uint128(block.timestamp - 1);
        launcher.setMemeverseForTest(verseId, verse);
        launcher.setGenesisFundForTest(verseId, 120 ether);
        launcher.setUserGenesisDataForTest(verseId, address(splitter), 24 ether, false, false);
        launcher.setAuxiliaryLiquiditiesForTest(verseId, 60 ether, 30 ether, 90 ether);
        polUAssetLp.mint(address(launcher), 60 ether);
        ptUAssetLp.mint(address(launcher), 30 ether);
        ptPolLp.mint(address(launcher), 90 ether);
        splitter.setSettleReentry(address(launcher), verseId);

        launcher.changeStage(verseId);

        assertTrue(splitter.reentryAttempted(), "settlement reentry attempted");
        assertTrue(splitter.reentrySucceeded(), "settlement reentry allowed");
        assertEq(uint256(launcher.getStageByVerseId(verseId)), uint256(IMemeverseLauncher.Stage.Unlocked), "unlocked");
        assertEq(polUAssetLp.balanceOf(address(splitter)), 12 ether, "settlement redeem succeeds");
    }

    function testChangeStage_AllowsPublicRedeemMemecoinLiquidityDuringUnlockSettlement() external {
        uint256 verseId = 31;
        _setLockedVerse(verseId);
        IMemeverseLauncher.Memeverse memory verse = launcher.getMemeverseByVerseId(verseId);
        verse.unlockTime = uint128(block.timestamp - 1);
        launcher.setMemeverseForTest(verseId, verse);

        MockERC20 memecoinLp = new MockERC20("MEME-LP", "MEME-LP", 18);
        RedeemMemecoinLiquidityReenterer reenterer = new RedeemMemecoinLiquidityReenterer();
        router.setLpToken(address(memecoin), address(uAsset), address(memecoinLp));
        memecoinLp.mint(address(launcher), 10 ether);
        liquidProof.mint(address(reenterer), 10 ether);
        splitter.setSettleMemecoinLiquidityReentry(address(reenterer), address(launcher), verseId, 4 ether);

        launcher.changeStage(verseId);

        assertTrue(splitter.reentryAttempted(), "settlement reentry attempted");
        assertTrue(reenterer.reentryAttempted(), "public reentry attempted");
        assertTrue(reenterer.reentrySucceeded(), "public reentry allowed");
        assertEq(liquidProof.balanceOf(address(reenterer)), 6 ether, "reenterer pol burned");
        assertEq(memecoinLp.balanceOf(address(reenterer)), 4 ether, "reenterer lp");
        assertEq(uint256(launcher.getStageByVerseId(verseId)), uint256(IMemeverseLauncher.Stage.Unlocked), "unlocked");
    }

    function testPreviewPreorderCapacityAndClaimNormalYT_SingleFieldAboveOldSplitMax() external {
        uint256 verseId = 30;
        _setLockedVerse(verseId);
        launcher.setGenesisFundForTest(verseId, type(uint128).max);
        launcher.setUserGenesisDataForTest(verseId, ALICE, type(uint128).max, false, false);
        launcher.setTotalNormalClaimableYTForTest(verseId, 2 ether);
        yt.mint(address(launcher), 2 ether);

        uint256 expectedCapacity = uint256(type(uint128).max) * 7 * 2_500 / (10 * launcher.RATIO());

        assertEq(launcher.previewPreorderCapacity(verseId), expectedCapacity, "preview capacity");

        vm.prank(ALICE);
        uint256 amount = launcher.claimNormalYT(verseId);

        assertEq(amount, 2 ether, "claim share");
    }

    /// @notice Verifies entering `Unlocked` snapshots pool resume times onto the hook with the fixed 24 hour window.
    /// @dev The protection window is now a constant product rule rather than a mutable config surface.
    function testChangeStage_LockedAfterUnlockSnapshotsHookResumeTimes() external {
        uint256 verseId = 24;
        _setLockedVerse(verseId);
        IMemeverseLauncher.Memeverse memory verse = launcher.getMemeverseByVerseId(verseId);
        verse.unlockTime = uint128(block.timestamp - 1);
        launcher.setMemeverseForTest(verseId, verse);

        PoolKey memory memecoinKey = router.getHookPoolKey(address(memecoin), address(uAsset));
        PoolKey memory polKey = router.getHookPoolKey(address(liquidProof), address(uAsset));
        PoolKey memory ptUAssetKey = router.getHookPoolKey(address(pt), address(uAsset));
        PoolKey memory ptPolKey = router.getHookPoolKey(address(pt), address(liquidProof));

        launcher.changeStage(verseId);

        uint40 resumeTime = uint40(block.timestamp + 24 hours);
        _assertProtectionWindow(memecoinKey, resumeTime, "memecoin/uAsset");
        _assertProtectionWindow(polKey, resumeTime, "POL/uAsset");
        _assertProtectionWindow(ptUAssetKey, resumeTime, "PT/uAsset");
        _assertProtectionWindow(ptPolKey, resumeTime, "PT/POL");
    }

    /// @notice Verifies unlock protection no longer depends on the router's pool-key helper after router rebinding.
    /// @dev Rebinding to a router that shares the same hook but has a broken helper must still protect the live pool.
    function testChangeStage_LockedAfterUnlockDoesNotDependOnRouterPoolKeyHelper() external {
        uint256 verseId = 27;
        _setLockedVerse(verseId);
        IMemeverseLauncher.Memeverse memory verse = launcher.getMemeverseByVerseId(verseId);
        verse.unlockTime = uint128(block.timestamp - 1);
        launcher.setMemeverseForTest(verseId, verse);

        PoolKey memory memecoinKey = router.getHookPoolKey(address(memecoin), address(uAsset));
        address sharedHook = address(router.hook());
        MockSwapRouterWithBrokenPoolKey brokenRouter = new MockSwapRouterWithBrokenPoolKey(sharedHook);
        MockLaunchSettlementHookForLauncherTest(sharedHook).setPoolInitializer(address(brokenRouter));
        launcher.setMemeverseSwapRouter(address(brokenRouter));

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
        vm.expectRevert(IMemeverseLauncher.InvalidClaim.selector);
        launcher.refund(verseId);
    }

    function testRefund_WhenPausedTransfersFundsAndMarksRefunded() external {
        uint256 verseId = 32;
        _setLockedVerse(verseId);
        IMemeverseLauncher.Memeverse memory verse = launcher.getMemeverseByVerseId(verseId);
        verse.currentStage = IMemeverseLauncher.Stage.Refund;
        launcher.setMemeverseForTest(verseId, verse);
        launcher.setUserGenesisDataForTest(verseId, ALICE, 5 ether, false, false);
        uAsset.mint(address(launcher), 5 ether);
        launcher.pause();

        vm.prank(ALICE);
        uint256 refunded = launcher.refund(verseId);

        (, bool isRefunded,) = launcher.userGenesisData(verseId, ALICE);
        assertEq(refunded, 5 ether, "refunded");
        assertTrue(isRefunded, "isRefunded");
        assertEq(uAsset.balanceOf(ALICE), 5 ether, "alice uAsset");
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
        vm.expectRevert(IMemeverseLauncher.InvalidClaim.selector);
        launcher.refundPreorder(verseId);
    }

    /// @notice Verifies refund preorder returns funds and marks the user as refunded.
    /// @dev Covers the successful preorder refund path, asserting balances and flags.
    function testRefundPreorder_WhenPausedTransfersFundsAndMarksRefunded() external {
        uint256 verseId = 23;
        _setLockedVerse(verseId);
        IMemeverseLauncher.Memeverse memory verse = launcher.getMemeverseByVerseId(verseId);
        verse.currentStage = IMemeverseLauncher.Stage.Refund;
        launcher.setMemeverseForTest(verseId, verse);
        launcher.setUserPreorderDataForTest(verseId, ALICE, 5 ether, 0, false);
        uAsset.mint(address(launcher), 5 ether);
        launcher.pause();

        vm.expectEmit(true, true, false, true, address(launcher));
        emit RefundPreorder(verseId, ALICE, 5 ether);

        vm.prank(ALICE);
        uint256 refunded = launcher.refundPreorder(verseId);

        (uint256 funds, uint256 claimedMemecoin, bool isRefunded) = launcher.userPreorderData(verseId, ALICE);
        assertEq(refunded, 5 ether, "refunded");
        assertEq(funds, 5 ether, "funds");
        assertEq(claimedMemecoin, 0, "claimed");
        assertTrue(isRefunded, "isRefunded");
        assertEq(uAsset.balanceOf(ALICE), 5 ether, "alice uAsset");
    }

    /// @notice Verifies normal YT claims revert when the caller has no genesis share.
    /// @dev Guards the new claim path from minting YT to unrelated accounts.
    function testClaimNormalYT_RevertsWhenUserHasNoShare() external {
        uint256 verseId = 1;
        _setLockedVerse(verseId);

        vm.prank(ALICE);
        vm.expectRevert(IMemeverseLauncher.InvalidClaim.selector);
        launcher.claimNormalYT(verseId);
    }

    /// @notice Verifies Locked-stage auxiliary fees remain claimable by normal users after unlock.
    /// @dev `changeStage` must flush historical auxiliary fees into `normalFeeStates` before switching to `Unlocked`.
    function testChangeStage_PreservesLockedAuxiliaryFeesForNormalClaimsAfterUnlock() external {
        uint256 verseId = 28;
        _setLockedVerse(verseId);
        launcher.setGenesisFundForTest(verseId, 120 ether);
        launcher.setUserGenesisDataForTest(verseId, ALICE, 24 ether, false, false);
        polend.setTotalLeveragedDebt(verseId, 40 ether);

        IMemeverseLauncher.Memeverse memory verse = launcher.getMemeverseByVerseId(verseId);
        verse.unlockTime = uint128(block.timestamp - 1);
        launcher.setMemeverseForTest(verseId, verse);

        router.setClaimQuote(address(memecoin), address(uAsset), address(launcher), 0, 0);
        if (address(liquidProof) < address(uAsset)) {
            router.setClaimQuote(address(liquidProof), address(uAsset), address(launcher), 0, 8 ether);
        } else {
            router.setClaimQuote(address(liquidProof), address(uAsset), address(launcher), 8 ether, 0);
        }
        if (address(pt) < address(uAsset)) {
            router.setClaimQuote(address(pt), address(uAsset), address(launcher), 12 ether, 0);
        } else {
            router.setClaimQuote(address(pt), address(uAsset), address(launcher), 0, 12 ether);
        }
        router.setClaimQuote(address(pt), address(liquidProof), address(launcher), 0, 0);

        assertEq(uint256(launcher.changeStage(verseId)), uint256(IMemeverseLauncher.Stage.Unlocked), "unlocked");

        (uint256 accUAssetFee, uint256 accPTFee) = launcher.normalFeeStates(verseId);
        assertEq(accUAssetFee, 6 ether, "locked normal uAsset fee kept");
        assertEq(accPTFee, 9 ether, "locked normal pt fee kept");

        vm.prank(ALICE);
        (uint256 claimedUAssetFee, uint256 claimedPTFee) = launcher.claimNormalFees(verseId);
        assertEq(claimedUAssetFee, 1.2 ether, "normal user gets unlock-delayed uAsset fee");
        assertEq(claimedPTFee, 1.8 ether, "normal user gets unlock-delayed pt fee");
    }

    /// @notice Verifies unlock fee capture uses full-precision division rather than overflowing intermediate multiplication.
    function testChangeStage_CapturesLargeAuxiliaryFeesWithoutOverflow() external {
        uint256 verseId = 41;
        _setLockedVerse(verseId);
        launcher.setGenesisFundForTest(verseId, 1);
        launcher.setUserGenesisDataForTest(verseId, ALICE, 1, false, false);

        uint256 leveragedDebt = uint256(1) << 120;
        uint256 feeAmount = uint256(1) << 70;
        polend.setTotalLeveragedDebt(verseId, leveragedDebt);

        IMemeverseLauncher.Memeverse memory verse = launcher.getMemeverseByVerseId(verseId);
        verse.unlockTime = uint128(block.timestamp - 1);
        launcher.setMemeverseForTest(verseId, verse);

        router.setClaimQuote(address(memecoin), address(uAsset), address(launcher), 0, 0);
        if (address(liquidProof) < address(uAsset)) {
            router.setClaimQuote(address(liquidProof), address(uAsset), address(launcher), 0, feeAmount);
        } else {
            router.setClaimQuote(address(liquidProof), address(uAsset), address(launcher), feeAmount, 0);
        }
        if (address(pt) < address(uAsset)) {
            router.setClaimQuote(address(pt), address(uAsset), address(launcher), feeAmount, 0);
        } else {
            router.setClaimQuote(address(pt), address(uAsset), address(launcher), 0, feeAmount);
        }
        router.setClaimQuote(address(pt), address(liquidProof), address(launcher), 0, 0);

        assertEq(uint256(launcher.changeStage(verseId)), uint256(IMemeverseLauncher.Stage.Unlocked), "unlocked");

        uint256 totalFunds = leveragedDebt + 1;
        uint256 expectedGovUAssetFee = FullMath.mulDiv(feeAmount, leveragedDebt, totalFunds);
        uint256 expectedGovPTFee = FullMath.mulDiv(feeAmount, leveragedDebt, totalFunds);
        uint256 expectedNormalUAssetFee = feeAmount - expectedGovUAssetFee;
        uint256 expectedNormalPTFee = feeAmount - expectedGovPTFee;

        (uint256 accUAssetFee, uint256 accPTFee) = launcher.normalFeeStates(verseId);
        assertEq(accUAssetFee, expectedNormalUAssetFee, "normal uAsset fee");
        assertEq(accPTFee, expectedNormalPTFee, "normal pt fee");

        (uint256 pendingUAssetFee, uint256 pendingPTFee) = launcher.pendingAuxiliaryGovFeeStates(verseId);
        assertEq(pendingUAssetFee, expectedGovUAssetFee, "pending gov uAsset fee");
        assertEq(pendingPTFee, expectedGovPTFee, "pending gov pt fee");
    }

    function testClaimNormalFees_SettledSplitterRedeemsClaimablePTToUAsset() external {
        uint256 verseId = 32;
        _setUnlockedVerse(verseId);
        splitter.setSettled(true);
        launcher.setGenesisFundForTest(verseId, 120 ether);
        launcher.setUserGenesisDataForTest(verseId, ALICE, 24 ether, false, false);
        launcher.setNormalFeeStateForTest(verseId, 10 ether, 20 ether);
        uAsset.mint(address(launcher), 10 ether);
        pt.mint(address(launcher), 20 ether);

        vm.prank(ALICE);
        (uint256 uAssetAmount, uint256 ptAmount) = launcher.claimNormalFees(verseId);

        assertEq(splitter.redeemPTCallCount(), 1, "redeemPT called");
        assertEq(splitter.lastRedeemPTVerseId(), verseId, "verse id");
        assertEq(splitter.lastRedeemPTAmount(), 4 ether, "pt redeemed");
        assertEq(splitter.lastRedeemPTTo(), ALICE, "redeem receiver");
        assertEq(uAssetAmount, 6 ether, "uAsset includes redeemed PT");
        assertEq(ptAmount, 0, "no PT returned");
        assertEq(uAsset.balanceOf(ALICE), 6 ether, "alice uAsset");
        assertEq(pt.balanceOf(ALICE), 0, "alice pt");
    }

    function testClaimNormalFees_UnsettledSplitterReportsTransferredPT() external {
        uint256 verseId = 46;
        _setUnlockedVerse(verseId);
        splitter.setSettled(false);
        launcher.setGenesisFundForTest(verseId, 120 ether);
        launcher.setUserGenesisDataForTest(verseId, ALICE, 24 ether, false, false);
        launcher.setNormalFeeStateForTest(verseId, 10 ether, 20 ether);
        uAsset.mint(address(launcher), 10 ether);
        pt.mint(address(launcher), 20 ether);

        vm.expectEmit(true, true, false, true, address(launcher));
        emit ClaimNormalFees(verseId, ALICE, 2 ether, 4 ether);

        vm.prank(ALICE);
        (uint256 uAssetAmount, uint256 ptAmount) = launcher.claimNormalFees(verseId);

        assertEq(uAssetAmount, 2 ether, "uAsset claim");
        assertEq(ptAmount, 4 ether, "returned claimed pt amount");
        assertEq(uAsset.balanceOf(ALICE), 2 ether, "alice uAsset");
        assertEq(pt.balanceOf(ALICE), 4 ether, "alice pt");
    }

    function testClaimNormalFees_ReentrantRedeemPTCannotDoubleClaimUAssetFee() external {
        uint256 verseId = 43;
        _setUnlockedVerse(verseId);
        splitter.setSettled(true);
        splitter.setPreviewPTToUAssetResult(4 ether);
        launcher.setGenesisFundForTest(verseId, 120 ether);
        launcher.setUserGenesisDataForTest(verseId, ALICE, 24 ether, false, false);
        launcher.setNormalFeeStateForTest(verseId, 10 ether, 20 ether);
        uAsset.mint(address(launcher), 10 ether);
        pt.mint(address(launcher), 20 ether);

        ClaimNormalFeesReenterer reenterer =
            new ClaimNormalFeesReenterer(launcher, IERC20(address(uAsset)), IERC20(address(pt)), verseId);
        splitter.setClaimNormalFeesReentry(address(reenterer));
        launcher.setUserGenesisDataForTest(verseId, address(reenterer), 24 ether, false, false);

        (uint256 claimedUAssetFee, uint256 claimedPTFee) = reenterer.claimNormalFees();

        assertTrue(reenterer.reentryAttempted(), "reentry attempted");
        assertEq(claimedUAssetFee, 6 ether, "single claim total");
        assertEq(claimedPTFee, 0, "pt redeemed");
        assertEq(uAsset.balanceOf(address(reenterer)), 6 ether, "no double uAsset fee");
    }

    function testClaimNormalFees_RedeemPTCallbackCanClaimNormalYTOnce() external {
        uint256 verseId = 44;
        _setUnlockedVerse(verseId);
        splitter.setSettled(true);
        splitter.setPreviewPTToUAssetResult(4 ether);
        launcher.setGenesisFundForTest(verseId, 120 ether);
        launcher.setUserGenesisDataForTest(verseId, ALICE, 24 ether, false, false);
        launcher.setNormalFeeStateForTest(verseId, 10 ether, 20 ether);
        launcher.setTotalNormalClaimableYTForTest(verseId, 60 ether);
        uAsset.mint(address(launcher), 10 ether);
        pt.mint(address(launcher), 20 ether);
        yt.mint(address(launcher), 60 ether);

        ClaimNormalFeesReenterer reenterer =
            new ClaimNormalFeesReenterer(launcher, IERC20(address(uAsset)), IERC20(address(pt)), verseId);
        splitter.setClaimNormalFeesReentryMode(address(reenterer), 2);
        launcher.setUserGenesisDataForTest(verseId, address(reenterer), 24 ether, false, false);

        (uint256 claimedUAssetFee, uint256 claimedPTFee) = reenterer.claimNormalFees();

        assertTrue(reenterer.reentryAttempted(), "reentry attempted");
        assertTrue(reenterer.reentrySucceeded(), "claimNormalYT reentry succeeded");
        assertEq(claimedUAssetFee, 6 ether, "single claim total");
        assertEq(claimedPTFee, 0, "pt redeemed");
        assertEq(uAsset.balanceOf(address(reenterer)), 6 ether, "uAsset claimed");
        assertEq(yt.balanceOf(address(reenterer)), 12 ether, "yt claimed");
        assertTrue(launcher.normalYTClaimed(verseId, address(reenterer)), "yt marked claimed");
    }

    function testClaimNormalFees_RedeemPTCallbackCanRedeemAuxiliaryLiquidityOnce() external {
        uint256 verseId = 45;
        _setUnlockedVerse(verseId);
        splitter.setSettled(true);
        splitter.setPreviewPTToUAssetResult(4 ether);
        launcher.setGenesisFundForTest(verseId, 120 ether);
        launcher.setUserGenesisDataForTest(verseId, ALICE, 24 ether, false, false);
        launcher.setNormalFeeStateForTest(verseId, 10 ether, 20 ether);
        launcher.setAuxiliaryLiquiditiesForTest(verseId, 60 ether, 30 ether, 90 ether);
        launcher.setBootstrapResidualClaimsForTest(verseId, 25 ether, 10 ether, 0, 0);
        uAsset.mint(address(launcher), 10 ether);
        pt.mint(address(launcher), 30 ether);
        liquidProof.mint(address(launcher), 25 ether);
        polUAssetLp.mint(address(launcher), 60 ether);
        ptUAssetLp.mint(address(launcher), 30 ether);
        ptPolLp.mint(address(launcher), 90 ether);

        ClaimNormalFeesReenterer reenterer =
            new ClaimNormalFeesReenterer(launcher, IERC20(address(uAsset)), IERC20(address(pt)), verseId);
        splitter.setClaimNormalFeesReentryMode(address(reenterer), 3);
        launcher.setUserGenesisDataForTest(verseId, address(reenterer), 24 ether, false, false);

        (uint256 claimedUAssetFee, uint256 claimedPTFee) = reenterer.claimNormalFees();

        assertTrue(reenterer.reentryAttempted(), "reentry attempted");
        assertTrue(reenterer.reentrySucceeded(), "redeemAuxiliaryLiquidity reentry succeeded");
        assertEq(claimedUAssetFee, 6 ether, "single claim total");
        assertEq(claimedPTFee, 0, "pt redeemed");
        assertEq(uAsset.balanceOf(address(reenterer)), 6 ether, "uAsset claimed");
        assertEq(polUAssetLp.balanceOf(address(reenterer)), 12 ether, "pol/uAsset lp claimed");
        assertEq(ptUAssetLp.balanceOf(address(reenterer)), 6 ether, "pt/uAsset lp claimed");
        assertEq(ptPolLp.balanceOf(address(reenterer)), 18 ether, "pt/pol lp claimed");
        assertEq(liquidProof.balanceOf(address(reenterer)), 5 ether, "pol residual claimed");
        assertEq(pt.balanceOf(address(reenterer)), 2 ether, "pt residual claimed");
        (,, bool isRedeemed) = launcher.userGenesisData(verseId, address(reenterer));
        assertTrue(isRedeemed, "user marked redeemed");
    }

    function testClaimNormalFees_SettledSplitterLeavesZeroBackingPTDustUnclaimed() external {
        uint256 verseId = 35;
        _setUnlockedVerse(verseId);
        splitter.setSettled(true);
        splitter.setPreviewPTToUAssetResult(0);
        launcher.setGenesisFundForTest(verseId, 120 ether);
        launcher.setUserGenesisDataForTest(verseId, ALICE, 24 ether, false, false);
        launcher.setNormalFeeStateForTest(verseId, 10 ether, 5);
        uAsset.mint(address(launcher), 10 ether);
        pt.mint(address(launcher), 5);

        vm.expectEmit(true, true, false, true, address(launcher));
        emit ClaimNormalFees(verseId, ALICE, 2 ether, 0);

        vm.prank(ALICE);
        (uint256 uAssetAmount, uint256 ptAmount) = launcher.claimNormalFees(verseId);

        assertEq(splitter.redeemPTCallCount(), 0, "zero backing pt not redeemed");
        assertEq(uAssetAmount, 2 ether, "uAsset still claimable");
        assertEq(ptAmount, 0, "pt dust not reported in return");
        assertEq(uAsset.balanceOf(ALICE), 2 ether, "alice uAsset");
        (, uint256 claimedPTFee) = launcher.userNormalFeeClaims(verseId, ALICE);
        assertEq(claimedPTFee, 0, "pt entitlement stays pending for self-heal");
    }

    function testClaimNormalFees_HandlesMaxUint128FeeShareWithoutOverflow() external {
        uint256 verseId = 36;
        uint256 largeFee = uint256(type(uint128).max) + 3;
        _setUnlockedVerse(verseId);
        splitter.setSettled(false);
        launcher.setGenesisFundForTest(verseId, type(uint128).max);
        launcher.setUserGenesisDataForTest(verseId, ALICE, type(uint128).max, false, false);
        launcher.setNormalFeeStateForTest(verseId, largeFee, largeFee);
        uAsset.mint(address(launcher), largeFee);
        pt.mint(address(launcher), largeFee);

        vm.prank(ALICE);
        (uint256 uAssetAmount, uint256 ptAmount) = launcher.claimNormalFees(verseId);

        assertEq(uAssetAmount, largeFee, "uAsset amount");
        assertEq(ptAmount, largeFee, "pt amount");
        assertEq(uAsset.balanceOf(ALICE), largeFee, "alice uAsset");
        assertEq(pt.balanceOf(ALICE), largeFee, "alice pt");
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

    /// @notice Verifies no-fee redemption rejects accidental native value.
    /// @dev Prevents stray ETH from being trapped by the no-fee early return.
    function testRedeemAndDistributeFees_NoFeesRevertsWhenMsgValueProvided() external {
        uint256 verseId = 1;
        _setLockedVerse(verseId);

        vm.expectRevert(abi.encodeWithSelector(IMemeverseLauncher.InvalidLzFee.selector, 0, 1));
        launcher.redeemAndDistributeFees{value: 1}(verseId, REWARD_RECEIVER);
    }

    /// @notice Test redeem and distribute fees remote path checks lz fee and sends oft.
    /// @dev Validates the remote dispatch branch requires the exact LayerZero fee and calls `send`.
    function testRedeemAndDistributeFees_RemotePathChecksLzFeeAndSendsOFT() external {
        uint256 verseId = 2;
        MockOFTToken remoteUAsset = new MockOFTToken("UASSET", "UASSET");
        MockOFTToken remoteMemecoin = new MockOFTToken("MEME", "MEME");
        IMemeverseLauncher.Memeverse memory verse;
        verse.uAsset = address(remoteUAsset);
        verse.memecoin = address(remoteMemecoin);
        verse.pol = address(liquidProof);
        verse.governor = address(0xCAFE);
        verse.yieldVault = address(0xD00D);
        verse.currentStage = IMemeverseLauncher.Stage.Locked;
        verse.omnichainIds = new uint32[](1);
        verse.omnichainIds[0] = 202;
        launcher.setMemeverseForTest(verseId, verse);
        registry.setEndpoint(202, 302);

        router.setClaimQuote(address(remoteMemecoin), address(remoteUAsset), address(launcher), 9 ether, 4 ether);
        router.setClaimQuote(address(liquidProof), address(remoteUAsset), address(launcher), 0, 6 ether);
        remoteUAsset.setQuoteFee(0.15 ether);
        remoteMemecoin.setQuoteFee(0.25 ether);

        remoteUAsset.mint(address(launcher), 100 ether);
        remoteMemecoin.mint(address(launcher), 100 ether);

        vm.expectRevert(abi.encodeWithSelector(IMemeverseLauncher.InvalidLzFee.selector, 0.4 ether, 0));
        launcher.redeemAndDistributeFees(verseId, REWARD_RECEIVER);

        launcher.redeemAndDistributeFees{value: 0.4 ether}(verseId, REWARD_RECEIVER);

        assertEq(remoteUAsset.sendCallCount(), 1);
        assertEq(remoteMemecoin.sendCallCount(), 1);
        assertEq(remoteUAsset.lastSendDstEid(), 302);
        assertEq(remoteMemecoin.lastSendDstEid(), 302);
        assertEq(remoteUAsset.lastNativeFeePaid(), 0.15 ether);
        assertEq(remoteMemecoin.lastNativeFeePaid(), 0.25 ether);
    }

    /// @notice Verifies remote fee redemption rejects overpayment instead of trapping extra ETH in the launcher.
    /// @dev Requires the caller to provide the exact quoted LayerZero fee and reject overpayments.
    function testRedeemAndDistributeFees_RemotePathRevertsWhenLzFeeIsNotExact() external {
        uint256 verseId = 24;
        MockOFTToken remoteUAsset = new MockOFTToken("UASSET", "UASSET");
        MockOFTToken remoteMemecoin = new MockOFTToken("MEME", "MEME");
        IMemeverseLauncher.Memeverse memory verse;
        verse.uAsset = address(remoteUAsset);
        verse.memecoin = address(remoteMemecoin);
        verse.pol = address(liquidProof);
        verse.governor = address(0xCAFE);
        verse.yieldVault = address(0xD00D);
        verse.currentStage = IMemeverseLauncher.Stage.Locked;
        verse.omnichainIds = new uint32[](1);
        verse.omnichainIds[0] = 202;
        launcher.setMemeverseForTest(verseId, verse);
        registry.setEndpoint(202, 302);

        router.setClaimQuote(address(remoteMemecoin), address(remoteUAsset), address(launcher), 9 ether, 4 ether);
        router.setClaimQuote(address(liquidProof), address(remoteUAsset), address(launcher), 0, 6 ether);
        remoteUAsset.setQuoteFee(0.15 ether);
        remoteMemecoin.setQuoteFee(0.25 ether);
        remoteUAsset.mint(address(launcher), 100 ether);
        remoteMemecoin.mint(address(launcher), 100 ether);

        vm.expectRevert(abi.encodeWithSelector(IMemeverseLauncher.InvalidLzFee.selector, 0.4 ether, 0.41 ether));
        launcher.redeemAndDistributeFees{value: 0.41 ether}(verseId, REWARD_RECEIVER);
    }

    /// @notice Test redeem and distribute fees remote path only gov fee skips memecoin send.
    /// @dev Ensures memecoin dispatch is skipped when its quote is zero in the remote path.
    function testRedeemAndDistributeFees_RemotePathOnlyGovFeeSkipsMemecoinSend() external {
        uint256 verseId = 21;
        MockOFTToken remoteUAsset = new MockOFTToken("UASSET", "UASSET");
        MockOFTToken remoteMemecoin = new MockOFTToken("MEME", "MEME");
        IMemeverseLauncher.Memeverse memory verse;
        verse.uAsset = address(remoteUAsset);
        verse.memecoin = address(remoteMemecoin);
        verse.pol = address(liquidProof);
        verse.governor = address(0xCAFE);
        verse.yieldVault = address(0xD00D);
        verse.currentStage = IMemeverseLauncher.Stage.Locked;
        verse.omnichainIds = new uint32[](1);
        verse.omnichainIds[0] = 202;
        launcher.setMemeverseForTest(verseId, verse);
        registry.setEndpoint(202, 302);

        if (address(remoteMemecoin) < address(remoteUAsset)) {
            router.setClaimQuote(address(remoteMemecoin), address(remoteUAsset), address(launcher), 0, 9 ether);
        } else {
            router.setClaimQuote(address(remoteMemecoin), address(remoteUAsset), address(launcher), 9 ether, 0);
        }
        router.setClaimQuote(address(liquidProof), address(remoteUAsset), address(launcher), 0, 0);
        remoteUAsset.setQuoteFee(0.15 ether);
        remoteUAsset.mint(address(launcher), 100 ether);

        launcher.redeemAndDistributeFees{value: 0.15 ether}(verseId, REWARD_RECEIVER);

        assertEq(remoteUAsset.sendCallCount(), 1);
        assertEq(remoteMemecoin.sendCallCount(), 0);
    }

    /// @notice Test redeem and distribute fees remote path only memecoin fee skips gov send.
    /// @dev Ensures governance dispatch is skipped when its quote is zero in the remote path.
    function testRedeemAndDistributeFees_RemotePathOnlyMemecoinFeeSkipsGovSend() external {
        uint256 verseId = 22;
        MockOFTToken remoteUAsset = new MockOFTToken("UASSET", "UASSET");
        MockOFTToken remoteMemecoin = new MockOFTToken("MEME", "MEME");
        IMemeverseLauncher.Memeverse memory verse;
        verse.uAsset = address(remoteUAsset);
        verse.memecoin = address(remoteMemecoin);
        verse.pol = address(liquidProof);
        verse.governor = address(0xCAFE);
        verse.yieldVault = address(0xD00D);
        verse.currentStage = IMemeverseLauncher.Stage.Locked;
        verse.omnichainIds = new uint32[](1);
        verse.omnichainIds[0] = 202;
        launcher.setMemeverseForTest(verseId, verse);
        registry.setEndpoint(202, 302);

        if (address(remoteMemecoin) < address(remoteUAsset)) {
            router.setClaimQuote(address(remoteMemecoin), address(remoteUAsset), address(launcher), 5 ether, 0);
        } else {
            router.setClaimQuote(address(remoteMemecoin), address(remoteUAsset), address(launcher), 0, 5 ether);
        }
        router.setClaimQuote(address(liquidProof), address(remoteUAsset), address(launcher), 0, 0);
        remoteMemecoin.setQuoteFee(0.25 ether);
        remoteMemecoin.mint(address(launcher), 100 ether);

        launcher.redeemAndDistributeFees{value: 0.25 ether}(verseId, REWARD_RECEIVER);

        assertEq(remoteUAsset.sendCallCount(), 0);
        assertEq(remoteMemecoin.sendCallCount(), 1);
    }

    /// @notice Verifies fee redemption uses the same overflow-safe reward split as fee quoting.
    /// @dev Prevents unchecked reward multiplication from wrapping and misallocating value between executor and governor.
    function testRedeemAndDistributeFees_UsesFullPrecisionForLargeUAssetFee() external {
        uint256 verseId = 26;
        uint256 rewardRate = 9999;
        uint256 largeFee = type(uint256).max / rewardRate + 1;
        _setLockedVerse(verseId);
        launcher.setExecutorRewardRate(rewardRate);

        if (address(memecoin) < address(uAsset)) {
            router.setClaimQuote(address(memecoin), address(uAsset), address(launcher), 0, largeFee);
        } else {
            router.setClaimQuote(address(memecoin), address(uAsset), address(launcher), largeFee, 0);
        }
        router.setClaimQuote(address(liquidProof), address(uAsset), address(launcher), 0, 0);

        uint256 expectedExecutorReward = FullMath.mulDiv(largeFee, rewardRate, 10_000);
        uint256 expectedGovFee = largeFee - expectedExecutorReward;

        (uint256 govFee, uint256 memecoinFee, uint256 polFee, uint256 executorReward) =
            launcher.redeemAndDistributeFees(verseId, REWARD_RECEIVER);

        assertEq(govFee, expectedGovFee, "gov fee");
        assertEq(memecoinFee, 0, "memecoin fee");
        assertEq(polFee, 0, "pol fee");
        assertEq(executorReward, expectedExecutorReward, "executor reward");
        assertEq(uAsset.balanceOf(REWARD_RECEIVER), expectedExecutorReward, "reward receiver uAsset");
        assertEq(uAsset.balanceOf(address(dispatcher)), expectedGovFee, "dispatcher uAsset");
    }

    /// @notice Test redeem and distribute fees remote path pre-redeems locked PT fee into the remote uAsset send.
    /// @dev Ensures remote governance never receives raw PT and the pre-redeemed amount is folded into the single uAsset OFT send.
    function testRedeemAndDistributeFees_RemotePathPreRedeemsLockedPTFeeAsUAsset() external {
        uint256 verseId = 23;
        MockOFTToken remoteUAsset = new MockOFTToken("UASSET", "UASSET");
        MockOFTToken remoteMemecoin = new MockOFTToken("MEME", "MEME");
        IMemeverseLauncher.Memeverse memory verse;
        verse.uAsset = address(remoteUAsset);
        verse.memecoin = address(remoteMemecoin);
        verse.pol = address(liquidProof);
        verse.governor = address(0xCAFE);
        verse.yieldVault = address(0xD00D);
        verse.currentStage = IMemeverseLauncher.Stage.Locked;
        verse.omnichainIds = new uint32[](1);
        verse.omnichainIds[0] = 202;
        launcher.setMemeverseForTest(verseId, verse);
        launcher.setGenesisFundForTest(verseId, 100 ether);
        polend.setTotalLeveragedDebt(verseId, 40 ether);
        polend.setPreRedeemPTFeeBacking(2 ether);
        registry.setEndpoint(202, 302);

        router.setClaimQuote(address(remoteMemecoin), address(remoteUAsset), address(launcher), 0, 0);
        router.setClaimQuote(address(liquidProof), address(remoteUAsset), address(launcher), 0, 0);
        if (address(pt) < address(remoteUAsset)) {
            router.setClaimQuote(address(pt), address(remoteUAsset), address(launcher), 14 ether, 0);
        } else {
            router.setClaimQuote(address(pt), address(remoteUAsset), address(launcher), 0, 14 ether);
        }
        router.setClaimQuote(address(pt), address(liquidProof), address(launcher), 0, 0);
        remoteUAsset.setQuoteFee(0.15 ether);

        launcher.redeemAndDistributeFees{value: 0.15 ether}(verseId, REWARD_RECEIVER);

        assertEq(polend.preRedeemPTFeeCallCount(), 1);
        assertEq(polend.lastPreRedeemPTFeeVerseId(), verseId);
        assertEq(polend.lastPreRedeemPTFeeAmount(), 4 ether);
        assertEq(polend.lastPreRedeemPTFeeMintTo(), address(launcher));
        assertEq(splitter.bridgeRedeemCallCount(), 0);
        assertEq(remoteUAsset.sendCallCount(), 1);
        assertEq(remoteUAsset.lastSendAmountLD(), 2 ether);
        assertEq(remoteMemecoin.sendCallCount(), 0);
    }

    function testRedeemAndDistributeFees_RemotePathKeepsPendingZeroBackingAuxiliaryGovPTFee() external {
        uint256 verseId = 37;
        MockOFTToken remoteUAsset = new MockOFTToken("UASSET", "UASSET");
        MockOFTToken remoteMemecoin = new MockOFTToken("MEME", "MEME");
        IMemeverseLauncher.Memeverse memory verse;
        verse.uAsset = address(remoteUAsset);
        verse.memecoin = address(remoteMemecoin);
        verse.pol = address(liquidProof);
        verse.governor = address(0xCAFE);
        verse.yieldVault = address(0xD00D);
        verse.currentStage = IMemeverseLauncher.Stage.Locked;
        verse.omnichainIds = new uint32[](1);
        verse.omnichainIds[0] = 202;
        launcher.setMemeverseForTest(verseId, verse);
        launcher.setPendingAuxiliaryGovFeeForTest(verseId, 3 ether, 1);
        registry.setEndpoint(202, 302);
        remoteUAsset.setQuoteFee(0.15 ether);

        launcher.redeemAndDistributeFees{value: 0.15 ether}(verseId, REWARD_RECEIVER);

        (uint256 pendingUAssetFee, uint256 pendingPTFee) = launcher.pendingAuxiliaryGovFeeStates(verseId);
        assertEq(pendingUAssetFee, 0, "uAsset pending cleared");
        assertEq(pendingPTFee, 0, "pt pending consumed from current redemption path");
        assertEq(remoteUAsset.sendCallCount(), 1, "uAsset sent");
        assertEq(remoteMemecoin.sendCallCount(), 0, "memecoin not sent");
    }

    function testRedeemAndDistributeFees_LocalPathPreRedeemsLockedPTFeeAsUAsset() external {
        uint256 verseId = 31;
        _setLockedVerse(verseId);
        launcher.setGenesisFundForTest(verseId, 100 ether);
        polend.setTotalLeveragedDebt(verseId, 40 ether);
        polend.setPreRedeemPTFeeBacking(2 ether);

        router.setClaimQuote(address(memecoin), address(uAsset), address(launcher), 0, 0);
        router.setClaimQuote(address(liquidProof), address(uAsset), address(launcher), 0, 0);
        if (address(pt) < address(uAsset)) {
            router.setClaimQuote(address(pt), address(uAsset), address(launcher), 14 ether, 0);
        } else {
            router.setClaimQuote(address(pt), address(uAsset), address(launcher), 0, 14 ether);
        }
        router.setClaimQuote(address(pt), address(liquidProof), address(launcher), 0, 0);

        launcher.redeemAndDistributeFees(verseId, REWARD_RECEIVER);

        assertEq(polend.preRedeemPTFeeCallCount(), 1, "preRedeem called");
        assertEq(polend.lastPreRedeemPTFeeVerseId(), verseId, "verse id");
        assertEq(polend.lastPreRedeemPTFeeAmount(), 4 ether, "pt amount");
        assertEq(polend.lastPreRedeemPTFeeMintTo(), address(dispatcher), "mint target");
        assertEq(splitter.bridgeRedeemCallCount(), 0, "bridgeRedeem not used");
        assertEq(pt.balanceOf(address(0xCAFE)), 0, "no raw pt to governor");
        assertEq(uAsset.balanceOf(address(0xCAFE)), 0, "no direct uAsset to governor");
        assertEq(uAsset.balanceOf(address(dispatcher)), 2 ether, "uAsset to dispatcher");
        assertEq(dispatcher.composeCallCount(), 1, "compose called");
        (, uint8 tokenType, uint256 composedAmount) = abi.decode(dispatcher.lastMessage(), (address, uint8, uint256));
        assertEq(tokenType, uint8(IMemeverseOFTEnum.TokenType.UASSET), "compose token type");
        assertEq(composedAmount, 2 ether, "composed uAsset backing");
        (, uint256 pendingPTFee) = launcher.pendingAuxiliaryGovFeeStates(verseId);
        assertEq(pendingPTFee, 0, "pending pt cleared after preRedeem");
    }

    function testRedeemAndDistributeFees_LocalPathLeavesZeroBackingPTDustPending() external {
        uint256 verseId = 36;
        _setLockedVerse(verseId);
        launcher.setGenesisFundForTest(verseId, 100 ether);
        launcher.setPendingAuxiliaryGovFeeForTest(verseId, 3 ether, 1);
        splitter.setPreviewPTToUAssetResult(0);
        uAsset.mint(address(launcher), 3 ether);

        (uint256 govFee, uint256 memecoinFee, uint256 liquidProofFee, uint256 executorReward) =
            launcher.redeemAndDistributeFees(verseId, REWARD_RECEIVER);

        assertEq(polend.preRedeemPTFeeCallCount(), 0, "zero backing pt not pre-redeemed");
        assertEq(govFee, 3 ether, "uAsset fee still distributed");
        assertEq(memecoinFee, 0, "memecoinFee");
        assertEq(liquidProofFee, 0, "liquidProofFee");
        assertEq(executorReward, 0, "executorReward");
        assertEq(uAsset.balanceOf(address(dispatcher)), 3 ether, "uAsset to dispatcher");
        assertEq(dispatcher.composeCallCount(), 1, "compose called");
        (uint256 pendingUAssetFee, uint256 pendingPTFee) = launcher.pendingAuxiliaryGovFeeStates(verseId);
        assertEq(pendingUAssetFee, 0, "uAsset pending cleared");
        assertEq(pendingPTFee, 1, "pt pending unchanged");
    }

    function testRedeemAndDistributeFees_AfterUnlockRedeemsPendingPTFeeThroughSplitter() external {
        uint256 verseId = 30;
        _setUnlockedVerse(verseId);
        launcher.setPendingAuxiliaryGovFeeForTest(verseId, 0, 7 ether);
        pt.mint(address(launcher), 7 ether);

        launcher.redeemAndDistributeFees(verseId, REWARD_RECEIVER);

        assertEq(splitter.redeemPTCallCount(), 1, "redeemPT called");
        assertEq(splitter.lastRedeemPTVerseId(), verseId, "verse id");
        assertEq(splitter.lastRedeemPTAmount(), 7 ether, "pt amount");
        assertEq(splitter.lastRedeemPTTo(), address(dispatcher), "redeem receiver");
        assertEq(polend.preRedeemPTFeeCallCount(), 0, "no preRedeem after unlock");
        assertEq(pt.balanceOf(address(0xCAFE)), 0, "no raw pt to governor");
        assertEq(uAsset.balanceOf(address(0xCAFE)), 0, "no direct uAsset to governor");
        assertEq(uAsset.balanceOf(address(dispatcher)), 7 ether, "uAsset to dispatcher");
        assertEq(dispatcher.composeCallCount(), 1, "compose called");
        (, uint256 pendingPTFee) = launcher.pendingAuxiliaryGovFeeStates(verseId);
        assertEq(pendingPTFee, 0, "pending pt cleared after redeem");
    }

    /// @notice Test redeem and distribute fees local path with only gov fee skips memecoin dispatch.
    /// @dev Confirms the local path keeps dispatcher fees aligned with the available memecoin/governance splits.
    function testRedeemAndDistributeFees_LocalPathWithOnlyGovFeeSkipsMemecoinDispatch() external {
        uint256 verseId = 15;
        _setLockedVerse(verseId);

        router.setClaimQuote(address(memecoin), address(uAsset), address(launcher), 9 ether, 0);
        router.setClaimQuote(address(liquidProof), address(uAsset), address(launcher), 0, 0);

        (uint256 govFee, uint256 memecoinFee,, uint256 executorReward) =
            launcher.redeemAndDistributeFees(verseId, REWARD_RECEIVER);

        assertGt(govFee, 0);
        assertEq(memecoinFee, 0);
        assertGt(executorReward, 0);
        assertEq(dispatcher.composeCallCount(), 1);
        assertEq(dispatcher.lastToken(), address(uAsset));
    }

    /// @notice Verifies local fee redemption rejects accidental native value.
    /// @dev Prevents stray ETH from being trapped in the launcher on same-chain paths.
    function testRedeemAndDistributeFees_LocalPathRevertsWhenMsgValueProvided() external {
        uint256 verseId = 25;
        _setLockedVerse(verseId);

        router.setClaimQuote(address(memecoin), address(uAsset), address(launcher), 9 ether, 0);
        router.setClaimQuote(address(liquidProof), address(uAsset), address(launcher), 0, 0);

        vm.expectRevert(abi.encodeWithSelector(IMemeverseLauncher.InvalidLzFee.selector, 0, 1));
        launcher.redeemAndDistributeFees{value: 1}(verseId, REWARD_RECEIVER);
    }

    /// @notice Test redeem and distribute fees local path with only memecoin fee skips gov dispatch.
    /// @dev Verifies executor rewards and gov dispatch are zero when only memecoin fees exist locally.
    function testRedeemAndDistributeFees_LocalPathWithOnlyMemecoinFeeSkipsGovDispatch() external {
        uint256 verseId = 16;
        _setLockedVerse(verseId);
        launcher.setExecutorRewardRate(0);

        router.setClaimQuote(address(memecoin), address(uAsset), address(launcher), 0, 5 ether);
        router.setClaimQuote(address(liquidProof), address(uAsset), address(launcher), 0, 0);

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

        router.setClaimQuote(address(memecoin), address(uAsset), address(launcher), 20 ether, 7 ether);
        router.setClaimQuote(address(liquidProof), address(uAsset), address(launcher), 12 ether, 5 ether);

        (uint256 govFee, uint256 memecoinFee, uint256 liquidProofFee, uint256 executorReward) =
            launcher.redeemAndDistributeFees(verseId, REWARD_RECEIVER);

        assertEq(memecoinFee, 7 ether, "memecoin fee");
        assertEq(liquidProofFee, 5 ether, "liquid proof fee");
        assertEq(executorReward, 0.05 ether, "executor reward");
        assertEq(govFee, 31.95 ether, "gov fee");

        assertEq(uAsset.balanceOf(REWARD_RECEIVER), executorReward, "reward receiver uAsset");
        assertEq(uAsset.balanceOf(address(dispatcher)), govFee, "dispatcher uAsset");
        assertEq(uAsset.balanceOf(address(0xCAFE)), 0, "no direct governor uAsset");
        assertEq(pt.balanceOf(address(0xCAFE)), 0, "no raw pt to governor");
        assertEq(memecoin.balanceOf(address(dispatcher)), memecoinFee, "dispatcher memecoin");
        assertEq(liquidProof.burnedAmount(), liquidProofFee, "burned liquid proof");
        assertEq(dispatcher.composeCallCount(), 2, "compose call count");
        assertEq(uAsset.balanceOf(address(launcher)), 0, "launcher uAsset");
        assertEq(memecoin.balanceOf(address(launcher)), 0, "launcher memecoin");
        assertEq(liquidProof.balanceOf(address(launcher)), 0, "launcher liquid proof");
    }

    /// @notice Verifies preview fee mapping matches actual redemption fee mapping.
    /// @dev Prevents preview and claim flows from drifting on token ordering.
    function testPreviewAndRedeemShareTheSameFeeMapping() external {
        uint256 verseId = 1;
        _setLockedVerse(verseId);

        router.setPreviewQuote(address(memecoin), address(uAsset), address(launcher), 9 ether, 4 ether);
        router.setPreviewQuote(address(liquidProof), address(uAsset), address(launcher), 13 ether, 6 ether);
        router.setClaimQuote(address(memecoin), address(uAsset), address(launcher), 9 ether, 4 ether);
        router.setClaimQuote(address(liquidProof), address(uAsset), address(launcher), 13 ether, 6 ether);

        (uint256 previewUAssetFee, uint256 previewMemecoinFee) = launcher.previewGenesisMakerFees(verseId);
        (uint256 govFee, uint256 memecoinFee,, uint256 executorReward) =
            launcher.redeemAndDistributeFees(verseId, REWARD_RECEIVER);

        assertEq(previewMemecoinFee, memecoinFee, "memecoin mapping");
        assertEq(previewUAssetFee, govFee + executorReward + uAsset.balanceOf(address(0xCAFE)), "uAsset mapping");
    }

    /// @notice Verifies memecoin LP redemption rejects zero POL input.
    /// @dev Confirms the restored zero-input guard is active.
    function testRedeemMemecoinLiquidity_RevertsOnZeroInput() external {
        uint256 verseId = 1;
        _setUnlockedVerse(verseId);

        vm.expectRevert(IMemeverseLauncher.ZeroInput.selector);
        launcher.redeemMemecoinLiquidity(verseId, 0, false);
    }

    /// @notice Verifies memecoin LP redemption rejects non-unlocked verses.
    /// @dev Confirms the restored stage guard is active for memecoin LP claims.
    function testRedeemMemecoinLiquidity_RevertsWhenNotUnlocked() external {
        uint256 verseId = 1;
        _setLockedVerse(verseId);

        vm.expectRevert(IMemeverseLauncher.NotUnlockedStage.selector);
        launcher.redeemMemecoinLiquidity(verseId, 1 ether, false);
    }

    /// @notice Verifies memecoin LP redemption burns POL and transfers pair LP shares.
    /// @dev Covers the restored router-based pair LP lookup in the happy path.
    function testRedeemMemecoinLiquidity_BurnsPOLAndTransfersMemecoinLp() external {
        uint256 verseId = 1;
        _setUnlockedVerse(verseId);
        IMemeverseLauncher.Memeverse memory verse = launcher.getMemeverseByVerseId(verseId);
        address verseMemecoin = verse.memecoin;
        address verseUAsset = verse.uAsset;
        MockERC20 memecoinLp = new MockERC20("MEME-LP", "MEME-LP", 18);
        router.setLpToken(address(verseMemecoin), address(verseUAsset), address(memecoinLp));
        memecoinLp.mint(address(launcher), 10 ether);
        liquidProof.mint(ALICE, 10 ether);

        vm.prank(ALICE);
        uint256 amountInLP = launcher.redeemMemecoinLiquidity(verseId, 4 ether, false);

        assertEq(amountInLP, 4 ether, "lp amount");
        assertEq(liquidProof.burnedAmount(), 4 ether, "burned pol");
        assertEq(liquidProof.balanceOf(ALICE), 6 ether, "alice pol balance");
        assertEq(memecoinLp.balanceOf(ALICE), 4 ether, "alice memecoin lp");
        assertEq(memecoinLp.balanceOf(address(launcher)), 6 ether, "launcher memecoin lp");
    }

    /// @notice Verifies memecoin LP redemption can unwrap into underlying assets.
    /// @dev Covers the new launcher overload wired for splitter settlement.
    function testRedeemMemecoinLiquidity_UnwrapsUnderlyingWhenRequested() external {
        uint256 verseId = 1;
        _setUnlockedVerse(verseId);

        MockERC20 memecoinLp = new MockERC20("MEME-LP", "MEME-LP", 18);
        router.setLpToken(address(memecoin), address(uAsset), address(memecoinLp));
        router.setRemoveLiquidityResult(address(memecoin), address(uAsset), 3 ether, 5 ether);
        memecoinLp.mint(address(launcher), 10 ether);
        liquidProof.mint(ALICE, 10 ether);

        vm.prank(ALICE);
        uint256 amountInLP = launcher.redeemMemecoinLiquidity(verseId, 4 ether, true);

        uint256 expectedMemecoinAmount = address(memecoin) < address(uAsset) ? 3 ether : 5 ether;
        uint256 expectedUAssetAmount = address(memecoin) < address(uAsset) ? 5 ether : 3 ether;

        assertEq(amountInLP, 4 ether, "lp amount");
        assertEq(liquidProof.burnedAmount(), 4 ether, "burned pol");
        assertEq(memecoin.balanceOf(ALICE), expectedMemecoinAmount, "alice memecoin");
        assertEq(uAsset.balanceOf(ALICE), expectedUAssetAmount, "alice uAsset");
        assertEq(memecoinLp.balanceOf(address(launcher)), 6 ether, "launcher memecoin lp");
    }

    function testRedeemMemecoinLiquidity_UnwrapKeepsInfiniteLpAllowanceForRouter() external {
        uint256 verseId = 1;
        _setUnlockedVerse(verseId);

        MockERC20 memecoinLp = new MockERC20("MEME-LP", "MEME-LP", 18);
        router.setLpToken(address(memecoin), address(uAsset), address(memecoinLp));
        router.setRemoveLiquidityResult(address(memecoin), address(uAsset), 3 ether, 5 ether);
        memecoinLp.mint(address(launcher), 10 ether);
        liquidProof.mint(ALICE, 10 ether);

        vm.startPrank(ALICE);
        launcher.redeemMemecoinLiquidity(verseId, 4 ether, true);
        launcher.redeemMemecoinLiquidity(verseId, 2 ether, true);
        vm.stopPrank();

        assertEq(
            memecoinLp.allowance(address(launcher), address(router)),
            0,
            "launcher LP allowance consumed after exact approval"
        );
        assertEq(memecoinLp.balanceOf(address(launcher)), 4 ether, "launcher memecoin lp");
    }

    function testRedeemMemecoinLiquidity_AllowsSplitterSettlementWhilePaused() external {
        uint256 verseId = 1;
        _setUnlockedVerse(verseId);

        MockERC20 memecoinLp = new MockERC20("MEME-LP", "MEME-LP", 18);
        router.setLpToken(address(memecoin), address(uAsset), address(memecoinLp));
        router.setRemoveLiquidityResult(address(memecoin), address(uAsset), 3 ether, 5 ether);
        memecoinLp.mint(address(launcher), 10 ether);
        liquidProof.mint(address(splitter), 10 ether);
        launcher.pause();

        vm.prank(address(splitter));
        uint256 amountInLP = launcher.redeemMemecoinLiquidity(verseId, 4 ether, true);

        assertEq(amountInLP, 4 ether, "lp amount");
        assertEq(liquidProof.burnedAmount(), 4 ether, "burned pol");
    }

    function testRedeemMemecoinLiquidity_AllowsUserPathWhilePaused() external {
        uint256 verseId = 1;
        _setUnlockedVerse(verseId);
        MockERC20 memecoinLp = new MockERC20("MEME-LP", "MEME-LP", 18);
        router.setLpToken(address(memecoin), address(uAsset), address(memecoinLp));
        memecoinLp.mint(address(launcher), 10 ether);
        liquidProof.mint(ALICE, 10 ether);
        launcher.pause();

        vm.prank(ALICE);
        uint256 amountInLP = launcher.redeemMemecoinLiquidity(verseId, 4 ether, false);

        assertEq(amountInLP, 4 ether, "lp amount");
        assertEq(liquidProof.burnedAmount(), 4 ether, "burned pol");
        assertEq(memecoinLp.balanceOf(ALICE), 4 ether, "alice memecoin lp");
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
        router.setLpToken(address(memecoin), address(uAsset), address(memecoinLp));
        memecoinLp.mint(address(launcher), 10 ether);
        liquidProof.mint(ALICE, 10 ether);

        vm.prank(ALICE);
        uint256 amountInLP = launcher.redeemMemecoinLiquidity(verseId, 4 ether, false);

        assertEq(amountInLP, 4 ether, "lp amount");
        assertEq(memecoinLp.balanceOf(ALICE), 4 ether, "alice memecoin lp");
    }

    /// @notice Test redeem memecoin liquidity reverts when launcher lp balance insufficient.
    /// @dev Ensures the contract only transfers LP when it holds enough balance.
    function testRedeemMemecoinLiquidity_RevertsWhenLauncherLpBalanceInsufficient() external {
        uint256 verseId = 12;
        _setUnlockedVerse(verseId);

        MockERC20 memecoinLp = new MockERC20("MEME-LP", "MEME-LP", 18);
        router.setLpToken(address(memecoin), address(uAsset), address(memecoinLp));
        liquidProof.mint(ALICE, 10 ether);

        vm.prank(ALICE);
        vm.expectRevert(IMemeverseLauncher.InsufficientLPBalance.selector);
        launcher.redeemMemecoinLiquidity(verseId, 4 ether, false);
    }

    /// @notice Verifies auxiliary liquidity redemption rejects non-unlocked verses.
    /// @dev Confirms the new auxiliary exit only opens after unlock.
    function testRedeemAuxiliaryLiquidity_RevertsWhenNotUnlocked() external {
        uint256 verseId = 1;
        _setLockedVerse(verseId);
        launcher.setUserGenesisDataForTest(verseId, ALICE, 1 ether, false, false);

        vm.prank(ALICE);
        vm.expectRevert(IMemeverseLauncher.NotUnlockedStage.selector);
        launcher.redeemAuxiliaryLiquidity(verseId);
    }

    /// @notice Verifies auxiliary liquidity redemption rejects accounts that already redeemed.
    /// @dev Confirms the shared redeemed flag still gates the new exit path.
    function testRedeemAuxiliaryLiquidity_RevertsWhenAlreadyRedeemed() external {
        uint256 verseId = 1;
        _setUnlockedVerse(verseId);
        launcher.setUserGenesisDataForTest(verseId, ALICE, 1 ether, false, true);

        vm.prank(ALICE);
        vm.expectRevert(IMemeverseLauncher.InvalidClaim.selector);
        launcher.redeemAuxiliaryLiquidity(verseId);
    }

    /// @notice Verifies auxiliary liquidity redemption transfers all three auxiliary LP tokens pro rata.
    /// @dev Asserts the launcher sends LP shares directly without unwrapping or reducing recorded liquidity.
    function testRedeemAuxiliaryLiquidity_TransfersShareAcrossAuxiliaryPools() external {
        uint256 verseId = 1;
        _setUnlockedVerse(verseId);
        launcher.setGenesisFundForTest(verseId, 120 ether);
        launcher.setUserGenesisDataForTest(verseId, ALICE, 24 ether, false, false);
        launcher.setAuxiliaryLiquiditiesForTest(verseId, 60 ether, 30 ether, 90 ether);
        polUAssetLp.mint(address(launcher), 60 ether);
        ptUAssetLp.mint(address(launcher), 30 ether);
        ptPolLp.mint(address(launcher), 90 ether);

        vm.prank(ALICE);
        (uint256 polUAssetLpAmount, uint256 ptUAssetLpAmount, uint256 ptPolLpAmount) =
            launcher.redeemAuxiliaryLiquidity(verseId);

        (, bool isRefunded, bool isRedeemed) = launcher.userGenesisData(verseId, ALICE);
        assertEq(polUAssetLpAmount, 12 ether, "pol/uAsset lp amount");
        assertEq(ptUAssetLpAmount, 6 ether, "pt/uAsset lp amount");
        assertEq(ptPolLpAmount, 18 ether, "pt/pol lp amount");
        assertEq(polUAssetLp.balanceOf(ALICE), 12 ether, "alice pol/uAsset lp");
        assertEq(ptUAssetLp.balanceOf(ALICE), 6 ether, "alice pt/uAsset lp");
        assertEq(ptPolLp.balanceOf(ALICE), 18 ether, "alice pt/pol lp");
        assertEq(
            uint256(router.lastRemoveLiquidityAmount(address(liquidProof), address(uAsset))), 0, "no pol/uAsset unwrap"
        );
        assertEq(uint256(router.lastRemoveLiquidityAmount(address(pt), address(uAsset))), 0, "no pt/uAsset unwrap");
        assertEq(uint256(router.lastRemoveLiquidityAmount(address(pt), address(liquidProof))), 0, "no pt/pol unwrap");
        (uint256 remainingPolUAssetLp, uint256 remainingPtUAssetLp, uint256 remainingPtPolLp) =
            launcher.auxiliaryLiquidities(verseId);
        assertEq(remainingPolUAssetLp, 60 ether, "recorded pol/uAsset lp unchanged");
        assertEq(remainingPtUAssetLp, 30 ether, "recorded pt/uAsset lp unchanged");
        assertEq(remainingPtPolLp, 90 ether, "recorded pt/pol lp unchanged");
        assertFalse(isRefunded, "is refunded");
        assertTrue(isRedeemed, "is redeemed");
    }

    function testRedeemAuxiliaryLiquidity_UserCanRedeemLpWhenCalledThroughRouterAddress() external {
        uint256 verseId = 23;
        _setUnlockedVerse(verseId);
        launcher.setGenesisFundForTest(verseId, 120 ether);
        launcher.setUserGenesisDataForTest(verseId, address(router), 24 ether, false, false);
        launcher.setAuxiliaryLiquiditiesForTest(verseId, 60 ether, 30 ether, 90 ether);
        polUAssetLp.mint(address(launcher), 60 ether);
        ptUAssetLp.mint(address(launcher), 30 ether);
        ptPolLp.mint(address(launcher), 90 ether);

        (uint256 polUAssetLpAmount,,) = router.redeemAuxiliary(address(launcher), verseId);

        (,, bool isRedeemed) = launcher.userGenesisData(verseId, address(router));
        assertEq(polUAssetLpAmount, 12 ether, "lp amount");
        assertEq(polUAssetLp.balanceOf(address(router)), 12 ether, "router lp");
        assertTrue(isRedeemed, "redeemed");
    }

    function testRedeemAuxiliaryLiquidity_DoesNotCallRouterRemoveLiquidity() external {
        uint256 verseId = 24;
        _setUnlockedVerse(verseId);
        launcher.setGenesisFundForTest(verseId, 120 ether);
        launcher.setUserGenesisDataForTest(verseId, ALICE, 24 ether, false, false);
        launcher.setAuxiliaryLiquiditiesForTest(verseId, 60 ether, 30 ether, 90 ether);
        polUAssetLp.mint(address(launcher), 60 ether);
        ptUAssetLp.mint(address(launcher), 30 ether);
        ptPolLp.mint(address(launcher), 90 ether);

        vm.prank(ALICE);
        (uint256 polUAssetLpAmount,,) = launcher.redeemAuxiliaryLiquidity(verseId);

        assertEq(polUAssetLpAmount, 12 ether, "lp amount");
        assertEq(
            uint256(router.lastRemoveLiquidityAmount(address(liquidProof), address(uAsset))), 0, "remove not called"
        );
    }

    /// @notice Verifies auxiliary liquidity remains redeemable during the post-unlock protection window.
    /// @dev The public-swap cooldown must not block auxiliary exits once the stage is unlocked.
    function testRedeemAuxiliaryLiquidity_AllowsDuringPostUnlockProtectionWindow() external {
        uint256 verseId = 22;
        _setUnlockedVerse(verseId);
        IMemeverseLauncher.Memeverse memory verse = launcher.getMemeverseByVerseId(verseId);
        verse.unlockTime = uint128(block.timestamp);
        launcher.setMemeverseForTest(verseId, verse);
        launcher.setGenesisFundForTest(verseId, 120 ether);
        launcher.setUserGenesisDataForTest(verseId, ALICE, 24 ether, false, false);
        launcher.setAuxiliaryLiquiditiesForTest(verseId, 60 ether, 30 ether, 90 ether);
        polUAssetLp.mint(address(launcher), 60 ether);
        ptUAssetLp.mint(address(launcher), 30 ether);
        ptPolLp.mint(address(launcher), 90 ether);

        vm.prank(ALICE);
        (uint256 polAmount,,) = launcher.redeemAuxiliaryLiquidity(verseId);

        assertEq(polAmount, 12 ether, "pol/uAsset lp amount");
    }

    function testRedeemAuxiliaryLiquidity_DistributesNormalBootstrapResiduals() external {
        uint256 verseId = 23;
        _setUnlockedVerse(verseId);
        launcher.setGenesisFundForTest(verseId, 120 ether);
        launcher.setUserGenesisDataForTest(verseId, ALICE, 24 ether, false, false);
        launcher.setAuxiliaryLiquiditiesForTest(verseId, 60 ether, 30 ether, 90 ether);
        launcher.setBootstrapResidualClaimsForTest(verseId, 25 ether, 10 ether, 0, 0);
        polUAssetLp.mint(address(launcher), 60 ether);
        ptUAssetLp.mint(address(launcher), 30 ether);
        ptPolLp.mint(address(launcher), 90 ether);
        liquidProof.mint(address(launcher), 25 ether);
        pt.mint(address(launcher), 10 ether);

        uint256 alicePolBefore = liquidProof.balanceOf(ALICE);
        uint256 alicePtBefore = pt.balanceOf(ALICE);

        vm.prank(ALICE);
        launcher.redeemAuxiliaryLiquidity(verseId);

        assertEq(liquidProof.balanceOf(ALICE) - alicePolBefore, 5 ether, "normal residual pol");
        assertEq(pt.balanceOf(ALICE) - alicePtBefore, 2 ether, "normal residual pt");
    }

    /// @notice Verifies auxiliary liquidity redemption rejects users without a genesis share.
    /// @dev Keeps the new exit path aligned with the old invalid-redeem guard.
    function testRedeemAuxiliaryLiquidity_RevertsWhenUserHasNoShare() external {
        uint256 verseId = 13;
        _setUnlockedVerse(verseId);

        vm.prank(ALICE);
        vm.expectRevert(IMemeverseLauncher.InvalidClaim.selector);
        launcher.redeemAuxiliaryLiquidity(verseId);
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
        verse.uAsset = address(uAsset);
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
        launcher.claimNormalYT(invalidVerseId);

        vm.expectRevert(IMemeverseLauncher.InvalidVerseId.selector);
        launcher.claimUnlockedPreorderMemecoin(invalidVerseId);

        vm.expectRevert(IMemeverseLauncher.InvalidVerseId.selector);
        launcher.redeemAndDistributeFees(invalidVerseId, REWARD_RECEIVER);

        vm.expectRevert(IMemeverseLauncher.InvalidVerseId.selector);
        launcher.redeemMemecoinLiquidity(invalidVerseId, 1 ether, false);

        vm.expectRevert(IMemeverseLauncher.InvalidVerseId.selector);
        launcher.redeemAuxiliaryLiquidity(invalidVerseId);

        vm.expectRevert(IMemeverseLauncher.InvalidVerseId.selector);
        launcher.mintPOLToken(invalidVerseId, 1 ether, 1 ether, 0, 0, 0, block.timestamp);
    }

    /// @notice Verifies automatic liquidity minting refunds unused inputs and mints matching POL.
    /// @dev Covers the `amountOutDesired == 0` router path to ensure refunds happen before LP minting.
    function testMintPOLToken_WithAutoLiquidity_RefundsUnusedInputsAndMintsPol() external {
        uint256 verseId = 1;
        _setLockedVerse(verseId);

        MockERC20 memecoinLp = new MockERC20("MEME-LP", "MEME-LP", 18);
        router.setLpToken(address(memecoin), address(uAsset), address(memecoinLp));
        router.setAddLiquidityResult(address(uAsset), address(memecoin), 8 ether, 6 ether, 10 ether);
        splitter.setPreviewPTToUAssetResult(6 ether);

        uAsset.mint(ALICE, 9 ether);
        memecoin.mint(ALICE, 13 ether);
        _approveMintInputs(ALICE);

        vm.prank(ALICE);
        (uint256 amountInUAsset, uint256 amountInMemecoin, uint256 amountOut) =
            launcher.mintPOLToken(verseId, 9 ether, 13 ether, 5 ether, 8 ether, 0, block.timestamp);

        assertEq(amountInUAsset, 6 ether, "uAsset used");
        assertEq(amountInMemecoin, 10 ether, "memecoin used");
        assertEq(amountOut, 8 ether, "pol out");
        assertEq(uAsset.balanceOf(ALICE), 3 ether, "uAsset refund");
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
        router.setLpToken(address(memecoin), address(uAsset), address(memecoinLp));
        router.setAddLiquidityResult(address(uAsset), address(memecoin), 8 ether, 6 ether, 10 ether);
        splitter.setPreviewPTToUAssetResult(6 ether);

        MintPolRefundObserver observer = new MintPolRefundObserver(
            launcher, IERC20(address(uAsset)), IERC20(address(memecoin)), IERC20(address(liquidProof)), verseId
        );
        callbackMemecoin.setCallbackTarget(address(observer));

        uAsset.mint(address(observer), 9 ether);
        memecoin.mint(address(observer), 13 ether);
        observer.approveLauncher();

        (uint256 amountInUAsset, uint256 amountInMemecoin, uint256 amountOut) =
            observer.executeMintPOLToken(9 ether, 13 ether, 5 ether, 8 ether, 0, block.timestamp);

        assertEq(amountInUAsset, 6 ether, "uAsset used");
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
        router.setLpToken(address(memecoin), address(uAsset), address(memecoinLp));
        router.setExactQuoteAmountsForLiquidity(address(uAsset), address(memecoin), 5 ether, 10 ether, 12 ether);
        router.setAddLiquidityResult(address(uAsset), address(memecoin), 5 ether, 7 ether, 9 ether);
        splitter.setPreviewPTToUAssetResult(7 ether);

        uAsset.mint(ALICE, 10 ether);
        memecoin.mint(ALICE, 12 ether);
        _approveMintInputs(ALICE);

        vm.prank(ALICE);
        (uint256 amountInUAsset, uint256 amountInMemecoin, uint256 amountOut) =
            launcher.mintPOLToken(verseId, 10 ether, 12 ether, 0, 0, 5 ether, block.timestamp);

        assertEq(amountInUAsset, 7 ether, "uAsset used");
        assertEq(amountInMemecoin, 9 ether, "memecoin used");
        assertEq(amountOut, 5 ether, "pol out");
        assertEq(uAsset.balanceOf(ALICE), 3 ether, "uAsset refund");
        assertEq(memecoin.balanceOf(ALICE), 3 ether, "memecoin refund");
        assertEq(liquidProof.balanceOf(ALICE), 5 ether, "alice pol");
        assertEq(memecoinLp.balanceOf(address(launcher)), 5 ether, "launcher lp");
        assertEq(router.addLiquidityDetailedCallCount(), 1, "detailed addLiquidity used");
    }

    function testMintPOLToken_MintsWhenPTBackingPreviewExceedsActualUAssetSpend() external {
        uint256 verseId = 1;
        _setLockedVerse(verseId);

        router.setExactQuoteAmountsForLiquidity(address(uAsset), address(memecoin), 5 ether, 10 ether, 12 ether);
        router.setAddLiquidityResult(address(uAsset), address(memecoin), 5 ether, 10 ether, 12 ether);
        splitter.setPreviewPTToUAssetResult(10 ether + 2);

        uAsset.mint(ALICE, 10 ether);
        memecoin.mint(ALICE, 12 ether);
        _approveMintInputs(ALICE);

        vm.prank(ALICE);
        (uint256 amountInUAsset,, uint256 amountOut) =
            launcher.mintPOLToken(verseId, 10 ether, 12 ether, 0, 0, 5 ether, block.timestamp);

        assertEq(amountInUAsset, 10 ether, "uAsset used");
        assertEq(amountOut, 5 ether, "pol out");
        assertEq(liquidProof.balanceOf(ALICE), 5 ether, "alice pol");
    }

    function testMintPOLToken_MintsWhenPTBackingPreviewExceedsActualUAssetSpendByOneWei() external {
        uint256 verseId = 1;
        _setLockedVerse(verseId);

        router.setExactQuoteAmountsForLiquidity(address(uAsset), address(memecoin), 5 ether, 10 ether, 12 ether);
        router.setAddLiquidityResult(address(uAsset), address(memecoin), 5 ether, 10 ether, 12 ether);
        splitter.setPreviewPTToUAssetResult(10 ether + 1);

        uAsset.mint(ALICE, 10 ether);
        memecoin.mint(ALICE, 12 ether);
        _approveMintInputs(ALICE);

        vm.prank(ALICE);
        (uint256 amountInUAsset,, uint256 amountOut) =
            launcher.mintPOLToken(verseId, 10 ether, 12 ether, 0, 0, 5 ether, block.timestamp);

        assertEq(amountInUAsset, 10 ether, "uAsset used");
        assertEq(amountOut, 5 ether, "pol out");
        assertEq(liquidProof.balanceOf(ALICE), 5 ether, "alice pol");
    }

    function testMintPOLToken_MintsWhenPTBackingPreviewIsBelowActualUAssetSpend() external {
        uint256 verseId = 1;
        _setLockedVerse(verseId);

        router.setExactQuoteAmountsForLiquidity(address(uAsset), address(memecoin), 5 ether, 10 ether, 12 ether);
        router.setAddLiquidityResult(address(uAsset), address(memecoin), 5 ether, 10 ether, 12 ether);
        splitter.setPreviewPTToUAssetResult(8 ether);

        uAsset.mint(ALICE, 10 ether);
        memecoin.mint(ALICE, 12 ether);
        _approveMintInputs(ALICE);

        vm.prank(ALICE);
        (uint256 amountInUAsset,, uint256 amountOut) =
            launcher.mintPOLToken(verseId, 10 ether, 12 ether, 0, 0, 5 ether, block.timestamp);

        assertEq(amountInUAsset, 10 ether, "uAsset used");
        assertEq(amountOut, 5 ether, "pol out");
        assertEq(liquidProof.balanceOf(ALICE), 5 ether, "alice pol");
    }

    function testMintPOLToken_MintsWhenPTBackingPreviewMatchesActualUAssetSpend() external {
        uint256 verseId = 1;
        _setLockedVerse(verseId);

        MockERC20 memecoinLp = new MockERC20("MEME-LP", "MEME-LP", 18);
        router.setLpToken(address(memecoin), address(uAsset), address(memecoinLp));
        router.setExactQuoteAmountsForLiquidity(address(uAsset), address(memecoin), 5 ether, 10 ether, 12 ether);
        router.setAddLiquidityResult(address(uAsset), address(memecoin), 5 ether, 10 ether, 12 ether);
        splitter.setPreviewPTToUAssetResult(10 ether);

        uAsset.mint(ALICE, 10 ether);
        memecoin.mint(ALICE, 12 ether);
        _approveMintInputs(ALICE);

        vm.prank(ALICE);
        (uint256 amountInUAsset,, uint256 amountOut) =
            launcher.mintPOLToken(verseId, 10 ether, 12 ether, 0, 0, 5 ether, block.timestamp);

        assertEq(amountInUAsset, 10 ether, "uAsset used");
        assertEq(amountOut, 5 ether, "pol out");
        assertEq(liquidProof.balanceOf(ALICE), 5 ether, "alice pol");
    }

    function testMintPOLToken_MintsWhenPTBackingPreviewIsOneWeiBelowActualUAssetSpend() external {
        uint256 verseId = 1;
        _setLockedVerse(verseId);

        router.setExactQuoteAmountsForLiquidity(address(uAsset), address(memecoin), 5 ether, 10 ether, 12 ether);
        router.setAddLiquidityResult(address(uAsset), address(memecoin), 5 ether, 10 ether, 12 ether);
        splitter.setPreviewPTToUAssetResult(10 ether - 1);

        uAsset.mint(ALICE, 10 ether);
        memecoin.mint(ALICE, 12 ether);
        _approveMintInputs(ALICE);

        vm.prank(ALICE);
        (uint256 amountInUAsset,, uint256 amountOut) =
            launcher.mintPOLToken(verseId, 10 ether, 12 ether, 0, 0, 5 ether, block.timestamp);

        assertEq(amountInUAsset, 10 ether, "uAsset used");
        assertEq(amountOut, 5 ether, "pol out");
        assertEq(liquidProof.balanceOf(ALICE), 5 ether, "alice pol");
    }

    /// @notice Verifies exact-liquidity minting fails closed when budgets cannot mint the requested POL amount.
    /// @dev Confirms the launcher no longer treats a padded quote as a hard budget gate and instead checks actual output.
    function testMintPOLToken_WithExactLiquidity_RevertsWhenDetailedLiquidityUnderMints() external {
        uint256 verseId = 1;
        _setLockedVerse(verseId);

        router.setExactQuoteAmountsForLiquidity(address(uAsset), address(memecoin), 5 ether, 10 ether, 12 ether);
        uAsset.mint(ALICE, 10 ether);
        memecoin.mint(ALICE, 12 ether);
        _approveMintInputs(ALICE);
        router.setAddLiquidityResult(address(uAsset), address(memecoin), 4 ether, 7 ether, 9 ether);

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
        router.setLpToken(address(memecoin), address(uAsset), address(memecoinLp));
        router.setExactQuoteAmountsForLiquidity(address(uAsset), address(memecoin), 5 ether, 10 ether, 12 ether);
        router.setAddLiquidityResult(address(uAsset), address(memecoin), 5 ether, 10 ether, 12 ether);
        splitter.setPreviewPTToUAssetResult(10 ether);

        uAsset.mint(ALICE, 10 ether);
        memecoin.mint(ALICE, 12 ether);
        _approveMintInputs(ALICE);

        vm.prank(ALICE);
        (uint256 amountInUAsset, uint256 amountInMemecoin, uint256 amountOut) =
            launcher.mintPOLToken(verseId, 10 ether, 12 ether, 0, 0, 5 ether, block.timestamp);

        assertEq(amountInUAsset, 10 ether);
        assertEq(amountInMemecoin, 12 ether);
        assertEq(amountOut, 5 ether);
        assertEq(uAsset.balanceOf(ALICE), 0);
        assertEq(memecoin.balanceOf(ALICE), 0);
    }

    /// @notice Verifies exact-liquidity minting uses the exact quote path even when the padded quote exceeds budget.
    /// @dev Proves `quoteAmountsForLiquidity(...)` no longer blocks exact-liquidity mints when `quoteExact...` fits.
    function testMintPOLToken_WithExactLiquidity_IgnoresPaddedQuoteBudgetOverrun() external {
        uint256 verseId = 19;
        _setLockedVerse(verseId);

        MockERC20 memecoinLp = new MockERC20("MEME-LP", "MEME-LP", 18);
        router.setLpToken(address(memecoin), address(uAsset), address(memecoinLp));
        router.setQuoteAmountsForLiquidity(address(uAsset), address(memecoin), 5 ether, 11 ether, 13 ether);
        router.setExactQuoteAmountsForLiquidity(address(uAsset), address(memecoin), 5 ether, 10 ether, 12 ether);
        router.setAddLiquidityResult(address(uAsset), address(memecoin), 5 ether, 10 ether, 12 ether);
        splitter.setPreviewPTToUAssetResult(10 ether);

        uAsset.mint(ALICE, 10 ether);
        memecoin.mint(ALICE, 12 ether);
        _approveMintInputs(ALICE);

        vm.prank(ALICE);
        (uint256 amountInUAsset, uint256 amountInMemecoin, uint256 amountOut) =
            launcher.mintPOLToken(verseId, 10 ether, 12 ether, 0, 0, 5 ether, block.timestamp);

        assertEq(amountInUAsset, 10 ether, "exact uAsset used");
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
