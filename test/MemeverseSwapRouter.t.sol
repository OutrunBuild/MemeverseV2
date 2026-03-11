// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {IPoolManager, ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta, BalanceDeltaLibrary, toBalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {LiquidityAmounts} from "../src/libraries/LiquidityAmounts.sol";
import {BaseHook} from "@uniswap/v4-hooks-public/src/base/BaseHook.sol";

import {MemeverseUniswapHook} from "../src/swap/MemeverseUniswapHook.sol";
import {MemeverseSwapRouter} from "../src/swap/MemeverseSwapRouter.sol";
import {IMemeverseUniswapHook} from "../src/swap/interfaces/IMemeverseUniswapHook.sol";
import {UniswapLP} from "../src/libraries/UniswapLP.sol";

contract MockPoolManagerForRouterTest {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using BeforeSwapDeltaLibrary for BeforeSwapDelta;

    error ManagerLocked();

    struct Slot0State {
        uint160 sqrtPriceX96;
        int24 tick;
        uint24 protocolFee;
        uint24 lpFee;
    }

    bytes internal constant ZERO_BYTES = bytes("");
    bytes32 internal constant POOLS_SLOT = bytes32(uint256(6));
    uint256 internal constant LIQUIDITY_OFFSET = 3;
    uint160 internal constant SQRT_PRICE_LOWER_X96 = 4_310_618_292;
    uint160 internal constant SQRT_PRICE_UPPER_X96 = 1_456_195_216_270_955_103_206_513_029_158_776_779_468_408_838_535;

    bool internal unlocked;
    mapping(bytes32 => bytes32) internal extStorage;
    mapping(PoolId => Slot0State) internal slot0State;
    mapping(PoolId => uint128) internal liquidityState;

    function initialize(PoolKey memory key, uint160 sqrtPriceX96) external returns (int24 tick) {
        PoolId poolId = key.toId();
        slot0State[poolId] = Slot0State({sqrtPriceX96: sqrtPriceX96, tick: 0, protocolFee: 0, lpFee: 0});
        liquidityState[poolId] = 1e24;
        _syncPoolStorage(poolId);
        key.hooks.beforeInitialize(msg.sender, key, sqrtPriceX96);
        tick = 0;
    }

    function unlock(bytes calldata data) external returns (bytes memory result) {
        unlocked = true;
        result = IUnlockCallbackLike(msg.sender).unlockCallback(data);
        unlocked = false;
    }

    function modifyLiquidity(PoolKey memory key, ModifyLiquidityParams memory params, bytes calldata)
        external
        returns (BalanceDelta delta, BalanceDelta feesAccrued)
    {
        if (!unlocked) revert ManagerLocked();
        uint256 amount0Used;
        uint256 amount1Used;

        if (params.liquidityDelta > 0) {
            key.hooks.beforeAddLiquidity(msg.sender, key, params, ZERO_BYTES);
            liquidityState[key.toId()] += uint128(uint256(params.liquidityDelta));
            _syncPoolStorage(key.toId());
            (amount0Used, amount1Used) = LiquidityAmounts.getAmountsForLiquidity(
                slot0State[key.toId()].sqrtPriceX96,
                SQRT_PRICE_LOWER_X96,
                SQRT_PRICE_UPPER_X96,
                uint128(uint256(params.liquidityDelta))
            );
            delta = toBalanceDelta(-int128(int256(amount0Used)), -int128(int256(amount1Used)));
            return (delta, feesAccrued);
        }

        liquidityState[key.toId()] -= uint128(uint256(-params.liquidityDelta));
        _syncPoolStorage(key.toId());
        (amount0Used, amount1Used) = LiquidityAmounts.getAmountsForLiquidity(
            slot0State[key.toId()].sqrtPriceX96,
            SQRT_PRICE_LOWER_X96,
            SQRT_PRICE_UPPER_X96,
            uint128(uint256(-params.liquidityDelta))
        );
        delta = toBalanceDelta(int128(int256(amount0Used)), int128(int256(amount1Used)));
    }

    function swap(PoolKey memory key, SwapParams memory params, bytes calldata hookData)
        external
        returns (BalanceDelta delta)
    {
        if (!unlocked) revert ManagerLocked();

        (, BeforeSwapDelta beforeSwapDelta,) = key.hooks.beforeSwap(msg.sender, key, params, hookData);
        int256 amountToSwap = params.amountSpecified + beforeSwapDelta.getSpecifiedDelta();

        BalanceDelta poolDelta = BalanceDeltaLibrary.ZERO_DELTA;
        if (amountToSwap != 0) {
            if (params.amountSpecified < 0) {
                uint256 inputAmount = uint256(-amountToSwap);
                uint256 outputAmount = inputAmount / 2;
                if (params.zeroForOne) {
                    poolDelta = toBalanceDelta(-int128(int256(inputAmount)), int128(int256(outputAmount)));
                } else {
                    poolDelta = toBalanceDelta(int128(int256(outputAmount)), -int128(int256(inputAmount)));
                }
            } else {
                uint256 outputAmount = uint256(amountToSwap);
                uint256 inputAmount = outputAmount * 2;
                if (params.zeroForOne) {
                    poolDelta = toBalanceDelta(-int128(int256(inputAmount)), int128(int256(outputAmount)));
                } else {
                    poolDelta = toBalanceDelta(int128(int256(outputAmount)), -int128(int256(inputAmount)));
                }
            }
        }

        (, int128 afterSwapUnspecifiedDelta) = key.hooks.afterSwap(msg.sender, key, params, poolDelta, hookData);

        int128 hookDeltaSpecified = beforeSwapDelta.getSpecifiedDelta();
        int128 hookDeltaUnspecified = beforeSwapDelta.getUnspecifiedDelta() + afterSwapUnspecifiedDelta;
        if (hookDeltaSpecified != 0 || hookDeltaUnspecified != 0) {
            BalanceDelta hookDelta = (params.amountSpecified < 0 == params.zeroForOne)
                ? toBalanceDelta(hookDeltaSpecified, hookDeltaUnspecified)
                : toBalanceDelta(hookDeltaUnspecified, hookDeltaSpecified);
            delta = poolDelta - hookDelta;
        } else {
            delta = poolDelta;
        }
    }

    function take(Currency currency, address to, uint256 amount) external {
        if (currency.isAddressZero()) {
            (bool success,) = to.call{value: amount}("");
            require(success, "native take");
        } else {
            require(MockERC20(Currency.unwrap(currency)).transfer(to, amount), "erc20 take");
        }
    }

    function sync(Currency) external {}

    function settle() external payable returns (uint256) {
        return msg.value;
    }

    function extsload(bytes32 slot) external view returns (bytes32) {
        return extStorage[slot];
    }

    function getSlot0(PoolId poolId) external view returns (uint160, int24, uint24, uint24) {
        Slot0State memory state = slot0State[poolId];
        return (state.sqrtPriceX96, state.tick, state.protocolFee, state.lpFee);
    }

    function getLiquidity(PoolId poolId) external view returns (uint128) {
        return liquidityState[poolId];
    }

    function _syncPoolStorage(PoolId poolId) internal {
        bytes32 stateSlot = keccak256(abi.encodePacked(PoolId.unwrap(poolId), POOLS_SLOT));
        Slot0State memory state = slot0State[poolId];
        extStorage[stateSlot] = bytes32(uint256(state.sqrtPriceX96));
        extStorage[bytes32(uint256(stateSlot) + LIQUIDITY_OFFSET)] = bytes32(uint256(liquidityState[poolId]));
    }

    receive() external payable {}
}

