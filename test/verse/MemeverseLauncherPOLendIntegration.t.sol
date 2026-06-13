// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta, toBalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {MemeverseLauncherTestHelper} from "../mocks/verse/MemeverseLauncherTestHelper.sol";
import {MemeverseLauncher} from "../../src/verse/MemeverseLauncher.sol";
import {IMemeverseLauncher} from "../../src/verse/interfaces/IMemeverseLauncher.sol";
import {IMemeverseProxyDeployer} from "../../src/verse/interfaces/IMemeverseProxyDeployer.sol";
import {IPOLend} from "../../src/polend/interfaces/IPOLend.sol";
import {POLend} from "../../src/polend/POLend.sol";
import {POLSplitter} from "../../src/polend/POLSplitter.sol";
import {IPOLSplitter} from "../../src/polend/interfaces/IPOLSplitter.sol";
import {IMemeverseUniswapHook} from "../../src/swap/interfaces/IMemeverseUniswapHook.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";

contract MockMemecoinForPOLendIntegration is MockERC20 {
    address public memeverseLauncher;
    uint256 public burnedAmount;

    constructor(address launcher_) MockERC20("MEME", "MEME", 18) {
        memeverseLauncher = launcher_;
    }

    function mint(address to, uint256 amount) public override {
        _mint(to, amount);
    }

    function burn(uint256 amount) external {
        burnedAmount += amount;
        _burn(msg.sender, amount);
    }

    function initialize(string calldata, string calldata, address, address) external {}
}

contract MockPolForPOLendIntegration is MockERC20 {
    address public memecoin;
    address public memeverseLauncher;
    bytes32 public lastPoolId;
    uint256 public burnedAmount;

    constructor(address launcher_, address memecoin_) MockERC20("POL", "POL", 18) {
        memeverseLauncher = launcher_;
        memecoin = memecoin_;
    }

    function mint(address to, uint256 amount) public override {
        _mint(to, amount);
    }

    function setPoolId(bytes32 poolId) external {
        require(msg.sender == memeverseLauncher, "not launcher");
        lastPoolId = poolId;
    }

    function burn(address from, uint256 amount) public override {
        burnedAmount += amount;
        _burn(from, amount);
    }

    function initialize(string calldata, string calldata, address, address, address) external {}
}

contract MockHookForPOLendIntegration {
    address public launcher;
    address public poolInitializer;
    CallRecorder internal recorder;
    uint256 public firstProtectionCallIndex;

    struct Quote {
        uint256 fee0;
        uint256 fee1;
    }
    mapping(bytes32 => Quote) internal claimQuotes;

    constructor(address launcher_, CallRecorder recorder_) {
        launcher = launcher_;
        recorder = recorder_;
    }

    function setPublicSwapResumeTime(address, address, uint40) external {
        if (firstProtectionCallIndex == 0) firstProtectionCallIndex = recorder.next();
    }

    function setPoolInitializer(address poolInitializer_) external {
        poolInitializer = poolInitializer_;
    }

    function setClaimQuote(address tokenA, address tokenB, uint256 fee0, uint256 fee1) external {
        claimQuotes[_pairKey(tokenA, tokenB)] = Quote({fee0: fee0, fee1: fee1});
    }

    function claimableFees(PoolKey calldata key, address)
        external
        view
        returns (uint256 fee0Amount, uint256 fee1Amount)
    {
        Quote memory quote = claimQuotes[_pairKey(Currency.unwrap(key.currency0), Currency.unwrap(key.currency1))];
        return (quote.fee0, quote.fee1);
    }

    function claimFeesCore(IMemeverseUniswapHook.ClaimFeesCoreParams calldata params)
        external
        returns (uint256 fee0Amount, uint256 fee1Amount)
    {
        address token0 = Currency.unwrap(params.key.currency0);
        address token1 = Currency.unwrap(params.key.currency1);
        Quote memory quote = claimQuotes[_pairKey(token0, token1)];
        fee0Amount = quote.fee0;
        fee1Amount = quote.fee1;

        _payClaimFee(token0, params.recipient, fee0Amount);
        _payClaimFee(token1, params.recipient, fee1Amount);
    }

    function _payClaimFee(address token, address recipient, uint256 amount) internal {
        if (amount == 0) return;
        if (MockERC20(token).balanceOf(address(this)) >= amount) {
            require(MockERC20(token).transfer(recipient, amount), "transfer failed");
            return;
        }
        MintableTokenForPOLendIntegration(token).mint(recipient, amount);
    }

    function _pairKey(address tokenA, address tokenB) internal pure returns (bytes32) {
        return keccak256(abi.encode(tokenA < tokenB ? tokenA : tokenB, tokenA < tokenB ? tokenB : tokenA));
    }
}

