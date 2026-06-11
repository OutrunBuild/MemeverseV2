// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {SqrtPriceMath} from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import {IPoolManager, SwapParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {toBalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {wadExp} from "solmate/utils/SignedWadMath.sol";

import {IMemeverseDynamicFeeEngine} from "../../src/swap/interfaces/IMemeverseDynamicFeeEngine.sol";
import {MemeverseDynamicFeeEngine} from "../../src/swap/MemeverseDynamicFeeEngine.sol";

contract DynamicFeeEngineHarness is MemeverseDynamicFeeEngine {
    constructor(IPoolManager _poolManager) MemeverseDynamicFeeEngine(_poolManager) {}

    function exposedSpotX18FromSqrtPrice(uint160 sqrtPriceX96) external pure returns (uint256) {
        return _spotX18FromSqrtPrice(sqrtPriceX96);
    }

    function exposedPriceMovePpmCapped(uint160 preSqrtPrice, uint160 postSqrtPrice) external pure returns (uint256) {
        return _priceMovePpmCapped(preSqrtPrice, postSqrtPrice);
    }

    function exposedVolatilitySqrtFeeBps(uint256 accumulator) external pure returns (uint256) {
        return _volatilitySqrtFeeBps(accumulator);
    }
}

contract DynamicFeeEngineV2 is MemeverseDynamicFeeEngine {
    constructor(IPoolManager _poolManager) MemeverseDynamicFeeEngine(_poolManager) {}

    function version() external pure returns (uint256) {
        return 2;
    }
}

