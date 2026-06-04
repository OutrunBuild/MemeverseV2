// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Vm} from "forge-std/Vm.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta, toBalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {POLend} from "../../src/polend/POLend.sol";
import {POLSplitter} from "../../src/polend/POLSplitter.sol";
import {IPOLend} from "../../src/polend/interfaces/IPOLend.sol";
import {IMemeverseLauncher} from "../../src/verse/interfaces/IMemeverseLauncher.sol";
import {IMemeverseUniswapHook} from "../../src/swap/interfaces/IMemeverseUniswapHook.sol";
import {
    MockMemecoinForPOLendIntegration,
    MockPolForPOLendIntegration,
    MockProxyDeployerForPOLendIntegration,
    MockYieldDispatcherForPOLendIntegration,
    TestableMemeverseLauncherPOLend
} from "./MemeverseLauncherPOLendIntegration.t.sol";

contract UniversalAssetForPOLendSettlementInvariant is MockERC20 {
    uint256 public repaidAmount;

    constructor() MockERC20("UASSET", "UASSET", 18) {}

    function mint(address to, uint256 amount) public override {
        _mint(to, amount);
    }

    function repay(address account, uint256 amount) external {
        if (account != msg.sender) {
            uint256 allowed = allowance[account][msg.sender];
            require(allowed >= amount, "insufficient allowance");
            allowance[account][msg.sender] = allowed - amount;
        }
        repaidAmount += amount;
        _burn(account, amount);
    }
}

contract LPTokenForPOLendSettlementInvariant is MockERC20 {
    constructor(string memory name_, string memory symbol_) MockERC20(name_, symbol_, 18) {}

    function mint(address to, uint256 amount) public override {
        _mint(to, amount);
    }
}

contract HookForPOLendSettlementInvariant {
    address public immutable launcher;
    address public poolInitializer;
    mapping(bytes32 => uint40) public publicSwapResumeTimes;
    mapping(bytes32 => FeeQuote) internal claimQuotes;

    struct FeeQuote {
        uint256 fee0;
        uint256 fee1;
    }

    constructor(address launcher_) {
        launcher = launcher_;
    }

    function setClaimQuote(address tokenA, address tokenB, uint256 tokenAFee, uint256 tokenBFee) external {
        (uint256 fee0, uint256 fee1) = tokenA < tokenB ? (tokenAFee, tokenBFee) : (tokenBFee, tokenAFee);
        claimQuotes[_pairKey(tokenA, tokenB)] = FeeQuote({fee0: fee0, fee1: fee1});
    }

    function setPoolInitializer(address poolInitializer_) external {
        poolInitializer = poolInitializer_;
    }

    function setPublicSwapResumeTime(address tokenA, address tokenB, uint40 resumeTime) external {
        require(msg.sender == launcher, "not launcher");
        publicSwapResumeTimes[_pairKey(tokenA, tokenB)] = resumeTime;
    }

    function claimableFees(PoolKey calldata key, address)
        external
        view
        returns (uint256 fee0Amount, uint256 fee1Amount)
    {
        FeeQuote memory quote = claimQuotes[_pairKey(Currency.unwrap(key.currency0), Currency.unwrap(key.currency1))];
        return (quote.fee0, quote.fee1);
    }

    function claimFeesCore(IMemeverseUniswapHook.ClaimFeesCoreParams calldata params)
        external
        returns (uint256 fee0Amount, uint256 fee1Amount)
    {
        address token0 = Currency.unwrap(params.key.currency0);
        address token1 = Currency.unwrap(params.key.currency1);
        FeeQuote memory quote = claimQuotes[_pairKey(token0, token1)];
        fee0Amount = quote.fee0;
        fee1Amount = quote.fee1;
        delete claimQuotes[_pairKey(token0, token1)];

        if (fee0Amount != 0) _pay(token0, params.recipient, fee0Amount);
        if (fee1Amount != 0) _pay(token1, params.recipient, fee1Amount);
    }

    function _pay(address token, address recipient, uint256 amount) internal {
        if (MockERC20(token).balanceOf(address(this)) >= amount) {
            require(MockERC20(token).transfer(recipient, amount), "transfer failed");
        } else {
            UniversalAssetForPOLendSettlementInvariant(token).mint(recipient, amount);
        }
    }

    function _pairKey(address tokenA, address tokenB) internal pure returns (bytes32) {
        return keccak256(abi.encode(tokenA < tokenB ? tokenA : tokenB, tokenA < tokenB ? tokenB : tokenA));
    }
}