interface IUnlockCallbackLike {
    function unlockCallback(bytes calldata data) external returns (bytes memory);
}

contract TestableMemeverseUniswapHookForRouter is MemeverseUniswapHook {
    constructor(
        IPoolManager _manager,
        address _owner,
        address _treasury,
        uint256 _antiSnipeDurationBlocks,
        uint256 _maxAntiSnipeProbabilityBase
    ) MemeverseUniswapHook(_manager, _owner, _treasury, _antiSnipeDurationBlocks, _maxAntiSnipeProbabilityBase) {}

    function validateHookAddress(BaseHook) internal pure override {}
}

contract NonPayableSwapCaller {
    MemeverseSwapRouter internal immutable router;

    constructor(MemeverseSwapRouter _router) {
        router = _router;
    }

    function attemptSwap(
        PoolKey calldata key,
        SwapParams calldata params,
        address recipient,
        address nativeRefundRecipient,
        uint256 deadline,
        uint256 amountOutMinimum,
        uint256 amountInMaximum,
        bytes calldata hookData
    )
        external
        payable
        returns (BalanceDelta delta, bool executed, IMemeverseUniswapHook.AntiSnipeFailureReason failureReason)
    {
        return router.swap{value: msg.value}(
            key, params, recipient, nativeRefundRecipient, deadline, amountOutMinimum, amountInMaximum, hookData
        );
    }
}

contract NonPayableTreasury {}