contract MockRouterForPOLendIntegration {
    address internal immutable hookAddress;
    uint128 internal createLiquidityResult;
    uint128 internal addLiquidityResult;
    mapping(bytes32 => address) internal lpTokens;
    mapping(bytes32 => bool) internal initializedPools;
    mapping(bytes32 => PairSpend) internal createSpendByPair;
    uint256 public createPoolAndAddLiquidityCallCount;
    mapping(bytes32 => uint256) internal lastCreateAmount0ByPair;
    mapping(bytes32 => uint256) internal lastCreateAmount1ByPair;
    mapping(bytes32 => uint256) internal lastAddAmount0ByPair;
    mapping(bytes32 => uint256) internal lastAddAmount1ByPair;

    struct RemoveLiquidityResult {
        uint256 amount0Out;
        uint256 amount1Out;
    }

    struct PairSpend {
        uint256 amount0Used;
        uint256 amount1Used;
    }

    mapping(bytes32 => RemoveLiquidityResult) internal removeLiquidityResults;
    address internal observedLauncher;
    uint256 internal observedVerseId;
    bool internal rejectZeroRemoveLiquidity;
    uint256 public removeLiquidityCallCount;
    mapping(uint256 callIndex => uint256 polUAssetLpAmount) public observedPolUAssetLpByCall;
    mapping(uint256 callIndex => uint256 ptUAssetLpAmount) public observedPtUAssetLpByCall;
    mapping(uint256 callIndex => uint256 ptPolLpAmount) public observedPtPolLpByCall;

    constructor(address hookAddress_) {
        hookAddress = hookAddress_;
    }

    // Boundary note:
    // This router proves launcher-side fund routing, pool-call ordering, and slippage/deadline parameter correctness.
    // It validates that the launcher passes proper slippage and deadline parameters but does not prove real Uniswap v4 settlement semantics.
    function hook() external view returns (address) {
        return hookAddress;
    }

    function setCreateLiquidityResult(uint128 liquidity_) external {
        createLiquidityResult = liquidity_;
    }

    function setAddLiquidityResult(uint128 liquidity_) external {
        addLiquidityResult = liquidity_;
    }

    function setLpToken(address tokenA, address tokenB, address liquidityToken) external {
        lpTokens[_pairKey(tokenA, tokenB)] = liquidityToken;
    }

    function setCreateSpend(address tokenA, address tokenB, uint256 amountAUsed, uint256 amountBUsed) external {
        (uint256 amount0Used, uint256 amount1Used) =
            tokenA < tokenB ? (amountAUsed, amountBUsed) : (amountBUsed, amountAUsed);
        createSpendByPair[_pairKey(tokenA, tokenB)] = PairSpend({amount0Used: amount0Used, amount1Used: amount1Used});
    }

    function lpToken(address tokenA, address tokenB) external view returns (address liquidityToken) {
        return lpTokens[_pairKey(tokenA, tokenB)];
    }

    function lastAddAmounts(address tokenA, address tokenB) external view returns (uint256 amountA, uint256 amountB) {
        bytes32 pairKey = _pairKey(tokenA, tokenB);
        if (tokenA < tokenB) {
            return (lastAddAmount0ByPair[pairKey], lastAddAmount1ByPair[pairKey]);
        }
        return (lastAddAmount1ByPair[pairKey], lastAddAmount0ByPair[pairKey]);
    }

    function lastCreateAmounts(address tokenA, address tokenB)
        external
        view
        returns (uint256 amountA, uint256 amountB)
    {
        bytes32 pairKey = _pairKey(tokenA, tokenB);
        if (tokenA < tokenB) {
            return (lastCreateAmount0ByPair[pairKey], lastCreateAmount1ByPair[pairKey]);
        }
        return (lastCreateAmount1ByPair[pairKey], lastCreateAmount0ByPair[pairKey]);
    }

    function createPoolAndAddLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint160 startPrice,
        address,
        uint256 deadline
    ) external returns (uint128 liquidity, PoolKey memory poolKey, uint256 amountAUsed, uint256 amountBUsed) {
        require(startPrice != 0, "startPrice cannot be zero");
        require(deadline >= block.timestamp, "expired deadline");
        bytes32 pairKey = _pairKey(tokenA, tokenB);
        PairSpend memory spend = createSpendByPair[pairKey];
        (amountAUsed, amountBUsed) =
            tokenA < tokenB ? (spend.amount0Used, spend.amount1Used) : (spend.amount1Used, spend.amount0Used);
        if (amountAUsed == 0 && amountBUsed == 0) {
            amountAUsed = amountADesired;
            amountBUsed = amountBDesired;
        }
        if (amountAUsed != 0) {
            require(MockERC20(tokenA).transferFrom(msg.sender, address(this), amountAUsed), "transfer failed");
        }
        if (amountBUsed != 0) {
            require(MockERC20(tokenB).transferFrom(msg.sender, address(this), amountBUsed), "transfer failed");
        }
        initializedPools[pairKey] = true;
        createPoolAndAddLiquidityCallCount++;
        if (tokenA < tokenB) {
            lastCreateAmount0ByPair[pairKey] = amountAUsed;
            lastCreateAmount1ByPair[pairKey] = amountBUsed;
        } else {
            lastCreateAmount0ByPair[pairKey] = amountBUsed;
            lastCreateAmount1ByPair[pairKey] = amountAUsed;
        }
        liquidity = createLiquidityResult;
        poolKey = PoolKey({
            currency0: Currency.wrap(tokenA < tokenB ? tokenA : tokenB),
            currency1: Currency.wrap(tokenA < tokenB ? tokenB : tokenA),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 200,
            hooks: IHooks(hookAddress)
        });
    }

    function addLiquidity(
        Currency currency0,
        Currency currency1,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        address,
        uint256
    ) external returns (uint128 liquidity) {
        require(amount0Desired >= amount0Min, "amount0 below min");
        require(amount1Desired >= amount1Min, "amount1 below min");
        address token0 = Currency.unwrap(currency0);
        address token1 = Currency.unwrap(currency1);
        bytes32 pairKey = _pairKey(token0, token1);
        require(initializedPools[pairKey], "pool not initialized");
        if (token0 < token1) {
            lastAddAmount0ByPair[pairKey] = amount0Desired;
            lastAddAmount1ByPair[pairKey] = amount1Desired;
        } else {
            lastAddAmount0ByPair[pairKey] = amount1Desired;
            lastAddAmount1ByPair[pairKey] = amount0Desired;
        }
        if (amount0Desired != 0) {
            require(MockERC20(token0).transferFrom(msg.sender, address(this), amount0Desired), "transfer failed");
        }
        if (amount1Desired != 0) {
            require(MockERC20(token1).transferFrom(msg.sender, address(this), amount1Desired), "transfer failed");
        }
        return addLiquidityResult;
    }

    function setRemoveLiquidityResult(address tokenA, address tokenB, uint256 amountAOut, uint256 amountBOut) external {
        (uint256 amount0Out, uint256 amount1Out) = tokenA < tokenB ? (amountAOut, amountBOut) : (amountBOut, amountAOut);
        removeLiquidityResults[_pairKey(tokenA, tokenB)] =
            RemoveLiquidityResult({amount0Out: amount0Out, amount1Out: amount1Out});
    }

    function observeAuxiliaryLiquidity(address launcher_, uint256 verseId_) external {
        observedLauncher = launcher_;
        observedVerseId = verseId_;
    }

    function setRejectZeroRemoveLiquidity(bool reject) external {
        rejectZeroRemoveLiquidity = reject;
    }

    function removeLiquidity(
        Currency currency0,
        Currency currency1,
        uint128 liquidity,
        uint256 amount0Min,
        uint256 amount1Min,
        address to,
        uint256
    ) external returns (BalanceDelta delta) {
        if (rejectZeroRemoveLiquidity) require(liquidity != 0, "zero liquidity");
        removeLiquidityCallCount++;
        if (observedLauncher != address(0)) {
            (uint256 polUAssetLpAmount, uint256 ptUAssetLpAmount, uint256 ptPolLpAmount) =
                MemeverseLauncher(observedLauncher).auxiliaryLiquidities(observedVerseId);
            observedPolUAssetLpByCall[removeLiquidityCallCount] = polUAssetLpAmount;
            observedPtUAssetLpByCall[removeLiquidityCallCount] = ptUAssetLpAmount;
            observedPtPolLpByCall[removeLiquidityCallCount] = ptPolLpAmount;
        }

        address token0 = Currency.unwrap(currency0);
        address token1 = Currency.unwrap(currency1);
        RemoveLiquidityResult memory result = removeLiquidityResults[_pairKey(token0, token1)];
        require(result.amount0Out >= amount0Min, "output0 below min");
        require(result.amount1Out >= amount1Min, "output1 below min");
        if (result.amount0Out != 0) MintableTokenForPOLendIntegration(token0).mint(to, result.amount0Out);
        if (result.amount1Out != 0) MintableTokenForPOLendIntegration(token1).mint(to, result.amount1Out);
        return toBalanceDelta(int128(uint128(result.amount0Out)), int128(uint128(result.amount1Out)));
    }

    function _pairKey(address tokenA, address tokenB) internal pure returns (bytes32) {
        return keccak256(abi.encode(tokenA < tokenB ? tokenA : tokenB, tokenA < tokenB ? tokenB : tokenA));
    }
}

contract CallRecorder {
    uint256 public counter;

    function next() external returns (uint256 index) {
        counter++;
        return counter;
    }
}

contract MockYieldDispatcherForPOLendIntegration {
    uint256 public composeCallCount;
    address public lastToken;
    bytes public lastMessage;

    function lzCompose(address token, bytes32, bytes calldata message, address, bytes calldata) external payable {
        composeCallCount++;
        lastToken = token;
        lastMessage = message;
    }
}

contract MockProxyDeployerForPOLendIntegration is IMemeverseProxyDeployer {
    function predictYieldVaultAddress(uint256) external pure returns (address) {
        return address(0xD00D);
    }

    function computeGovernorAndIncentivizerAddress(uint256) external pure returns (address, address) {
        return (address(0xCAFE), address(0xBEEF));
    }

    function deployMemecoin(uint256) external pure returns (address) {
        revert PermissionDenied();
    }

    function deployPOL(uint256) external pure returns (address) {
        revert PermissionDenied();
    }

    function deployYieldVault(uint256) external pure returns (address) {
        revert PermissionDenied();
    }

    function deployGovernorAndIncentivizer(string calldata, address, address, address, address, uint256, uint256)
        external
        pure
        returns (address, address)
    {
        revert PermissionDenied();
    }

    function quorumNumerator() external pure returns (uint256) {
        return 0;
    }

    function setQuorumNumerator(uint256) external pure {}

    function minQuorumNumerator() external pure returns (uint256) {
        return 0;
    }

    function bootstrapPeriod() external pure returns (uint256) {
        return 0;
    }

    function setMinQuorumNumerator(uint256) external pure {}

    function setBootstrapPeriod(uint256) external pure {}

    function maxTreasurySpendRatio() external pure returns (uint256) {
        return 0;
    }

    function upgradeSupermajorityRatio() external pure returns (uint256) {
        return 0;
    }

    function setMaxTreasurySpendRatio(uint256) external pure {}

    function setUpgradeSupermajorityRatio(uint256) external pure {}
}

contract MintableTokenForPOLendIntegration is MockERC20 {
    constructor(string memory name_, string memory symbol_) MockERC20(name_, symbol_, 18) {}

    function mint(address to, uint256 amount) public override {
        _mint(to, amount);
    }
}