contract RouterForPOLendSettlementInvariant {
    address internal immutable hookAddress;
    uint128 internal createLiquidityResult;
    uint128 internal defaultAddLiquidityResult;
    mapping(bytes32 => address) internal lpTokens;
    mapping(bytes32 => uint128) internal pairCreateLiquidityResults;
    mapping(bytes32 => uint128) internal pairAddLiquidityResults;
    mapping(bytes32 => PairSpend) internal pairCreateSpends;
    mapping(bytes32 => mapping(address => uint256)) internal pairTokenPulled;
    mapping(bytes32 => PairQuote) internal exactLiquidityQuotes;
    mapping(bytes32 => PairOutputRate) internal outputRates;

    struct PairOutputRate {
        uint256 amount0PerLp;
        uint256 amount1PerLp;
    }

    struct PairQuote {
        uint256 amount0Required;
        uint256 amount1Required;
    }

    struct PairSpend {
        bool enabled;
        uint256 amount0Used;
        uint256 amount1Used;
    }

    constructor(address hookAddress_) {
        hookAddress = hookAddress_;
    }

    function hook() external view returns (address) {
        return hookAddress;
    }

    function setCreateLiquidityResult(uint128 liquidity) external {
        createLiquidityResult = liquidity;
    }

    function setPairCreateLiquidityResult(address tokenA, address tokenB, uint128 liquidity) external {
        pairCreateLiquidityResults[_pairKey(tokenA, tokenB)] = liquidity;
    }

    function setPairAddLiquidityResult(address tokenA, address tokenB, uint128 liquidity) external {
        pairAddLiquidityResults[_pairKey(tokenA, tokenB)] = liquidity;
    }

    function setPairCreateSpend(address tokenA, address tokenB, uint256 tokenAUsed, uint256 tokenBUsed) external {
        (uint256 amount0Used, uint256 amount1Used) =
            tokenA < tokenB ? (tokenAUsed, tokenBUsed) : (tokenBUsed, tokenAUsed);
        pairCreateSpends[_pairKey(tokenA, tokenB)] =
            PairSpend({enabled: true, amount0Used: amount0Used, amount1Used: amount1Used});
    }

    function pulledForPair(address tokenA, address tokenB, address token) external view returns (uint256) {
        return pairTokenPulled[_pairKey(tokenA, tokenB)][token];
    }

    function setExactLiquidityQuote(address tokenA, address tokenB, uint256 tokenARequired, uint256 tokenBRequired)
        external
    {
        (uint256 amount0Required, uint256 amount1Required) =
            tokenA < tokenB ? (tokenARequired, tokenBRequired) : (tokenBRequired, tokenARequired);
        exactLiquidityQuotes[_pairKey(tokenA, tokenB)] =
            PairQuote({amount0Required: amount0Required, amount1Required: amount1Required});
    }

    function setDefaultAddLiquidityResult(uint128 liquidity) external {
        defaultAddLiquidityResult = liquidity;
    }

    function setLpToken(address tokenA, address tokenB, address liquidityToken) external {
        lpTokens[_pairKey(tokenA, tokenB)] = liquidityToken;
    }

    function lpToken(address tokenA, address tokenB) external view returns (address liquidityToken) {
        return lpTokens[_pairKey(tokenA, tokenB)];
    }

    function setPairOutputPerLp(address tokenA, address tokenB, uint256 tokenAOutPerLp, uint256 tokenBOutPerLp)
        external
    {
        (uint256 amount0PerLp, uint256 amount1PerLp) =
            tokenA < tokenB ? (tokenAOutPerLp, tokenBOutPerLp) : (tokenBOutPerLp, tokenAOutPerLp);
        outputRates[_pairKey(tokenA, tokenB)] = PairOutputRate({amount0PerLp: amount0PerLp, amount1PerLp: amount1PerLp});
    }

    function createPoolAndAddLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint160,
        address to,
        uint256
    ) external returns (uint128 liquidity, PoolKey memory poolKey, uint256 amountAUsed, uint256 amountBUsed) {
        (amountAUsed, amountBUsed) = _createSpendForPair(tokenA, tokenB, amountADesired, amountBDesired);
        _pull(tokenA, amountAUsed);
        _pull(tokenB, amountBUsed);
        pairTokenPulled[_pairKey(tokenA, tokenB)][tokenA] += amountAUsed;
        pairTokenPulled[_pairKey(tokenA, tokenB)][tokenB] += amountBUsed;
        liquidity = _createLiquidityForPair(tokenA, tokenB);
        LPTokenForPOLendSettlementInvariant(_lpTokenOrCreate(tokenA, tokenB)).mint(to, liquidity);
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
        uint256,
        uint256,
        address to,
        uint256
    ) external returns (uint128 liquidity) {
        address token0 = Currency.unwrap(currency0);
        address token1 = Currency.unwrap(currency1);
        _pull(token0, amount0Desired);
        _pull(token1, amount1Desired);
        liquidity = defaultAddLiquidityResult;
        LPTokenForPOLendSettlementInvariant(_lpTokenOrCreate(token0, token1)).mint(to, liquidity);
    }

    function quoteExactAmountsForLiquidity(address tokenA, address tokenB, uint128)
        external
        view
        returns (uint256 amountARequired, uint256 amountBRequired)
    {
        PairQuote memory quote = exactLiquidityQuotes[_pairKey(tokenA, tokenB)];
        if (tokenA < tokenB) return (quote.amount0Required, quote.amount1Required);
        return (quote.amount1Required, quote.amount0Required);
    }

    function addLiquidityDetailed(
        Currency currency0,
        Currency currency1,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        address to,
        uint256
    ) external returns (uint128 liquidity, uint256 amount0Used, uint256 amount1Used) {
        require(amount0Desired >= amount0Min, "amount0 below min");
        require(amount1Desired >= amount1Min, "amount1 below min");
        address token0 = Currency.unwrap(currency0);
        address token1 = Currency.unwrap(currency1);
        _pull(token0, amount0Desired);
        _pull(token1, amount1Desired);
        liquidity = pairAddLiquidityResults[_pairKey(token0, token1)];
        if (liquidity == 0) liquidity = defaultAddLiquidityResult;
        LPTokenForPOLendSettlementInvariant(_lpTokenOrCreate(token0, token1)).mint(to, liquidity);
        return (liquidity, amount0Desired, amount1Desired);
    }

    function removeLiquidity(
        Currency currency0,
        Currency currency1,
        uint128 liquidity,
        uint256,
        uint256,
        address to,
        uint256
    ) external returns (BalanceDelta delta) {
        address tokenA = Currency.unwrap(currency0);
        address tokenB = Currency.unwrap(currency1);
        bytes32 pairKey = _pairKey(tokenA, tokenB);
        require(MockERC20(lpTokens[pairKey]).transferFrom(msg.sender, address(this), liquidity), "transfer failed");

        PairOutputRate memory rate = outputRates[pairKey];
        uint256 amount0Out = uint256(liquidity) * rate.amount0PerLp / 1 ether;
        uint256 amount1Out = uint256(liquidity) * rate.amount1PerLp / 1 ether;
        address token0 = tokenA < tokenB ? tokenA : tokenB;
        address token1 = tokenA < tokenB ? tokenB : tokenA;
        if (amount0Out != 0) _pay(token0, to, amount0Out);
        if (amount1Out != 0) _pay(token1, to, amount1Out);
        return toBalanceDelta(int128(uint128(amount0Out)), int128(uint128(amount1Out)));
    }

    function _pull(address token, uint256 amount) internal {
        if (amount != 0) require(MockERC20(token).transferFrom(msg.sender, address(this), amount), "transfer failed");
    }

    function _lpTokenOrCreate(address tokenA, address tokenB) internal returns (address liquidityToken) {
        bytes32 pairKey = _pairKey(tokenA, tokenB);
        liquidityToken = lpTokens[pairKey];
        if (liquidityToken == address(0)) {
            liquidityToken = address(new LPTokenForPOLendSettlementInvariant("AUTO-LP", "AUTO-LP"));
            lpTokens[pairKey] = liquidityToken;
        }
    }

    function _createLiquidityForPair(address tokenA, address tokenB) internal view returns (uint128 liquidity) {
        liquidity = pairCreateLiquidityResults[_pairKey(tokenA, tokenB)];
        if (liquidity != 0) return liquidity;
        if (defaultAddLiquidityResult != 0) return defaultAddLiquidityResult;
        return createLiquidityResult;
    }

    function _pay(address token, address to, uint256 amount) internal {
        if (MockERC20(token).balanceOf(address(this)) >= amount) {
            require(MockERC20(token).transfer(to, amount), "transfer failed");
        } else {
            UniversalAssetForPOLendSettlementInvariant(token).mint(to, amount);
        }
    }

    function _createSpendForPair(address tokenA, address tokenB, uint256 amountADesired, uint256 amountBDesired)
        internal
        view
        returns (uint256 amountAUsed, uint256 amountBUsed)
    {
        PairSpend memory spend = pairCreateSpends[_pairKey(tokenA, tokenB)];
        if (!spend.enabled) return (amountADesired, amountBDesired);
        if (tokenA < tokenB) return (spend.amount0Used, spend.amount1Used);
        return (spend.amount1Used, spend.amount0Used);
    }

    function _pairKey(address tokenA, address tokenB) internal pure returns (bytes32) {
        return keccak256(abi.encode(tokenA < tokenB ? tokenA : tokenB, tokenA < tokenB ? tokenB : tokenA));
    }
}

