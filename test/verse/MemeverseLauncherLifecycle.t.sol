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
import {SwapParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta, toBalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";

import {MemeverseLauncher} from "../../src/verse/MemeverseLauncher.sol";
import {IMemeverseLauncher} from "../../src/verse/interfaces/IMemeverseLauncher.sol";
import {IMemeverseSwapRouter} from "../../src/swap/interfaces/IMemeverseSwapRouter.sol";

contract MockSwapRouter {
    using SafeERC20 for IERC20;
    bytes32 internal constant LAUNCH_SETTLEMENT_HOOKDATA_HASH = keccak256("memeverse.launch-settlement.hookdata");

    struct Quote {
        uint256 fee0;
        uint256 fee1;
    }

    struct AddLiquidityResult {
        uint128 liquidity;
        uint256 amount0Used;
        uint256 amount1Used;
    }

    struct LaunchSwapResult {
        uint256 amountIn;
        uint256 amountOut;
    }

    mapping(bytes32 => Quote) internal previewQuotes;
    mapping(bytes32 => Quote) internal claimQuotes;
    mapping(bytes32 => address) internal lpTokens;
    mapping(bytes32 => AddLiquidityResult) internal addLiquidityResults;
    mapping(bytes32 => LaunchSwapResult) internal launchSwapResults;
    mapping(bytes32 => uint256) internal liquidityQuoteAmountA;
    mapping(bytes32 => uint256) internal liquidityQuoteAmountB;

    function _pairKey(address tokenA, address tokenB) internal pure returns (bytes32) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        return keccak256(abi.encode(token0, token1));
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
        (uint256 amount0Used, uint256 amount1Used) =
            tokenA < tokenB ? (amountAUsed, amountBUsed) : (amountBUsed, amountAUsed);
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
        liquidityQuoteAmountA[key] = amountARequired;
        liquidityQuoteAmountB[key] = amountBRequired;
    }

    /// @notice Sets the mocked launch preorder swap result for a pair.
    /// @dev Stores the input budget consumed and the memecoin amount returned to the recipient.
    /// @param tokenIn Input token used by the launch settlement swap.
    /// @param tokenOut Output token returned by the launch settlement swap.
    /// @param amountIn Mock amount of `tokenIn` consumed.
    /// @param amountOut Mock amount of `tokenOut` returned.
    function setLaunchSwapResult(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut) external {
        launchSwapResults[keccak256(abi.encode(_pairKey(tokenIn, tokenOut), tokenIn, tokenOut))] =
            LaunchSwapResult({amountIn: amountIn, amountOut: amountOut});
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
        return (liquidityQuoteAmountA[key], liquidityQuoteAmountB[key]);
    }

    /// @notice Returns a normalized mock pool key for a token pair.
    /// @dev Matches the launcher's expectations for router pool-key derivation.
    /// @param tokenA First token in the pair.
    /// @param tokenB Second token in the pair.
    /// @return key Mock pool key for the pair.
    function getHookPoolKey(address tokenA, address tokenB) external pure returns (PoolKey memory key) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        return PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: 0,
            tickSpacing: 0,
            hooks: IHooks(address(0))
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
    /// @param nativeRefundRecipient Unused native refund recipient.
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
        address nativeRefundRecipient,
        uint256 deadline
    ) external returns (uint128 liquidity) {
        amount0Desired;
        amount1Desired;
        amount0Min;
        amount1Min;
        nativeRefundRecipient;
        deadline;

        address token0 = Currency.unwrap(currency0);
        address token1 = Currency.unwrap(currency1);
        AddLiquidityResult memory result = addLiquidityResults[_pairKey(token0, token1)];
        if (result.amount0Used != 0) IERC20(token0).safeTransferFrom(msg.sender, address(this), result.amount0Used);
        if (result.amount1Used != 0) IERC20(token1).safeTransferFrom(msg.sender, address(this), result.amount1Used);

        address liquidityToken = lpTokens[_pairKey(token0, token1)];
        if (result.liquidity != 0 && liquidityToken != address(0)) {
            MockERC20(liquidityToken).mint(to, result.liquidity);
        }
        return result.liquidity;
    }

    /// @notice Executes a mocked pool bootstrap for a pair.
    /// @dev Reuses the configured add-liquidity result and returns the normalized pool key.
    /// @param tokenA First bootstrap token.
    /// @param tokenB Second bootstrap token.
    /// @param amountADesired Unused desired amount for `tokenA`.
    /// @param amountBDesired Unused desired amount for `tokenB`.
    /// @param startPrice Unused pool start price.
    /// @param recipient Recipient of mocked LP shares.
    /// @param nativeRefundRecipient Unused native refund recipient.
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
        address nativeRefundRecipient,
        uint256 deadline
    ) external returns (uint128 liquidity, PoolKey memory poolKey) {
        amountADesired;
        amountBDesired;
        startPrice;
        nativeRefundRecipient;
        deadline;

        poolKey = this.getHookPoolKey(tokenA, tokenB);
        AddLiquidityResult memory result = addLiquidityResults[_pairKey(tokenA, tokenB)];
        address liquidityToken = lpTokens[_pairKey(tokenA, tokenB)];
        if (result.liquidity != 0 && liquidityToken != address(0)) {
            MockERC20(liquidityToken).mint(recipient, result.liquidity);
        }
        return (result.liquidity, poolKey);
    }

    /// @notice Executes the mocked swap path.
    /// @dev When the launch settlement marker is provided, returns the configured preorder launch swap result.
    /// @param key Mock pool key being swapped against.
    /// @param params Mock swap params forwarded by the launcher.
    /// @param recipient Recipient of the mocked output token.
    /// @param nativeRefundRecipient Unused native refund recipient.
    /// @param deadline Unused deadline.
    /// @param amountOutMinimum Unused minimum output amount.
    /// @param amountInMaximum Unused maximum input amount.
    /// @param hookData Marker payload used to distinguish launch settlement.
    /// @return delta Mock balance delta for the launch settlement swap.
    function swap(
        PoolKey calldata key,
        SwapParams calldata params,
        address recipient,
        address nativeRefundRecipient,
        uint256 deadline,
        uint256 amountOutMinimum,
        uint256 amountInMaximum,
        bytes calldata hookData
    ) external returns (BalanceDelta delta) {
        nativeRefundRecipient;
        deadline;
        amountOutMinimum;
        amountInMaximum;

        if (keccak256(hookData) != keccak256(abi.encode(LAUNCH_SETTLEMENT_HOOKDATA_HASH))) {
            revert("unexpected hookData");
        }

        address tokenIn = params.zeroForOne ? Currency.unwrap(key.currency0) : Currency.unwrap(key.currency1);
        address tokenOut = params.zeroForOne ? Currency.unwrap(key.currency1) : Currency.unwrap(key.currency0);
        LaunchSwapResult memory result =
            launchSwapResults[keccak256(abi.encode(_pairKey(tokenIn, tokenOut), tokenIn, tokenOut))];
        if (result.amountOut != 0) {
            MockERC20(tokenOut).mint(recipient, result.amountOut);
        }

        if (params.zeroForOne) {
            return toBalanceDelta(-int128(int256(result.amountIn)), int128(int256(result.amountOut)));
        }
        return toBalanceDelta(int128(int256(result.amountOut)), -int128(int256(result.amountIn)));
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
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
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
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @param nativeFee See implementation.
    function setQuoteFee(uint256 nativeFee) external {
        nextQuoteFee = MessagingFee({nativeFee: nativeFee, lzTokenFee: 0});
    }

    /// @notice Oft version.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @return interfaceId See implementation.
    /// @return version See implementation.
    function oftVersion() external pure returns (bytes4 interfaceId, uint64 version) {
        return (type(IOFT).interfaceId, 1);
    }

    /// @notice Token.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @return See implementation.
    function token() external view returns (address) {
        return address(this);
    }

    /// @notice Approval required.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @return See implementation.
    function approvalRequired() external pure returns (bool) {
        return false;
    }

    /// @notice Shared decimals.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @return See implementation.
    function sharedDecimals() external pure returns (uint8) {
        return 6;
    }

    /// @notice Quote oft.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @return See implementation.
    function quoteOFT(SendParam calldata)
        external
        pure
        returns (OFTLimit memory, OFTFeeDetail[] memory, OFTReceipt memory)
    {
        revert("unused");
    }

    /// @notice Quote send.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
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
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
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
        address _oftDispatcher,
        address _lzEndpointRegistry,
        uint256 _executorRewardRate,
        uint128 _oftReceiveGasLimit,
        uint128 _oftDispatcherGasLimit,
        uint256 _preorderCapRatio,
        uint256 _preorderVestingDuration
    )
        MemeverseLauncher(
            _owner,
            _localLzEndpoint,
            _memeverseRegistrar,
            _memeverseProxyDeployer,
            _oftDispatcher,
            _lzEndpointRegistry,
            _executorRewardRate,
            _oftReceiveGasLimit,
            _oftDispatcherGasLimit,
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
    /// @param totalLiquidProofFunds Mock liquid-proof-side genesis total.
    function setGenesisFundForTest(uint256 verseId, uint128 totalMemecoinFunds, uint128 totalLiquidProofFunds)
        external
    {
        genesisFunds[verseId] =
            GenesisFund({totalMemecoinFunds: totalMemecoinFunds, totalLiquidProofFunds: totalLiquidProofFunds});
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
}

contract MemeverseLauncherLifecycleTest is Test {
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
        router = new MockSwapRouter();
        dispatcher = new MockOFTDispatcher();
        upt = new MockERC20("UPT", "UPT", 18);
        memecoin = new MockERC20("MEME", "MEME", 18);
        liquidProof = new MockLiquidProof();
        proxyDeployer = new MockPredictOnlyProxyDeployer(address(0xD00D), address(0xCAFE), address(0xF00D));
        registry = new MockLzEndpointRegistry();

        launcher.setMemeverseSwapRouter(address(router));
        launcher.setOFTDispatcher(address(dispatcher));
        launcher.setMemeverseProxyDeployer(address(proxyDeployer));
        launcher.setLzEndpointRegistry(address(registry));
    }

    function _setLockedVerse(uint256 verseId) internal {
        IMemeverseLauncher.Memeverse memory verse;
        verse.UPT = address(upt);
        verse.memecoin = address(memecoin);
        verse.liquidProof = address(liquidProof);
        verse.governor = address(0xCAFE);
        verse.yieldVault = address(0xD00D);
        verse.currentStage = IMemeverseLauncher.Stage.Locked;
        verse.omnichainIds = new uint32[](1);
        verse.omnichainIds[0] = uint32(block.chainid);
        launcher.setMemeverseForTest(verseId, verse);
    }

    function _setUnlockedVerse(uint256 verseId) internal {
        _setLockedVerse(verseId);
        IMemeverseLauncher.Memeverse memory verse = launcher.getMemeverseByVerseId(verseId);
        verse.currentStage = IMemeverseLauncher.Stage.Unlocked;
        launcher.setMemeverseForTest(verseId, verse);
    }

    function _setGenesisVerse(uint256 verseId, bool flashGenesis, uint128 endTime) internal {
        IMemeverseLauncher.Memeverse memory verse;
        verse.UPT = address(upt);
        verse.memecoin = address(memecoin);
        verse.liquidProof = address(liquidProof);
        verse.currentStage = IMemeverseLauncher.Stage.Genesis;
        verse.endTime = endTime;
        verse.flashGenesis = flashGenesis;
        verse.omnichainIds = new uint32[](1);
        verse.omnichainIds[0] = uint32(block.chainid + 1);
        launcher.setMemeverseForTest(verseId, verse);
    }

    function _approveMintInputs(address user) internal {
        vm.startPrank(user);
        upt.approve(address(launcher), type(uint256).max);
        memecoin.approve(address(launcher), type(uint256).max);
        vm.stopPrank();
    }

    /// @notice Verifies preview fee mapping preserves token ordering for both pools.
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
    /// @dev The launcher must not preview LP fees during genesis.
    function testPreviewGenesisMakerFees_RevertsWhenNotLocked() external {
        uint256 verseId = 1;
        IMemeverseLauncher.Memeverse memory verse;
        verse.currentStage = IMemeverseLauncher.Stage.Genesis;
        launcher.setMemeverseForTest(verseId, verse);

        vm.expectRevert(IMemeverseLauncher.NotReachedLockedStage.selector);
        launcher.previewGenesisMakerFees(verseId);
    }

    /// @notice Test claimable poltoken returns zero when already claimed.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
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
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function testQuoteDistributionLzFee_ReturnsZeroForLocalGovernanceChain() external {
        uint256 verseId = 1;
        _setLockedVerse(verseId);

        uint256 fee = launcher.quoteDistributionLzFee(verseId);

        assertEq(fee, 0);
    }

    /// @notice Test quote distribution lz fee quotes remote gov and memecoin fees.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function testQuoteDistributionLzFee_QuotesRemoteGovAndMemecoinFees() external {
        uint256 verseId = 1;
        MockOFTToken remoteUpt = new MockOFTToken("UPT", "UPT");
        MockOFTToken remoteMemecoin = new MockOFTToken("MEME", "MEME");
        IMemeverseLauncher.Memeverse memory verse;
        verse.UPT = address(remoteUpt);
        verse.memecoin = address(remoteMemecoin);
        verse.liquidProof = address(liquidProof);
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
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function testQuoteDistributionLzFee_QuotesOnlyGovFeeWhenMemecoinFeeIsZero() external {
        uint256 verseId = 18;
        MockOFTToken remoteUpt = new MockOFTToken("UPT", "UPT");
        MockOFTToken remoteMemecoin = new MockOFTToken("MEME", "MEME");
        IMemeverseLauncher.Memeverse memory verse;
        verse.UPT = address(remoteUpt);
        verse.memecoin = address(remoteMemecoin);
        verse.liquidProof = address(liquidProof);
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
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function testQuoteDistributionLzFee_QuotesOnlyMemecoinFeeWhenGovFeeIsZero() external {
        uint256 verseId = 19;
        MockOFTToken remoteUpt = new MockOFTToken("UPT", "UPT");
        MockOFTToken remoteMemecoin = new MockOFTToken("MEME", "MEME");
        IMemeverseLauncher.Memeverse memory verse;
        verse.UPT = address(remoteUpt);
        verse.memecoin = address(remoteMemecoin);
        verse.liquidProof = address(liquidProof);
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
    /// @dev The launcher must not claim or distribute fees during genesis.
    function testRedeemAndDistributeFees_RevertsWhenNotLocked() external {
        uint256 verseId = 1;
        IMemeverseLauncher.Memeverse memory verse;
        verse.currentStage = IMemeverseLauncher.Stage.Genesis;
        launcher.setMemeverseForTest(verseId, verse);

        vm.expectRevert(IMemeverseLauncher.NotReachedLockedStage.selector);
        launcher.redeemAndDistributeFees(verseId, REWARD_RECEIVER);
    }

    /// @notice Verifies expired Genesis moves to Refund when minimum funding was never met.
    /// @dev Captures the stage-transition bug where the refund branch was unreachable.
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
    /// @dev Confirms endTime no longer blocks the early-lock path.
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
    /// @dev Covers the new launcher-managed preorder settlement path.
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

    /// @notice Verifies non-flash Genesis cannot lock early even if the minimum funding target is met.
    /// @dev Preserves the requirement that non-flash launches wait for endTime expiry.
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
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
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
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
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
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
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

    /// @notice Test refund reverts when stage or user state invalid.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
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
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
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
    /// @dev Covers the successful preorder refund path in Refund stage.
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
    /// @dev Exposes the regression where claimed users remained fully claimable.
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
    /// @dev Confirms the early-return path does not mutate balances.
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
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function testRedeemAndDistributeFees_RemotePathChecksLzFeeAndSendsOFT() external {
        uint256 verseId = 2;
        MockOFTToken remoteUpt = new MockOFTToken("UPT", "UPT");
        MockOFTToken remoteMemecoin = new MockOFTToken("MEME", "MEME");
        IMemeverseLauncher.Memeverse memory verse;
        verse.UPT = address(remoteUpt);
        verse.memecoin = address(remoteMemecoin);
        verse.liquidProof = address(liquidProof);
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

        vm.expectRevert(IMemeverseLauncher.InsufficientLzFee.selector);
        launcher.redeemAndDistributeFees(verseId, REWARD_RECEIVER);

        launcher.redeemAndDistributeFees{value: 0.4 ether}(verseId, REWARD_RECEIVER);

        assertEq(remoteUpt.sendCallCount(), 1);
        assertEq(remoteMemecoin.sendCallCount(), 1);
        assertEq(remoteUpt.lastSendDstEid(), 302);
        assertEq(remoteMemecoin.lastSendDstEid(), 302);
        assertEq(remoteUpt.lastNativeFeePaid(), 0.15 ether);
        assertEq(remoteMemecoin.lastNativeFeePaid(), 0.25 ether);
    }

    /// @notice Test redeem and distribute fees remote path only gov fee skips memecoin send.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function testRedeemAndDistributeFees_RemotePathOnlyGovFeeSkipsMemecoinSend() external {
        uint256 verseId = 21;
        MockOFTToken remoteUpt = new MockOFTToken("UPT", "UPT");
        MockOFTToken remoteMemecoin = new MockOFTToken("MEME", "MEME");
        IMemeverseLauncher.Memeverse memory verse;
        verse.UPT = address(remoteUpt);
        verse.memecoin = address(remoteMemecoin);
        verse.liquidProof = address(liquidProof);
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
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function testRedeemAndDistributeFees_RemotePathOnlyMemecoinFeeSkipsGovSend() external {
        uint256 verseId = 22;
        MockOFTToken remoteUpt = new MockOFTToken("UPT", "UPT");
        MockOFTToken remoteMemecoin = new MockOFTToken("MEME", "MEME");
        IMemeverseLauncher.Memeverse memory verse;
        verse.UPT = address(remoteUpt);
        verse.memecoin = address(remoteMemecoin);
        verse.liquidProof = address(liquidProof);
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
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
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

    /// @notice Test redeem and distribute fees local path with only memecoin fee skips gov dispatch.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
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
    /// @dev Covers the restored fee distribution flow through the mock dispatcher.
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
    /// @dev Confirms the restored stage guard is active.
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

    /// @notice Test redeem memecoin liquidity reverts when launcher lp balance insufficient.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
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
    /// @dev Confirms the single-claim protection is preserved.
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

    /// @notice Test redeem pol liquidity reverts when launcher lp balance insufficient.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
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
    /// @dev Confirms the restored zero-input guard is active.
    function testMintPOLToken_RevertsOnZeroInput() external {
        uint256 verseId = 1;
        _setLockedVerse(verseId);

        vm.expectRevert(IMemeverseLauncher.ZeroInput.selector);
        launcher.mintPOLToken(verseId, 0, 1 ether, 0, 0, 0, block.timestamp);
    }

    /// @notice Verifies mintPOLToken rejects verses before the locked stage.
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

    /// @notice Verifies automatic liquidity minting refunds unused inputs and mints matching POL.
    /// @dev Covers the `amountOutDesired == 0` router path.
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

    /// @notice Verifies exact-liquidity minting uses the router quote and mints the requested POL.
    /// @dev Covers the `amountOutDesired != 0` router path.
    function testMintPOLToken_WithExactLiquidity_UsesRouterQuoteAndMintsRequestedPol() external {
        uint256 verseId = 1;
        _setLockedVerse(verseId);

        MockERC20 memecoinLp = new MockERC20("MEME-LP", "MEME-LP", 18);
        router.setLpToken(address(memecoin), address(upt), address(memecoinLp));
        router.setQuoteAmountsForLiquidity(address(upt), address(memecoin), 5 ether, 7 ether, 9 ether);
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
    }

    /// @notice Verifies exact-liquidity minting reverts when the router quote exceeds the caller budget.
    /// @dev Confirms the launcher does not over-consume user inputs in exact mode.
    function testMintPOLToken_WithExactLiquidity_RevertsWhenQuoteExceedsBudget() external {
        uint256 verseId = 1;
        _setLockedVerse(verseId);

        router.setQuoteAmountsForLiquidity(address(upt), address(memecoin), 5 ether, 11 ether, 9 ether);
        upt.mint(ALICE, 10 ether);
        memecoin.mint(ALICE, 12 ether);
        _approveMintInputs(ALICE);

        vm.prank(ALICE);
        vm.expectRevert(
            abi.encodeWithSelector(IMemeverseSwapRouter.InputAmountExceedsMaximum.selector, 11 ether, 10 ether)
        );
        launcher.mintPOLToken(verseId, 10 ether, 12 ether, 0, 0, 5 ether, block.timestamp);
    }

    /// @notice Test mint poltoken with exact liquidity no refund path.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function testMintPOLToken_WithExactLiquidity_NoRefundPath() external {
        uint256 verseId = 17;
        _setLockedVerse(verseId);

        MockERC20 memecoinLp = new MockERC20("MEME-LP", "MEME-LP", 18);
        router.setLpToken(address(memecoin), address(upt), address(memecoinLp));
        router.setQuoteAmountsForLiquidity(address(upt), address(memecoin), 5 ether, 10 ether, 12 ether);
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

    /// @notice Verifies only the owner can sweep native dust from the launcher.
    /// @dev Exposes the regression where any caller could drain the contract's native balance.
    function testRemoveGasDust_RevertsWhenCallerIsNotOwner() external {
        vm.deal(address(launcher), 1 ether);

        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, ALICE));
        launcher.removeGasDust(ALICE);
    }
}