contract MockPOLendForTask5 {
    MockERC20 internal immutable uAsset;
    uint256 internal totalLeveragedDebt_;
    uint256 internal totalLeveragedInterest_;
    uint128 public mockSettlementDustReserve;
    uint128 public maxSettlementDustReserve = type(uint128).max;
    uint256 public lastFundSettlementDustReserveAmount;
    address public lastFundSettlementDustReserveUAsset;
    IPOLend.LendMarket internal market;
    uint256 internal lastRefundVerseId;
    uint256 public lastCallIndex;
    uint256 public preRedeemPTFeeCallCount;
    uint256 public lastPreRedeemPTFeeVerseId;
    uint256 public lastPreRedeemPTFeeAmount;
    address public lastPreRedeemPTFeeMintTo;
    IMemeverseLauncher.Stage public observedStageAtGlobalSettlement;
    CallRecorder internal recorder;

    constructor(MockERC20 uAsset_, CallRecorder recorder_) {
        uAsset = uAsset_;
        recorder = recorder_;
    }

    function setTotalLeveragedDebt(uint256 verseId, uint256 amount) external {
        verseId;
        totalLeveragedDebt_ = amount;
    }

    function setTotalLeveragedInterest(uint256 verseId, uint256 amount) external {
        verseId;
        totalLeveragedInterest_ = amount;
    }

    function setLendMarket(address pt, address yt) external {
        pt;
        market.yt = yt;
    }

    function registerLendMarket(uint256) external {}

    function settlementDustStates(address uAsset_) external view returns (uint128 reserve, uint128 maxReserve) {
        uAsset_;
        return (mockSettlementDustReserve, maxSettlementDustReserve);
    }

    function fundSettlementDustReserve(address uAsset_, uint256 amount) external {
        lastFundSettlementDustReserveUAsset = uAsset_;
        lastFundSettlementDustReserveAmount = amount;
        require(MockERC20(uAsset_).transferFrom(msg.sender, address(this), amount), "transfer failed");
        uint256 capacity = maxSettlementDustReserve - mockSettlementDustReserve;
        uint256 credited = amount < capacity ? amount : capacity;
        mockSettlementDustReserve += uint128(credited);
    }

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

    function getTotalDebtByUAsset(address uAsset_) external view returns (uint256) {
        if (uAsset_ == address(0)) revert IPOLend.ZeroInput();
        return uAsset_ == address(uAsset) ? totalLeveragedDebt_ : 0;
    }

    function getLeveragedDebtInfo(uint256) external view returns (IPOLend.LeveragedDebtInfo memory info) {
        info.totalLeveragedInterest = totalLeveragedInterest_;
        info.totalLeveragedDebt = totalLeveragedDebt_;
        info.interestRate = market.interestRate;
    }

    function getLendMarket(uint256) external view returns (IPOLend.LendMarket memory) {
        return market;
    }

    function finalizeLeveragedGenesis(uint256 verseId) external {
        verseId;
        if (totalLeveragedDebt_ != 0) uAsset.mint(msg.sender, totalLeveragedDebt_);
        market.state = IPOLend.MarketState.Locked;
    }

    function recordLeveragedYT(uint256 verseId, address yt_, uint256 totalLeveragedYT) external {
        verseId;
        market.yt = yt_;
        market.totalLeveragedYT = totalLeveragedYT;
    }

    function markRefundable(uint256 verseId) external {
        lastRefundVerseId = verseId;
        market.state = IPOLend.MarketState.Refund;
    }

    function executeGlobalSettlement(uint256 verseId) external {
        lastCallIndex = recorder.next();
        observedStageAtGlobalSettlement = IMemeverseLauncher(msg.sender).getStageByVerseId(verseId);
        market.state = IPOLend.MarketState.Settled;
    }

    function preRedeemPTFee(uint256 verseId, uint256 ptAmount, address mintTo)
        external
        returns (uint256 uAssetBacking)
    {
        preRedeemPTFeeCallCount++;
        lastPreRedeemPTFeeVerseId = verseId;
        lastPreRedeemPTFeeAmount = ptAmount;
        lastPreRedeemPTFeeMintTo = mintTo;
        uAsset.mint(mintTo, ptAmount);
        return ptAmount;
    }

    function burnPreRedeemedBacking(uint256, uint256) external {}

    function lastRefundedVerse() external view returns (uint256) {
        return lastRefundVerseId;
    }
}

contract MockPOLSplitterForTask5 is IPOLSplitter {
    address internal immutable pt;
    address internal immutable yt;
    address internal pol;
    address internal polendAddr;
    uint256 internal previewPTToUAssetResult;
    uint256 public lastCallIndex;
    uint256 public initializeVerseCallCount;
    uint256 public lastPTBackingVerseId;
    uint256 public lastPTBackingNumerator;
    uint256 public lastPTBackingDenominator;
    IMemeverseLauncher.Stage public observedStageAtSettle;
    CallRecorder internal recorder;

    constructor(address pt_, address yt_, CallRecorder recorder_) {
        pt = pt_;
        yt = yt_;
        recorder = recorder_;
    }

    function setPolForTest(address pol_) external {
        pol = pol_;
    }

    function setPolendForTest(address polend_) external {
        polendAddr = polend_;
    }

    function splitInfos(uint256)
        external
        view
        returns (address, address, address, address, address, uint256, uint256, uint256, uint256, uint256, bool)
    {
        return (pt, yt, pol, address(0), address(0), 0, 0, 0, 0, 0, false);
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
        return (pt, false);
    }

    function getPOLAndMemecoin(uint256) external view returns (address, address) {
        return (pol, address(0));
    }

    function preRedeemedStates(uint256) external pure returns (uint256 ptAmount, uint256 uAssetBacking) {
        return (0, 0);
    }

    function ptBackingRatios(uint256) external pure returns (uint256 numerator, uint256 denominator) {
        return (0, 0);
    }

    function initializeVerse(uint256, address, address, address, string calldata, string calldata)
        external
        returns (address, address)
    {
        initializeVerseCallCount++;
        return (pt, yt);
    }

    function split(uint256, uint256 polAmount) external returns (uint256 ptAmount, uint256 ytAmount) {
        /// forge-lint: disable-next-line(erc20-unchecked-transfer)
        MockERC20(pol).transferFrom(msg.sender, address(this), polAmount);
        MintableTokenForPOLendIntegration(pt).mint(msg.sender, polAmount);
        MintableTokenForPOLendIntegration(yt).mint(msg.sender, polAmount);
        return (polAmount, polAmount);
    }

    function merge(uint256, uint256) external pure returns (uint256) {
        revert PermissionDenied();
    }

    function settle(uint256 verseId) external returns (uint256, uint256) {
        lastCallIndex = recorder.next();
        observedStageAtSettle = IMemeverseLauncher(msg.sender).getStageByVerseId(verseId);
        return (0, 0);
    }

    function recordPTBackingRatio(uint256 verseId, uint256 numerator, uint256 denominator) external {
        lastPTBackingVerseId = verseId;
        lastPTBackingNumerator = numerator;
        lastPTBackingDenominator = denominator;
    }

    function setPreviewPTToUAssetResult(uint256 result) external {
        previewPTToUAssetResult = result;
    }

    function previewPTToUAsset(uint256, uint256 ptAmount) external view returns (uint256 uAssetAmount) {
        if (previewPTToUAssetResult != 0) return ptAmount;
        if (lastPTBackingNumerator == 0 || lastPTBackingDenominator == 0) return 0;
        return FullMath.mulDiv(ptAmount, lastPTBackingNumerator, lastPTBackingDenominator);
    }

    function preRedeemPTFee(uint256, uint256) external pure returns (uint256 uAssetBacking) {
        return 0;
    }

    function redeemPT(uint256, uint256, address) external pure returns (uint256) {
        revert PermissionDenied();
    }

    function redeemYT(uint256, uint256, address) external pure returns (uint256, uint256) {
        revert PermissionDenied();
    }

    function previewRedeemYTUAsset(uint256, uint256) external pure returns (uint256) {
        return 0;
    }

    function polend() external view returns (address) {
        return polendAddr;
    }
}