contract MemeverseLauncherPOLendSettlementInvariantTest is Test {
    uint256 internal constant VERSE_ID = 1;
    uint256 internal constant NORMAL_FUNDS = 10 ether;
    uint256 internal constant LEVERAGED_INTEREST = 1 ether;
    uint256 internal constant LEVERAGED_DEBT = 10 ether;
    uint256 internal constant MAIN_LIQUIDITY = 70 ether;
    uint256 internal constant AUXILIARY_LIQUIDITY = 100 ether;
    uint256 internal constant MAX_SETTLEMENT_DUST = 100;

    address internal constant ALICE = address(0xA11CE);
    address internal constant LEVERAGED_USER = address(0x1E4);
    address internal constant TREASURY = address(0x7E45);

    TestableMemeverseLauncherPOLend internal launcher;
    UniversalAssetForPOLendSettlementInvariant internal uAsset;
    MockMemecoinForPOLendIntegration internal memecoin;
    MockPolForPOLendIntegration internal pol;
    POLend internal polend;
    POLSplitter internal splitter;
    RouterForPOLendSettlementInvariant internal router;
    HookForPOLendSettlementInvariant internal hook;
    MockYieldDispatcherForPOLendIntegration internal dispatcher;
    LPTokenForPOLendSettlementInvariant internal mainLp;
    LPTokenForPOLendSettlementInvariant internal polUAssetLp;

    function setUp() external {
        launcher = (new TestableMemeverseLauncherPOLend())
        .createProxy(
            address(this),
            address(0x1),
            address(0x2),
            address(0x3),
            address(0x4),
            address(0x5),
            address(0x10),
            address(0x11),
            25,
            115_000,
            135_000,
            2_500,
            7 days
        );

        uAsset = new UniversalAssetForPOLendSettlementInvariant();
        memecoin = new MockMemecoinForPOLendIntegration(address(launcher));
        pol = new MockPolForPOLendIntegration(address(launcher), address(memecoin));
        hook = new HookForPOLendSettlementInvariant(address(launcher));
        router = new RouterForPOLendSettlementInvariant(address(hook));
        dispatcher = new MockYieldDispatcherForPOLendIntegration();

        address predictedSplitter = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 3);
        polend = _deployPOLend(predictedSplitter);
        launcher.setPolendForTest(address(polend));
        splitter = _deploySplitter();

        launcher.setMemeverseUniswapHook(address(hook));
        hook.setPoolInitializer(address(router));
        launcher.setMemeverseSwapRouter(address(router));
        launcher.setYieldDispatcher(address(dispatcher));
        launcher.setMemeverseProxyDeployer(address(new MockProxyDeployerForPOLendIntegration()));
        launcher.setPolSplitterForTest(address(splitter));
        launcher.setFundMetaData(address(uAsset), LEVERAGED_INTEREST, 1);

        polend.setMaxSettlementDustReserve(address(uAsset), uint128(MAX_SETTLEMENT_DUST));

        mainLp = new LPTokenForPOLendSettlementInvariant("MEME-UASSET-LP", "MEME-UASSET-LP");
        polUAssetLp = new LPTokenForPOLendSettlementInvariant("POL-UASSET-LP", "POL-UASSET-LP");
        router.setLpToken(address(memecoin), address(uAsset), address(mainLp));
        router.setLpToken(address(pol), address(uAsset), address(polUAssetLp));
        router.setCreateLiquidityResult(uint128(MAIN_LIQUIDITY));
        router.setDefaultAddLiquidityResult(uint128(AUXILIARY_LIQUIDITY));
        router.setPairCreateLiquidityResult(address(memecoin), address(uAsset), uint128(MAIN_LIQUIDITY));
        router.setPairOutputPerLp(address(memecoin), address(uAsset), 0, 1 ether);
    }

    function testRealPathMixedFundsCoversSettlementDustAndLeavesNormalAuxiliaryRemainder() external {
        _setGenesisVerse(uint128(block.timestamp + 1 days));
        _registerLendMarket();
        _normalGenesis(NORMAL_FUNDS);
        _leveragedGenesis(LEVERAGED_INTEREST);
        _allowLauncherToSplitPOL();

        vm.warp(block.timestamp + 1 days + 1);
        assertEq(uint256(launcher.changeStage(VERSE_ID)), uint256(IMemeverseLauncher.Stage.Locked), "genesis locked");
        assertEq(pol.allowance(address(launcher), address(splitter)), type(uint256).max, "splitter allowance inf");
        (uint256 ptBackingNumerator, uint256 ptBackingDenominator) = splitter.ptBackingRatios(VERSE_ID);
        assertEq(ptBackingNumerator, (NORMAL_FUNDS + LEVERAGED_DEBT) * 7 / 10, "pt backing numerator");
        assertEq(ptBackingDenominator, MAIN_LIQUIDITY, "pt backing denominator");

        (address pt,,,,,,,,,,) = splitter.splitInfos(VERSE_ID);
        router.setPairOutputPerLp(address(pol), address(uAsset), 0.04 ether, 0.08 ether);
        router.setPairOutputPerLp(pt, address(uAsset), 0.1 ether - 5, 0.06 ether);
        router.setPairOutputPerLp(pt, address(pol), 0, 0);
        hook.setClaimQuote(address(pol), address(uAsset), 0, 10 ether);

        assertEq(uint256(launcher.changeStage(VERSE_ID)), uint256(IMemeverseLauncher.Stage.Locked), "still locked");

        (uint128 reserveBeforeSettlement,) = polend.settlementDustStates(address(uAsset));
        uint256 treasuryBeforeSettlement = uAsset.balanceOf(TREASURY);
        uint256 globalDebtBeforeSettlement = polend.getTotalDebtByUAsset(address(uAsset));
        uint256 expectedRecoveredUAsset = LEVERAGED_DEBT - 50;
        uint256 consumedSettlementDust = LEVERAGED_DEBT - expectedRecoveredUAsset;
        assertLe(consumedSettlementDust, reserveBeforeSettlement, "reserve cap");

        IMemeverseLauncher.Memeverse memory verse = launcher.getMemeverseByVerseId(VERSE_ID);
        vm.warp(verse.unlockTime + 1);
        assertEq(uint256(launcher.changeStage(VERSE_ID)), uint256(IMemeverseLauncher.Stage.Unlocked), "unlocked");

        {
            (address settlementPt,,,,,, uint256 splitterSettlementUAsset,,,,) = splitter.splitInfos(VERSE_ID);
            uint256 settlementPTBacking = splitter.previewPTToUAsset(VERSE_ID, MockERC20(settlementPt).totalSupply());
            assertGe(splitterSettlementUAsset, settlementPTBacking, "settlementUAsset >= PT backing");
        }

        IPOLend.LendMarket memory market = polend.getLendMarket(VERSE_ID);
        (uint256 residualUAsset,) = polend.residualStates(VERSE_ID);
        (uint256 accUAssetFee, uint256 accPTFee) = launcher.normalFeeStates(VERSE_ID);
        (uint256 polUAssetLpAmount, uint256 ptUAssetLpAmount, uint256 ptPolLpAmount) =
            launcher.auxiliaryLiquidities(VERSE_ID);

        assertEq(uint256(market.state), uint256(IPOLend.MarketState.Settled), "market settled");
        assertEq(globalDebtBeforeSettlement, LEVERAGED_DEBT, "pre settlement global debt");
        assertEq(
            globalDebtBeforeSettlement - LEVERAGED_DEBT,
            polend.getTotalDebtByUAsset(address(uAsset)),
            "global debt conserved"
        );
        assertEq(polend.getTotalDebtByUAsset(address(uAsset)), 0, "global debt cleared");
        (uint128 reserveAfterSettlement,) = polend.settlementDustStates(address(uAsset));
        assertEq(reserveAfterSettlement, reserveBeforeSettlement - consumedSettlementDust, "reserve after");
        assertEq(residualUAsset, 0, "dust covered deficit");
        assertEq(uAsset.balanceOf(TREASURY), treasuryBeforeSettlement, "unused reserve not swept");
        assertEq(polUAssetLpAmount, 50 ether, "normal pol/uAsset lp");
        assertEq(ptUAssetLpAmount, 50 ether, "normal pt/uAsset lp");
        assertEq(ptPolLpAmount, 50 ether, "normal pt/pol lp");
        assertEq(accUAssetFee, 5 ether, "locked normal uAsset fees");
        assertEq(accPTFee, 0, "no pt fees captured");
        assertEq(uAsset.repaidAmount(), LEVERAGED_DEBT, "debt repaid");
    }

    function testRealPathPureLeveragedBoundaryConsumesAllAuxiliaryLiquidity() external {
        _setGenesisVerse(uint128(block.timestamp + 1 days));
        _registerLendMarket();
        _leveragedGenesis(LEVERAGED_INTEREST);
        _allowLauncherToSplitPOL();

        vm.warp(block.timestamp + 1 days + 1);
        assertEq(uint256(launcher.changeStage(VERSE_ID)), uint256(IMemeverseLauncher.Stage.Locked), "genesis locked");
        assertEq(pol.allowance(address(launcher), address(splitter)), type(uint256).max, "splitter allowance inf");

        (address pt,,,,,,,,,,) = splitter.splitInfos(VERSE_ID);
        router.setPairOutputPerLp(address(pol), address(uAsset), 0.02 ether, 0.04 ether);
        router.setPairOutputPerLp(pt, address(uAsset), 0.1 ether, 0.03 ether);
        router.setPairOutputPerLp(pt, address(pol), 0, 0);

        uint256 globalDebtBeforeSettlement = polend.getTotalDebtByUAsset(address(uAsset));
        IMemeverseLauncher.Memeverse memory verse = launcher.getMemeverseByVerseId(VERSE_ID);
        vm.warp(verse.unlockTime + 1);
        assertEq(uint256(launcher.changeStage(VERSE_ID)), uint256(IMemeverseLauncher.Stage.Unlocked), "unlocked");

        {
            (address settlementPt,,,,,, uint256 splitterSettlementUAsset,,,,) = splitter.splitInfos(VERSE_ID);
            uint256 settlementPTBacking = splitter.previewPTToUAsset(VERSE_ID, MockERC20(settlementPt).totalSupply());
            assertGe(splitterSettlementUAsset, settlementPTBacking, "settlementUAsset >= PT backing");
        }

        IPOLend.LendMarket memory market = polend.getLendMarket(VERSE_ID);
        (uint256 residualUAsset,) = polend.residualStates(VERSE_ID);
        (uint256 polUAssetLpAmount, uint256 ptUAssetLpAmount, uint256 ptPolLpAmount) =
            launcher.auxiliaryLiquidities(VERSE_ID);

        assertEq(uint256(market.state), uint256(IPOLend.MarketState.Settled), "market settled");
        assertEq(globalDebtBeforeSettlement, LEVERAGED_DEBT, "pre settlement global debt");
        assertEq(
            globalDebtBeforeSettlement - LEVERAGED_DEBT,
            polend.getTotalDebtByUAsset(address(uAsset)),
            "global debt conserved"
        );
        assertEq(polend.getTotalDebtByUAsset(address(uAsset)), 0, "global debt cleared");
        (uint128 reserveAfterSettlement,) = polend.settlementDustStates(address(uAsset));
        assertEq(reserveAfterSettlement, MAX_SETTLEMENT_DUST, "reserve unchanged");
        assertEq(residualUAsset, 0, "exact recovery");
        assertEq(polUAssetLpAmount, 0, "pol/uAsset lp consumed");
        assertEq(ptUAssetLpAmount, 0, "pt/uAsset lp consumed");
        assertEq(ptPolLpAmount, 0, "pt/pol lp consumed");
        assertEq(launcher.totalNormalClaimableYT(VERSE_ID), 0, "no normal yt");
        assertEq(uAsset.repaidAmount(), LEVERAGED_DEBT, "debt repaid");
    }

    function testLockDerivesAuxiliaryUAssetFromActualMainBackingAndRoutesUnusedBudget() external {
        uint256 totalGenesisFunds = NORMAL_FUNDS + LEVERAGED_DEBT;
        uint256 mainPoolUAssetUsed = 10 ether;
        uint256 mainUAssetFunds = totalGenesisFunds * 7 / 10;
        uint256 memecoinAmount = mainUAssetFunds;
        uint256 polForPolUAsset = MAIN_LIQUIDITY * 2 / 7;
        uint256 polToSplit = MAIN_LIQUIDITY * 3 / 7;
        uint256 ptForPtUAsset = polToSplit / 3;
        uint256 expectedPolUAsset = polForPolUAsset * mainPoolUAssetUsed / MAIN_LIQUIDITY;

        polend.setMaxSettlementDustReserve(address(uAsset), uint128(20 ether));
        router.setPairCreateSpend(address(memecoin), address(uAsset), memecoinAmount, mainPoolUAssetUsed);

        _setGenesisVerse(uint128(block.timestamp + 1 days));
        _registerLendMarket();
        _normalGenesis(NORMAL_FUNDS);
        _leveragedGenesis(LEVERAGED_INTEREST);
        _allowLauncherToSplitPOL();

        uint256 treasuryBefore = uAsset.balanceOf(TREASURY);
        vm.warp(block.timestamp + 1 days + 1);
        assertEq(uint256(launcher.changeStage(VERSE_ID)), uint256(IMemeverseLauncher.Stage.Locked), "genesis locked");

        (address pt,,,,,,,,,,) = splitter.splitInfos(VERSE_ID);
        uint256 expectedPtUAsset = splitter.previewPTToUAsset(VERSE_ID, ptForPtUAsset);
        uint256 expectedUnusedUAsset = totalGenesisFunds - mainPoolUAssetUsed - expectedPolUAsset - expectedPtUAsset;

        (uint256 backingNumerator, uint256 backingDenominator) = splitter.ptBackingRatios(VERSE_ID);
        assertEq(backingNumerator, mainPoolUAssetUsed, "backing numerator");
        assertEq(backingDenominator, MAIN_LIQUIDITY, "backing denominator");
        assertEq(
            router.pulledForPair(address(pol), address(uAsset), address(uAsset)),
            expectedPolUAsset,
            "pol/uAsset backing spend"
        );
        assertEq(
            router.pulledForPair(pt, address(uAsset), address(uAsset)), expectedPtUAsset, "pt/uAsset backing spend"
        );
        (uint128 reserveAfterLock,) = polend.settlementDustStates(address(uAsset));
        assertEq(reserveAfterLock, LEVERAGED_INTEREST + expectedUnusedUAsset, "unused bootstrap reserve");
        assertEq(uAsset.balanceOf(TREASURY), treasuryBefore, "no treasury excess");
    }

    function testRealPathFundBasedAmountAboveOneCoversSettlementPTBacking() external {
        uint256 fundBasedAmount = 4;
        uint256 mainUAssetFunds = LEVERAGED_DEBT * 7 / 10;
        uint128 mainLiquidity = uint128(mainUAssetFunds * 2);
        uint256 memecoinPerMainLp = mainUAssetFunds * fundBasedAmount * 1 ether / mainLiquidity;
        uint256 uAssetPerMainLp = mainUAssetFunds * 1 ether / mainLiquidity;

        launcher.setFundMetaData(address(uAsset), LEVERAGED_INTEREST, fundBasedAmount);
        router.setPairCreateLiquidityResult(address(memecoin), address(uAsset), mainLiquidity);
        router.setPairOutputPerLp(address(memecoin), address(uAsset), memecoinPerMainLp, uAssetPerMainLp);

        _setGenesisVerse(uint128(block.timestamp + 1 days));
        _registerLendMarket();
        _leveragedGenesis(LEVERAGED_INTEREST);
        _allowLauncherToSplitPOL();

        vm.warp(block.timestamp + 1 days + 1);
        assertEq(uint256(launcher.changeStage(VERSE_ID)), uint256(IMemeverseLauncher.Stage.Locked), "genesis locked");
        (uint256 ptBackingNumerator, uint256 ptBackingDenominator) = splitter.ptBackingRatios(VERSE_ID);
        assertEq(ptBackingNumerator, mainUAssetFunds, "pt backing numerator");
        assertEq(ptBackingDenominator, mainLiquidity, "pt backing denominator");

        uint256 polForPolUAsset = uint256(mainLiquidity) * 2 / 7;
        uint256 polToSplit = uint256(mainLiquidity) * 3 / 7;
        uint256 ptForPtUAsset = polToSplit / 3;
        uint256 ptForPtPol = polToSplit - ptForPtUAsset;
        uint256 polForPtPol = uint256(mainLiquidity) - polForPolUAsset - polToSplit;
        uint256 auxiliaryFunds = LEVERAGED_DEBT - mainUAssetFunds;
        uint256 polUAssetFunds = auxiliaryFunds * 2 / 3;
        uint256 ptUAssetFunds = auxiliaryFunds - polUAssetFunds;

        (address pt,,,,,,,,,,) = splitter.splitInfos(VERSE_ID);
        router.setPairOutputPerLp(
            address(pol),
            address(uAsset),
            polForPolUAsset * 1 ether / AUXILIARY_LIQUIDITY,
            polUAssetFunds * 1 ether / AUXILIARY_LIQUIDITY
        );
        router.setPairOutputPerLp(
            pt,
            address(uAsset),
            ptForPtUAsset * 1 ether / AUXILIARY_LIQUIDITY,
            ptUAssetFunds * 1 ether / AUXILIARY_LIQUIDITY
        );
        router.setPairOutputPerLp(
            pt, address(pol), ptForPtPol * 1 ether / AUXILIARY_LIQUIDITY, polForPtPol * 1 ether / AUXILIARY_LIQUIDITY
        );

        IMemeverseLauncher.Memeverse memory verse = launcher.getMemeverseByVerseId(VERSE_ID);
        vm.warp(verse.unlockTime + 1);
        assertEq(uint256(launcher.changeStage(VERSE_ID)), uint256(IMemeverseLauncher.Stage.Unlocked), "unlocked");

        (address settlementPt,,,,,, uint256 splitterSettlementUAsset,,,,) = splitter.splitInfos(VERSE_ID);
        uint256 settlementPTBacking = splitter.previewPTToUAsset(VERSE_ID, MockERC20(settlementPt).totalSupply());
        assertGe(splitterSettlementUAsset, settlementPTBacking, "settlementUAsset >= PT backing");
    }

    function testRealPathLockedPreRedeemPTFeeSettlementBacking() external {
        _setGenesisVerse(uint128(block.timestamp + 1 days));
        _registerLendMarket();
        _normalGenesis(NORMAL_FUNDS);
        _leveragedGenesis(LEVERAGED_INTEREST);
        _allowLauncherToSplitPOL();

        vm.warp(block.timestamp + 1 days + 1);
        assertEq(uint256(launcher.changeStage(VERSE_ID)), uint256(IMemeverseLauncher.Stage.Locked), "genesis locked");
        IMemeverseLauncher.Memeverse memory sameChainVerse = launcher.getMemeverseByVerseId(VERSE_ID);
        sameChainVerse.omnichainIds[0] = uint32(block.chainid);
        launcher.setMemeverseForTest(VERSE_ID, sameChainVerse);

        (address pt,,,,,,,,,,) = splitter.splitInfos(VERSE_ID);
        uint256 polAmount = 10 ether;
        uint256 ptFee = 2 ether;
        uint256 requiredUAsset = splitter.previewPTToUAsset(VERSE_ID, polAmount);
        uint256 requiredMemecoin = 10 ether;

        uAsset.mint(ALICE, requiredUAsset);
        memecoin.mint(ALICE, requiredMemecoin);
        router.setExactLiquidityQuote(address(uAsset), address(memecoin), requiredUAsset, requiredMemecoin);
        router.setPairAddLiquidityResult(address(uAsset), address(memecoin), uint128(polAmount));

        vm.startPrank(ALICE);
        uAsset.approve(address(launcher), requiredUAsset);
        memecoin.approve(address(launcher), requiredMemecoin);
        launcher.mintPOLToken(VERSE_ID, requiredUAsset, requiredMemecoin, 0, 0, polAmount, block.timestamp);
        pol.approve(address(splitter), polAmount);
        splitter.split(VERSE_ID, polAmount);
        // solhint-disable-next-line erc20-unchecked-transfer
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        MockERC20(pt).transfer(address(hook), ptFee);
        vm.stopPrank();

        hook.setClaimQuote(pt, address(uAsset), ptFee, 0);
        launcher.redeemAndDistributeFees(VERSE_ID, address(0xE));
        (uint256 preRedeemedPTAmount, uint256 preRedeemedUAssetBacking) = splitter.preRedeemedStates(VERSE_ID);
        uint256 expectedPreRedeemedPTAmount = ptFee * LEVERAGED_DEBT / (NORMAL_FUNDS + LEVERAGED_DEBT);
        uint256 expectedPreRedeemedUAssetBacking = splitter.previewPTToUAsset(VERSE_ID, expectedPreRedeemedPTAmount);
        assertEq(preRedeemedPTAmount, expectedPreRedeemedPTAmount, "preRedeemed pt");
        assertEq(preRedeemedUAssetBacking, expectedPreRedeemedUAssetBacking, "preRedeemed backing");
        assertEq(MockERC20(pt).balanceOf(address(hook)), 0, "hook pt fee consumed");

        router.setPairOutputPerLp(address(pol), address(uAsset), 0.04 ether, 0.08 ether);
        router.setPairOutputPerLp(pt, address(uAsset), 0.2 ether, 0.06 ether);
        router.setPairOutputPerLp(pt, address(pol), 0, 0);

        IMemeverseLauncher.Memeverse memory verse = launcher.getMemeverseByVerseId(VERSE_ID);
        vm.warp(verse.unlockTime + 1);
        assertEq(uint256(launcher.changeStage(VERSE_ID)), uint256(IMemeverseLauncher.Stage.Unlocked), "unlocked");

        (address settlementPt,,,,,, uint256 splitterSettlementUAsset,,,,) = splitter.splitInfos(VERSE_ID);
        uint256 settlementPTBacking = splitter.previewPTToUAsset(VERSE_ID, MockERC20(settlementPt).totalSupply());
        assertGe(splitterSettlementUAsset, settlementPTBacking, "settlementUAsset >= PT backing");
    }

    function _deploySplitter() internal returns (POLSplitter deployedSplitter) {
        POLSplitter implementation = new POLSplitter();
        bytes memory data = abi.encodeCall(POLSplitter.initialize, (address(this), address(launcher)));
        return POLSplitter(address(new ERC1967Proxy(address(implementation), data)));
    }

    function _deployPOLend(address splitter_) internal returns (POLend deployedPOLend) {
        POLend implementation = new POLend();
        bytes memory data = abi.encodeCall(
            POLend.initialize, (address(this), 0.1 ether, 10 ether, TREASURY, address(launcher), splitter_)
        );
        return POLend(address(new ERC1967Proxy(address(implementation), data)));
    }

    function _setGenesisVerse(uint128 endTime) internal {
        IMemeverseLauncher.Memeverse memory verse;
        verse.name = "Verse";
        verse.symbol = "VRS";
        verse.uAsset = address(uAsset);
        verse.memecoin = address(memecoin);
        verse.pol = address(pol);
        verse.governor = address(0xCAFE);
        verse.yieldVault = address(0xD00D);
        verse.currentStage = IMemeverseLauncher.Stage.Genesis;
        verse.endTime = endTime;
        verse.unlockTime = endTime + 7 days;
        verse.omnichainIds = new uint32[](1);
        verse.omnichainIds[0] = uint32(block.chainid + 1);
        launcher.setMemeverseForTest(VERSE_ID, verse);
    }

    function _registerLendMarket() internal {
        vm.prank(address(launcher));
        polend.registerLendMarket(VERSE_ID);
    }

    function _normalGenesis(uint256 amount) internal {
        uAsset.mint(ALICE, amount);
        vm.startPrank(ALICE);
        uAsset.approve(address(launcher), amount);
        launcher.genesis(VERSE_ID, amount, ALICE);
        vm.stopPrank();
    }

    function _leveragedGenesis(uint256 interestAmount) internal {
        uAsset.mint(LEVERAGED_USER, interestAmount);
        vm.startPrank(LEVERAGED_USER);
        uAsset.approve(address(polend), interestAmount);
        polend.leveragedGenesis(VERSE_ID, interestAmount);
        vm.stopPrank();
    }

    function _allowLauncherToSplitPOL() internal {
        vm.prank(address(launcher));
        pol.approve(address(splitter), type(uint256).max);
    }
}