contract MemeverseDynamicFeeEngineTest is Test {
    PoolId internal constant POOL_ID = PoolId.wrap(bytes32(uint256(0x1234)));
    address internal constant AUTHORIZED_HOOK = address(0xA11CE);
    address internal constant TRADER_A = address(0xCAFE);
    address internal constant TRADER_B = address(0xBEEF);
    uint160 internal constant SQRT_PRICE_1_1 = 79228162514264337593543950336;
    uint160 internal constant SQRT_PRICE_UP = 80024378775772204256025656563;
    uint160 internal constant PRICE_MOVE_59_999_UP_POST = 81570347323081481549928488305;
    uint160 internal constant PRICE_MOVE_60_000_UP_POST = 81570385799687631547685037519;
    uint160 internal constant PRICE_MOVE_59_999_DOWN_POST = 76814594370895530393110659596;
    uint160 internal constant PRICE_MOVE_60_000_DOWN_POST = 76814553512101337462432816780;
    uint160 internal constant PRICE_MOVE_149_999_UP_POST = 84962701926156676880859777928;
    uint160 internal constant PRICE_MOVE_150_000_UP_POST = 84962738866485953687210797630;
    uint160 internal constant PRICE_MOVE_149_999_DOWN_POST = 73044799624479866430778194544;
    uint160 internal constant PRICE_MOVE_150_000_DOWN_POST = 73044756656988588048856075193;
    uint160 internal constant PRICE_MOVE_FALLBACK_OUTSIDE_UP_POST = 84962738866485953687210797631;
    uint160 internal constant PRICE_MOVE_FALLBACK_OUTSIDE_DOWN_POST = 73044756656988588048856075192;
    uint160 internal constant PRICE_MOVE_999_UP_POST = 79267727102650874847096721154;
    uint160 internal constant PRICE_MOVE_1000_UP_POST = 79267766696949822951113378805;
    uint160 internal constant PRICE_MOVE_999_DOWN_POST = 79188578158425281008671148299;
    uint160 internal constant PRICE_MOVE_1000_DOWN_POST = 79188538524532033966444101902;
    uint160 internal constant SPOT_VECTOR_128_PLUS_1 = uint160((uint256(1) << 128) + 1);
    uint160 internal constant SPOT_VECTOR_128_127_PLUS_1 = uint160((uint256(1) << 128) + (uint256(1) << 127) + 1);
    uint256 internal constant EWVWAP_PRECISION = 1e18;
    uint256 internal constant Q192 = uint256(1) << 192;
    uint256 internal constant PIF_CAP_PPM = 150_000;
    uint256 internal constant VOL_MAX_FEE_BPS = 50;
    uint256 internal constant VOL_MAX_DEVIATION_ACCUMULATOR = 1_500_000;
    uint256 internal constant BPS_BASE = 10_000;
    uint256 internal constant FEE_BASE_BPS = 100;

    DynamicFeeEngineHarness internal engine;

    function setUp() external {
        engine = _deployEngineProxy(IPoolManager(address(0x1001)), address(this), AUTHORIZED_HOOK);
        vm.warp(1);
    }

    function testEngineImplementationInitializeReverts() external {
        MemeverseDynamicFeeEngine implementation = new MemeverseDynamicFeeEngine(IPoolManager(address(0x1001)));

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementation.initialize(address(this), address(0));
    }

    /// @notice UUPS storage isolation: proxy state must not leak into the bare implementation contract.
    function testEngineImplementationStorageIsolation() external {
        IPoolManager poolManager = IPoolManager(address(0x1001));
        MemeverseDynamicFeeEngine proxy = _deployEngineProxy(poolManager, address(this), AUTHORIZED_HOOK);
        MemeverseDynamicFeeEngine bareImpl = new MemeverseDynamicFeeEngine(poolManager);

        // Write state through the proxy.
        vm.prank(AUTHORIZED_HOOK);
        proxy.refreshBeforeSwap(_refreshParams(POOL_ID, SQRT_PRICE_1_1));
        vm.prank(AUTHORIZED_HOOK);
        proxy.updateAfterSwap(
            IMemeverseDynamicFeeEngine.UpdateAfterSwapParams({
                poolId: POOL_ID,
                delta: toBalanceDelta(int128(-10 ether), int128(9 ether)),
                trader: TRADER_A,
                preSqrtPriceX96: SQRT_PRICE_1_1,
                postSqrtPriceX96: SQRT_PRICE_UP
            })
        );

        // Proxy state is populated (precondition).
        IMemeverseDynamicFeeEngine.DynamicFeeState memory proxyState =
            proxy.getDynamicFeeState(AUTHORIZED_HOOK, POOL_ID);
        IMemeverseDynamicFeeEngine.AddressBatchState memory proxyBatch =
            proxy.getAddressBatchState(AUTHORIZED_HOOK, TRADER_A, POOL_ID);
        assertGt(proxyState.weightedVolume0, 0, "proxy volume");
        assertGt(proxyState.shortImpactPpm, 0, "proxy short");
        assertGt(proxyBatch.batchAccumPpm, 0, "proxy batch");

        // Bare implementation must report zero state — delegatecall isolates storage.
        IMemeverseDynamicFeeEngine.DynamicFeeState memory implState =
            bareImpl.getDynamicFeeState(AUTHORIZED_HOOK, POOL_ID);
        IMemeverseDynamicFeeEngine.AddressBatchState memory implBatch =
            bareImpl.getAddressBatchState(AUTHORIZED_HOOK, TRADER_A, POOL_ID);
        assertEq(implState.weightedVolume0, 0, "impl volume");
        assertEq(implState.weightedPriceVolume0, 0, "impl price volume");
        assertEq(implState.ewVWAPX18, 0, "impl ewvwap");
        assertEq(implState.volAnchorSqrtPriceX96, 0, "impl anchor");
        assertEq(implState.volDeviationAccumulator, 0, "impl deviation");
        assertEq(implState.shortImpactPpm, 0, "impl short");
        assertEq(implState.shortLastTs, 0, "impl short ts");
        assertEq(implBatch.batchAccumPpm, 0, "impl batch");
        assertEq(implBatch.batchStartTs, 0, "impl batch ts");
    }

    function testEngineProxyInitializeRevertsOnSecondCall() external {
        MemeverseDynamicFeeEngine initialized =
            _deployEngineProxy(IPoolManager(address(0x1001)), address(this), AUTHORIZED_HOOK);

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        initialized.initialize(address(0xB0B), address(0));
    }

    function testEngineInitializeRevertsZeroAddressOwner() external {
        DynamicFeeEngineHarness impl = new DynamicFeeEngineHarness(IPoolManager(address(0x1001)));
        bytes memory zeroOwnerData = abi.encodeCall(MemeverseDynamicFeeEngine.initialize, (address(0), AUTHORIZED_HOOK));

        vm.expectRevert(IMemeverseDynamicFeeEngine.ZeroAddress.selector);
        new ERC1967Proxy(address(impl), zeroOwnerData);
    }

    function testEngineInitializeRevertsZeroAddressHook() external {
        DynamicFeeEngineHarness impl = new DynamicFeeEngineHarness(IPoolManager(address(0x1001)));
        bytes memory zeroHookData = abi.encodeCall(MemeverseDynamicFeeEngine.initialize, (address(this), address(0)));

        vm.expectRevert(IMemeverseDynamicFeeEngine.ZeroAddress.selector);
        new ERC1967Proxy(address(impl), zeroHookData);
    }

    function testEngineUpgradeRevertsForNonOwner() external {
        IPoolManager poolManager = IPoolManager(address(0x1001));
        MemeverseDynamicFeeEngine initialized = _deployEngineProxy(poolManager, address(this), AUTHORIZED_HOOK);
        DynamicFeeEngineV2 newImplementation = new DynamicFeeEngineV2(poolManager);

        vm.prank(address(0xB0B));
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(0xB0B)));
        initialized.upgradeToAndCall(address(newImplementation), bytes(""));
    }

    function testEngineOwnerUpgradePreservesState() external {
        IPoolManager poolManager = IPoolManager(address(0x1001));
        MemeverseDynamicFeeEngine initialized = _deployEngineProxy(poolManager, address(this), AUTHORIZED_HOOK);
        vm.prank(AUTHORIZED_HOOK);
        initialized.refreshBeforeSwap(_refreshParams(POOL_ID, SQRT_PRICE_1_1));
        vm.prank(AUTHORIZED_HOOK);
        initialized.updateAfterSwap(
            IMemeverseDynamicFeeEngine.UpdateAfterSwapParams({
                poolId: POOL_ID,
                delta: toBalanceDelta(int128(-10 ether), int128(9 ether)),
                trader: TRADER_A,
                preSqrtPriceX96: SQRT_PRICE_1_1,
                postSqrtPriceX96: SQRT_PRICE_UP
            })
        );
        IMemeverseDynamicFeeEngine.DynamicFeeState memory beforeUpgrade =
            initialized.getDynamicFeeState(AUTHORIZED_HOOK, POOL_ID);
        IMemeverseDynamicFeeEngine.AddressBatchState memory batchBeforeUpgrade =
            initialized.getAddressBatchState(AUTHORIZED_HOOK, TRADER_A, POOL_ID);
        assertGt(beforeUpgrade.weightedVolume0, 0, "precondition volume");
        assertGt(beforeUpgrade.shortImpactPpm, 0, "precondition short");
        assertGt(batchBeforeUpgrade.batchAccumPpm, 0, "precondition batch");

        DynamicFeeEngineV2 newImplementation = new DynamicFeeEngineV2(poolManager);
        initialized.upgradeToAndCall(address(newImplementation), bytes(""));

        DynamicFeeEngineV2 upgraded = DynamicFeeEngineV2(address(initialized));
        IMemeverseDynamicFeeEngine.DynamicFeeState memory afterUpgrade =
            initialized.getDynamicFeeState(AUTHORIZED_HOOK, POOL_ID);
        IMemeverseDynamicFeeEngine.AddressBatchState memory batchAfterUpgrade =
            initialized.getAddressBatchState(AUTHORIZED_HOOK, TRADER_A, POOL_ID);
        assertEq(upgraded.version(), 2, "version");
        assertEq(initialized.owner(), address(this), "owner");
        assertEq(address(initialized.poolManager()), address(poolManager), "pool manager");
        assertEq(afterUpgrade.weightedVolume0, beforeUpgrade.weightedVolume0, "weighted volume");
        assertEq(afterUpgrade.weightedPriceVolume0, beforeUpgrade.weightedPriceVolume0, "weighted price volume");
        assertEq(afterUpgrade.ewVWAPX18, beforeUpgrade.ewVWAPX18, "ewvwap");
        assertEq(afterUpgrade.volAnchorSqrtPriceX96, beforeUpgrade.volAnchorSqrtPriceX96, "vol anchor");
        assertEq(afterUpgrade.volDeviationAccumulator, beforeUpgrade.volDeviationAccumulator, "volatility");
        assertEq(afterUpgrade.shortImpactPpm, beforeUpgrade.shortImpactPpm, "short impact");
        assertEq(batchAfterUpgrade.batchAccumPpm, batchBeforeUpgrade.batchAccumPpm, "batch pif");
        assertEq(batchAfterUpgrade.batchStartTs, batchBeforeUpgrade.batchStartTs, "batch start");
    }

    function testUnauthorizedCallerCannotRefreshBeforeSwap() external {
        vm.expectRevert(abi.encodeWithSelector(IMemeverseDynamicFeeEngine.UnauthorizedCaller.selector, address(0xBAD)));
        vm.prank(address(0xBAD));
        engine.refreshBeforeSwap(_refreshParams(POOL_ID, SQRT_PRICE_1_1));
    }

    function testUnauthorizedCallerCannotPrepareSwapFee() external {
        IMemeverseDynamicFeeEngine.PrepareSwapFeeParams memory params =
            _prepareParams(TRADER_A, uint40(block.timestamp));

        vm.expectRevert(abi.encodeWithSelector(IMemeverseDynamicFeeEngine.UnauthorizedCaller.selector, address(0xBAD)));
        vm.prank(address(0xBAD));
        engine.prepareSwapFee(params);
    }

    function testUnauthorizedCallerCannotUpdateAfterSwap() external {
        IMemeverseDynamicFeeEngine.UpdateAfterSwapParams memory attackerParams =
            IMemeverseDynamicFeeEngine.UpdateAfterSwapParams({
                poolId: POOL_ID,
                delta: toBalanceDelta(int128(-10 ether), int128(9 ether)),
                trader: TRADER_A,
                preSqrtPriceX96: SQRT_PRICE_1_1,
                postSqrtPriceX96: SQRT_PRICE_UP
            });

        vm.expectRevert(abi.encodeWithSelector(IMemeverseDynamicFeeEngine.UnauthorizedCaller.selector, address(0xBAD)));
        vm.prank(address(0xBAD));
        engine.updateAfterSwap(attackerParams);
    }

    function testNewEngineAuthorizesHookAtInit() external {
        address newHook = address(0xD00D);
        MemeverseDynamicFeeEngine newEngine = _deployEngineProxy(IPoolManager(address(0x1001)), address(this), newHook);

        vm.prank(newHook);
        newEngine.refreshBeforeSwap(_refreshParams(POOL_ID, SQRT_PRICE_1_1));

        IMemeverseDynamicFeeEngine.DynamicFeeState memory state = newEngine.getDynamicFeeState(newHook, POOL_ID);
        assertEq(state.volAnchorSqrtPriceX96, SQRT_PRICE_1_1, "authorized hook anchor");
    }

    /// @notice authorizedHook is set once at initialize() and has no setter — owner upgrade also cannot change it.
    function testAuthorizedHookImmutableAfterInitialize() external {
        assertEq(engine.authorizedHook(), AUTHORIZED_HOOK, "initial authorized hook");

        // Owner upgrade preserves authorizedHook — there is no setter in the contract.
        IPoolManager poolManager = IPoolManager(address(0x1001));
        DynamicFeeEngineV2 newImpl = new DynamicFeeEngineV2(poolManager);
        engine.upgradeToAndCall(address(newImpl), bytes(""));
        assertEq(engine.authorizedHook(), AUTHORIZED_HOOK, "authorized hook unchanged after upgrade");

        // Re-initialize is blocked by Initializable guard.
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        engine.initialize(address(this), address(0xBAD));
        assertEq(engine.authorizedHook(), AUTHORIZED_HOOK, "authorized hook unchanged after rejected re-init");
    }

    function testQuoteUsesExponentialLaunchFeeAtMidDecay() external {
        uint40 launchTimestamp = uint40(block.timestamp);
        IMemeverseDynamicFeeEngine.PrepareSwapFeeParams memory params = _prepareParams(TRADER_A, launchTimestamp);

        vm.warp(launchTimestamp + 450);
        vm.prank(AUTHORIZED_HOOK);
        IMemeverseDynamicFeeEngine.PreparedSwapFee memory quote = engine.prepareSwapFee(params);

        assertEq(quote.feeBps, _expectedLaunchFee(450, 900, 5000, 100), "exponential launch fee");
    }

    function testQuoteLaunchFeeReturnsMinFeeWhenLaunchTimestampIsZero() external {
        IMemeverseDynamicFeeEngine.PrepareSwapFeeParams memory params = _prepareParams(TRADER_A, 0);

        vm.prank(AUTHORIZED_HOOK);
        IMemeverseDynamicFeeEngine.PreparedSwapFee memory quote = engine.prepareSwapFee(params);

        assertEq(quote.feeBps, 100, "unlaunched pool should charge min fee");
    }

    function testPrepareSwapFeeZeroLiquidityReturnsBaseFeeAndZeroAmounts() external {
        IMemeverseDynamicFeeEngine.PrepareSwapFeeParams memory params = _prepareParams(TRADER_A, 0);
        params.liquidity = 0;
        params.swapParams.amountSpecified = -1 ether;

        vm.prank(AUTHORIZED_HOOK);
        IMemeverseDynamicFeeEngine.PreparedSwapFee memory quote = engine.prepareSwapFee(params);

        assertEq(quote.feeBps, FEE_BASE_BPS, "zero liquidity base fee");
        assertEq(quote.estimatedInputAmount, 0, "zero liquidity no input");
        assertEq(quote.estimatedOutputAmount, 0, "zero liquidity no output");
        assertEq(quote.estimatedGrossOutputAmount, 0, "zero liquidity no gross output");
    }

    function testPrepareSwapFeeZeroAmountSpecifiedReturnsBaseFeeAndZeroAmounts() external {
        IMemeverseDynamicFeeEngine.PrepareSwapFeeParams memory params = _prepareParams(TRADER_A, 0);
        params.swapParams.amountSpecified = 0;

        vm.prank(AUTHORIZED_HOOK);
        IMemeverseDynamicFeeEngine.PreparedSwapFee memory quote = engine.prepareSwapFee(params);

        assertEq(quote.feeBps, FEE_BASE_BPS, "zero amount base fee");
        assertEq(quote.estimatedInputAmount, 0, "zero amount no input");
        assertEq(quote.estimatedOutputAmount, 0, "zero amount no output");
        assertEq(quote.estimatedGrossOutputAmount, 0, "zero amount no gross output");
    }

    function testPrepareSwapFeeDoesNotWriteRealizedState() external {
        IMemeverseDynamicFeeEngine.PrepareSwapFeeParams memory params =
            _prepareParams(TRADER_A, uint40(block.timestamp));

        vm.prank(AUTHORIZED_HOOK);
        engine.prepareSwapFee(params);

        IMemeverseDynamicFeeEngine.DynamicFeeState memory state = engine.getDynamicFeeState(AUTHORIZED_HOOK, POOL_ID);
        IMemeverseDynamicFeeEngine.AddressBatchState memory batch =
            engine.getAddressBatchState(AUTHORIZED_HOOK, TRADER_A, POOL_ID);

        assertEq(batch.batchAccumPpm, 0, "batch unchanged");
        assertEq(state.weightedVolume0, 0, "ewvwap volume unchanged");
        assertEq(state.shortImpactPpm, 0, "short impact unchanged");
    }

    function testPrepareSwapFeeExactOutputGrossesOutputSideProtocolFee() external {
        IMemeverseDynamicFeeEngine.PrepareSwapFeeParams memory params = _prepareParams(TRADER_A, 0);
        params.swapParams.amountSpecified = 10 ether;
        params.protocolFeeOnInput = false;

        vm.prank(AUTHORIZED_HOOK);
        IMemeverseDynamicFeeEngine.PreparedSwapFee memory quote = engine.prepareSwapFee(params);

        uint256 expectedGrossOutputAmount = 10_030_090_270_812_437_312;
        uint256 expectedOutputSideProtocolFee = 30_090_270_812_437_312;

        assertEq(quote.feeBps, FEE_BASE_BPS, "base fee");
        assertEq(quote.estimatedOutputAmount, 10 ether, "net output");
        assertEq(
            quote.estimatedGrossOutputAmount,
            expectedGrossOutputAmount,
            "gross output includes output-side protocol fee"
        );
        assertEq(
            quote.estimatedGrossOutputAmount - quote.estimatedOutputAmount,
            expectedOutputSideProtocolFee,
            "reserved output-side protocol fee"
        );
        assertGt(quote.estimatedInputAmount, 0, "input estimated");
    }

    function testQuoteSwapUsesMemoryVolatilityRefreshBeforeEstimatingFee() external {
        vm.warp(1_000);
        IPoolManager poolManager = IPoolManager(address(0x1001));
        address hook = address(0xA110);
        DynamicFeeEngineHarness quoteEngine = _deployEngineProxy(poolManager, address(this), hook);

        vm.prank(hook);
        quoteEngine.refreshBeforeSwap(_refreshParams(POOL_ID, SQRT_PRICE_1_1));
        vm.prank(hook);
        quoteEngine.updateAfterSwap(
            IMemeverseDynamicFeeEngine.UpdateAfterSwapParams({
                poolId: POOL_ID,
                delta: toBalanceDelta(int128(-10 ether), int128(9 ether)),
                trader: TRADER_A,
                preSqrtPriceX96: SQRT_PRICE_1_1,
                postSqrtPriceX96: SQRT_PRICE_UP
            })
        );

        vm.warp(block.timestamp + 60);

        IMemeverseDynamicFeeEngine.QuoteSwapContext memory quoteContext = IMemeverseDynamicFeeEngine.QuoteSwapContext({
            poolId: POOL_ID,
            swapParams: SwapParams({zeroForOne: true, amountSpecified: -10_000 ether, sqrtPriceLimitX96: 0}),
            trader: TRADER_A,
            preSqrtPriceX96: SQRT_PRICE_1_1,
            liquidity: 1_000_000 ether,
            protocolFeeOnInput: true,
            launchFeeConfig: _launchFeeConfig(),
            launchTimestamp: uint40(block.timestamp - 900)
        });
        IMemeverseDynamicFeeEngine.PrepareSwapFeeParams memory prepareParams =
            _prepareParams(TRADER_A, uint40(block.timestamp - 900));
        prepareParams.poolId = POOL_ID;
        prepareParams.preSqrtPriceX96 = SQRT_PRICE_1_1;
        prepareParams.swapParams = quoteContext.swapParams;
        prepareParams.liquidity = 1_000_000 ether;

        vm.prank(hook);
        IMemeverseDynamicFeeEngine.PreparedSwapFee memory quote = quoteEngine.quoteSwapWithContext(hook, quoteContext);
        vm.prank(hook);
        IMemeverseDynamicFeeEngine.PreparedSwapFee memory prepared = quoteEngine.prepareSwapFee(prepareParams);

        assertEq(quote.volatilityPartBps, prepared.volatilityPartBps, "quote refreshed volatility");
        assertEq(quote.feeBps, prepared.feeBps, "quote fee");
    }

    function testPrepareSwapFeeExactInputUsesNetPoolInputAfterFees() external {
        IMemeverseDynamicFeeEngine.PrepareSwapFeeParams memory params =
            _prepareParams(TRADER_A, uint40(block.timestamp - 1));
        params.swapParams.amountSpecified = -10_000 ether;
        params.protocolFeeOnInput = true;
        params.liquidity = 1_000_000 ether;

        vm.prank(AUTHORIZED_HOOK);
        IMemeverseDynamicFeeEngine.PreparedSwapFee memory quote = engine.prepareSwapFee(params);

        uint256 userInputAmount = 10_000 ether;
        uint256 expectedNetPoolInput = userInputAmount - FullMath.mulDiv(userInputAmount, quote.feeBps, BPS_BASE);
        uint160 firstPassPostSqrtPrice =
            SqrtPriceMath.getNextSqrtPriceFromInput(SQRT_PRICE_1_1, params.liquidity, userInputAmount, true);
        uint160 expectedPostSqrtPrice =
            SqrtPriceMath.getNextSqrtPriceFromInput(SQRT_PRICE_1_1, params.liquidity, expectedNetPoolInput, true);
        uint256 expectedOutputAmount =
            SqrtPriceMath.getAmount1Delta(expectedPostSqrtPrice, SQRT_PRICE_1_1, params.liquidity, false);

        assertLt(quote.estimatedInputAmount, userInputAmount, "not first iteration input");
        assertEq(quote.estimatedInputAmount, expectedNetPoolInput, "net pool input");
        assertLt(quote.estimatedOutputAmount, userInputAmount, "not gross-output shortcut");
        assertEq(quote.estimatedOutputAmount, expectedOutputAmount, "net-input output");
        assertLt(
            quote.pifPpm, engine.exposedPriceMovePpmCapped(SQRT_PRICE_1_1, firstPassPostSqrtPrice), "not first pif"
        );
        assertEq(quote.pifPpm, engine.exposedPriceMovePpmCapped(SQRT_PRICE_1_1, expectedPostSqrtPrice), "net pif");
    }

    function testQuoteSwapExactOutputInputSideFeeReturnsRequestedOutput() external {
        vm.warp(1_000);
        (
            address hook,
            DynamicFeeEngineHarness quoteEngine,
            IMemeverseDynamicFeeEngine.QuoteSwapContext memory context
        ) = _quoteFixture(SQRT_PRICE_1_1, 1_000_000 ether);

        uint256 requestedOutput = 100 ether;
        context.swapParams.amountSpecified = int256(requestedOutput);
        context.protocolFeeOnInput = true;
        vm.prank(hook);
        IMemeverseDynamicFeeEngine.PreparedSwapFee memory quote = quoteEngine.quoteSwapWithContext(hook, context);

        assertGt(quote.estimatedInputAmount, 0, "input estimated");
        assertEq(quote.estimatedOutputAmount, requestedOutput, "user output");
        assertEq(quote.estimatedGrossOutputAmount, requestedOutput, "no output gross-up");
    }

    function testQuoteSwapExactOutputOutputSideFeeGrossesRequestedOutput() external {
        vm.warp(1_000);
        (
            address hook,
            DynamicFeeEngineHarness quoteEngine,
            IMemeverseDynamicFeeEngine.QuoteSwapContext memory context
        ) = _quoteFixture(SQRT_PRICE_1_1, 1_000_000 ether);

        uint256 requestedOutput = 100 ether;
        context.swapParams.amountSpecified = int256(requestedOutput);
        context.protocolFeeOnInput = false;
        vm.prank(hook);
        IMemeverseDynamicFeeEngine.PreparedSwapFee memory quote = quoteEngine.quoteSwapWithContext(hook, context);

        assertGt(quote.estimatedInputAmount, 0, "input estimated");
        assertEq(quote.estimatedOutputAmount, requestedOutput, "user output");
        assertGt(quote.estimatedGrossOutputAmount, requestedOutput, "gross output");
    }

    function testQuoteSwapNonAdverseReturnsBaseFee() external {
        vm.warp(1_000);
        (
            address hook,
            DynamicFeeEngineHarness quoteEngine,
            IMemeverseDynamicFeeEngine.QuoteSwapContext memory context
        ) = _quoteFixture(SQRT_PRICE_1_1, 1_000_000 ether);

        vm.prank(hook);
        quoteEngine.updateAfterSwap(
            IMemeverseDynamicFeeEngine.UpdateAfterSwapParams({
                poolId: context.poolId,
                delta: toBalanceDelta(int128(-10 ether), int128(9 ether)),
                trader: TRADER_A,
                preSqrtPriceX96: SQRT_PRICE_1_1,
                postSqrtPriceX96: SQRT_PRICE_UP
            })
        );

        context.swapParams.zeroForOne = false;
        context.swapParams.amountSpecified = -1 ether;
        context.protocolFeeOnInput = true;
        vm.prank(hook);
        IMemeverseDynamicFeeEngine.PreparedSwapFee memory quote = quoteEngine.quoteSwapWithContext(hook, context);

        assertFalse(quote.isAdverse, "non-adverse");
        assertEq(quote.feeBps, FEE_BASE_BPS, "base fee");
        assertEq(quote.adverseImpactPartBps, 0, "no adverse fee");
    }

    function testUpdateAfterSwapWritesRealizedStateForTraderNamespace() external {
        vm.prank(AUTHORIZED_HOOK);
        engine.refreshBeforeSwap(_refreshParams(POOL_ID, SQRT_PRICE_1_1));

        IMemeverseDynamicFeeEngine.UpdateAfterSwapParams memory params = IMemeverseDynamicFeeEngine.UpdateAfterSwapParams({
            poolId: POOL_ID,
            delta: toBalanceDelta(int128(-10 ether), int128(9 ether)),
            trader: TRADER_A,
            preSqrtPriceX96: SQRT_PRICE_1_1,
            postSqrtPriceX96: SQRT_PRICE_UP
        });

        vm.prank(AUTHORIZED_HOOK);
        engine.updateAfterSwap(params);

        IMemeverseDynamicFeeEngine.DynamicFeeState memory state = engine.getDynamicFeeState(AUTHORIZED_HOOK, POOL_ID);
        IMemeverseDynamicFeeEngine.AddressBatchState memory batch =
            engine.getAddressBatchState(AUTHORIZED_HOOK, TRADER_A, POOL_ID);
        IMemeverseDynamicFeeEngine.AddressBatchState memory otherBatch =
            engine.getAddressBatchState(AUTHORIZED_HOOK, TRADER_B, POOL_ID);

        assertGt(batch.batchAccumPpm, 0, "batch pif");
        assertEq(otherBatch.batchAccumPpm, 0, "other trader untouched");
        assertGt(state.shortImpactPpm, 0, "short impact");
        assertGt(state.volDeviationAccumulator, 0, "volatility accumulator");
        assertGt(state.weightedVolume0, 0, "ewvwap volume");
    }

    function testSpotConversionHandlesWideSqrtPriceVectors() external view {
        assertEq(engine.exposedSpotX18FromSqrtPrice(SQRT_PRICE_1_1), 1e18, "one-to-one spot");
        assertEq(
            engine.exposedSpotX18FromSqrtPrice(SPOT_VECTOR_128_PLUS_1),
            _expectedSpotX18(SPOT_VECTOR_128_PLUS_1),
            "wide spot low fractional"
        );
        assertEq(
            engine.exposedSpotX18FromSqrtPrice(SPOT_VECTOR_128_127_PLUS_1),
            _expectedSpotX18(SPOT_VECTOR_128_127_PLUS_1),
            "wide spot high fractional"
        );
    }

    function testPriceMovePpmReturnsExactBoundaryValues() external view {
        assertEq(engine.exposedPriceMovePpmCapped(SQRT_PRICE_1_1, PRICE_MOVE_59_999_UP_POST), 59_999, "up 59_999");
        assertEq(engine.exposedPriceMovePpmCapped(SQRT_PRICE_1_1, PRICE_MOVE_60_000_UP_POST), 60_000, "up 60_000");
        assertEq(engine.exposedPriceMovePpmCapped(SQRT_PRICE_1_1, PRICE_MOVE_59_999_DOWN_POST), 59_999, "down 59_999");
        assertEq(engine.exposedPriceMovePpmCapped(SQRT_PRICE_1_1, PRICE_MOVE_60_000_DOWN_POST), 60_000, "down 60_000");
        assertEq(engine.exposedPriceMovePpmCapped(SQRT_PRICE_1_1, PRICE_MOVE_149_999_UP_POST), 149_999, "up 149_999");
        assertEq(engine.exposedPriceMovePpmCapped(SQRT_PRICE_1_1, PRICE_MOVE_150_000_UP_POST), PIF_CAP_PPM, "up cap");
        assertEq(
            engine.exposedPriceMovePpmCapped(SQRT_PRICE_1_1, PRICE_MOVE_149_999_DOWN_POST), 149_999, "down 149_999"
        );
        assertEq(
            engine.exposedPriceMovePpmCapped(SQRT_PRICE_1_1, PRICE_MOVE_150_000_DOWN_POST), PIF_CAP_PPM, "down cap"
        );
        assertEq(
            engine.exposedPriceMovePpmCapped(SQRT_PRICE_1_1, PRICE_MOVE_FALLBACK_OUTSIDE_UP_POST),
            PIF_CAP_PPM,
            "up outside cap"
        );
        assertEq(
            engine.exposedPriceMovePpmCapped(SQRT_PRICE_1_1, PRICE_MOVE_FALLBACK_OUTSIDE_DOWN_POST),
            PIF_CAP_PPM,
            "down outside cap"
        );
        assertEq(engine.exposedPriceMovePpmCapped(SQRT_PRICE_1_1, PRICE_MOVE_999_UP_POST), 999, "up 999");
        assertEq(engine.exposedPriceMovePpmCapped(SQRT_PRICE_1_1, PRICE_MOVE_1000_UP_POST), 1000, "up 1000");
        assertEq(engine.exposedPriceMovePpmCapped(SQRT_PRICE_1_1, PRICE_MOVE_999_DOWN_POST), 999, "down 999");
        assertEq(engine.exposedPriceMovePpmCapped(SQRT_PRICE_1_1, PRICE_MOVE_1000_DOWN_POST), 1000, "down 1000");
    }

    function testVolatilitySqrtFeeAndAccumulatorBoundaries() external {
        assertEq(engine.exposedVolatilitySqrtFeeBps(0), 0, "zero accumulator");
        assertEq(engine.exposedVolatilitySqrtFeeBps(VOL_MAX_DEVIATION_ACCUMULATOR / 2), 35, "half accumulator sqrt fee");
        assertEq(engine.exposedVolatilitySqrtFeeBps(VOL_MAX_DEVIATION_ACCUMULATOR), VOL_MAX_FEE_BPS, "max accumulator");

        vm.prank(AUTHORIZED_HOOK);
        engine.refreshBeforeSwap(_refreshParams(POOL_ID, SQRT_PRICE_1_1));

        vm.prank(AUTHORIZED_HOOK);
        engine.updateAfterSwap(
            IMemeverseDynamicFeeEngine.UpdateAfterSwapParams({
                poolId: POOL_ID,
                delta: toBalanceDelta(int128(-10 ether), int128(9 ether)),
                trader: TRADER_A,
                preSqrtPriceX96: SQRT_PRICE_1_1,
                postSqrtPriceX96: uint160(SQRT_PRICE_1_1 * 2)
            })
        );

        IMemeverseDynamicFeeEngine.DynamicFeeState memory state = engine.getDynamicFeeState(AUTHORIZED_HOOK, POOL_ID);
        assertEq(state.volDeviationAccumulator, VOL_MAX_DEVIATION_ACCUMULATOR, "accumulator cap");
    }

    function testAdverseAndRevertingFeeComposition() external {
        vm.warp(1_000);
        vm.prank(AUTHORIZED_HOOK);
        engine.updateAfterSwap(
            IMemeverseDynamicFeeEngine.UpdateAfterSwapParams({
                poolId: POOL_ID,
                delta: toBalanceDelta(int128(-10 ether), int128(9 ether)),
                trader: TRADER_A,
                preSqrtPriceX96: SQRT_PRICE_1_1,
                postSqrtPriceX96: SQRT_PRICE_UP
            })
        );

        IMemeverseDynamicFeeEngine.PrepareSwapFeeParams memory adverseParams =
            _prepareParams(TRADER_A, uint40(block.timestamp - 900));
        adverseParams.preSqrtPriceX96 = SQRT_PRICE_UP;
        adverseParams.swapParams.zeroForOne = false;
        adverseParams.swapParams.amountSpecified = -10_000 ether;
        adverseParams.liquidity = 1_000_000 ether;
        vm.prank(AUTHORIZED_HOOK);
        IMemeverseDynamicFeeEngine.PreparedSwapFee memory adverseQuote = engine.prepareSwapFee(adverseParams);

        assertTrue(adverseQuote.isAdverse, "adverse");
        assertEq(
            adverseQuote.feeBps,
            FEE_BASE_BPS + adverseQuote.adverseImpactPartBps + adverseQuote.volatilityPartBps
                + adverseQuote.shortImpactPartBps,
            "adverse fee composition"
        );
        assertEq(adverseQuote.pifPpm, 19_469, "adverse pif");
        assertEq(adverseQuote.adverseImpactPartBps, 66, "adverse part");
        assertEq(adverseQuote.volatilityPartBps, 0, "volatility part");
        assertEq(adverseQuote.shortImpactPartBps, 49, "short part");
        assertEq(adverseQuote.feeBps, 215, "adverse fee");

        IMemeverseDynamicFeeEngine.PrepareSwapFeeParams memory revertingParams = adverseParams;
        revertingParams.preSqrtPriceX96 = SQRT_PRICE_1_1;
        revertingParams.swapParams.zeroForOne = false;
        revertingParams.swapParams.amountSpecified = -1 ether;

        vm.prank(AUTHORIZED_HOOK);
        IMemeverseDynamicFeeEngine.PreparedSwapFee memory revertingQuote = engine.prepareSwapFee(revertingParams);

        assertFalse(revertingQuote.isAdverse, "reverting");
        assertEq(revertingQuote.feeBps, FEE_BASE_BPS, "reverting fee");
    }

    function testBatchAccumulationIncreasesFeeWithinWindow() external {
        IMemeverseDynamicFeeEngine.PrepareSwapFeeParams memory beforeBatch =
            _prepareParams(TRADER_A, uint40(block.timestamp - 1));
        beforeBatch.swapParams.amountSpecified = -10 ether;
        beforeBatch.liquidity = 1_000_000 ether;

        vm.prank(AUTHORIZED_HOOK);
        IMemeverseDynamicFeeEngine.PreparedSwapFee memory firstQuote = engine.prepareSwapFee(beforeBatch);

        vm.prank(AUTHORIZED_HOOK);
        engine.updateAfterSwap(
            IMemeverseDynamicFeeEngine.UpdateAfterSwapParams({
                poolId: POOL_ID,
                delta: toBalanceDelta(int128(-10 ether), int128(9 ether)),
                trader: TRADER_A,
                preSqrtPriceX96: SQRT_PRICE_1_1,
                postSqrtPriceX96: SQRT_PRICE_UP
            })
        );

        vm.warp(block.timestamp + 1);
        vm.prank(AUTHORIZED_HOOK);
        IMemeverseDynamicFeeEngine.PreparedSwapFee memory batchedQuote = engine.prepareSwapFee(beforeBatch);

        assertGt(batchedQuote.adverseImpactPartBps, firstQuote.adverseImpactPartBps, "batch adverse part");
        assertGt(batchedQuote.feeBps, firstQuote.feeBps, "batch fee");
    }

    function testOwnerCannotUpgradeToImplementationWithDifferentPoolManager() external {
        DynamicFeeEngineHarness proxy =
            _deployEngineProxy(IPoolManager(address(0x1001)), address(this), AUTHORIZED_HOOK);
        DynamicFeeEngineHarness newImpl = new DynamicFeeEngineHarness(IPoolManager(address(0xD1F)));

        vm.expectRevert(
            abi.encodeWithSelector(
                IMemeverseDynamicFeeEngine.UpgradePoolManagerMismatch.selector, address(0x1001), address(0xD1F)
            )
        );
        proxy.upgradeToAndCall(address(newImpl), bytes(""));
    }

    function testOwnerCanUpgradeWithSamePoolManager() external {
        DynamicFeeEngineHarness proxy =
            _deployEngineProxy(IPoolManager(address(0x1001)), address(this), AUTHORIZED_HOOK);
        DynamicFeeEngineHarness newImpl = new DynamicFeeEngineHarness(IPoolManager(address(0x1001)));

        proxy.upgradeToAndCall(address(newImpl), bytes(""));
        assertEq(address(proxy.poolManager()), address(0x1001), "poolManager preserved");
    }

    function _deployEngineProxy(IPoolManager manager_, address owner_, address authorizedHook_)
        internal
        returns (DynamicFeeEngineHarness deployed)
    {
        DynamicFeeEngineHarness impl = new DynamicFeeEngineHarness(manager_);
        bytes memory data = abi.encodeCall(MemeverseDynamicFeeEngine.initialize, (owner_, authorizedHook_));
        deployed = DynamicFeeEngineHarness(address(new ERC1967Proxy(address(impl), data)));
    }

    function _refreshParams(PoolId poolId, uint160 sqrtPriceX96)
        internal
        pure
        returns (IMemeverseDynamicFeeEngine.RefreshBeforeSwapParams memory params)
    {
        params = IMemeverseDynamicFeeEngine.RefreshBeforeSwapParams({poolId: poolId, preSqrtPriceX96: sqrtPriceX96});
    }

    function _prepareParams(address trader, uint40 launchTimestamp)
        internal
        pure
        returns (IMemeverseDynamicFeeEngine.PrepareSwapFeeParams memory params)
    {
        params = IMemeverseDynamicFeeEngine.PrepareSwapFeeParams({
            poolId: POOL_ID,
            swapParams: SwapParams({zeroForOne: true, amountSpecified: -1 ether, sqrtPriceLimitX96: 0}),
            trader: trader,
            preSqrtPriceX96: SQRT_PRICE_1_1,
            liquidity: 1_000_000 ether,
            protocolFeeOnInput: true,
            launchFeeConfig: _launchFeeConfig(),
            launchTimestamp: launchTimestamp
        });
    }

    function _launchFeeConfig() internal pure returns (IMemeverseDynamicFeeEngine.LaunchFeeConfig memory config) {
        config =
            IMemeverseDynamicFeeEngine.LaunchFeeConfig({startFeeBps: 5000, minFeeBps: 100, decayDurationSeconds: 900});
    }

    function _quoteFixture(uint160 sqrtPriceX96, uint128 liquidity)
        internal
        returns (
            address hook,
            DynamicFeeEngineHarness quoteEngine,
            IMemeverseDynamicFeeEngine.QuoteSwapContext memory context
        )
    {
        hook = address(0xA110);
        quoteEngine = _deployEngineProxy(IPoolManager(address(0x1001)), address(this), hook);
        context = IMemeverseDynamicFeeEngine.QuoteSwapContext({
            poolId: POOL_ID,
            swapParams: SwapParams({zeroForOne: true, amountSpecified: -1 ether, sqrtPriceLimitX96: 0}),
            trader: TRADER_A,
            preSqrtPriceX96: sqrtPriceX96,
            liquidity: liquidity,
            protocolFeeOnInput: true,
            launchFeeConfig: _launchFeeConfig(),
            launchTimestamp: uint40(block.timestamp - 900)
        });
    }

    function _expectedLaunchFee(uint256 elapsed, uint256 duration, uint256 startFeeBps, uint256 minFeeBps)
        internal
        pure
        returns (uint256)
    {
        if (elapsed >= duration) return minFeeBps;
        int256 expAtElapsedWad = wadExp(-int256(FullMath.mulDiv(elapsed, 4e18, duration)));
        int256 expAtEndWad = wadExp(-4e18);
        uint256 normalizedWad = uint256((expAtElapsedWad - expAtEndWad) * 1e18 / (1e18 - expAtEndWad));
        return minFeeBps + FullMath.mulDiv(startFeeBps - minFeeBps, normalizedWad, 1e18);
    }

    function _expectedSpotX18(uint160 sqrtPriceX96) internal pure returns (uint256) {
        (uint256 squareHi, uint256 squareLo) = _squareWide(sqrtPriceX96);
        uint256 integerPart = (squareHi << 64) | (squareLo >> 192);
        uint256 fractionalPart = squareLo & (Q192 - 1);
        return integerPart * EWVWAP_PRECISION + FullMath.mulDiv(fractionalPart, EWVWAP_PRECISION, Q192);
    }

    function _squareWide(uint160 value) internal pure returns (uint256 hi, uint256 lo) {
        uint256 upper = uint256(value) >> 128;
        uint256 lower = uint128(value);
        uint256 lowerSquared = lower * lower;
        uint256 cross = (lower * upper) << 1;
        unchecked {
            lo = lowerSquared + (cross << 128);
        }
        hi = (upper * upper) + (cross >> 128);
        if (lo < lowerSquared) ++hi;
    }

    /// @notice Same-block swap must preserve full undecayed short impact.
    ///         _decayLinearPpm returns accumulatorPpm unchanged when block.timestamp <= lastTs.
    function testSameBlockSwapPreservesFullShortImpact() external {
        vm.warp(1000);

        // Seed short impact state via updateAfterSwap.
        vm.prank(AUTHORIZED_HOOK);
        engine.updateAfterSwap(
            IMemeverseDynamicFeeEngine.UpdateAfterSwapParams({
                poolId: POOL_ID,
                delta: toBalanceDelta(int128(-10 ether), int128(9 ether)),
                trader: TRADER_A,
                preSqrtPriceX96: SQRT_PRICE_1_1,
                postSqrtPriceX96: SQRT_PRICE_UP
            })
        );

        // Verify short impact was written.
        IMemeverseDynamicFeeEngine.DynamicFeeState memory state = engine.getDynamicFeeState(AUTHORIZED_HOOK, POOL_ID);
        assertGt(state.shortImpactPpm, 0, "short impact seeded");
        assertEq(state.shortLastTs, uint40(block.timestamp), "short last ts is current block");

        // Same block — no vm.warp. Call prepareSwapFee.
        IMemeverseDynamicFeeEngine.PrepareSwapFeeParams memory params = _prepareParams(TRADER_A, 0);
        params.preSqrtPriceX96 = SQRT_PRICE_UP;
        params.swapParams.zeroForOne = false;
        params.swapParams.amountSpecified = -10_000 ether;
        params.liquidity = 1_000_000 ether;

        vm.prank(AUTHORIZED_HOOK);
        IMemeverseDynamicFeeEngine.PreparedSwapFee memory quote = engine.prepareSwapFee(params);

        // Short impact part must be non-zero — decay should not have fired.
        assertGt(quote.shortImpactPartBps, 0, "same-block short impact not decayed");

        // Compare with a 1-second-later call to confirm decay makes a difference.
        vm.warp(block.timestamp + 1);
        vm.prank(AUTHORIZED_HOOK);
        IMemeverseDynamicFeeEngine.PreparedSwapFee memory decayedQuote = engine.prepareSwapFee(params);

        assertGt(quote.shortImpactPartBps, decayedQuote.shortImpactPartBps, "same-block fee higher than decayed fee");
    }

    /// @notice updateAfterSwap guards against zero preSqrtPriceX96: calling with 0 must not write any state.
    function testUpdateAfterSwapZeroPreSqrtPriceWritesNoState() external {
        vm.prank(AUTHORIZED_HOOK);
        engine.updateAfterSwap(
            IMemeverseDynamicFeeEngine.UpdateAfterSwapParams({
                poolId: POOL_ID,
                delta: toBalanceDelta(int128(-10 ether), int128(9 ether)),
                trader: TRADER_A,
                preSqrtPriceX96: 0,
                postSqrtPriceX96: SQRT_PRICE_UP
            })
        );

        IMemeverseDynamicFeeEngine.DynamicFeeState memory state = engine.getDynamicFeeState(AUTHORIZED_HOOK, POOL_ID);
        IMemeverseDynamicFeeEngine.AddressBatchState memory batch =
            engine.getAddressBatchState(AUTHORIZED_HOOK, TRADER_A, POOL_ID);

        assertEq(state.weightedVolume0, 0, "volume stays zero");
        assertEq(state.weightedPriceVolume0, 0, "price volume stays zero");
        assertEq(state.ewVWAPX18, 0, "ewvwap stays zero");
        assertEq(state.volAnchorSqrtPriceX96, 0, "anchor stays zero");
        assertEq(state.volDeviationAccumulator, 0, "deviation stays zero");
        assertEq(state.shortImpactPpm, 0, "short impact stays zero");
        assertEq(state.shortLastTs, 0, "short last ts stays zero");
        assertEq(batch.batchAccumPpm, 0, "batch accum stays zero");
        assertEq(batch.batchStartTs, 0, "batch start ts stays zero");
    }

    function testTransferOwnershipReverts() external {
        vm.expectRevert(IMemeverseDynamicFeeEngine.EngineOwnershipManagedByHook.selector);
        engine.transferOwnership(address(0xBEEF));
    }

    function testRenounceOwnershipReverts() external {
        vm.expectRevert(IMemeverseDynamicFeeEngine.EngineOwnershipManagedByHook.selector);
        engine.renounceOwnership();
    }
}