contract MemeverseLauncherPOLendIntegrationTest is Test, MemeverseLauncherTestHelper {
    uint256 internal constant VERSE_ID = 1;

    IMemeverseLauncher internal launcher;
    address internal launcherProxy;
    MockRouterForPOLendIntegration internal router;
    MockHookForPOLendIntegration internal hook;
    MockProxyDeployerForPOLendIntegration internal proxyDeployer;
    MockERC20 internal uAsset;
    MockMemecoinForPOLendIntegration internal memecoin;
    MockPolForPOLendIntegration internal pol;
    MockPOLendForTask5 internal polend;
    MockPOLSplitterForTask5 internal splitter;
    MockYieldDispatcherForPOLendIntegration internal dispatcher;
    MintableTokenForPOLendIntegration internal pt;
    MintableTokenForPOLendIntegration internal yt;
    MockERC20 internal polUAssetLp;
    MockERC20 internal ptUAssetLp;
    MockERC20 internal ptPolLp;
    CallRecorder internal recorder;

    function setUp() external {
        proxyDeployer = new MockProxyDeployerForPOLendIntegration();
        uAsset = new MockERC20("UASSET", "UASSET", 18);
        recorder = new CallRecorder();
        polend = new MockPOLendForTask5(uAsset, recorder);
        dispatcher = new MockYieldDispatcherForPOLendIntegration();
        pt = new MintableTokenForPOLendIntegration("PT", "PT");
        yt = new MintableTokenForPOLendIntegration("YT", "YT");
        polUAssetLp = new MockERC20("POL-UASSET-LP", "POL-UASSET-LP", 18);
        ptUAssetLp = new MockERC20("PT-UASSET-LP", "PT-UASSET-LP", 18);
        ptPolLp = new MockERC20("PT-POL-LP", "PT-POL-LP", 18);
        splitter = new MockPOLSplitterForTask5(address(pt), address(yt), recorder);
        MemeverseLauncher impl = new MemeverseLauncher();
        launcherProxy = address(new ERC1967Proxy(
            address(impl),
            abi.encodeCall(MemeverseLauncher.initialize, (
                address(this),
                address(0x1),
                address(0x2),
                address(0x3),
                address(0x4),
                address(0x5),
                address(polend),
                address(splitter),
                25,
                uint128(115_000),
                uint128(135_000),
                2_500,
                7 days
            ))
        ));
        launcher = IMemeverseLauncher(launcherProxy);
        memecoin = new MockMemecoinForPOLendIntegration(address(launcher));
        pol = new MockPolForPOLendIntegration(address(launcher), address(memecoin));
        splitter.setPolForTest(address(pol));
        splitter.setPolendForTest(address(polend));
        hook = new MockHookForPOLendIntegration(address(launcher), recorder);
        router = new MockRouterForPOLendIntegration(address(hook));

        launcher.setMemeverseUniswapHook(address(hook));
        hook.setPoolInitializer(address(router));
        launcher.setMemeverseSwapRouter(address(router));
        launcher.setYieldDispatcher(address(dispatcher));
        launcher.setMemeverseProxyDeployer(address(proxyDeployer));
        launcher.setFundMetaData(address(uAsset), 10 ether, 1);

        polend.setLendMarket(address(pt), address(yt));
        router.setCreateLiquidityResult(1400 ether);
        router.setAddLiquidityResult(100 ether);
        router.setLpToken(address(pol), address(uAsset), address(polUAssetLp));
        router.setLpToken(address(pt), address(uAsset), address(ptUAssetLp));
        router.setLpToken(address(pt), address(pol), address(ptPolLp));
    }

    function _deployRealPOLend() internal returns (POLend realPolend) {
        POLend implementation = new POLend();
        bytes memory data = abi.encodeCall(
            POLend.initialize, (address(this), 0.1 ether, 10 ether, address(this), launcherProxy, address(splitter))
        );
        return POLend(address(new ERC1967Proxy(address(implementation), data)));
    }

    function _deployRealPOLendAndSplitter()
        internal
        returns (POLend realPolend, POLSplitter realSplitter, address realPT)
    {
        POLSplitter splitterImplementation = new POLSplitter();
        bytes memory splitterData = abi.encodeCall(POLSplitter.initialize, (address(this), launcherProxy));
        realSplitter = POLSplitter(address(new ERC1967Proxy(address(splitterImplementation), splitterData)));

        POLend polendImplementation = new POLend();
        bytes memory polendData = abi.encodeCall(
            POLend.initialize,
            (address(this), 0.1 ether, 10 ether, address(this), launcherProxy, address(realSplitter))
        );
        realPolend = POLend(address(new ERC1967Proxy(address(polendImplementation), polendData)));

        setPolendForTest(launcherProxy, address(realPolend));
        setPolSplitterForTest(launcherProxy, address(realSplitter));

        vm.prank(launcherProxy);
        (realPT,) =
            realSplitter.initializeVerse(VERSE_ID, address(pol), address(memecoin), address(uAsset), "Verse", "VRS");
        vm.prank(launcherProxy);
        realSplitter.recordPTBackingRatio(VERSE_ID, 1, 2);
    }

    function _seedLauncherAndPolendFunding(uint256 normalFunds, uint256 leveragedFunds) internal {
        if (normalFunds != 0) uAsset.mint(launcherProxy, normalFunds);
        if (leveragedFunds != 0) uAsset.mint(launcherProxy, leveragedFunds);
    }

    function _sortedTokenAddresses(address a, address b, address c)
        internal
        pure
        returns (address low, address mid, address high)
    {
        low = a;
        mid = b;
        high = c;
        if (low > mid) (low, mid) = (mid, low);
        if (mid > high) (mid, high) = (high, mid);
        if (low > mid) (low, mid) = (mid, low);
    }

    function _setSemanticClaimQuote(address tokenA, address tokenB, uint256 tokenAFee, uint256 tokenBFee) internal {
        (uint256 fee0, uint256 fee1) = tokenA < tokenB ? (tokenAFee, tokenBFee) : (tokenBFee, tokenAFee);
        hook.setClaimQuote(tokenA, tokenB, fee0, fee1);
    }

    function _setGenesisVerse(uint128 endTime, bool flashGenesis) internal {
        setMemeverseForTest(
            launcherProxy, VERSE_ID,
            address(uAsset), address(memecoin), address(pol),
            address(0xD00D), // yieldVault
            address(0xCAFE), // governor
            address(0), // incentivizer
            endTime, endTime + 7 days,
            IMemeverseLauncher.Stage.Genesis, flashGenesis
        );
        uint32[] memory chainIds = new uint32[](1);
        chainIds[0] = uint32(block.chainid + 1);
        setOmnichainIdsForTest(launcherProxy, VERSE_ID, chainIds);
    }

    /// @dev Write a full Memeverse struct back to proxy storage, preserving omnichainIds.
    function _writeVerseBack(IMemeverseLauncher.Memeverse memory verse) internal {
        setMemeverseForTest(
            launcherProxy, VERSE_ID,
            verse.uAsset, verse.memecoin, verse.pol,
            verse.yieldVault, verse.governor, verse.incentivizer,
            verse.endTime, verse.unlockTime,
            verse.currentStage, verse.flashGenesis
        );
        setOmnichainIdsForTest(launcherProxy, VERSE_ID, verse.omnichainIds);
    }

    function testChangeStage_LocksWhenLeveragedInterestAloneMeetsThreshold() external {
        _setGenesisVerse(uint128(block.timestamp + 1 days), false);
        polend.setTotalLeveragedInterest(VERSE_ID, 100 ether);
        polend.setTotalLeveragedDebt(VERSE_ID, 1000 ether);
        _seedLauncherAndPolendFunding(0, 1000 ether);
        vm.warp(block.timestamp + 1 days + 1);

        assertEq(uint256(launcher.changeStage(VERSE_ID)), uint256(IMemeverseLauncher.Stage.Locked), "or gate");
    }

    function testDeployLiquidity_CreatesFourPoolsAndSplitsNormalLeveragedYT() external {
        _setGenesisVerse(uint128(block.timestamp + 1 days), false);
        setGenesisFundForTest(launcherProxy, VERSE_ID, 1000 ether);
        polend.setTotalLeveragedDebt(VERSE_ID, 1000 ether);
        _seedLauncherAndPolendFunding(1000 ether, 1000 ether);

        forceDeployLiquidity(
            launcherProxy, VERSE_ID,
            address(uAsset), address(memecoin), address(pol),
            polend.getTotalLeveragedDebt(VERSE_ID),
            address(polend), address(splitter)
        );

        (uint256 polUAssetLpAmount, uint256 ptUAssetLpAmount, uint256 ptPolLpAmount) =
            MemeverseLauncher(launcherProxy).auxiliaryLiquidities(VERSE_ID);
        IPOLend.LendMarket memory market = polend.getLendMarket(VERSE_ID);
        assertGt(polUAssetLpAmount, 0, "pol/uAsset");
        assertGt(ptUAssetLpAmount, 0, "pt/uAsset");
        assertGt(ptPolLpAmount, 0, "pt/pol");
        assertEq(router.createPoolAndAddLiquidityCallCount(), 4, "four pools created");
        assertEq(MemeverseLauncher(launcherProxy).totalNormalClaimableYT(VERSE_ID), 300 ether, "normal yt");
        assertEq(market.totalLeveragedYT, 300 ether, "leveraged yt");
        assertEq(yt.balanceOf(address(polend)), 300 ether, "leveraged yt moved");
    }

    function testDeployLiquidity_UsesUnifiedTotalFundsForFourPoolAllocation() external {
        _setGenesisVerse(uint128(block.timestamp + 1 days), false);
        setGenesisFundForTest(launcherProxy, VERSE_ID, 800 ether);
        polend.setTotalLeveragedDebt(VERSE_ID, 100 ether);
        _seedLauncherAndPolendFunding(800 ether, 100 ether);

        forceDeployLiquidity(
            launcherProxy, VERSE_ID,
            address(uAsset), address(memecoin), address(pol),
            polend.getTotalLeveragedDebt(VERSE_ID),
            address(polend), address(splitter)
        );

        (, uint256 mainUAsset) = router.lastCreateAmounts(address(memecoin), address(uAsset));
        (uint256 polUAssetPol, uint256 polUAssetUAsset) = router.lastCreateAmounts(address(pol), address(uAsset));
        (, uint256 ptUAssetUAsset) = router.lastCreateAmounts(address(pt), address(uAsset));
        (, uint256 ptPolPol) = router.lastCreateAmounts(address(pt), address(pol));
        assertEq(mainUAsset, 630 ether, "main uAsset");
        assertEq(polUAssetPol, 400 ether, "pol/uAsset pol");
        assertEq(polUAssetUAsset, 180 ether, "pol/uAsset uAsset");
        assertEq(ptUAssetUAsset, 90 ether, "pt/uAsset uAsset");
        assertEq(ptPolPol, 400 ether, "pt/pol pol");
        uint256 expectedNormalYT = uint256(600 ether) * 800 / 900;
        uint256 expectedLeveragedYT = uint256(600 ether) - expectedNormalYT;
        assertEq(MemeverseLauncher(launcherProxy).totalNormalClaimableYT(VERSE_ID), expectedNormalYT, "normal yt");
        assertEq(polend.getLendMarket(VERSE_ID).totalLeveragedYT, expectedLeveragedYT, "leveraged yt");
    }

    function testDeployLiquidity_RecordsActualMainPoolUAssetSpendForPTBacking() external {
        _setGenesisVerse(uint128(block.timestamp + 1 days), false);
        setGenesisFundForTest(launcherProxy, VERSE_ID, 1000 ether);
        polend.setTotalLeveragedDebt(VERSE_ID, 1000 ether);
        _seedLauncherAndPolendFunding(1000 ether, 1000 ether);

        uint256 budgetedMainUAsset = 1400 ether;
        uint256 actualMainUAssetUsed = 1000 ether;
        router.setCreateSpend(address(memecoin), address(uAsset), budgetedMainUAsset, actualMainUAssetUsed);

        forceDeployLiquidity(
            launcherProxy, VERSE_ID,
            address(uAsset), address(memecoin), address(pol),
            polend.getTotalLeveragedDebt(VERSE_ID),
            address(polend), address(splitter)
        );

        assertEq(splitter.lastPTBackingVerseId(), VERSE_ID, "verse id");
        assertEq(splitter.lastPTBackingNumerator(), actualMainUAssetUsed, "pt backing numerator");
        assertEq(splitter.lastPTBackingDenominator(), 1400 ether, "pt backing denominator");
    }

    function testDeployLiquidity_MainPoolBurnsUnspentDesiredMemecoinBudget() external {
        _setGenesisVerse(uint128(block.timestamp + 1 days), false);
        setGenesisFundForTest(launcherProxy, VERSE_ID, 800 ether);
        polend.setTotalLeveragedDebt(VERSE_ID, 100 ether);
        _seedLauncherAndPolendFunding(800 ether, 100 ether);

        router.setCreateSpend(address(memecoin), address(uAsset), 620 ether, 600 ether);

        forceDeployLiquidity(
            launcherProxy, VERSE_ID,
            address(uAsset), address(memecoin), address(pol),
            polend.getTotalLeveragedDebt(VERSE_ID),
            address(polend), address(splitter)
        );

        assertEq(memecoin.burnedAmount(), 10 ether, "unspent memecoin burned");
    }

    function testDeployLiquidity_RoutesUnusedBootstrapUAssetAndBurnsUnusedMemecoin() external {
        _setGenesisVerse(uint128(block.timestamp + 1 days), false);
        setGenesisFundForTest(launcherProxy, VERSE_ID, 800 ether);
        polend.setTotalLeveragedDebt(VERSE_ID, 100 ether);
        _seedLauncherAndPolendFunding(800 ether, 100 ether);

        uint256 polUAssetSpend = uint256(1_200 ether) / 7;
        uint256 ptUAssetSpend = uint256(600 ether) / 7;
        uint256 expectedUnusedUAsset = 900 ether - 600 ether - polUAssetSpend - ptUAssetSpend;

        router.setCreateSpend(address(memecoin), address(uAsset), 620 ether, 600 ether);
        router.setCreateSpend(address(pol), address(uAsset), 400 ether, polUAssetSpend);
        router.setCreateSpend(address(pt), address(uAsset), 200 ether, ptUAssetSpend);

        uint256 leveragedDebt = polend.getTotalLeveragedDebt(VERSE_ID);
        vm.expectEmit(true, true, true, true);
        emit IMemeverseLauncher.BootstrapUnusedAssetsHandled(
            VERSE_ID, address(uAsset), address(memecoin), expectedUnusedUAsset, expectedUnusedUAsset, 0, 10 ether
        );
        this._callForceDeployLiquidity(
            launcherProxy, VERSE_ID,
            address(uAsset), address(memecoin), address(pol),
            leveragedDebt,
            address(polend), address(splitter)
        );

        assertEq(polend.lastFundSettlementDustReserveUAsset(), address(uAsset), "fund uAsset");
        assertEq(polend.lastFundSettlementDustReserveAmount(), expectedUnusedUAsset, "fund amount");
        assertEq(polend.mockSettlementDustReserve(), expectedUnusedUAsset, "credited reserve");
        assertEq(memecoin.burnedAmount(), 10 ether, "burned memecoin");
        assertEq(uAsset.balanceOf(address(launcher)), 0, "no uAsset left");
    }

    function testDeployLiquidity_RevertWhenLeveragedLiquidityNotFunded() external {
        _setGenesisVerse(uint128(block.timestamp + 1 days), false);
        setGenesisFundForTest(launcherProxy, VERSE_ID, 1000 ether);
        polend.setTotalLeveragedDebt(VERSE_ID, 1000 ether);
        _seedLauncherAndPolendFunding(1000 ether, 0);

        uint256 leveragedDebt = polend.getTotalLeveragedDebt(VERSE_ID);
        vm.expectRevert();
        this._callForceDeployLiquidity(
            launcherProxy, VERSE_ID,
            address(uAsset), address(memecoin), address(pol),
            leveragedDebt,
            address(polend), address(splitter)
        );
    }

    function _callForceDeployLiquidity(
        address proxy, uint256 verseId, address uAsset, address memecoin, address pol,
        uint256 totalLeveragedDebt, address polendAddr, address polSplitterAddr
    ) external {
        forceDeployLiquidity(proxy, verseId, uAsset, memecoin, pol, totalLeveragedDebt, polendAddr, polSplitterAddr);
    }

    function testChangeStage_FinalizesAndInitializesWhenLeveragedInterestMeetsThreshold() external {
        _setGenesisVerse(uint128(block.timestamp + 1 days), false);
        polend.setTotalLeveragedInterest(VERSE_ID, 100 ether);
        polend.setTotalLeveragedDebt(VERSE_ID, 1000 ether);
        vm.warp(block.timestamp + 1 days + 1);

        assertEq(uint256(launcher.changeStage(VERSE_ID)), uint256(IMemeverseLauncher.Stage.Locked), "locked");
        assertEq(splitter.initializeVerseCallCount(), 1, "splitter initialized");
    }

    function testDeployLiquidity_RequiresRealLeveragedFundsFromPOLend() external {
        _setGenesisVerse(uint128(block.timestamp + 1 days), false);
        setGenesisFundForTest(launcherProxy, VERSE_ID, 1000 ether);
        _seedLauncherAndPolendFunding(1000 ether, 0);

        POLend realPolend = _deployRealPOLend();
        realPolend.setMaxSettlementDustReserve(address(uAsset), uint128(1e9));
        vm.prank(address(launcher));
        realPolend.registerLendMarket(VERSE_ID);
        setPolendForTest(launcherProxy, address(realPolend));

        uAsset.mint(address(this), 1100 ether);
        uAsset.approve(address(realPolend), type(uint256).max);
        realPolend.leveragedGenesis(VERSE_ID, 100 ether);
        vm.prank(address(launcher));
        realPolend.finalizeLeveragedGenesis(VERSE_ID);
        uint256 treasuryBalanceAfterReservation = uAsset.balanceOf(address(this));
        if (treasuryBalanceAfterReservation != 0) {
            assertTrue(uAsset.transfer(address(0xDEAD), treasuryBalanceAfterReservation), "transfer failed");
        }

        forceDeployLiquidity(
            launcherProxy, VERSE_ID,
            address(uAsset), address(memecoin), address(pol),
            realPolend.getTotalLeveragedDebt(VERSE_ID),
            address(realPolend), address(splitter)
        );

        assertEq(uAsset.balanceOf(address(launcher)), 0, "launcher spent funded uAsset");
        assertEq(realPolend.getTotalLeveragedDebt(VERSE_ID), 1000 ether, "real debt tracked");
    }

    function testSettleLeveragedAuxiliaryLiquidity_MapsSortedDeltasToTokens() external {
        MintableTokenForPOLendIntegration tokenA = new MintableTokenForPOLendIntegration("A", "A");
        MintableTokenForPOLendIntegration tokenB = new MintableTokenForPOLendIntegration("B", "B");
        MintableTokenForPOLendIntegration tokenC = new MintableTokenForPOLendIntegration("C", "C");
        (address testUAsset, address testPt, address testPol) =
            _sortedTokenAddresses(address(tokenA), address(tokenB), address(tokenC));
        assertGt(uint160(testPol), uint160(testUAsset), "pol/uAsset caller order reversed");

        MockPOLSplitterForTask5 testSplitter = new MockPOLSplitterForTask5(testPt, address(yt), recorder);
        testSplitter.setPolForTest(testPol);
        testSplitter.setPolendForTest(address(polend));
        setPolSplitterForTest(launcherProxy, address(testSplitter));

        _setGenesisVerse(uint128(block.timestamp), false);
        IMemeverseLauncher.Memeverse memory verse = launcher.getMemeverseByVerseId(VERSE_ID);
        verse.currentStage = IMemeverseLauncher.Stage.Unlocked;
        verse.uAsset = testUAsset;
        verse.pol = testPol;
        _writeVerseBack(verse);
        setGenesisFundForTest(launcherProxy, VERSE_ID, 1000 ether);
        polend.setTotalLeveragedDebt(VERSE_ID, 1000 ether);
        setAuxiliaryLiquiditiesForTest(launcherProxy, VERSE_ID, 100 ether, 50 ether, 80 ether);

        router.setRemoveLiquidityResult(testPol, testUAsset, 30 ether, 15 ether);
        router.setRemoveLiquidityResult(testPt, testUAsset, 12 ether, 6 ether);
        router.setRemoveLiquidityResult(testPt, testPol, 20 ether, 10 ether);

        vm.prank(address(polend));
        (uint256 polAmount, uint256 ptAmount, uint256 uAssetAmount) =
            launcher.settleLeveragedAuxiliaryLiquidity(VERSE_ID);

        assertEq(polAmount, 40 ether, "pol amount");
        assertEq(ptAmount, 32 ether, "pt amount");
        assertEq(uAssetAmount, 21 ether, "uAsset amount");
    }

    function testSettleLeveragedAuxiliaryLiquidity_AllowsPOLendWhilePaused() external {
        _setGenesisVerse(uint128(block.timestamp), false);
        IMemeverseLauncher.Memeverse memory verse = launcher.getMemeverseByVerseId(VERSE_ID);
        verse.currentStage = IMemeverseLauncher.Stage.Unlocked;
        _writeVerseBack(verse);
        setGenesisFundForTest(launcherProxy, VERSE_ID, 1000 ether);
        polend.setTotalLeveragedDebt(VERSE_ID, 1000 ether);
        setAuxiliaryLiquiditiesForTest(launcherProxy, VERSE_ID, 100 ether, 50 ether, 80 ether);
        router.setRemoveLiquidityResult(address(pol), address(uAsset), 30 ether, 15 ether);
        router.setRemoveLiquidityResult(address(pt), address(uAsset), 12 ether, 6 ether);
        router.setRemoveLiquidityResult(address(pt), address(pol), 20 ether, 10 ether);
        MemeverseLauncher(launcherProxy).pause();

        vm.prank(address(polend));
        (uint256 polAmount, uint256 ptAmount, uint256 uAssetAmount) =
            launcher.settleLeveragedAuxiliaryLiquidity(VERSE_ID);

        assertEq(polAmount, 40 ether, "pol amount");
        assertEq(ptAmount, 32 ether, "pt amount");
        assertEq(uAssetAmount, 21 ether, "uAsset amount");
    }

    function testSettleLeveragedAuxiliaryLiquidity_DecrementsStorageBeforeExternalRemovals() external {
        _setGenesisVerse(uint128(block.timestamp), false);
        IMemeverseLauncher.Memeverse memory verse = launcher.getMemeverseByVerseId(VERSE_ID);
        verse.currentStage = IMemeverseLauncher.Stage.Unlocked;
        _writeVerseBack(verse);
        setGenesisFundForTest(launcherProxy, VERSE_ID, 1000 ether);
        polend.setTotalLeveragedDebt(VERSE_ID, 1000 ether);
        setAuxiliaryLiquiditiesForTest(launcherProxy, VERSE_ID, 100 ether, 50 ether, 80 ether);
        router.setRemoveLiquidityResult(address(pol), address(uAsset), 30 ether, 15 ether);
        router.setRemoveLiquidityResult(address(pt), address(uAsset), 12 ether, 6 ether);
        router.setRemoveLiquidityResult(address(pt), address(pol), 20 ether, 10 ether);
        router.observeAuxiliaryLiquidity(address(launcher), VERSE_ID);

        vm.prank(address(polend));
        launcher.settleLeveragedAuxiliaryLiquidity(VERSE_ID);

        assertEq(router.observedPolUAssetLpByCall(1), 50 ether, "pol/uAsset decremented before first call");
        assertEq(router.observedPtUAssetLpByCall(1), 25 ether, "pt/uAsset decremented before first call");
        assertEq(router.observedPtPolLpByCall(1), 40 ether, "pt/pol decremented before first call");
    }

    function testSettleLeveragedAuxiliaryLiquidity_SkipsZeroLpRemovals() external {
        _setGenesisVerse(uint128(block.timestamp), false);
        IMemeverseLauncher.Memeverse memory verse = launcher.getMemeverseByVerseId(VERSE_ID);
        verse.currentStage = IMemeverseLauncher.Stage.Unlocked;
        _writeVerseBack(verse);
        setGenesisFundForTest(launcherProxy, VERSE_ID, 1000 ether);
        polend.setTotalLeveragedDebt(VERSE_ID, 1);
        setAuxiliaryLiquiditiesForTest(launcherProxy, VERSE_ID, 1, 1, 1);
        router.setRejectZeroRemoveLiquidity(true);

        vm.prank(address(polend));
        (uint256 polAmount, uint256 ptAmount, uint256 uAssetAmount) =
            launcher.settleLeveragedAuxiliaryLiquidity(VERSE_ID);

        assertEq(router.removeLiquidityCallCount(), 0, "zero lp removals skipped");
        assertEq(polAmount, 0, "pol amount");
        assertEq(ptAmount, 0, "pt amount");
        assertEq(uAssetAmount, 0, "uAsset amount");
    }

    function testSettleLeveragedAuxiliaryLiquidity_RevertsForNonPOLendCaller() external {
        _setGenesisVerse(uint128(block.timestamp), false);
        IMemeverseLauncher.Memeverse memory verse = launcher.getMemeverseByVerseId(VERSE_ID);
        verse.currentStage = IMemeverseLauncher.Stage.Unlocked;
        _writeVerseBack(verse);

        vm.prank(address(0xBEEF));
        vm.expectRevert(IMemeverseLauncher.PermissionDenied.selector);
        launcher.settleLeveragedAuxiliaryLiquidity(VERSE_ID);
    }

    function testFuzz_SettleLeveragedAuxiliaryLiquidity_ResultNeverExceedsLpAmount(
        uint128 lpAmount,
        uint128 normalFunds,
        uint128 leveragedDebt
    ) external pure {
        vm.assume(leveragedDebt > 0);
        uint256 totalFunds = uint256(normalFunds) + uint256(leveragedDebt);
        uint256 result = FullMath.mulDiv(lpAmount, leveragedDebt, totalFunds);
        assertLe(result, uint256(lpAmount), "result > lp");
        assertLe(result, uint256(type(uint128).max), "uint128 overflow");
    }

    function testRedeemAndDistributeFees_BurnsPolAndRoutesNormalFeesToUsersDaoFeesToTreasury() external {
        _setGenesisVerse(uint128(block.timestamp + 1 days), false);
        IMemeverseLauncher.Memeverse memory verse = launcher.getMemeverseByVerseId(VERSE_ID);
        verse.currentStage = IMemeverseLauncher.Stage.Locked;
        verse.omnichainIds[0] = uint32(block.chainid);
        _writeVerseBack(verse);
        setGenesisFundForTest(launcherProxy, VERSE_ID, 1000 ether);
        polend.setTotalLeveragedDebt(VERSE_ID, 1000 ether);
        splitter.setPreviewPTToUAssetResult(1);

        hook.setClaimQuote(address(pol), address(uAsset), 30 ether, 40 ether);
        hook.setClaimQuote(address(pt), address(pol), 50 ether, 20 ether);
        hook.setClaimQuote(address(pt), address(uAsset), 25 ether, 15 ether);

        uint256 initialPolSupply = pol.totalSupply();
        uint256 expectedPolFee =
            (address(pol) < address(uAsset) ? 30 ether : 40 ether) + (address(pt) < address(pol) ? 20 ether : 50 ether);
        launcher.redeemAndDistributeFees(VERSE_ID, address(0xE));

        assertEq(pol.burnedAmount(), expectedPolFee, "pol fees burned");
        (uint256 accUAssetFee, uint256 accPTFee) = MemeverseLauncher(launcherProxy).normalFeeStates(VERSE_ID);
        assertGt(accUAssetFee, 0, "normal fee stored");
        assertGt(accPTFee, 0, "normal pt fee stored");
        assertEq(uAsset.balanceOf(verse.governor), 0, "no direct dao uasset fee");
        assertGt(uAsset.balanceOf(address(dispatcher)), 0, "dao uasset fee dispatched");
        assertEq(dispatcher.composeCallCount(), 1, "governor compose");
        assertEq(pt.balanceOf(verse.governor), 0, "dao raw pt not paid");
        assertGt(polend.preRedeemPTFeeCallCount(), 0, "dao pt fee pre-redeemed");
        assertEq(pol.totalSupply(), initialPolSupply, "net pol supply");
    }

    function testRedeemAndDistributeFees_RealPOLendSplitterRevertsZeroBackingAuxiliaryGovPTFee() external {
        _setGenesisVerse(uint128(block.timestamp + 1 days), false);
        setGenesisFundForTest(launcherProxy, VERSE_ID, 0);

        (POLend realPolend, POLSplitter realSplitter, address realPT) = _deployRealPOLendAndSplitter();
        realPolend.setMaxSettlementDustReserve(address(uAsset), uint128(1 ether));
        vm.prank(address(launcher));
        realPolend.registerLendMarket(VERSE_ID);
        uAsset.mint(address(this), 0.1 ether);
        uAsset.approve(address(realPolend), type(uint256).max);
        realPolend.leveragedGenesis(VERSE_ID, 0.1 ether);
        vm.prank(address(launcher));
        realPolend.finalizeLeveragedGenesis(VERSE_ID);

        IMemeverseLauncher.Memeverse memory verse = launcher.getMemeverseByVerseId(VERSE_ID);
        verse.currentStage = IMemeverseLauncher.Stage.Locked;
        verse.omnichainIds[0] = uint32(block.chainid);
        _writeVerseBack(verse);

        pol.mint(address(this), 1);
        pol.approve(address(realSplitter), 1);
        realSplitter.split(VERSE_ID, 1);
        assertTrue(MockERC20(realPT).transfer(address(hook), 1), "pt transfer");
        assertEq(realSplitter.previewPTToUAsset(VERSE_ID, 1), 0, "zero backing");

        _setSemanticClaimQuote(realPT, address(uAsset), 1, 0);

        launcher.redeemAndDistributeFees(VERSE_ID, address(0xE));

        (, uint256 pendingPTFee) = MemeverseLauncher(launcherProxy).pendingAuxiliaryGovFeeStates(VERSE_ID);
        assertEq(pendingPTFee, 1, "pt pending retained");
    }

    function testChangeStage_UnlockedSkipsPolendSettlementWhenDebtIsZero() external {
        _setGenesisVerse(uint128(block.timestamp), false);
        IMemeverseLauncher.Memeverse memory verse = launcher.getMemeverseByVerseId(VERSE_ID);
        verse.currentStage = IMemeverseLauncher.Stage.Locked;
        verse.unlockTime = uint128(block.timestamp);
        _writeVerseBack(verse);
        vm.warp(block.timestamp + 1);

        launcher.changeStage(VERSE_ID);

        assertEq(splitter.lastCallIndex(), 1, "splitter settles");
        assertEq(
            uint256(splitter.observedStageAtSettle()),
            uint256(IMemeverseLauncher.Stage.Unlocked),
            "splitter sees Unlocked"
        );
        assertEq(hook.firstProtectionCallIndex(), 2, "protection after splitter");
        assertEq(polend.lastCallIndex(), 0, "polend skipped");
        assertEq(uint256(launcher.getStageByVerseId(VERSE_ID)), uint256(IMemeverseLauncher.Stage.Unlocked), "unlocked");
    }

    function testChangeStage_UnlockedCallsSplitterThenPolendWhenDebtExists() external {
        _setGenesisVerse(uint128(block.timestamp), false);
        IMemeverseLauncher.Memeverse memory verse = launcher.getMemeverseByVerseId(VERSE_ID);
        verse.currentStage = IMemeverseLauncher.Stage.Locked;
        verse.unlockTime = uint128(block.timestamp);
        _writeVerseBack(verse);
        polend.setTotalLeveragedDebt(VERSE_ID, 1 ether);
        vm.warp(block.timestamp + 1);

        launcher.changeStage(VERSE_ID);

        assertEq(splitter.lastCallIndex(), 1, "splitter first");
        assertEq(polend.lastCallIndex(), 2, "polend second");
        assertEq(hook.firstProtectionCallIndex(), 3, "protection after settlements");
        assertEq(
            uint256(splitter.observedStageAtSettle()),
            uint256(IMemeverseLauncher.Stage.Unlocked),
            "splitter sees Unlocked"
        );
        assertEq(
            uint256(polend.observedStageAtGlobalSettlement()),
            uint256(IMemeverseLauncher.Stage.Unlocked),
            "polend sees Unlocked"
        );
    }

    function testChangeStage_WhenPausedUnlockedCallsSplitterThenPolendWhenDebtExists() external {
        _setGenesisVerse(uint128(block.timestamp), false);
        IMemeverseLauncher.Memeverse memory verse = launcher.getMemeverseByVerseId(VERSE_ID);
        verse.currentStage = IMemeverseLauncher.Stage.Locked;
        verse.unlockTime = uint128(block.timestamp);
        _writeVerseBack(verse);
        polend.setTotalLeveragedDebt(VERSE_ID, 1 ether);
        vm.warp(block.timestamp + 1);
        MemeverseLauncher(launcherProxy).pause();

        launcher.changeStage(VERSE_ID);

        assertEq(splitter.lastCallIndex(), 1, "splitter first");
        assertEq(polend.lastCallIndex(), 2, "polend second");
        assertEq(hook.firstProtectionCallIndex(), 3, "protection after settlements");
        assertEq(uint256(launcher.getStageByVerseId(VERSE_ID)), uint256(IMemeverseLauncher.Stage.Unlocked), "unlocked");
    }

    function testChangeStage_RealPOLendZeroDebtVerseCanUnlock() external {
        _setGenesisVerse(uint128(block.timestamp), false);
        IMemeverseLauncher.Memeverse memory verse = launcher.getMemeverseByVerseId(VERSE_ID);
        verse.currentStage = IMemeverseLauncher.Stage.Locked;
        verse.unlockTime = uint128(block.timestamp);
        _writeVerseBack(verse);

        POLend realPolend = _deployRealPOLend();
        realPolend.setMaxSettlementDustReserve(address(uAsset), uint128(1e9));
        vm.prank(address(launcher));
        realPolend.registerLendMarket(VERSE_ID);
        setPolendForTest(launcherProxy, address(realPolend));
        vm.warp(block.timestamp + 1);

        assertEq(uint256(launcher.changeStage(VERSE_ID)), uint256(IMemeverseLauncher.Stage.Unlocked), "unlocked");
    }

    function testRedeemAuxiliaryLiquidity_UsesPostSettlementRemainingLp() external {
        _setGenesisVerse(uint128(block.timestamp), false);
        IMemeverseLauncher.Memeverse memory verse = launcher.getMemeverseByVerseId(VERSE_ID);
        verse.currentStage = IMemeverseLauncher.Stage.Unlocked;
        _writeVerseBack(verse);
        setGenesisFundForTest(launcherProxy, VERSE_ID, 1000 ether);
        setUserGenesisDataForTest(launcherProxy, VERSE_ID, address(this), 200 ether, false, false);
        polend.setTotalLeveragedDebt(VERSE_ID, 600 ether);

        setAuxiliaryLiquiditiesForTest(launcherProxy, VERSE_ID, 100 ether, 50 ether, 80 ether);
        router.setRemoveLiquidityResult(address(pol), address(uAsset), 30 ether, 15 ether);
        router.setRemoveLiquidityResult(address(pt), address(uAsset), 12 ether, 6 ether);
        router.setRemoveLiquidityResult(address(pt), address(pol), 20 ether, 10 ether);

        vm.prank(address(polend));
        launcher.settleLeveragedAuxiliaryLiquidity(VERSE_ID);

        polUAssetLp.mint(address(launcher), 100 ether);
        ptUAssetLp.mint(address(launcher), 50 ether);
        ptPolLp.mint(address(launcher), 80 ether);

        (uint256 polUAssetLpAmount, uint256 ptUAssetLpAmount, uint256 ptPolLpAmount) =
            launcher.redeemAuxiliaryLiquidity(VERSE_ID);
        assertEq(polUAssetLpAmount, 12.5 ether, "pol/uAsset lp");
        assertEq(ptUAssetLpAmount, 6.25 ether, "pt/uAsset lp");
        assertEq(ptPolLpAmount, 10 ether, "pt/pol lp");
        assertEq(polUAssetLp.balanceOf(address(this)), 12.5 ether, "caller pol/uAsset lp");
    }

    function testRedeemAuxiliaryLiquidity_DistributesNormalBootstrapResiduals() external {
        _setGenesisVerse(uint128(block.timestamp), false);
        IMemeverseLauncher.Memeverse memory verse = launcher.getMemeverseByVerseId(VERSE_ID);
        verse.currentStage = IMemeverseLauncher.Stage.Unlocked;
        _writeVerseBack(verse);
        setGenesisFundForTest(launcherProxy, VERSE_ID, 1000 ether);
        setUserGenesisDataForTest(launcherProxy, VERSE_ID, address(this), 200 ether, false, false);
        setAuxiliaryLiquiditiesForTest(launcherProxy, VERSE_ID, 100 ether, 50 ether, 80 ether);
        setBootstrapResidualClaimsForTest(launcherProxy, VERSE_ID, 25 ether, 10 ether, 0, 0);
        polUAssetLp.mint(address(launcher), 100 ether);
        ptUAssetLp.mint(address(launcher), 50 ether);
        ptPolLp.mint(address(launcher), 80 ether);
        pol.mint(address(launcher), 25 ether);
        pt.mint(address(launcher), 10 ether);

        uint256 polBefore = pol.balanceOf(address(this));
        uint256 ptBefore = pt.balanceOf(address(this));

        launcher.redeemAuxiliaryLiquidity(VERSE_ID);

        assertEq(pol.balanceOf(address(this)) - polBefore, 5 ether, "normal residual pol");
        assertEq(pt.balanceOf(address(this)) - ptBefore, 2 ether, "normal residual pt");
    }

    function testPreviewPreorderCapacity_IncreasesAfterLeveragedGenesis() external {
        _setGenesisVerse(uint128(block.timestamp + 1 days), false);
        POLend realPolend = _deployRealPOLend();
        realPolend.setMaxSettlementDustReserve(address(uAsset), uint128(1e9));
        vm.prank(address(launcher));
        realPolend.registerLendMarket(VERSE_ID);
        setPolendForTest(launcherProxy, address(realPolend));
        setGenesisFundForTest(launcherProxy, VERSE_ID, 100 ether);

        uint256 capacityBefore = launcher.previewPreorderCapacity(VERSE_ID);
        assertEq(capacityBefore, 17.5 ether, "capacity before");

        address caller = address(0xBEE);
        uAsset.mint(caller, 10 ether);
        vm.prank(caller);
        uAsset.approve(address(realPolend), 10 ether);
        vm.prank(caller);
        realPolend.leveragedGenesis(VERSE_ID, 10 ether);
        assertEq(realPolend.getTotalLeveragedDebt(VERSE_ID), 100 ether, "leveraged debt");

        uint256 capacityAfter = launcher.previewPreorderCapacity(VERSE_ID);
        assertEq(capacityAfter, 35 ether, "capacity after");
        assertGt(capacityAfter, capacityBefore, "capacity increased");
    }

    // --- Pure Leveraged Genesis: totalNormalFunds == 0, totalLeveragedDebt > 0 ---

    function testPureLeveragedGenesis_EndToEndLifecycle() external {
        uint256 leveragedDebt = 1000 ether;
        uint256 leveragedInterest = 100 ether;

        // ── Phase 1: Setup pure leveraged verse ──
        _setGenesisVerse(uint128(block.timestamp + 1 days), false);
        polend.setTotalLeveragedInterest(VERSE_ID, leveragedInterest);
        polend.setTotalLeveragedDebt(VERSE_ID, leveragedDebt);
        _seedLauncherAndPolendFunding(0, leveragedDebt);

        // ── Phase 2: Genesis → Locked ──
        vm.warp(block.timestamp + 1 days + 1);
        assertEq(uint256(launcher.changeStage(VERSE_ID)), uint256(IMemeverseLauncher.Stage.Locked), "stage locked");

        // 4 pools created, normal YT = 0, all YT to leveraged
        assertEq(router.createPoolAndAddLiquidityCallCount(), 4, "four pools");
        assertEq(MemeverseLauncher(launcherProxy).totalNormalClaimableYT(VERSE_ID), 0, "normal yt zero");
        IPOLend.LendMarket memory market = polend.getLendMarket(VERSE_ID);
        assertGt(market.totalLeveragedYT, 0, "leveraged yt exists");
        assertEq(yt.balanceOf(address(polend)), market.totalLeveragedYT, "yt at polend");
        assertEq(splitter.initializeVerseCallCount(), 1, "splitter initialized");

        // ── Phase 3: Locked → Unlocked ──
        IMemeverseLauncher.Memeverse memory verse = launcher.getMemeverseByVerseId(VERSE_ID);
        verse.currentStage = IMemeverseLauncher.Stage.Locked;
        verse.unlockTime = uint128(block.timestamp);
        _writeVerseBack(verse);
        vm.warp(block.timestamp + 1);

        launcher.changeStage(VERSE_ID);

        assertEq(uint256(launcher.getStageByVerseId(VERSE_ID)), uint256(IMemeverseLauncher.Stage.Unlocked), "unlocked");
        assertEq(splitter.lastCallIndex(), 1, "splitter settled");
        assertEq(polend.lastCallIndex(), 2, "polend settled");

        // ── Phase 4: Normal-side claims revert ──
        vm.expectRevert(IMemeverseLauncher.InvalidClaim.selector);
        launcher.claimNormalYT(VERSE_ID);

        vm.expectRevert(IMemeverseLauncher.InvalidClaim.selector);
        launcher.claimNormalFees(VERSE_ID);

        vm.expectRevert(IMemeverseLauncher.InvalidClaim.selector);
        launcher.redeemAuxiliaryLiquidity(VERSE_ID);

        // ── Phase 5: settleLeveragedAuxiliaryLiquidity → 100% to leveraged ──
        setAuxiliaryLiquiditiesForTest(launcherProxy, VERSE_ID, 100 ether, 50 ether, 80 ether);
        router.setRemoveLiquidityResult(address(pol), address(uAsset), 30 ether, 15 ether);
        router.setRemoveLiquidityResult(address(pt), address(uAsset), 12 ether, 6 ether);
        router.setRemoveLiquidityResult(address(pt), address(pol), 20 ether, 10 ether);

        vm.prank(address(polend));
        (uint256 polAmt, uint256 ptAmt, uint256 uAssetAmt) = launcher.settleLeveragedAuxiliaryLiquidity(VERSE_ID);

        assertEq(polAmt, 40 ether, "pol 100pct");
        assertEq(ptAmt, 32 ether, "pt 100pct");
        assertEq(uAssetAmt, 21 ether, "uAsset 100pct");

        // Remaining auxiliary LP should be 0 after full leveraged settlement
        (uint256 remPolUAsset, uint256 remPtUAsset, uint256 remPtPol) = MemeverseLauncher(launcherProxy).auxiliaryLiquidities(VERSE_ID);
        assertEq(remPolUAsset, 0, "remaining pol/uAsset");
        assertEq(remPtUAsset, 0, "remaining pt/uAsset");
        assertEq(remPtPol, 0, "remaining pt/pol");
    }
}