contract SettlementDustInvariantHandler is Test {
    uint256 internal constant VERSE_ID = 1;
    uint256 internal constant OTHER_VERSE_ID = 2;
    uint256 internal constant MAIN_LIQUIDITY = 70 ether;
    uint256 internal constant AUXILIARY_LIQUIDITY = 100 ether;
    uint256 internal constant MAIN_UASSET_RATE = 1 ether;

    address internal constant ALICE = address(0xA11CE);
    address internal constant LEVERAGED_USER = address(0x1E4);
    address internal constant OTHER_LEVERAGED_USER = address(0x2E4);
    address internal constant TREASURY = address(0x7E45);

    bytes32 internal constant GLOBAL_SETTLEMENT_EXECUTED =
        keccak256("GlobalSettlementExecuted(uint256,address,uint256,uint256,uint256,uint256,uint256,uint256)");

    bool public attempted;
    bool public succeeded;
    uint256 public debt;
    uint256 public expectedRecoveredUAsset;
    uint256 public recoveredUAsset;
    uint256 public consumedSettlementDust;
    uint256 public settlementDustReserveAfter;
    uint256 public residualUAsset;
    uint256 public totalLeveragedInterest;
    uint256 public autoReserve;
    uint256 public treasuryInterest;
    uint256 public bootstrapUnusedUAsset;
    uint256 public extraReserve;
    uint256 public reserveBeforeSettlement;
    uint256 public reserveAfterSettlement;
    uint256 public maxReserve;
    uint256 public treasuryDelta;
    uint256 public repaidAmount;
    uint256 public otherMarketDebt;
    uint256 public expectedGlobalDebtAfterSettlement;
    uint256 public globalDebtBeforeSettlement;
    uint256 public globalDebtAfter;
    uint256 public marketStateAfter;
    uint256 public stageAfter;
    uint256 public otherMarketStateAfter;
    uint256 public settlementUAssetAfter;
    uint256 public ptTotalSupplyAfter;
    uint256 public ptBackingAfter;
    uint256 public expectedSettlementUAssetBeforePTRedeem;
    uint256 public expectedRedeemedPTAmount;
    uint256 public expectedRedeemedPTBacking;
    uint256 public expectedOutstandingPTBackingBeforeSettlement;
    uint256 public initialPolUAssetLp;
    uint256 public initialPtUAssetLp;
    uint256 public initialPtPolLp;
    uint256 public remainingPolUAssetLp;
    uint256 public remainingPtUAssetLp;
    uint256 public remainingPtPolLp;
    uint256 public expectedRemainingPolUAssetLp;
    uint256 public expectedRemainingPtUAssetLp;
    uint256 public expectedRemainingPtPolLp;

    TestableMemeverseLauncherPOLend internal launcher;
    UniversalAssetForPOLendSettlementInvariant internal uAsset;
    MockMemecoinForPOLendIntegration internal memecoin;
    MockPolForPOLendIntegration internal pol;
    HookForPOLendSettlementInvariant internal hook;
    RouterForPOLendSettlementInvariant internal router;
    MockYieldDispatcherForPOLendIntegration internal dispatcher;
    POLSplitter internal splitter;
    POLend internal polend;

    constructor() {
        launcher = _deployLauncher();
        uAsset = new UniversalAssetForPOLendSettlementInvariant();
        memecoin = new MockMemecoinForPOLendIntegration(address(launcher));
        pol = new MockPolForPOLendIntegration(address(launcher), address(memecoin));
        hook = new HookForPOLendSettlementInvariant(address(launcher));
        router = new RouterForPOLendSettlementInvariant(address(hook));
        dispatcher = new MockYieldDispatcherForPOLendIntegration();
        splitter = _deploySplitter(launcher);
        polend = _deployPOLend(launcher, splitter);

        _wireLauncher(launcher, router, hook, dispatcher, splitter, polend);

        LPTokenForPOLendSettlementInvariant mainLp =
            new LPTokenForPOLendSettlementInvariant("MEME-UASSET-LP", "MEME-UASSET-LP");
        LPTokenForPOLendSettlementInvariant polUAssetLp =
            new LPTokenForPOLendSettlementInvariant("POL-UASSET-LP", "POL-UASSET-LP");
        router.setLpToken(address(memecoin), address(uAsset), address(mainLp));
        router.setLpToken(address(pol), address(uAsset), address(polUAssetLp));
        router.setCreateLiquidityResult(uint128(MAIN_LIQUIDITY));
        router.setDefaultAddLiquidityResult(uint128(AUXILIARY_LIQUIDITY));
        router.setPairCreateLiquidityResult(address(memecoin), address(uAsset), uint128(MAIN_LIQUIDITY));
    }

    function settle(
        uint256 normalFundsSeed,
        uint256 interestSeed,
        uint256 maxDustSeed,
        uint256 extraReserveSeed,
        uint256 polUAssetPolRateSeed,
        uint256 polUAssetUAssetRateSeed,
        uint256 ptUAssetPtRateSeed,
        uint256 ptUAssetUAssetRateSeed,
        uint256 ptPolPtRateSeed,
        uint256 ptPolPolRateSeed,
        uint256 mainMemecoinRateSeed,
        uint256 auxiliaryFeeSeed
    ) external {
        if (attempted) return;
        attempted = true;

        uint256 normalFunds = bound(normalFundsSeed, 0, 50 ether);
        uint256 leveragedInterest = bound(interestSeed, 1, 5 ether);
        maxReserve = bound(maxDustSeed, 1, 2 ether);
        extraReserve = bound(extraReserveSeed, 0, 2 ether);
        uint256 polUAssetPolRate = bound(polUAssetPolRateSeed, 0, 0.2 ether);
        uint256 polUAssetUAssetRate = bound(polUAssetUAssetRateSeed, 0, 0.5 ether);
        uint256 ptUAssetPtRate = bound(ptUAssetPtRateSeed, 0, 0.1 ether);
        uint256 ptUAssetUAssetRate = bound(ptUAssetUAssetRateSeed, 0, 0.5 ether);
        uint256 ptPolPtRate = bound(ptPolPtRateSeed, 0, 0.1 ether);
        uint256 ptPolPolRate = bound(ptPolPolRateSeed, 0, 0.2 ether);
        uint256 mainMemecoinRate = bound(mainMemecoinRateSeed, 0, 2 ether);
        uint256 auxiliaryUAssetFee = bound(auxiliaryFeeSeed, 0, 1 ether);

        launcher.setFundMetaData(address(uAsset), leveragedInterest, 1);
        polend.setMaxSettlementDustReserve(address(uAsset), uint128(maxReserve));

        router.setPairOutputPerLp(address(memecoin), address(uAsset), mainMemecoinRate, MAIN_UASSET_RATE);

        _setGenesisVerse(launcher, uAsset, memecoin, pol, uint128(block.timestamp + 1 days));
        vm.prank(address(launcher));
        polend.registerLendMarket(VERSE_ID);
        if (normalFunds != 0) _normalGenesis(launcher, uAsset, normalFunds);
        _leveragedGenesis(polend, uAsset, leveragedInterest);
        uint256 otherLeveragedInterest = leveragedInterest + 1;
        _createOtherOutstandingMarket(otherLeveragedInterest);

        vm.prank(address(launcher));
        pol.approve(address(splitter), type(uint256).max);

        uint256 treasuryBeforeLock = uAsset.balanceOf(TREASURY);
        vm.warp(block.timestamp + 1 days + 1);
        launcher.changeStage(VERSE_ID);
        totalLeveragedInterest = polend.getTotalLeveragedInterest(VERSE_ID);
        (uint128 reserveAfterLock,) = polend.settlementDustStates(address(uAsset));
        autoReserve = reserveAfterLock;
        treasuryInterest = uAsset.balanceOf(TREASURY) - treasuryBeforeLock;
        debt = polend.getTotalLeveragedDebt(VERSE_ID);
        (address pt,,,,,,,,,,) = splitter.splitInfos(VERSE_ID);
        uint256 launchUAssetSpend = router.pulledForPair(address(memecoin), address(uAsset), address(uAsset))
            + router.pulledForPair(address(pol), address(uAsset), address(uAsset))
            + router.pulledForPair(pt, address(uAsset), address(uAsset));
        uint256 launchFunds = normalFunds + debt;
        bootstrapUnusedUAsset = launchFunds > launchUAssetSpend ? launchFunds - launchUAssetSpend : 0;

        if (extraReserve != 0) {
            uAsset.mint(address(this), extraReserve);
            uAsset.approve(address(polend), extraReserve);
            polend.fundSettlementDustReserve(address(uAsset), extraReserve);
        }

        router.setPairOutputPerLp(address(pol), address(uAsset), polUAssetPolRate, polUAssetUAssetRate);
        router.setPairOutputPerLp(pt, address(uAsset), ptUAssetPtRate, ptUAssetUAssetRate);
        router.setPairOutputPerLp(pt, address(pol), ptPolPtRate, ptPolPolRate);
        hook.setClaimQuote(address(pol), address(uAsset), 0, auxiliaryUAssetFee);

        uint256 treasuryBefore = uAsset.balanceOf(TREASURY);
        (initialPolUAssetLp, initialPtUAssetLp, initialPtPolLp) = launcher.auxiliaryLiquidities(VERSE_ID);

        uint256 totalFunds = normalFunds + debt;
        uint256 leveragedPolUAssetLp = initialPolUAssetLp * debt / totalFunds;
        uint256 leveragedPtUAssetLp = initialPtUAssetLp * debt / totalFunds;
        uint256 leveragedPtPolLp = initialPtPolLp * debt / totalFunds;
        expectedRemainingPolUAssetLp = initialPolUAssetLp - leveragedPolUAssetLp;
        expectedRemainingPtUAssetLp = initialPtUAssetLp - leveragedPtUAssetLp;
        expectedRemainingPtPolLp = initialPtPolLp - leveragedPtPolLp;

        uint256 polAmount =
            leveragedPolUAssetLp * polUAssetPolRate / 1 ether + leveragedPtPolLp * ptPolPolRate / 1 ether;
        uint256 ptAmount = leveragedPtUAssetLp * ptUAssetPtRate / 1 ether + leveragedPtPolLp * ptPolPtRate / 1 ether;
        uint256 ptBacking = splitter.previewPTToUAsset(VERSE_ID, ptAmount);
        expectedOutstandingPTBackingBeforeSettlement = splitter.previewPTToUAsset(VERSE_ID, MockERC20(pt).totalSupply());
        expectedSettlementUAssetBeforePTRedeem = expectedOutstandingPTBackingBeforeSettlement + polAmount
            * MAIN_UASSET_RATE / 1 ether + hookUAssetFee(address(pol), address(uAsset));
        expectedRedeemedPTAmount = ptAmount;
        expectedRedeemedPTBacking = ptBacking;
        expectedRecoveredUAsset = leveragedPolUAssetLp * polUAssetUAssetRate / 1 ether + leveragedPtUAssetLp
            * ptUAssetUAssetRate / 1 ether + polAmount * MAIN_UASSET_RATE / 1 ether + ptBacking;

        uint256 treasuryBeforeOtherLock = uAsset.balanceOf(TREASURY);
        vm.prank(address(launcher));
        polend.finalizeLeveragedGenesis(OTHER_VERSE_ID);
        otherMarketDebt = polend.getTotalLeveragedDebt(OTHER_VERSE_ID);
        assertNotEq(otherMarketDebt, debt, "other market debt differs");
        expectedGlobalDebtAfterSettlement = otherMarketDebt;
        globalDebtBeforeSettlement = polend.getTotalDebtByUAsset(address(uAsset));
        treasuryBefore += uAsset.balanceOf(TREASURY) - treasuryBeforeOtherLock;
        (uint128 reserveBefore,) = polend.settlementDustStates(address(uAsset));
        reserveBeforeSettlement = reserveBefore;

        IMemeverseLauncher.Memeverse memory verse = launcher.getMemeverseByVerseId(VERSE_ID);
        vm.warp(verse.unlockTime + 1);
        vm.recordLogs();
        try launcher.changeStage(VERSE_ID) returns (IMemeverseLauncher.Stage) {
            succeeded = true;
            _captureSettlementEvent();
        } catch {
            succeeded = false;
        }

        stageAfter = uint256(launcher.getStageByVerseId(VERSE_ID));
        marketStateAfter = uint256(polend.getLendMarket(VERSE_ID).state);
        otherMarketStateAfter = uint256(polend.getLendMarket(OTHER_VERSE_ID).state);
        globalDebtAfter = polend.getTotalDebtByUAsset(address(uAsset));
        (uint128 reserveAfter,) = polend.settlementDustStates(address(uAsset));
        reserveAfterSettlement = reserveAfter;
        treasuryDelta = uAsset.balanceOf(TREASURY) - treasuryBefore;
        repaidAmount = uAsset.repaidAmount();
        (residualUAsset,) = polend.residualStates(VERSE_ID);
        (address ptAfter,,,,,, uint256 splitterSettlementUAsset,,,,) = splitter.splitInfos(VERSE_ID);
        settlementUAssetAfter = splitterSettlementUAsset;
        ptTotalSupplyAfter = MockERC20(ptAfter).totalSupply();
        ptBackingAfter = splitter.previewPTToUAsset(VERSE_ID, ptTotalSupplyAfter);
        (remainingPolUAssetLp, remainingPtUAssetLp, remainingPtPolLp) = launcher.auxiliaryLiquidities(VERSE_ID);
    }

    function expectedDeficit() external view returns (uint256) {
        return debt > expectedRecoveredUAsset ? debt - expectedRecoveredUAsset : 0;
    }

    function expectedRedeemPTExceedsSettlementBacking() external view returns (bool) {
        return expectedRedeemedPTBacking > expectedSettlementUAssetBeforePTRedeem;
    }

    function expectedRedeemPTConvertsToZero() external view returns (bool) {
        return expectedRedeemedPTAmount != 0 && expectedRedeemedPTBacking == 0;
    }

    function hookUAssetFee(address tokenA, address tokenB) internal view returns (uint256 fee) {
        (uint256 fee0, uint256 fee1) = hook.claimableFees(
            PoolKey({
                currency0: Currency.wrap(tokenA < tokenB ? tokenA : tokenB),
                currency1: Currency.wrap(tokenA < tokenB ? tokenB : tokenA),
                fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
                tickSpacing: 200,
                hooks: IHooks(address(hook))
            }),
            address(launcher)
        );
        fee = tokenA < tokenB ? fee1 : fee0;
    }

    function _captureSettlementEvent() internal {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length != 3 || logs[i].topics[0] != GLOBAL_SETTLEMENT_EXECUTED) continue;
            (
                uint256 eventDebt,
                uint256 eventRecovered,
                uint256 eventConsumed,
                uint256 reserveAfterFromEvent,
                uint256 eventResidualUAsset,
            ) = abi.decode(logs[i].data, (uint256, uint256, uint256, uint256, uint256, uint256));
            debt = eventDebt;
            recoveredUAsset = eventRecovered;
            consumedSettlementDust = eventConsumed;
            settlementDustReserveAfter = reserveAfterFromEvent;
            residualUAsset = eventResidualUAsset;
        }
    }

    function _deployLauncher() internal returns (TestableMemeverseLauncherPOLend) {
        return (new TestableMemeverseLauncherPOLend())
        .createProxy(
            address(this),
            address(0x1),
            address(0x2),
            address(0x3),
            address(0x4),
            address(0x5),
            address(0x10),
            address(0x11),
            25,
            115_000,
            135_000,
            2_500,
            7 days
        );
    }

    function _deploySplitter(TestableMemeverseLauncherPOLend launcher_) internal returns (POLSplitter) {
        POLSplitter implementation = new POLSplitter();
        bytes memory data = abi.encodeCall(POLSplitter.initialize, (address(this), address(launcher_)));
        return POLSplitter(address(new ERC1967Proxy(address(implementation), data)));
    }

    function _deployPOLend(TestableMemeverseLauncherPOLend launcher_, POLSplitter splitter_) internal returns (POLend) {
        POLend implementation = new POLend();
        bytes memory data = abi.encodeCall(
            POLend.initialize, (address(this), 0.1 ether, 10 ether, TREASURY, address(launcher_), address(splitter_))
        );
        return POLend(address(new ERC1967Proxy(address(implementation), data)));
    }

    function _createOtherOutstandingMarket(uint256 interestAmount) internal {
        _setOtherGenesisVerse(launcher, uAsset, memecoin, pol, uint128(block.timestamp + 1 days));
        polend.setDefaultInterestRate(0.25 ether);
        vm.prank(address(launcher));
        polend.registerLendMarket(OTHER_VERSE_ID);
        polend.setDefaultInterestRate(0.1 ether);

        _leveragedGenesisFor(polend, uAsset, OTHER_VERSE_ID, OTHER_LEVERAGED_USER, interestAmount);
    }

    function _wireLauncher(
        TestableMemeverseLauncherPOLend launcher_,
        RouterForPOLendSettlementInvariant router_,
        HookForPOLendSettlementInvariant hook_,
        MockYieldDispatcherForPOLendIntegration dispatcher_,
        POLSplitter splitter_,
        POLend polend_
    ) internal {
        launcher_.setMemeverseUniswapHook(address(hook_));
        hook_.setPoolInitializer(address(router_));
        launcher_.setMemeverseSwapRouter(address(router_));
        launcher_.setYieldDispatcher(address(dispatcher_));
        launcher_.setMemeverseProxyDeployer(address(new MockProxyDeployerForPOLendIntegration()));
        launcher_.setPolSplitterForTest(address(splitter_));
        launcher_.setPolendForTest(address(polend_));
    }

    function _setGenesisVerse(
        TestableMemeverseLauncherPOLend launcher_,
        UniversalAssetForPOLendSettlementInvariant uAsset_,
        MockMemecoinForPOLendIntegration memecoin_,
        MockPolForPOLendIntegration pol_,
        uint128 endTime
    ) internal {
        IMemeverseLauncher.Memeverse memory verse;
        verse.name = "Verse";
        verse.symbol = "VRS";
        verse.uAsset = address(uAsset_);
        verse.memecoin = address(memecoin_);
        verse.pol = address(pol_);
        verse.governor = address(0xCAFE);
        verse.yieldVault = address(0xD00D);
        verse.currentStage = IMemeverseLauncher.Stage.Genesis;
        verse.endTime = endTime;
        verse.unlockTime = endTime + 7 days;
        verse.omnichainIds = new uint32[](1);
        verse.omnichainIds[0] = uint32(block.chainid + 1);
        launcher_.setMemeverseForTest(VERSE_ID, verse);
    }

    function _setOtherGenesisVerse(
        TestableMemeverseLauncherPOLend launcher_,
        UniversalAssetForPOLendSettlementInvariant uAsset_,
        MockMemecoinForPOLendIntegration memecoin_,
        MockPolForPOLendIntegration pol_,
        uint128 endTime
    ) internal {
        IMemeverseLauncher.Memeverse memory verse;
        verse.name = "Other Verse";
        verse.symbol = "OVRS";
        verse.uAsset = address(uAsset_);
        verse.memecoin = address(memecoin_);
        verse.pol = address(pol_);
        verse.governor = address(0xBEEF);
        verse.yieldVault = address(0xD0D0);
        verse.currentStage = IMemeverseLauncher.Stage.Genesis;
        verse.endTime = endTime;
        verse.unlockTime = endTime + 7 days;
        verse.omnichainIds = new uint32[](1);
        verse.omnichainIds[0] = uint32(block.chainid + 2);
        launcher_.setMemeverseForTest(OTHER_VERSE_ID, verse);
    }

    function _normalGenesis(
        TestableMemeverseLauncherPOLend launcher_,
        UniversalAssetForPOLendSettlementInvariant uAsset_,
        uint256 amount
    ) internal {
        uAsset_.mint(ALICE, amount);
        vm.startPrank(ALICE);
        uAsset_.approve(address(launcher_), amount);
        launcher_.genesis(VERSE_ID, amount, ALICE);
        vm.stopPrank();
    }

    function _leveragedGenesis(
        POLend polend_,
        UniversalAssetForPOLendSettlementInvariant uAsset_,
        uint256 interestAmount
    ) internal {
        _leveragedGenesisFor(polend_, uAsset_, VERSE_ID, LEVERAGED_USER, interestAmount);
    }

    function _leveragedGenesisFor(
        POLend polend_,
        UniversalAssetForPOLendSettlementInvariant uAsset_,
        uint256 verseId,
        address user,
        uint256 interestAmount
    ) internal {
        uAsset_.mint(user, interestAmount);
        vm.startPrank(user);
        uAsset_.approve(address(polend_), interestAmount);
        polend_.leveragedGenesis(verseId, interestAmount);
        vm.stopPrank();
    }
}

