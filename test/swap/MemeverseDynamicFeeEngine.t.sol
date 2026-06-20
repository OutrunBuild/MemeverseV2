// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {SqrtPriceMath} from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import {IPoolManager, SwapParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {toBalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {wadExp} from "solmate/utils/SignedWadMath.sol";

import {IMemeverseDynamicFeeEngine} from "../../src/swap/interfaces/IMemeverseDynamicFeeEngine.sol";
import {MemeverseDynamicFeeEngine} from "../../src/swap/MemeverseDynamicFeeEngine.sol";
import {OutrunOwnableUpgradeable} from "../../src/common/access/OutrunOwnableUpgradeable.sol";
import {FeeMath} from "../../src/swap/libraries/FeeMath.sol";
import {MemeverseDynamicFeeEngineV2} from "../mocks/upgrade/MemeverseDynamicFeeEngineV2.sol";
import {FeeEngineStorageSlots} from "../mocks/swap/FeeEngineStorageSlots.sol";

contract MemeverseDynamicFeeEngineTest is Test {
    using FeeEngineStorageSlots for *;
    // ERC7201 storage-namespace base slot for OutrunOwnableUpgradeable._owner.
    bytes32 internal constant OWNABLE_STORAGE_LOCATION =
        0x7f241041d6960443a72c6e46e3b41069d0f1a8933ddb434b1da86a3f3cba9f00;
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

    MemeverseDynamicFeeEngine internal engine;

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
        MemeverseDynamicFeeEngine impl = new MemeverseDynamicFeeEngine(IPoolManager(address(0x1001)));
        bytes memory zeroOwnerData = abi.encodeCall(MemeverseDynamicFeeEngine.initialize, (address(0), AUTHORIZED_HOOK));

        vm.expectRevert(abi.encodeWithSelector(OutrunOwnableUpgradeable.OwnableInvalidOwner.selector, address(0)));
        new ERC1967Proxy(address(impl), zeroOwnerData);
    }

    function testEngineInitializeRevertsZeroAddressHook() external {
        MemeverseDynamicFeeEngine impl = new MemeverseDynamicFeeEngine(IPoolManager(address(0x1001)));
        bytes memory zeroHookData = abi.encodeCall(MemeverseDynamicFeeEngine.initialize, (address(this), address(0)));

        vm.expectRevert(IMemeverseDynamicFeeEngine.ZeroAddress.selector);
        new ERC1967Proxy(address(impl), zeroHookData);
    }

    function testEngineUpgradeRevertsForNonOwner() external {
        IPoolManager poolManager = IPoolManager(address(0x1001));
        MemeverseDynamicFeeEngine initialized = _deployEngineProxy(poolManager, address(this), AUTHORIZED_HOOK);
        MemeverseDynamicFeeEngineV2 newImplementation = new MemeverseDynamicFeeEngineV2(poolManager);

        vm.prank(address(0xB0B));
        vm.expectRevert(
            abi.encodeWithSelector(OutrunOwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(0xB0B))
        );
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

        // Precondition: V1 getters confirm state was written before we rely on raw-slot reads.
        IMemeverseDynamicFeeEngine.DynamicFeeState memory beforeUpgrade =
            initialized.getDynamicFeeState(AUTHORIZED_HOOK, POOL_ID);
        IMemeverseDynamicFeeEngine.AddressBatchState memory batchBeforeUpgrade =
            initialized.getAddressBatchState(AUTHORIZED_HOOK, TRADER_A, POOL_ID);
        assertGt(beforeUpgrade.weightedVolume0, 0, "precondition volume");
        assertGt(beforeUpgrade.shortImpactPpm, 0, "precondition short");
        assertGt(batchBeforeUpgrade.batchAccumPpm, 0, "precondition batch");

        // Snapshot raw storage pre-upgrade. The V2 facade shell exposes no fee-state getters, so post-upgrade
        // survival must be asserted via vm.load against the same slots. Empirical cross-check: each vm.load value
        // here must match the V1 getter-derived value (decoded below) before the upgrade — this validates the
        // slot calculations rather than just asserting equality across the upgrade.
        bytes32 dynamicFeeStateBaseSlot = FeeEngineStorageSlots.dynamicFeeStateSlot(AUTHORIZED_HOOK, POOL_ID);
        bytes32 batchStateBaseSlot = FeeEngineStorageSlots.addressBatchStateSlot(AUTHORIZED_HOOK, TRADER_A, POOL_ID);
        bytes32 authorizedHookSlot = FeeEngineStorageSlots.authorizedHookSlot();

        bytes32 expectedWeightedVolume0 = vm.load(address(initialized), dynamicFeeStateBaseSlot);
        // shortImpactPpm sits at slot base+4 of DynamicFeeState: fields 3-4
        // (volAnchorSqrtPriceX96:160 + volLastMoveTs:40 + volDeviationAccumulator:24 + volCarryAccumulator:24 = 248)
        // pack into base+3, then shortImpactPpm(24) + shortLastTs(40) share base+4.
        bytes32 expectedShortImpactSlot =
            bytes32(uint256(dynamicFeeStateBaseSlot) + FeeEngineStorageSlots.DFS_PACKED_SHORT);
        bytes32 expectedShortImpactPpm = vm.load(address(initialized), expectedShortImpactSlot);
        // base+1 / base+2: weightedPriceVolume0 / ewVWAPX18 (single-word fields, whole-slot snapshot+survive).
        bytes32 expectedWeightedPriceVolume0 = vm.load(
            address(initialized),
            bytes32(uint256(dynamicFeeStateBaseSlot) + FeeEngineStorageSlots.DFS_WEIGHTED_PRICE_VOLUME0)
        );
        bytes32 expectedEwVWAPX18 = vm.load(
            address(initialized), bytes32(uint256(dynamicFeeStateBaseSlot) + FeeEngineStorageSlots.DFS_EWVWAP_X18)
        );
        // base+3: packed vol slot (volAnchor:160|volLastMoveTs:40|volDeviation:24|volCarry:24). Whole-slot
        // snapshot+survive — no field unpacking needed to assert the packed slot survives intact.
        bytes32 expectedPackedVolSlot = bytes32(uint256(dynamicFeeStateBaseSlot) + FeeEngineStorageSlots.DFS_PACKED_VOL);
        bytes32 expectedPackedVol = vm.load(address(initialized), expectedPackedVolSlot);
        bytes32 expectedBatchSlot = vm.load(address(initialized), batchStateBaseSlot);
        bytes32 expectedAuthorizedHook = vm.load(address(initialized), authorizedHookSlot);
        bytes32 expectedOwner = vm.load(address(initialized), OWNABLE_STORAGE_LOCATION);

        // Cross-check that the slot math matches the getter-decoded values (empirical slot validation).
        assertEq(uint256(expectedWeightedVolume0), beforeUpgrade.weightedVolume0, "slot cross-check volume");
        assertEq(
            uint256(uint24(uint256(expectedShortImpactPpm))), beforeUpgrade.shortImpactPpm, "slot cross-check short"
        );
        assertEq(
            uint256(uint192(uint256(expectedBatchSlot))), batchBeforeUpgrade.batchAccumPpm, "slot cross-check batch pif"
        );
        assertEq(
            uint256(uint64(uint256(expectedBatchSlot) >> 192)),
            batchBeforeUpgrade.batchStartTs,
            "slot cross-check batch ts"
        );
        assertEq(address(uint160(uint256(expectedAuthorizedHook))), AUTHORIZED_HOOK, "slot cross-check authorized hook");
        assertEq(address(uint160(uint256(expectedOwner))), address(this), "slot cross-check owner");

        MemeverseDynamicFeeEngineV2 newImplementation = new MemeverseDynamicFeeEngineV2(poolManager);
        initialized.upgradeToAndCall(address(newImplementation), bytes(""));

        // Post-upgrade: read the same slots. Values must be unchanged — ERC1967 upgrades only swap the
        // implementation address, not the proxy storage.
        MemeverseDynamicFeeEngineV2 upgraded = MemeverseDynamicFeeEngineV2(address(initialized));
        assertEq(upgraded.version(), 2, "version");
        assertEq(address(upgraded.poolManager()), address(poolManager), "pool manager");
        assertEq(vm.load(address(initialized), dynamicFeeStateBaseSlot), expectedWeightedVolume0, "weighted volume");
        assertEq(
            vm.load(
                address(initialized),
                bytes32(uint256(dynamicFeeStateBaseSlot) + FeeEngineStorageSlots.DFS_WEIGHTED_PRICE_VOLUME0)
            ),
            expectedWeightedPriceVolume0,
            "weighted price volume"
        );
        assertEq(
            vm.load(
                address(initialized), bytes32(uint256(dynamicFeeStateBaseSlot) + FeeEngineStorageSlots.DFS_EWVWAP_X18)
            ),
            expectedEwVWAPX18,
            "ewVWAP"
        );
        assertEq(vm.load(address(initialized), expectedPackedVolSlot), expectedPackedVol, "packed vol slot survived");
        assertEq(vm.load(address(initialized), expectedShortImpactSlot), expectedShortImpactPpm, "short impact");
        assertEq(vm.load(address(initialized), batchStateBaseSlot), expectedBatchSlot, "batch packed slot");
        assertEq(vm.load(address(initialized), authorizedHookSlot), expectedAuthorizedHook, "authorized hook");
        assertEq(vm.load(address(initialized), OWNABLE_STORAGE_LOCATION), expectedOwner, "owner");
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

        // Re-initialize is blocked by the V1 Initializable guard while the V1 implementation is still live.
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        engine.initialize(address(this), address(0xBAD));

        // Owner upgrade preserves authorizedHook — there is no setter in the contract. The V2 facade shell
        // exposes no authorizedHook() getter, so survival is verified via vm.load against the V1 storage slot
        // (namespace-base + 2 per MemeverseDynamicFeeEngineStorage field order).
        IPoolManager poolManager = IPoolManager(address(0x1001));
        MemeverseDynamicFeeEngineV2 newImpl = new MemeverseDynamicFeeEngineV2(poolManager);
        engine.upgradeToAndCall(address(newImpl), bytes(""));
        bytes32 authorizedHookSlot = FeeEngineStorageSlots.authorizedHookSlot();
        assertEq(
            address(uint160(uint256(vm.load(address(engine), authorizedHookSlot)))),
            AUTHORIZED_HOOK,
            "authorized hook unchanged after upgrade"
        );
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
        MemeverseDynamicFeeEngine quoteEngine = _deployEngineProxy(poolManager, address(this), hook);

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
        assertLt(quote.pifPpm, FeeMath.priceMovePpmCapped(SQRT_PRICE_1_1, firstPassPostSqrtPrice), "not first pif");
        assertEq(quote.pifPpm, FeeMath.priceMovePpmCapped(SQRT_PRICE_1_1, expectedPostSqrtPrice), "net pif");
    }

    function testQuoteSwapExactOutputInputSideFeeReturnsRequestedOutput() external {
        vm.warp(1_000);
        (
            address hook,
            MemeverseDynamicFeeEngine quoteEngine,
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
            MemeverseDynamicFeeEngine quoteEngine,
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
            MemeverseDynamicFeeEngine quoteEngine,
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

    function testSpotConversionHandlesWideSqrtPriceVectors() external pure {
        assertEq(FeeMath.spotX18FromSqrtPrice(SQRT_PRICE_1_1), 1e18, "one-to-one spot");
        assertEq(
            FeeMath.spotX18FromSqrtPrice(SPOT_VECTOR_128_PLUS_1),
            _expectedSpotX18(SPOT_VECTOR_128_PLUS_1),
            "wide spot low fractional"
        );
        assertEq(
            FeeMath.spotX18FromSqrtPrice(SPOT_VECTOR_128_127_PLUS_1),
            _expectedSpotX18(SPOT_VECTOR_128_127_PLUS_1),
            "wide spot high fractional"
        );
    }

    function testPriceMovePpmReturnsExactBoundaryValues() external pure {
        assertEq(FeeMath.priceMovePpmCapped(SQRT_PRICE_1_1, PRICE_MOVE_59_999_UP_POST), 59_999, "up 59_999");
        assertEq(FeeMath.priceMovePpmCapped(SQRT_PRICE_1_1, PRICE_MOVE_60_000_UP_POST), 60_000, "up 60_000");
        assertEq(FeeMath.priceMovePpmCapped(SQRT_PRICE_1_1, PRICE_MOVE_59_999_DOWN_POST), 59_999, "down 59_999");
        assertEq(FeeMath.priceMovePpmCapped(SQRT_PRICE_1_1, PRICE_MOVE_60_000_DOWN_POST), 60_000, "down 60_000");
        assertEq(FeeMath.priceMovePpmCapped(SQRT_PRICE_1_1, PRICE_MOVE_149_999_UP_POST), 149_999, "up 149_999");
        assertEq(FeeMath.priceMovePpmCapped(SQRT_PRICE_1_1, PRICE_MOVE_150_000_UP_POST), PIF_CAP_PPM, "up cap");
        assertEq(FeeMath.priceMovePpmCapped(SQRT_PRICE_1_1, PRICE_MOVE_149_999_DOWN_POST), 149_999, "down 149_999");
        assertEq(FeeMath.priceMovePpmCapped(SQRT_PRICE_1_1, PRICE_MOVE_150_000_DOWN_POST), PIF_CAP_PPM, "down cap");
        assertEq(
            FeeMath.priceMovePpmCapped(SQRT_PRICE_1_1, PRICE_MOVE_FALLBACK_OUTSIDE_UP_POST),
            PIF_CAP_PPM,
            "up outside cap"
        );
        assertEq(
            FeeMath.priceMovePpmCapped(SQRT_PRICE_1_1, PRICE_MOVE_FALLBACK_OUTSIDE_DOWN_POST),
            PIF_CAP_PPM,
            "down outside cap"
        );
        assertEq(FeeMath.priceMovePpmCapped(SQRT_PRICE_1_1, PRICE_MOVE_999_UP_POST), 999, "up 999");
        assertEq(FeeMath.priceMovePpmCapped(SQRT_PRICE_1_1, PRICE_MOVE_1000_UP_POST), 1000, "up 1000");
        assertEq(FeeMath.priceMovePpmCapped(SQRT_PRICE_1_1, PRICE_MOVE_999_DOWN_POST), 999, "down 999");
        assertEq(FeeMath.priceMovePpmCapped(SQRT_PRICE_1_1, PRICE_MOVE_1000_DOWN_POST), 1000, "down 1000");
    }

    function testVolatilitySqrtFeeAndAccumulatorBoundaries() external {
        assertEq(FeeMath.volatilitySqrtFeeBps(0), 0, "zero accumulator");
        assertEq(FeeMath.volatilitySqrtFeeBps(VOL_MAX_DEVIATION_ACCUMULATOR / 2), 35, "half accumulator sqrt fee");
        assertEq(FeeMath.volatilitySqrtFeeBps(VOL_MAX_DEVIATION_ACCUMULATOR), VOL_MAX_FEE_BPS, "max accumulator");

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
        MemeverseDynamicFeeEngine proxy =
            _deployEngineProxy(IPoolManager(address(0x1001)), address(this), AUTHORIZED_HOOK);
        // Facade shell with a mismatched immutable poolManager: V1 _authorizeUpgrade casts the new impl to
        // MemeverseDynamicFeeEngine and compares poolManager() — the facade's matching getter reports 0xD1F.
        MemeverseDynamicFeeEngineV2 newImpl = new MemeverseDynamicFeeEngineV2(IPoolManager(address(0xD1F)));

        vm.expectRevert(
            abi.encodeWithSelector(
                IMemeverseDynamicFeeEngine.UpgradePoolManagerMismatch.selector, address(0x1001), address(0xD1F)
            )
        );
        proxy.upgradeToAndCall(address(newImpl), bytes(""));
    }

    function testOwnerCanUpgradeWithSamePoolManager() external {
        MemeverseDynamicFeeEngine proxy =
            _deployEngineProxy(IPoolManager(address(0x1001)), address(this), AUTHORIZED_HOOK);
        MemeverseDynamicFeeEngineV2 newImpl = new MemeverseDynamicFeeEngineV2(IPoolManager(address(0x1001)));

        proxy.upgradeToAndCall(address(newImpl), bytes(""));
        // Post-upgrade the proxy delegatecalls the facade's poolManager() view; immutable reads the facade's
        // constructor value, which matched the V1 immutable, so the reported address is preserved.
        assertEq(address(proxy.poolManager()), address(0x1001), "poolManager preserved");
    }

    function _deployEngineProxy(IPoolManager manager_, address owner_, address authorizedHook_)
        internal
        returns (MemeverseDynamicFeeEngine deployed)
    {
        MemeverseDynamicFeeEngine impl = new MemeverseDynamicFeeEngine(manager_);
        bytes memory data = abi.encodeCall(MemeverseDynamicFeeEngine.initialize, (owner_, authorizedHook_));
        deployed = MemeverseDynamicFeeEngine(address(new ERC1967Proxy(address(impl), data)));
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
            MemeverseDynamicFeeEngine quoteEngine,
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
        (uint256 squareHi, uint256 squareLo) = FeeMath.squareWide(sqrtPriceX96);
        uint256 integerPart = (squareHi << 64) | (squareLo >> 192);
        uint256 fractionalPart = squareLo & (Q192 - 1);
        return integerPart * EWVWAP_PRECISION + FullMath.mulDiv(fractionalPart, EWVWAP_PRECISION, Q192);
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

    function testTransferOwnershipUsesInheritedOnlyOwnerGuard() external {
        vm.prank(AUTHORIZED_HOOK);
        vm.expectRevert(
            abi.encodeWithSelector(OutrunOwnableUpgradeable.OwnableUnauthorizedAccount.selector, AUTHORIZED_HOOK)
        );
        engine.transferOwnership(address(0xBEEF));

        engine.transferOwnership(address(0xBEEF));

        assertEq(engine.owner(), address(0xBEEF), "engine owner");
    }
}