contract MemeverseSwapRouterTest is Test {
    using PoolIdLibrary for PoolKey;

    event EmergencyFlagUpdated(bool oldFlag, bool newFlag);

    uint160 internal constant SQRT_PRICE_1_1 = 79228162514264337593543950336;
    uint256 internal constant ALICE_PK = 0xA11CE;

    MockPoolManagerForRouterTest internal manager;
    TestableMemeverseUniswapHookForRouter internal hook;
    MemeverseSwapRouter internal router;
    MockERC20 internal token0;
    MockERC20 internal token1;
    address internal treasury;
    address internal alice;
    PoolKey internal key;
    PoolId internal poolId;

    function setUp() public {
        manager = new MockPoolManagerForRouterTest();
        treasury = makeAddr("treasury");
        alice = vm.addr(ALICE_PK);
        hook = new TestableMemeverseUniswapHookForRouter(IPoolManager(address(manager)), address(this), treasury, 10, 1);
        router = new MemeverseSwapRouter(
            IPoolManager(address(manager)), IMemeverseUniswapHook(address(hook)), IPermit2(address(0xBEEF))
        );

        token0 = new MockERC20("Token0", "TK0", 18);
        token1 = new MockERC20("Token1", "TK1", 18);
        token0.mint(address(this), 1_000_000 ether);
        token1.mint(address(this), 1_000_000 ether);
        token0.mint(alice, 1_000_000 ether);
        token1.mint(alice, 1_000_000 ether);
        token0.mint(address(manager), 1_000_000 ether);
        token1.mint(address(manager), 1_000_000 ether);

        token0.approve(address(router), type(uint256).max);
        token1.approve(address(router), type(uint256).max);
        vm.prank(alice);
        token0.approve(address(router), type(uint256).max);
        vm.prank(alice);
        token1.approve(address(router), type(uint256).max);

        key = _dynamicPoolKey(Currency.wrap(address(token0)), Currency.wrap(address(token1)));
        poolId = key.toId();
        manager.initialize(key, SQRT_PRICE_1_1);
    }

    function _setProtocolFeeCurrency(Currency feeCurrency) internal {
        hook.setProtocolFeeCurrency(feeCurrency);
    }

    function testRequestSwapAttempt_IsPermissionless() external {
        vm.roll(block.number + 11);
        (bool allowed, IMemeverseUniswapHook.AntiSnipeFailureReason reason) = hook.requestSwapAttempt(
            key,
            SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}),
            address(this),
            100 ether,
            address(this)
        );

        assertTrue(allowed, "allowed");
        assertEq(uint8(reason), uint8(IMemeverseUniswapHook.AntiSnipeFailureReason.None), "reason");
        (uint248 attempts, bool successful) = hook.antiSnipeBlockData(poolId, block.number);
        assertEq(attempts, 0, "attempts");
        assertFalse(successful, "successful");
    }

    function testRequestSwapAttempt_RevertsOnSecondSamePoolRequestInSameTx() external {
        PoolKey memory nativeKey = _dynamicPoolKey(CurrencyLibrary.ADDRESS_ZERO, Currency.wrap(address(token1)));
        _dealAndInitializeNativePool(nativeKey, false);
        _setProtocolFeeCurrency(nativeKey.currency0);

        (bool allowed, IMemeverseUniswapHook.AntiSnipeFailureReason reason) = hook.requestSwapAttempt{value: 100 ether}(
            nativeKey,
            SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}),
            address(this),
            100 ether,
            address(this)
        );

        assertFalse(allowed, "first request should soft-fail");
        assertEq(uint8(reason), uint8(IMemeverseUniswapHook.AntiSnipeFailureReason.NoPriceLimitSet), "reason");

        vm.expectRevert(IMemeverseUniswapHook.PoolAlreadyRequestedThisTransaction.selector);
        hook.requestSwapAttempt{value: 100 ether}(
            nativeKey,
            SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}),
            address(this),
            100 ether,
            address(this)
        );
    }

    function testConstructor_RevertsWhenMaxAntiSnipeProbabilityBaseIsZero() external {
        vm.expectRevert(IMemeverseUniswapHook.ZeroValue.selector);
        new TestableMemeverseUniswapHookForRouter(IPoolManager(address(manager)), address(this), treasury, 10, 0);
    }

    function testConstructor_RevertsWhenTreasuryIsZeroAddress() external {
        vm.expectRevert(IMemeverseUniswapHook.ZeroAddress.selector);
        new TestableMemeverseUniswapHookForRouter(IPoolManager(address(manager)), address(this), address(0), 10, 1);
    }

    function testSetTreasury_RevertsOnZeroAddress() external {
        vm.expectRevert(IMemeverseUniswapHook.ZeroAddress.selector);
        hook.setTreasury(address(0));
    }

    function testSetEmergencyFlag_EmitsEventAndUpdatesState() external {
        vm.expectEmit(false, false, false, true);
        emit EmergencyFlagUpdated(false, true);
        hook.setEmergencyFlag(true);

        assertTrue(hook.emergencyFlag(), "emergency flag");
    }

    function testQuoteSwap_WhenEmergencyFlagEnabled_ReturnsBaseFee() external {
        _setProtocolFeeCurrency(key.currency0);

        IMemeverseUniswapHook.SwapQuote memory normalQuote =
            hook.quoteSwap(key, SwapParams({zeroForOne: true, amountSpecified: -10_000 ether, sqrtPriceLimitX96: 0}));
        hook.setEmergencyFlag(true);
        IMemeverseUniswapHook.SwapQuote memory emergencyQuote =
            hook.quoteSwap(key, SwapParams({zeroForOne: true, amountSpecified: -10_000 ether, sqrtPriceLimitX96: 0}));

        assertEq(emergencyQuote.feeBps, 100, "base fee only");
        assertGe(normalQuote.feeBps, emergencyQuote.feeBps, "normal fee not below emergency fee");
    }

    function testSwap_SupportsMultipleProtocolFeeCurrenciesAcrossPools() external {
        PoolKey memory nativeKey = _dynamicPoolKey(CurrencyLibrary.ADDRESS_ZERO, Currency.wrap(address(token1)));
        _dealAndInitializeNativePool(nativeKey, true);

        _setProtocolFeeCurrency(key.currency0);
        _setProtocolFeeCurrency(nativeKey.currency0);

        uint256 treasuryToken0Before = token0.balanceOf(treasury);
        uint256 treasuryNativeBefore = treasury.balance;

        uint160 erc20PriceLimit = uint160((uint256(SQRT_PRICE_1_1) * 99) / 100);
        router.swap(
            key,
            SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: erc20PriceLimit}),
            address(this),
            address(this),
            block.timestamp,
            0,
            100 ether,
            ""
        );

        uint160 nativePriceLimit = uint160((uint256(SQRT_PRICE_1_1) * 99) / 100);
        router.swap{value: 300 ether}(
            nativeKey,
            SwapParams({zeroForOne: true, amountSpecified: 100 ether, sqrtPriceLimitX96: nativePriceLimit}),
            address(this),
            address(this),
            block.timestamp,
            0,
            300 ether,
            ""
        );

        assertGt(token0.balanceOf(treasury), treasuryToken0Before, "erc20 protocol fee collected");
        assertGt(treasury.balance, treasuryNativeBefore, "native protocol fee collected");
    }

    function testQuoteFailedAttempt_ExactOutputUsesEstimatedInputNotAmountInMaximum() external {
        _setProtocolFeeCurrency(key.currency1);
        SwapParams memory params = SwapParams({zeroForOne: true, amountSpecified: 100 ether, sqrtPriceLimitX96: 0});

        IMemeverseUniswapHook.SwapQuote memory swapQuote = hook.quoteSwap(key, params);
        IMemeverseUniswapHook.FailedAttemptQuote memory failureQuote = hook.quoteFailedAttempt(key, params, 300 ether);

        assertEq(failureQuote.feeBps, swapQuote.feeBps, "same fee bps");
        assertLt(failureQuote.feeAmount, FullMath.mulDiv(300 ether, failureQuote.feeBps, 10_000), "not max-based");
        assertGt(failureQuote.feeAmount, 0, "failure fee quoted");
    }

    function testSoftFail_ChargesTreasuryWhenInputIsProtocolCurrency() external {
        _setProtocolFeeCurrency(key.currency0);
        IMemeverseUniswapHook.FailedAttemptQuote memory failureQuote = hook.quoteFailedAttempt(
            key, SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}), 100 ether
        );
        uint256 balance0Before = token0.balanceOf(address(this));
        uint256 balance1Before = token1.balanceOf(address(this));
        uint256 treasury0Before = token0.balanceOf(treasury);

        (BalanceDelta delta, bool executed, IMemeverseUniswapHook.AntiSnipeFailureReason reason) = router.swap(
            key,
            SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}),
            address(this),
            address(this),
            block.timestamp,
            0,
            100 ether,
            ""
        );

        assertEq(BalanceDelta.unwrap(delta), 0, "delta");
        assertFalse(executed, "executed");
        assertEq(uint8(reason), uint8(IMemeverseUniswapHook.AntiSnipeFailureReason.NoPriceLimitSet), "reason");
        assertEq(token0.balanceOf(address(this)), balance0Before - failureQuote.feeAmount, "token0 charged");
        assertEq(token1.balanceOf(address(this)), balance1Before, "token1 unchanged");
        assertEq(token0.balanceOf(treasury), treasury0Before + failureQuote.feeAmount, "treasury charged");

        (uint248 attempts, bool successful) = hook.antiSnipeBlockData(poolId, block.number);
        assertEq(attempts, 1, "attempts");
        assertFalse(successful, "successful");

        (
            uint256 weightedVolume0,
            uint256 weightedPriceVolume0,
            uint256 ewVWAPX18,
            uint160 volAnchorSqrtPriceX96,
            uint40 volLastMoveTs,
            uint24 volDeviationAccumulator,
            uint24 volCarryAccumulator,
            uint24 shortImpactPpm,
            uint40 shortLastTs
        ) = hook.poolEWVWAPParams(poolId);
        assertEq(weightedVolume0, 0, "weightedVolume0");
        assertEq(weightedPriceVolume0, 0, "weightedPriceVolume0");
        assertEq(ewVWAPX18, 0, "ewVWAPX18");
        assertEq(volAnchorSqrtPriceX96, 0, "volAnchor");
        assertEq(volLastMoveTs, 0, "volLastMoveTs");
        assertEq(volDeviationAccumulator, 0, "volDeviationAccumulator");
        assertEq(volCarryAccumulator, 0, "volCarryAccumulator");
        assertEq(shortImpactPpm, 0, "shortImpactPpm");
        assertEq(shortLastTs, 0, "shortLastTs");
    }

    function testSoftFail_ChargesLpWhenInputIsNotProtocolCurrency() external {
        _setProtocolFeeCurrency(key.currency1);
        router.addLiquidity(
            key.currency0,
            key.currency1,
            100 ether,
            100 ether,
            90 ether,
            90 ether,
            address(this),
            address(this),
            block.timestamp
        );
        IMemeverseUniswapHook.FailedAttemptQuote memory failureQuote = hook.quoteFailedAttempt(
            key, SwapParams({zeroForOne: true, amountSpecified: 100 ether, sqrtPriceLimitX96: 0}), 300 ether
        );
        uint256 balance0Before = token0.balanceOf(address(this));
        uint256 balance1Before = token1.balanceOf(address(this));
        uint256 hookBalance0Before = token0.balanceOf(address(hook));
        (,, uint256 fee0PerShareBefore,) = hook.poolInfo(poolId);

        (BalanceDelta delta, bool executed, IMemeverseUniswapHook.AntiSnipeFailureReason reason) = router.swap(
            key,
            SwapParams({zeroForOne: true, amountSpecified: 100 ether, sqrtPriceLimitX96: 0}),
            address(this),
            address(this),
            block.timestamp,
            0,
            300 ether,
            ""
        );

        assertEq(BalanceDelta.unwrap(delta), 0, "delta");
        assertFalse(executed, "executed");
        assertEq(uint8(reason), uint8(IMemeverseUniswapHook.AntiSnipeFailureReason.NoPriceLimitSet), "reason");
        assertEq(token0.balanceOf(address(this)), balance0Before - failureQuote.feeAmount, "token0 charged");
        assertEq(token1.balanceOf(address(this)), balance1Before, "token1 unchanged");
        assertEq(token0.balanceOf(address(hook)), hookBalance0Before + failureQuote.feeAmount, "lp fee held by hook");
        (,, uint256 fee0PerShareAfter,) = hook.poolInfo(poolId);
        assertGt(fee0PerShareAfter, fee0PerShareBefore, "lp fee accrued");
        (uint248 attempts, bool successful) = hook.antiSnipeBlockData(poolId, block.number);
        assertEq(attempts, 1, "attempts");
        assertFalse(successful, "successful");
    }

    function testSoftFail_NativeInputRefundsAttachedValue() external {
        PoolKey memory nativeKey = _dynamicPoolKey(CurrencyLibrary.ADDRESS_ZERO, Currency.wrap(address(token1)));
        vm.deal(address(this), 1_000_000 ether);
        manager.initialize(nativeKey, SQRT_PRICE_1_1);
        _setProtocolFeeCurrency(nativeKey.currency0);
        IMemeverseUniswapHook.FailedAttemptQuote memory failureQuote = hook.quoteFailedAttempt(
            nativeKey, SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}), 100 ether
        );

        uint256 treasuryNativeBefore = treasury.balance;
        uint256 nativeBefore = address(this).balance;
        (BalanceDelta delta, bool executed, IMemeverseUniswapHook.AntiSnipeFailureReason reason) = router.swap{
            value: 100 ether
        }(
            nativeKey,
            SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}),
            address(this),
            address(this),
            block.timestamp,
            0,
            0,
            ""
        );

        assertEq(BalanceDelta.unwrap(delta), 0, "delta");
        assertFalse(executed, "executed");
        assertEq(uint8(reason), uint8(IMemeverseUniswapHook.AntiSnipeFailureReason.NoPriceLimitSet), "reason");
        assertEq(address(this).balance, nativeBefore - failureQuote.feeAmount, "only failure fee retained");
        assertEq(treasury.balance, treasuryNativeBefore + failureQuote.feeAmount, "treasury charged");
        assertEq(address(router).balance, 0, "router keeps no native");
    }

    function testSwapReverts_WhenNativeProtocolFeeTreasuryCannotReceiveETH() external {
        PoolKey memory nativeKey = _dynamicPoolKey(CurrencyLibrary.ADDRESS_ZERO, Currency.wrap(address(token1)));
        _dealAndInitializeNativePool(nativeKey, true);
        hook.setTreasury(address(new NonPayableTreasury()));
        _setProtocolFeeCurrency(nativeKey.currency0);
        uint160 priceLimit = uint160((uint256(SQRT_PRICE_1_1) * 99) / 100);

        vm.expectRevert(IMemeverseUniswapHook.NativeTreasuryMustAcceptETH.selector);
        router.swap{value: 300 ether}(
            nativeKey,
            SwapParams({zeroForOne: true, amountSpecified: 100 ether, sqrtPriceLimitX96: priceLimit}),
            address(this),
            address(this),
            block.timestamp,
            0,
            300 ether,
            ""
        );
    }

    function testSoftFail_NonPayableCallerCanUseCustomNativeRefundRecipient() external {
        PoolKey memory nativeKey = _dynamicPoolKey(CurrencyLibrary.ADDRESS_ZERO, Currency.wrap(address(token1)));
        PoolId nativePoolId = nativeKey.toId();
        _dealAndInitializeNativePool(nativeKey, false);
        _setProtocolFeeCurrency(nativeKey.currency0);
        IMemeverseUniswapHook.FailedAttemptQuote memory failureQuote = hook.quoteFailedAttempt(
            nativeKey, SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}), 100 ether
        );

        NonPayableSwapCaller caller = new NonPayableSwapCaller(router);
        uint256 nativeBefore = address(this).balance;
        uint256 treasuryNativeBefore = treasury.balance;

        (BalanceDelta delta, bool executed, IMemeverseUniswapHook.AntiSnipeFailureReason reason) = caller.attemptSwap{
            value: 100 ether
        }(
            nativeKey,
            SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}),
            address(caller),
            address(this),
            block.timestamp,
            0,
            0,
            ""
        );

        assertEq(BalanceDelta.unwrap(delta), 0, "delta");
        assertFalse(executed, "executed");
        assertEq(uint8(reason), uint8(IMemeverseUniswapHook.AntiSnipeFailureReason.NoPriceLimitSet), "reason");
        assertEq(address(this).balance, nativeBefore - failureQuote.feeAmount, "only failure fee retained");
        assertEq(treasury.balance, treasuryNativeBefore + failureQuote.feeAmount, "treasury charged");
        assertEq(address(router).balance, 0, "router keeps no native");

        (uint248 attempts, bool successful) = hook.antiSnipeBlockData(nativePoolId, block.number);
        assertEq(attempts, 1, "attempts");
        assertFalse(successful, "successful");
    }

    function testSwapPass_RecordsAttemptAndExecutes() external {
        _setProtocolFeeCurrency(key.currency0);
        uint256 balance0Before = token0.balanceOf(address(this));
        uint256 balance1Before = token1.balanceOf(address(this));
        uint256 treasury0Before = token0.balanceOf(treasury);
        uint160 priceLimit = uint160((uint256(SQRT_PRICE_1_1) * 99) / 100);

        (BalanceDelta delta, bool executed, IMemeverseUniswapHook.AntiSnipeFailureReason reason) = router.swap(
            key,
            SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: priceLimit}),
            address(this),
            address(this),
            block.timestamp,
            40 ether,
            100 ether,
            ""
        );

        assertTrue(executed, "executed");
        assertEq(uint8(reason), uint8(IMemeverseUniswapHook.AntiSnipeFailureReason.None), "reason");
        assertLt(token0.balanceOf(address(this)), balance0Before, "token0 spent");
        assertGt(token1.balanceOf(address(this)), balance1Before, "token1 received");
        assertGt(token0.balanceOf(treasury), treasury0Before, "treasury collected token0");
        assertLt(delta.amount0(), 0, "delta0");
        assertGt(delta.amount1(), 0, "delta1");

        (uint248 attempts, bool successful) = hook.antiSnipeBlockData(poolId, block.number);
        assertEq(attempts, 1, "attempts");
        assertTrue(successful, "successful");
    }

    function testSwapPass_OneForZeroExactInputExecutes() external {
        _setProtocolFeeCurrency(key.currency1);
        uint256 balance0Before = token0.balanceOf(address(this));
        uint256 balance1Before = token1.balanceOf(address(this));
        uint256 treasury1Before = token1.balanceOf(treasury);
        uint160 priceLimit = uint160((uint256(SQRT_PRICE_1_1) * 101) / 100);

        (BalanceDelta delta, bool executed, IMemeverseUniswapHook.AntiSnipeFailureReason reason) = router.swap(
            key,
            SwapParams({zeroForOne: false, amountSpecified: -100 ether, sqrtPriceLimitX96: priceLimit}),
            address(this),
            address(this),
            block.timestamp,
            40 ether,
            100 ether,
            ""
        );

        assertTrue(executed, "executed");
        assertEq(uint8(reason), uint8(IMemeverseUniswapHook.AntiSnipeFailureReason.None), "reason");
        assertGt(token0.balanceOf(address(this)), balance0Before, "token0 received");
        assertLt(token1.balanceOf(address(this)), balance1Before, "token1 spent");
        assertGt(token1.balanceOf(treasury), treasury1Before, "treasury collected token1");
        assertGt(delta.amount0(), 0, "delta0");
        assertLt(delta.amount1(), 0, "delta1");
    }

    function testSwapPass_ZeroForOneExactInput_OutputSideProtocolFee() external {
        _setProtocolFeeCurrency(key.currency1);
        uint256 balance1Before = token1.balanceOf(address(this));
        uint256 treasury1Before = token1.balanceOf(treasury);
        uint160 priceLimit = uint160((uint256(SQRT_PRICE_1_1) * 99) / 100);

        (BalanceDelta delta, bool executed,) = router.swap(
            key,
            SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: priceLimit}),
            address(this),
            address(this),
            block.timestamp,
            40 ether,
            100 ether,
            ""
        );

        assertTrue(executed, "executed");
        assertGt(token1.balanceOf(address(this)), balance1Before, "token1 received");
        assertLt(delta.amount1(), int128(int256(50 ether)), "output reduced by output-side fee");
        assertGt(token1.balanceOf(treasury), treasury1Before, "treasury collected token1");
    }

    function testSwapPass_OneForZeroExactInput_OutputSideProtocolFee() external {
        _setProtocolFeeCurrency(key.currency0);
        uint256 balance0Before = token0.balanceOf(address(this));
        uint256 treasury0Before = token0.balanceOf(treasury);
        uint160 priceLimit = uint160((uint256(SQRT_PRICE_1_1) * 101) / 100);

        (BalanceDelta delta, bool executed,) = router.swap(
            key,
            SwapParams({zeroForOne: false, amountSpecified: -100 ether, sqrtPriceLimitX96: priceLimit}),
            address(this),
            address(this),
            block.timestamp,
            40 ether,
            100 ether,
            ""
        );

        assertTrue(executed, "executed");
        assertGt(token0.balanceOf(address(this)), balance0Before, "token0 received");
        assertLt(delta.amount0(), int128(int256(50 ether)), "output reduced by output-side fee");
        assertGt(token0.balanceOf(treasury), treasury0Before, "treasury collected token0");
    }

    function testSwapPass_ZeroForOneExactOutputExecutesAndChargesInputFee() external {
        _setProtocolFeeCurrency(key.currency0);
        uint256 balance0Before = token0.balanceOf(address(this));
        uint256 balance1Before = token1.balanceOf(address(this));
        uint256 treasury0Before = token0.balanceOf(treasury);
        uint160 priceLimit = uint160((uint256(SQRT_PRICE_1_1) * 99) / 100);

        (BalanceDelta delta, bool executed, IMemeverseUniswapHook.AntiSnipeFailureReason reason) = router.swap(
            key,
            SwapParams({zeroForOne: true, amountSpecified: 100 ether, sqrtPriceLimitX96: priceLimit}),
            address(this),
            address(this),
            block.timestamp,
            0,
            300 ether,
            ""
        );

        assertTrue(executed, "executed");
        assertEq(uint8(reason), uint8(IMemeverseUniswapHook.AntiSnipeFailureReason.None), "reason");
        assertEq(token1.balanceOf(address(this)) - balance1Before, 100 ether, "exact output received");
        assertGt(balance0Before - token0.balanceOf(address(this)), 200 ether, "input includes fee");
        assertGt(token0.balanceOf(treasury), treasury0Before, "treasury collected token0");
        assertEq(delta.amount1(), int128(int256(100 ether)), "delta1");
        assertLt(delta.amount0(), -int128(int256(200 ether)), "delta0 fee-adjusted");
    }

    function testSwapPass_OneForZeroExactOutputExecutesAndChargesInputFee() external {
        _setProtocolFeeCurrency(key.currency1);
        uint256 balance0Before = token0.balanceOf(address(this));
        uint256 balance1Before = token1.balanceOf(address(this));
        uint256 treasury1Before = token1.balanceOf(treasury);
        uint160 priceLimit = uint160((uint256(SQRT_PRICE_1_1) * 101) / 100);

        (BalanceDelta delta, bool executed, IMemeverseUniswapHook.AntiSnipeFailureReason reason) = router.swap(
            key,
            SwapParams({zeroForOne: false, amountSpecified: 100 ether, sqrtPriceLimitX96: priceLimit}),
            address(this),
            address(this),
            block.timestamp,
            0,
            300 ether,
            ""
        );

        assertTrue(executed, "executed");
        assertEq(uint8(reason), uint8(IMemeverseUniswapHook.AntiSnipeFailureReason.None), "reason");
        assertEq(token0.balanceOf(address(this)) - balance0Before, 100 ether, "exact output received");
        assertGt(balance1Before - token1.balanceOf(address(this)), 200 ether, "input includes fee");
        assertGt(token1.balanceOf(treasury), treasury1Before, "treasury collected token1");
        assertEq(delta.amount0(), int128(int256(100 ether)), "delta0");
        assertLt(delta.amount1(), -int128(int256(200 ether)), "delta1 fee-adjusted");
    }

    function testSwapPass_ZeroForOneExactOutput_OutputSideProtocolFeeGrossesUp() external {
        _setProtocolFeeCurrency(key.currency1);
        uint256 balance0Before = token0.balanceOf(address(this));
        uint256 balance1Before = token1.balanceOf(address(this));
        uint256 treasury1Before = token1.balanceOf(treasury);
        uint160 priceLimit = uint160((uint256(SQRT_PRICE_1_1) * 99) / 100);

        (BalanceDelta delta, bool executed,) = router.swap(
            key,
            SwapParams({zeroForOne: true, amountSpecified: 100 ether, sqrtPriceLimitX96: priceLimit}),
            address(this),
            address(this),
            block.timestamp,
            0,
            300 ether,
            ""
        );

        assertTrue(executed, "executed");
        assertEq(token1.balanceOf(address(this)) - balance1Before, 100 ether, "exact net output");
        assertGt(balance0Before - token0.balanceOf(address(this)), 200 ether, "gross-up raises input");
        assertEq(delta.amount1(), int128(int256(100 ether)), "delta1 net output");
        assertGt(token1.balanceOf(treasury), treasury1Before, "treasury collected token1");
    }

    function testSwapPass_OneForZeroExactOutput_OutputSideProtocolFeeGrossesUp() external {
        _setProtocolFeeCurrency(key.currency0);
        uint256 balance0Before = token0.balanceOf(address(this));
        uint256 balance1Before = token1.balanceOf(address(this));
        uint256 treasury0Before = token0.balanceOf(treasury);
        uint160 priceLimit = uint160((uint256(SQRT_PRICE_1_1) * 101) / 100);

        (BalanceDelta delta, bool executed,) = router.swap(
            key,
            SwapParams({zeroForOne: false, amountSpecified: 100 ether, sqrtPriceLimitX96: priceLimit}),
            address(this),
            address(this),
            block.timestamp,
            0,
            300 ether,
            ""
        );

        assertTrue(executed, "executed");
        assertEq(token0.balanceOf(address(this)) - balance0Before, 100 ether, "exact net output");
        assertGt(balance1Before - token1.balanceOf(address(this)), 200 ether, "gross-up raises input");
        assertEq(delta.amount0(), int128(int256(100 ether)), "delta0 net output");
        assertGt(token0.balanceOf(treasury), treasury0Before, "treasury collected token0");
    }

    function testSwapPass_AfterAntiSnipeWindow_SkipsAttemptRecording() external {
        _setProtocolFeeCurrency(key.currency0);
        vm.roll(block.number + 11);

        uint256 balance0Before = token0.balanceOf(address(this));
        uint256 balance1Before = token1.balanceOf(address(this));

        (BalanceDelta delta, bool executed, IMemeverseUniswapHook.AntiSnipeFailureReason reason) = router.swap(
            key,
            SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}),
            address(this),
            address(this),
            block.timestamp,
            40 ether,
            100 ether,
            ""
        );

        assertTrue(executed, "executed");
        assertEq(uint8(reason), uint8(IMemeverseUniswapHook.AntiSnipeFailureReason.None), "reason");
        assertLt(token0.balanceOf(address(this)), balance0Before, "token0 spent");
        assertGt(token1.balanceOf(address(this)), balance1Before, "token1 received");
        assertLt(delta.amount0(), 0, "delta0");
        assertGt(delta.amount1(), 0, "delta1");

        (uint248 attempts, bool successful) = hook.antiSnipeBlockData(poolId, block.number);
        assertEq(attempts, 0, "attempts");
        assertFalse(successful, "successful");
    }

    function testSwapReverts_WhenExactOutputExceedsAmountInMaximum() external {
        _setProtocolFeeCurrency(key.currency0);
        uint160 priceLimit = uint160((uint256(SQRT_PRICE_1_1) * 99) / 100);

        vm.expectRevert();
        router.swap(
            key,
            SwapParams({zeroForOne: true, amountSpecified: 100 ether, sqrtPriceLimitX96: priceLimit}),
            address(this),
            address(this),
            block.timestamp,
            0,
            200 ether,
            ""
        );
    }

    function testSwapReverts_WhenExactInputFallsBelowAmountOutMinimum() external {
        _setProtocolFeeCurrency(key.currency0);
        uint160 priceLimit = uint160((uint256(SQRT_PRICE_1_1) * 99) / 100);

        vm.expectRevert();
        router.swap(
            key,
            SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: priceLimit}),
            address(this),
            address(this),
            block.timestamp,
            60 ether,
            100 ether,
            ""
        );
    }

    function testPreviewSwap_ExactOutputInputSideIncludesFeeInUserInput() external {
        _setProtocolFeeCurrency(key.currency0);
        IMemeverseUniswapHook.SwapQuote memory preview =
            hook.quoteSwap(key, SwapParams({zeroForOne: true, amountSpecified: 100 ether, sqrtPriceLimitX96: 0}));

        assertTrue(preview.protocolFeeOnInput, "protocolFeeOnInput");
        assertEq(preview.estimatedUserOutputAmount, 100 ether, "net output");
        assertGt(preview.estimatedUserInputAmount, preview.estimatedProtocolFeeAmount, "user input > protocol fee");
        assertGt(preview.estimatedUserInputAmount, preview.estimatedLpFeeAmount, "user input > lp fee");
        assertGt(
            preview.estimatedUserInputAmount,
            preview.estimatedProtocolFeeAmount + preview.estimatedLpFeeAmount,
            "user input covers both fee components"
        );
    }

    function testRouterQuoteSwap_ProxiesHookQuote() external {
        _setProtocolFeeCurrency(key.currency0);
        SwapParams memory params = SwapParams({zeroForOne: true, amountSpecified: 100 ether, sqrtPriceLimitX96: 0});

        IMemeverseUniswapHook.SwapQuote memory hookQuote = hook.quoteSwap(key, params);
        IMemeverseUniswapHook.SwapQuote memory routerQuote = router.quoteSwap(key, params);

        assertEq(routerQuote.feeBps, hookQuote.feeBps, "feeBps");
        assertEq(routerQuote.estimatedUserInputAmount, hookQuote.estimatedUserInputAmount, "user input");
        assertEq(routerQuote.estimatedUserOutputAmount, hookQuote.estimatedUserOutputAmount, "user output");
        assertEq(routerQuote.estimatedProtocolFeeAmount, hookQuote.estimatedProtocolFeeAmount, "protocol fee");
        assertEq(routerQuote.estimatedLpFeeAmount, hookQuote.estimatedLpFeeAmount, "lp fee");
        assertEq(routerQuote.protocolFeeOnInput, hookQuote.protocolFeeOnInput, "fee side");
    }

    function testSwapPass_NativeInputExactOutputExecutes() external {
        PoolKey memory nativeKey = _dynamicPoolKey(CurrencyLibrary.ADDRESS_ZERO, Currency.wrap(address(token1)));
        _dealAndInitializeNativePool(nativeKey, true);
        _setProtocolFeeCurrency(nativeKey.currency0);

        uint160 priceLimit = uint160((uint256(SQRT_PRICE_1_1) * 99) / 100);
        uint256 token1Before = token1.balanceOf(address(this));

        (BalanceDelta delta, bool executed,) = router.swap{value: 300 ether}(
            nativeKey,
            SwapParams({zeroForOne: true, amountSpecified: 100 ether, sqrtPriceLimitX96: priceLimit}),
            address(this),
            address(this),
            block.timestamp,
            0,
            300 ether,
            ""
        );

        assertTrue(executed, "executed");
        assertEq(token1.balanceOf(address(this)) - token1Before, 100 ether, "native exact output received");
        assertEq(delta.amount1(), int128(int256(100 ether)), "delta1");
    }

    function testRouterClaimFees_UsesHookCoreWithSignature() external {
        _setProtocolFeeCurrency(key.currency0);

        vm.prank(alice);
        router.addLiquidity(
            key.currency0, key.currency1, 100 ether, 100 ether, 90 ether, 90 ether, alice, alice, block.timestamp
        );

        uint160 priceLimit = uint160((uint256(SQRT_PRICE_1_1) * 99) / 100);
        router.swap(
            key,
            SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: priceLimit}),
            address(this),
            address(this),
            block.timestamp,
            40 ether,
            100 ether,
            ""
        );

        uint256 balanceBefore = token0.balanceOf(alice);
        uint256 nonce = hook.claimNonces(alice);
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                hook.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256(
                            "ClaimFees(address owner,address recipient,bytes32 poolId,uint256 nonce,uint256 deadline)"
                        ),
                        alice,
                        alice,
                        PoolId.unwrap(poolId),
                        nonce,
                        block.timestamp
                    )
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ALICE_PK, digest);

        vm.prank(alice);
        (uint256 fee0Amount, uint256 fee1Amount) = router.claimFees(key, alice, block.timestamp, v, r, s);

        assertGt(fee0Amount, 0, "fee0 claimed");
        assertEq(fee1Amount, 0, "fee1 claimed");
        assertEq(token0.balanceOf(alice), balanceBefore + fee0Amount, "alice received claimed fee");
    }

    function testClaimableFees_ViewMatchesClaimAndDoesNotMutateState() external {
        _setProtocolFeeCurrency(key.currency0);

        vm.prank(alice);
        router.addLiquidity(
            key.currency0, key.currency1, 100 ether, 100 ether, 90 ether, 90 ether, alice, alice, block.timestamp
        );

        uint160 priceLimit = uint160((uint256(SQRT_PRICE_1_1) * 99) / 100);
        router.swap(
            key,
            SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: priceLimit}),
            address(this),
            address(this),
            block.timestamp,
            40 ether,
            100 ether,
            ""
        );

        (uint256 fee0OffsetBefore, uint256 fee1OffsetBefore, uint256 pendingFee0Before, uint256 pendingFee1Before) =
            hook.userFeeState(poolId, alice);

        (uint256 previewFee0, uint256 previewFee1) = hook.claimableFees(key, alice);

        (uint256 fee0OffsetAfter, uint256 fee1OffsetAfter, uint256 pendingFee0After, uint256 pendingFee1After) =
            hook.userFeeState(poolId, alice);

        assertEq(fee0OffsetAfter, fee0OffsetBefore, "fee0 offset mutated");
        assertEq(fee1OffsetAfter, fee1OffsetBefore, "fee1 offset mutated");
        assertEq(pendingFee0After, pendingFee0Before, "pending fee0 mutated");
        assertEq(pendingFee1After, pendingFee1Before, "pending fee1 mutated");
        assertGt(previewFee0, 0, "preview fee0");
        assertEq(previewFee1, 0, "preview fee1");

        vm.prank(alice);
        (uint256 claimedFee0, uint256 claimedFee1) = hook.claimFeesCore(
            IMemeverseUniswapHook.ClaimFeesCoreParams({
                key: key,
                owner: alice,
                recipient: alice,
                deadline: block.timestamp,
                v: uint8(0),
                r: bytes32(0),
                s: bytes32(0)
            })
        );

        assertEq(claimedFee0, previewFee0, "preview fee0 mismatch");
        assertEq(claimedFee1, previewFee1, "preview fee1 mismatch");
    }

    function testRouterGetHookPoolKey_ReturnsDynamicHookKey() external {
        address tokenA = address(token0);
        address tokenB = address(token1);
        if (tokenB < tokenA) {
            (tokenA, tokenB) = (tokenB, tokenA);
        }

        PoolKey memory expected = _dynamicPoolKey(Currency.wrap(tokenA), Currency.wrap(tokenB));
        PoolKey memory routerKey = router.getHookPoolKey(address(token0), address(token1));

        assertEq(Currency.unwrap(routerKey.currency0), Currency.unwrap(expected.currency0), "currency0");
        assertEq(Currency.unwrap(routerKey.currency1), Currency.unwrap(expected.currency1), "currency1");
        assertEq(routerKey.fee, expected.fee, "fee");
        assertEq(routerKey.tickSpacing, expected.tickSpacing, "tickSpacing");
        assertEq(address(routerKey.hooks), address(expected.hooks), "hooks");
    }

    function testRouterPreviewClaimableFees_MatchesHookClaimableFees() external {
        _setProtocolFeeCurrency(key.currency0);

        vm.prank(alice);
        router.addLiquidity(
            key.currency0, key.currency1, 100 ether, 100 ether, 90 ether, 90 ether, alice, alice, block.timestamp
        );

        uint160 priceLimit = uint160((uint256(SQRT_PRICE_1_1) * 99) / 100);
        router.swap(
            key,
            SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: priceLimit}),
            address(this),
            address(this),
            block.timestamp,
            40 ether,
            100 ether,
            ""
        );

        PoolKey memory routerKey = router.getHookPoolKey(address(token0), address(token1));
        (uint256 hookFee0, uint256 hookFee1) = hook.claimableFees(routerKey, alice);
        (uint256 routerFee0, uint256 routerFee1) = router.previewClaimableFees(address(token0), address(token1), alice);

        assertEq(routerFee0, hookFee0, "fee0");
        assertEq(routerFee1, hookFee1, "fee1");
    }

    function testLpToken_ReturnsHookPoolLpTokenAddress() external view {
        (address poolLpToken,,,) = hook.poolInfo(poolId);
        assertEq(hook.lpToken(key), poolLpToken, "lp token");
    }

    function testRouterCreatePoolAndAddLiquidity_UsesHookCore() external {
        MockERC20 tokenA = new MockERC20("A", "A", 18);
        MockERC20 tokenB = new MockERC20("B", "B", 18);
        tokenA.mint(address(this), 1_000_000 ether);
        tokenB.mint(address(this), 1_000_000 ether);
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);

        (uint128 liquidity, PoolKey memory createdKey) = router.createPoolAndAddLiquidity(
            address(tokenA), address(tokenB), 100 ether, 100 ether, address(this), address(this), block.timestamp
        );

        (address liquidityToken,,,) = hook.poolInfo(createdKey.toId());
        assertEq(address(createdKey.hooks), address(hook), "hook");
        assertEq(createdKey.fee, 0x800000, "dynamic fee");
        assertGt(liquidity, 0, "liquidity");
        assertGt(UniswapLP(liquidityToken).balanceOf(address(this)), 0, "lp balance");
    }

    function _dynamicPoolKey(Currency currency0, Currency currency1) internal view returns (PoolKey memory) {
        return PoolKey({
            currency0: currency0, currency1: currency1, fee: 0x800000, tickSpacing: 200, hooks: IHooks(address(hook))
        });
    }

    function _dealAndInitializeNativePool(PoolKey memory nativeKey, bool fundManager) internal {
        vm.deal(address(this), 1_000_000 ether);
        if (fundManager) vm.deal(address(manager), 1_000_000 ether);
        manager.initialize(nativeKey, SQRT_PRICE_1_1);
    }

    receive() external payable {}
}