contract MemeverseLauncherPOLendSettlementStdInvariantTest is StdInvariant, Test {
    SettlementDustInvariantHandler internal handler;

    function setUp() external {
        handler = new SettlementDustInvariantHandler();
        targetContract(address(handler));
    }

    function invariant_settlementEitherRevertsOnlyWhenDustBoundsAreExceeded() external view {
        if (!handler.attempted()) return;

        uint256 deficit = handler.expectedDeficit();
        bool exceedsDustBounds = deficit > handler.maxReserve() || deficit > handler.reserveBeforeSettlement();
        bool invalidPTRedemption =
            handler.expectedRedeemPTConvertsToZero() || handler.expectedRedeemPTExceedsSettlementBacking();
        if (handler.succeeded()) {
            assertFalse(exceedsDustBounds || invalidPTRedemption, "successful settlement exceeded bounds");
        } else {
            assertTrue(exceedsDustBounds || invalidPTRedemption, "settlement reverted without exceeding bounds");
        }
    }

    function invariant_successfulSettlementRepaysDebtAndClearsGlobalAccounting() external view {
        if (!handler.attempted() || !handler.succeeded()) return;

        assertEq(handler.repaidAmount(), handler.debt(), "repaid debt");
        assertEq(
            handler.globalDebtBeforeSettlement(),
            handler.debt() + handler.otherMarketDebt(),
            "pre settlement global debt"
        );
        assertEq(
            handler.globalDebtBeforeSettlement() - handler.debt(), handler.globalDebtAfter(), "global debt conserved"
        );
        assertEq(handler.globalDebtAfter(), handler.expectedGlobalDebtAfterSettlement(), "other market debt remains");
        assertNotEq(handler.otherMarketDebt(), handler.debt(), "other market debt differs");
        assertEq(handler.marketStateAfter(), uint256(IPOLend.MarketState.Settled), "market settled");
        assertEq(handler.stageAfter(), uint256(IMemeverseLauncher.Stage.Unlocked), "stage unlocked");
        assertEq(handler.otherMarketStateAfter(), uint256(IPOLend.MarketState.Locked), "other market locked");
    }

    function invariant_successfulSettlementUsesOnlyBoundedReserveForDeficit() external view {
        if (!handler.attempted() || !handler.succeeded()) return;

        uint256 deficit = handler.expectedDeficit();
        assertEq(handler.recoveredUAsset(), handler.expectedRecoveredUAsset(), "recovered uasset");
        assertEq(handler.consumedSettlementDust(), deficit, "consumed dust");
        assertLe(handler.consumedSettlementDust(), handler.maxReserve(), "max dust cap");
        assertLe(handler.consumedSettlementDust(), handler.reserveBeforeSettlement(), "reserve cap");
    }

    function invariant_successfulSettlementRoutesReserveAndResiduals() external view {
        if (!handler.attempted() || !handler.succeeded()) return;

        uint256 expectedResidual =
            handler.expectedRecoveredUAsset() > handler.debt() ? handler.expectedRecoveredUAsset() - handler.debt() : 0;
        uint256 expectedReserveAfter = handler.reserveBeforeSettlement() - handler.consumedSettlementDust();

        assertEq(handler.residualUAsset(), expectedResidual, "residual uasset");
        assertEq(handler.settlementDustReserveAfter(), expectedReserveAfter, "reserve after event");
        assertEq(handler.treasuryDelta(), 0, "unused reserve not swept");
        assertEq(handler.reserveAfterSettlement(), expectedReserveAfter, "reserve after");
    }

    function invariant_successfulSettlementPreservesInterestReserveAccounting() external view {
        if (!handler.attempted() || !handler.succeeded()) return;

        uint256 expectedResidual =
            handler.recoveredUAsset() > handler.debt() ? handler.recoveredUAsset() - handler.debt() : 0;

        assertEq(
            handler.autoReserve() + handler.treasuryInterest(),
            handler.totalLeveragedInterest() + handler.bootstrapUnusedUAsset(),
            "lock funding split"
        );
        assertEq(
            handler.consumedSettlementDust() + handler.reserveAfterSettlement(),
            handler.reserveBeforeSettlement(),
            "reserve split"
        );
        assertGe(handler.reserveBeforeSettlement(), handler.autoReserve() + handler.extraReserve(), "reserve source");
        assertEq(handler.residualUAsset(), expectedResidual, "residual from recovered");
    }

    function invariant_successfulSplitterSettlementBacksPTSupply() external view {
        if (!handler.attempted() || !handler.succeeded()) return;

        assertGe(handler.settlementUAssetAfter(), handler.ptBackingAfter(), "settlementUAsset >= PT backing");
    }

    function invariant_settlementConsumesOnlyLeveragedAuxiliaryShare() external view {
        if (!handler.attempted() || !handler.succeeded()) return;

        assertEq(handler.remainingPolUAssetLp(), handler.expectedRemainingPolUAssetLp(), "pol/uasset remainder");
        assertEq(handler.remainingPtUAssetLp(), handler.expectedRemainingPtUAssetLp(), "pt/uasset remainder");
        assertEq(handler.remainingPtPolLp(), handler.expectedRemainingPtPolLp(), "pt/pol remainder");
    }
}
