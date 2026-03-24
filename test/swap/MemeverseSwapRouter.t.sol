// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {IPoolManager, ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta, BalanceDeltaLibrary, toBalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {LiquidityAmounts} from "../../src/swap/libraries/LiquidityAmounts.sol";
import {BaseHook} from "@uniswap/v4-hooks-public/src/base/BaseHook.sol";

import {MemeverseUniswapHook} from "../../src/swap/MemeverseUniswapHook.sol";
import {MemeverseSwapRouter} from "../../src/swap/MemeverseSwapRouter.sol";
import {IMemeverseUniswapHook} from "../../src/swap/interfaces/IMemeverseUniswapHook.sol";
import {IMemeverseSwapRouter} from "../../src/swap/interfaces/IMemeverseSwapRouter.sol";
import {UniswapLP} from "../../src/swap/tokens/UniswapLP.sol";

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

    /// @notice Initializes mock pool state for a hook-managed pair.
    /// @dev Seeds slot0 and liquidity before calling the hook initialize callback.
    /// @param key Pool key to initialize.
    /// @param sqrtPriceX96 Initial square-root price for the pool.
    /// @return tick Mock initial tick returned to the caller.
    function initialize(PoolKey memory key, uint160 sqrtPriceX96) external returns (int24 tick) {
        PoolId poolId = key.toId();
        slot0State[poolId] = Slot0State({sqrtPriceX96: sqrtPriceX96, tick: 0, protocolFee: 0, lpFee: 0});
        liquidityState[poolId] = 1e24;
        _syncPoolStorage(poolId);
        key.hooks.beforeInitialize(msg.sender, key, sqrtPriceX96);
        tick = 0;
    }

    /// @notice Opens the mock manager unlock window and forwards the callback.
    /// @dev Mimics the pool manager unlock flow expected by the router and hook.
    /// @param data Encoded callback payload.
    /// @return result Raw callback return data.
    function unlock(bytes calldata data) external returns (bytes memory result) {
        unlocked = true;
        result = IUnlockCallbackLike(msg.sender).unlockCallback(data);
        unlocked = false;
    }

    /// @notice Applies a mocked liquidity modification for a pool key.
    /// @dev Tracks liquidity and returns deterministic token deltas for tests.
    /// @param key Pool key whose liquidity is modified.
    /// @param params Liquidity modification parameters.
    /// @param hookData Unused hook data forwarded by the router test harness.
    /// @return delta Mock balance delta for the liquidity change.
    /// @return feesAccrued Mock accrued fees, always zero in this harness.
    function modifyLiquidity(PoolKey memory key, ModifyLiquidityParams memory params, bytes calldata hookData)
        external
        returns (BalanceDelta delta, BalanceDelta feesAccrued)
    {
        hookData;
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

    /// @notice Executes a mocked swap against the configured hook callbacks.
    /// @dev Produces deterministic deltas that are sufficient for router integration tests.
    /// @param key Pool key to swap against.
    /// @param params Swap parameters.
    /// @param hookData Opaque hook data forwarded into the mock hook callbacks.
    /// @return delta Mock balance delta for the swap.
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

    /// @notice Transfers a mocked currency out of the manager.
    /// @dev Supports both native and ERC20 payouts for router settlement tests.
    /// @param currency Currency to transfer.
    /// @param to Recipient of the transfer.
    /// @param amount Amount to transfer.
    function take(Currency currency, address to, uint256 amount) external {
        if (currency.isAddressZero()) {
            (bool success,) = to.call{value: amount}("");
            require(success, "native take");
        } else {
            require(MockERC20(Currency.unwrap(currency)).transfer(to, amount), "erc20 take");
        }
    }

    /// @notice No-op sync hook for the mock manager.
    /// @dev Present only to satisfy the router integration surface.
    /// @param currency Unused currency argument required by the interface.
    function sync(Currency currency) external pure {
        currency;
    }

    /// @notice Accepts native settlement in the mock manager.
    /// @dev Returns the attached value to mimic manager settlement accounting.
    /// @return Amount of native value received.
    function settle() external payable returns (uint256) {
        return msg.value;
    }

    /// @notice Reads a mocked external storage slot.
    /// @dev Used by the hook to inspect pool manager state.
    /// @param slot Storage slot to read.
    /// @return Mocked slot value.
    function extsload(bytes32 slot) external view returns (bytes32) {
        return extStorage[slot];
    }

    /// @notice Returns the mocked slot0 tuple for a pool.
    /// @dev Exposes the harness state to tests.
    /// @param poolId Pool id whose slot0 is requested.
    /// @return sqrtPriceX96 Mock square-root price.
    /// @return tick Mock current tick.
    /// @return protocolFee Mock protocol fee.
    /// @return lpFee Mock LP fee.
    function getSlot0(PoolId poolId)
        external
        view
        returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee)
    {
        Slot0State memory state = slot0State[poolId];
        return (state.sqrtPriceX96, state.tick, state.protocolFee, state.lpFee);
    }

    /// @notice Returns the mocked active liquidity for a pool.
    /// @dev Exposes the harness state to tests.
    /// @param poolId Pool id whose liquidity is requested.
    /// @return liquidity Mock active liquidity.
    function getLiquidity(PoolId poolId) external view returns (uint128 liquidity) {
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
    /// @notice Called by the mock manager during the unlock flow.
    /// @dev Mirrors the router callback surface used in tests.
    /// @param data Encoded callback payload.
    /// @return Encoded callback result.
    function unlockCallback(bytes calldata data) external returns (bytes memory);
}

contract TestableMemeverseUniswapHookForRouter is MemeverseUniswapHook {
    constructor(IPoolManager _manager, address _owner, address _treasury, address _launchSettlementCaller)
        MemeverseUniswapHook(_manager, _owner, _treasury, _launchSettlementCaller)
    {}

    function validateHookAddress(BaseHook) internal pure override {}
}

contract NonPayableSwapCaller {
    MemeverseSwapRouter internal immutable router;

    constructor(MemeverseSwapRouter _router) {
        router = _router;
    }

    /// @notice Attempts a routed swap from a non-payable caller harness.
    /// @dev Used to verify native refund routing when the caller cannot receive ETH.
    /// @param key Pool key to swap against.
    /// @param params Swap parameters.
    /// @param recipient Recipient of any swap output.
    /// @param nativeRefundRecipient Recipient of any native refund.
    /// @param deadline Latest valid timestamp for the call.
    /// @param amountOutMinimum Minimum acceptable output amount.
    /// @param amountInMaximum Maximum acceptable input amount.
    /// @param hookData Opaque hook data forwarded to the router.
    /// @return delta Final swap delta returned by the router.
    function attemptSwap(
        PoolKey calldata key,
        SwapParams calldata params,
        address recipient,
        address nativeRefundRecipient,
        uint256 deadline,
        uint256 amountOutMinimum,
        uint256 amountInMaximum,
        bytes calldata hookData
    ) external payable returns (BalanceDelta delta) {
        return router.swap{value: msg.value}(
            key, params, recipient, nativeRefundRecipient, deadline, amountOutMinimum, amountInMaximum, hookData
        );
    }
}

contract NonPayableTreasury {}

contract DirectLaunchSettlementSpoofer {
    MockPoolManagerForRouterTest internal immutable manager;

    constructor(MockPoolManagerForRouterTest _manager) {
        manager = _manager;
    }

    /// @notice Attempts to spoof the launch settlement marker through a direct pool-manager unlock flow.
    /// @dev Used to verify the hook enforces settlement authorization even when the router is bypassed.
    /// @param key Pool key to swap against.
    /// @param params Swap parameters.
    /// @param hookData Marker payload forwarded into the hook callbacks.
    /// @return delta The swap delta returned by the mocked direct call path.
    function spoof(PoolKey calldata key, SwapParams calldata params, bytes calldata hookData)
        external
        returns (BalanceDelta delta)
    {
        delta = abi.decode(manager.unlock(abi.encode(key, params, hookData)), (BalanceDelta));
    }

    /// @notice Executes the mocked swap during the manager unlock callback.
    /// @dev The manager calls back into this contract during `unlock`.
    /// @param data Encoded pool key, swap params, and hook data.
    /// @return result ABI-encoded swap delta.
    function unlockCallback(bytes calldata data) external returns (bytes memory result) {
        (PoolKey memory key, SwapParams memory params, bytes memory hookData) =
            abi.decode(data, (PoolKey, SwapParams, bytes));
        BalanceDelta delta = manager.swap(key, params, hookData);
        result = abi.encode(delta);
    }
}

contract MemeverseSwapRouterTest is Test {
    using PoolIdLibrary for PoolKey;

    event EmergencyFlagUpdated(bool oldFlag, bool newFlag);

    uint160 internal constant SQRT_PRICE_1_1 = 79228162514264337593543950336;
    uint160 internal constant FULL_RANGE_MIN_SQRT_PRICE_X96 = 4_310_618_292;
    uint160 internal constant FULL_RANGE_MAX_SQRT_PRICE_X96 =
        1_456_195_216_270_955_103_206_513_029_158_776_779_468_408_838_535;
    uint256 internal constant ALICE_PK = 0xA11CE;
    bytes32 internal constant LAUNCH_SETTLEMENT_HOOKDATA_HASH = keccak256("memeverse.launch-settlement.hookdata");

    MockPoolManagerForRouterTest internal manager;
    TestableMemeverseUniswapHookForRouter internal hook;
    MemeverseSwapRouter internal router;
    MockERC20 internal token0;
    MockERC20 internal token1;
    address internal treasury;
    address internal alice;
    DirectLaunchSettlementSpoofer internal spoofSettlementCaller;
    PoolKey internal key;
    PoolId internal poolId;

    /// @notice Deploys the mock manager, hook, router, and test tokens.
    /// @dev Seeds balances and approvals used throughout the router test suite.
    function setUp() public {
        manager = new MockPoolManagerForRouterTest();
        treasury = makeAddr("treasury");
        alice = vm.addr(ALICE_PK);
        hook = new TestableMemeverseUniswapHookForRouter(
            IPoolManager(address(manager)), address(this), treasury, address(this)
        );
        router = new MemeverseSwapRouter(
            IPoolManager(address(manager)),
            IMemeverseUniswapHook(address(hook)),
            IPermit2(address(0xBEEF)),
            address(this)
        );
        hook.setLaunchSettlementCaller(address(router));
        spoofSettlementCaller = new DirectLaunchSettlementSpoofer(manager);

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

    /// @notice Configures which currency the hook should collect protocol fees in.
    /// @dev Helper invoked by tests before swaps to keep protocol-fee context consistent.
    function _setProtocolFeeCurrency(Currency feeCurrency) internal {
        hook.setProtocolFeeCurrency(feeCurrency);
    }

    /// @notice Progresses the block timestamp past the launch window.
    /// @dev Ensures tests can trigger post-launch behavior without waiting in real time.
    function _matureLaunchWindow() internal {
        vm.warp(block.timestamp + 900);
    }

    /// @notice Verifies hook deployment rejects a zero treasury address.
    /// @dev Covers constructor validation.
    function testConstructor_RevertsWhenTreasuryIsZeroAddress() external {
        vm.expectRevert(IMemeverseUniswapHook.ZeroAddress.selector);
        new TestableMemeverseUniswapHookForRouter(
            IPoolManager(address(manager)), address(this), address(0), address(this)
        );
    }

    /// @notice Verifies hook deployment rejects a zero launch settlement operator.
    /// @dev Covers constructor validation for the launch settlement permission boundary.
    function testConstructor_RevertsWhenLaunchSettlementOperatorIsZeroAddress() external {
        vm.expectRevert(IMemeverseSwapRouter.ZeroAddress.selector);
        new MemeverseSwapRouter(
            IPoolManager(address(manager)), IMemeverseUniswapHook(address(hook)), IPermit2(address(0xBEEF)), address(0)
        );

        vm.expectRevert(IMemeverseUniswapHook.ZeroAddress.selector);
        new TestableMemeverseUniswapHookForRouter(IPoolManager(address(manager)), address(this), treasury, address(0));
    }

    /// @notice Verifies swaps reject pool keys wired to a different hook address.
    /// @dev Covers router validation that only its configured hook may be used.
    function testSwapReverts_WhenHookAddressDoesNotMatchRouterHook() external {
        PoolKey memory invalidKey = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            fee: 0x800000,
            tickSpacing: 200,
            hooks: IHooks(address(0x1234))
        });

        vm.expectRevert(IMemeverseSwapRouter.InvalidHook.selector);
        router.swap(
            invalidKey,
            SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}),
            address(this),
            address(this),
            block.timestamp,
            0,
            100 ether,
            ""
        );
    }

    /// @notice Verifies swaps reject zero `amountSpecified`.
    /// @dev Covers router validation for meaningless swap requests.
    function testSwapReverts_WhenAmountSpecifiedIsZero() external {
        vm.expectRevert(IMemeverseSwapRouter.SwapAmountCannotBeZero.selector);
        router.swap(
            key,
            SwapParams({zeroForOne: true, amountSpecified: 0, sqrtPriceLimitX96: 0}),
            address(this),
            address(this),
            block.timestamp,
            0,
            100 ether,
            ""
        );
    }

    /// @notice Verifies exact-output swaps require a non-zero `amountInMaximum`.
    /// @dev Prevents exact-output callers from omitting the user input budget.
    function testSwapReverts_WhenExactOutputOmitsAmountInMaximum() external {
        vm.expectRevert(IMemeverseSwapRouter.AmountInMaximumRequired.selector);
        router.swap(
            key,
            SwapParams({zeroForOne: true, amountSpecified: 100 ether, sqrtPriceLimitX96: 0}),
            address(this),
            address(this),
            block.timestamp,
            0,
            0,
            ""
        );
    }

    /// @notice Verifies setting the treasury to the zero address reverts.
    /// @dev Covers owner configuration validation.
    function testSetTreasury_RevertsOnZeroAddress() external {
        vm.expectRevert(IMemeverseUniswapHook.ZeroAddress.selector);
        hook.setTreasury(address(0));
    }

    /// @notice Verifies toggling the emergency flag updates state and emits the event.
    /// @dev Covers the hook emergency configuration path.
    function testSetEmergencyFlag_EmitsEventAndUpdatesState() external {
        vm.expectEmit(false, false, false, true);
        emit EmergencyFlagUpdated(false, true);
        hook.setEmergencyFlag(true);

        assertTrue(hook.emergencyFlag(), "emergency flag");
    }

    /// @notice Verifies swap quotes fall back to the base fee when emergency mode is enabled.
    /// @dev Covers quote behavior under the emergency flag.
    function testQuoteSwap_WhenEmergencyFlagEnabled_ReturnsBaseFee() external {
        _setProtocolFeeCurrency(key.currency0);
        _matureLaunchWindow();

        IMemeverseUniswapHook.SwapQuote memory normalQuote =
            hook.quoteSwap(key, SwapParams({zeroForOne: true, amountSpecified: -10_000 ether, sqrtPriceLimitX96: 0}));
        hook.setEmergencyFlag(true);
        IMemeverseUniswapHook.SwapQuote memory emergencyQuote =
            hook.quoteSwap(key, SwapParams({zeroForOne: true, amountSpecified: -10_000 ether, sqrtPriceLimitX96: 0}));

        assertEq(emergencyQuote.feeBps, 100, "base fee only");
        assertGe(normalQuote.feeBps, emergencyQuote.feeBps, "normal fee not below emergency fee");
    }

    /// @notice Verifies swaps handle multiple protocol-fee currencies across pools.
    /// @dev Covers protocol-fee accounting across independently configured pools.
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

    /// @notice Verifies swaps revert when native protocol fees cannot be delivered to the treasury.
    /// @dev Covers the native protocol-fee settlement failure path.
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

    /// @notice Verifies successful swaps record an anti-snipe attempt and execute.
    /// @dev Covers the standard exact-input happy path.
    function testSwapPass_RecordsAttemptAndExecutes() external {
        _setProtocolFeeCurrency(key.currency0);
        _matureLaunchWindow();
        uint256 balance0Before = token0.balanceOf(address(this));
        uint256 balance1Before = token1.balanceOf(address(this));
        uint256 treasury0Before = token0.balanceOf(treasury);
        uint160 priceLimit = uint160((uint256(SQRT_PRICE_1_1) * 99) / 100);

        BalanceDelta delta = router.swap(
            key,
            SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: priceLimit}),
            address(this),
            address(this),
            block.timestamp,
            40 ether,
            100 ether,
            ""
        );

        assertLt(token0.balanceOf(address(this)), balance0Before, "token0 spent");
        assertGt(token1.balanceOf(address(this)), balance1Before, "token1 received");
        assertGt(token0.balanceOf(treasury), treasury0Before, "treasury collected token0");
        assertLt(delta.amount0(), 0, "delta0");
        assertGt(delta.amount1(), 0, "delta1");
    }

    /// @notice Verifies routed swaps do not pay for a redundant launch-fee quote round-trip.
    /// @dev A successful swap should read the pool slot0 storage once for quote math and once for state update.
    function testSwapPass_AntiSnipePathAvoidsRedundantFailureQuoteRead() external {
        _setProtocolFeeCurrency(key.currency0);
        _matureLaunchWindow();
        uint160 priceLimit = uint160((uint256(SQRT_PRICE_1_1) * 99) / 100);
        bytes32 poolStateSlot = keccak256(abi.encodePacked(PoolId.unwrap(poolId), bytes32(uint256(6))));

        vm.expectCall(
            address(manager), abi.encodeCall(MockPoolManagerForRouterTest.extsload, (poolStateSlot)), uint64(2)
        );

        BalanceDelta delta = router.swap(
            key,
            SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: priceLimit}),
            address(this),
            address(this),
            block.timestamp,
            40 ether,
            100 ether,
            ""
        );

        assertLt(delta.amount0(), 0, "delta0");
        assertGt(delta.amount1(), 0, "delta1");
    }

    /// @notice Verifies only the configured launch settlement operator can execute the preorder settlement swap.
    /// @dev Prevents ordinary users from accessing the fixed 1% settlement path.
    function testExecuteLaunchPreorderSwap_RevertsWhenCallerIsNotSettlementOperator() external {
        _setProtocolFeeCurrency(key.currency0);
        uint160 priceLimit = uint160((uint256(SQRT_PRICE_1_1) * 99) / 100);

        vm.prank(alice);
        vm.expectRevert(IMemeverseSwapRouter.InvalidLaunchSettlementOperator.selector);
        router.swap(
            key,
            SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: priceLimit}),
            address(this),
            address(this),
            block.timestamp,
            40 ether,
            100 ether,
            abi.encode(LAUNCH_SETTLEMENT_HOOKDATA_HASH)
        );
    }

    /// @notice Verifies launch settlement swaps bypass the launch fee floor and dynamic fee logic and settle at 1%.
    /// @dev Confirms the treasury only receives the 30% protocol slice of a 1% total fee.
    function testExecuteLaunchPreorderSwap_UsesFixedOnePercentFee() external {
        _setProtocolFeeCurrency(key.currency0);
        uint160 priceLimit = uint160((uint256(SQRT_PRICE_1_1) * 99) / 100);
        uint256 treasury0Before = token0.balanceOf(treasury);

        IMemeverseUniswapHook.SwapQuote memory quoteAtLaunch = hook.quoteSwap(
            key, SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: priceLimit})
        );
        assertEq(quoteAtLaunch.feeBps, 5000, "public launch fee");

        BalanceDelta delta = router.swap(
            key,
            SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: priceLimit}),
            address(this),
            address(this),
            block.timestamp,
            40 ether,
            100 ether,
            abi.encode(LAUNCH_SETTLEMENT_HOOKDATA_HASH)
        );

        assertLt(delta.amount0(), 0, "delta0");
        assertGt(delta.amount1(), 0, "delta1");
        assertEq(token0.balanceOf(treasury) - treasury0Before, 0.3 ether, "fixed 1% protocol fee");
    }

    /// @notice Verifies changing the launch fee floor does not change the fixed-fee preorder settlement path.
    /// @dev Guards against coupling settlement pricing to the owner-configurable launch decay minimum.
    function testExecuteLaunchPreorderSwap_IgnoresConfigurableLaunchFeeFloor() external {
        _setProtocolFeeCurrency(key.currency0);
        hook.setDefaultLaunchFeeConfig(
            IMemeverseUniswapHook.LaunchFeeConfig({startFeeBps: 4000, minFeeBps: 300, decayDurationSeconds: 900})
        );

        uint160 priceLimit = uint160((uint256(SQRT_PRICE_1_1) * 99) / 100);
        uint256 treasury0Before = token0.balanceOf(treasury);

        BalanceDelta delta = router.swap(
            key,
            SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: priceLimit}),
            address(this),
            address(this),
            block.timestamp,
            40 ether,
            100 ether,
            abi.encode(LAUNCH_SETTLEMENT_HOOKDATA_HASH)
        );

        assertLt(delta.amount0(), 0, "delta0");
        assertGt(delta.amount1(), 0, "delta1");
        assertEq(token0.balanceOf(treasury) - treasury0Before, 0.3 ether, "settlement remains fixed 1%");
    }

    /// @notice Verifies spoofed launch-settlement markers also fail when callers bypass the router.
    /// @dev Locks the authorization check into the hook instead of relying only on the router.
    function testDirectPoolManagerSwap_RevertsWhenLaunchSettlementMarkerIsSpoofed() external {
        _setProtocolFeeCurrency(key.currency0);
        uint160 priceLimit = uint160((uint256(SQRT_PRICE_1_1) * 99) / 100);

        vm.expectRevert(IMemeverseUniswapHook.Unauthorized.selector);
        spoofSettlementCaller.spoof(
            key,
            SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: priceLimit}),
            abi.encode(LAUNCH_SETTLEMENT_HOOKDATA_HASH)
        );
    }

    /// @notice Verifies one-for-zero exact-input swaps execute successfully.
    /// @dev Covers the basic exact-input routing path.
    function testSwapPass_OneForZeroExactInputExecutes() external {
        _setProtocolFeeCurrency(key.currency1);
        _matureLaunchWindow();
        uint256 balance0Before = token0.balanceOf(address(this));
        uint256 balance1Before = token1.balanceOf(address(this));
        uint256 treasury1Before = token1.balanceOf(treasury);
        uint160 priceLimit = uint160((uint256(SQRT_PRICE_1_1) * 101) / 100);

        BalanceDelta delta = router.swap(
            key,
            SwapParams({zeroForOne: false, amountSpecified: -100 ether, sqrtPriceLimitX96: priceLimit}),
            address(this),
            address(this),
            block.timestamp,
            40 ether,
            100 ether,
            ""
        );

        assertGt(token0.balanceOf(address(this)), balance0Before, "token0 received");
        assertLt(token1.balanceOf(address(this)), balance1Before, "token1 spent");
        assertGt(token1.balanceOf(treasury), treasury1Before, "treasury collected token1");
        assertGt(delta.amount0(), 0, "delta0");
        assertLt(delta.amount1(), 0, "delta1");
    }

    /// @notice Verifies zero-for-one exact-input swaps apply output-side protocol fees.
    /// @dev Covers output-fee accounting for exact-input swaps.
    function testSwapPass_ZeroForOneExactInput_OutputSideProtocolFee() external {
        _setProtocolFeeCurrency(key.currency1);
        uint256 balance1Before = token1.balanceOf(address(this));
        uint256 treasury1Before = token1.balanceOf(treasury);
        uint160 priceLimit = uint160((uint256(SQRT_PRICE_1_1) * 99) / 100);

        BalanceDelta delta = router.swap(
            key,
            SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: priceLimit}),
            address(this),
            address(this),
            block.timestamp,
            40 ether,
            100 ether,
            ""
        );

        assertGt(token1.balanceOf(address(this)), balance1Before, "token1 received");
        assertLt(delta.amount1(), int128(int256(50 ether)), "output reduced by output-side fee");
        assertGt(token1.balanceOf(treasury), treasury1Before, "treasury collected token1");
    }

    /// @notice Verifies one-for-zero exact-input swaps apply output-side protocol fees.
    /// @dev Covers output-fee accounting for exact-input swaps.
    function testSwapPass_OneForZeroExactInput_OutputSideProtocolFee() external {
        _setProtocolFeeCurrency(key.currency0);
        uint256 balance0Before = token0.balanceOf(address(this));
        uint256 treasury0Before = token0.balanceOf(treasury);
        uint160 priceLimit = uint160((uint256(SQRT_PRICE_1_1) * 101) / 100);

        BalanceDelta delta = router.swap(
            key,
            SwapParams({zeroForOne: false, amountSpecified: -100 ether, sqrtPriceLimitX96: priceLimit}),
            address(this),
            address(this),
            block.timestamp,
            40 ether,
            100 ether,
            ""
        );

        assertGt(token0.balanceOf(address(this)), balance0Before, "token0 received");
        assertLt(delta.amount0(), int128(int256(50 ether)), "output reduced by output-side fee");
        assertGt(token0.balanceOf(treasury), treasury0Before, "treasury collected token0");
    }

    /// @notice Verifies zero-for-one exact-output swaps execute and charge input-side fees.
    /// @dev Covers exact-output fee accounting.
    function testSwapPass_ZeroForOneExactOutputExecutesAndChargesInputFee() external {
        _setProtocolFeeCurrency(key.currency0);
        uint256 balance0Before = token0.balanceOf(address(this));
        uint256 balance1Before = token1.balanceOf(address(this));
        uint256 treasury0Before = token0.balanceOf(treasury);
        uint160 priceLimit = uint160((uint256(SQRT_PRICE_1_1) * 99) / 100);

        BalanceDelta delta = router.swap(
            key,
            SwapParams({zeroForOne: true, amountSpecified: 100 ether, sqrtPriceLimitX96: priceLimit}),
            address(this),
            address(this),
            block.timestamp,
            0,
            300 ether,
            ""
        );

        assertEq(token1.balanceOf(address(this)) - balance1Before, 100 ether, "exact output received");
        assertGt(balance0Before - token0.balanceOf(address(this)), 200 ether, "input includes fee");
        assertGt(token0.balanceOf(treasury), treasury0Before, "treasury collected token0");
        assertEq(delta.amount1(), int128(int256(100 ether)), "delta1");
        assertLt(delta.amount0(), -int128(int256(200 ether)), "delta0 fee-adjusted");
    }

    /// @notice Verifies one-for-zero exact-output swaps execute and charge input-side fees.
    /// @dev Covers exact-output fee accounting.
    function testSwapPass_OneForZeroExactOutputExecutesAndChargesInputFee() external {
        _setProtocolFeeCurrency(key.currency1);
        uint256 balance0Before = token0.balanceOf(address(this));
        uint256 balance1Before = token1.balanceOf(address(this));
        uint256 treasury1Before = token1.balanceOf(treasury);
        uint160 priceLimit = uint160((uint256(SQRT_PRICE_1_1) * 101) / 100);

        BalanceDelta delta = router.swap(
            key,
            SwapParams({zeroForOne: false, amountSpecified: 100 ether, sqrtPriceLimitX96: priceLimit}),
            address(this),
            address(this),
            block.timestamp,
            0,
            300 ether,
            ""
        );

        assertEq(token0.balanceOf(address(this)) - balance0Before, 100 ether, "exact output received");
        assertGt(balance1Before - token1.balanceOf(address(this)), 200 ether, "input includes fee");
        assertGt(token1.balanceOf(treasury), treasury1Before, "treasury collected token1");
        assertEq(delta.amount0(), int128(int256(100 ether)), "delta0");
        assertLt(delta.amount1(), -int128(int256(200 ether)), "delta1 fee-adjusted");
    }

    /// @notice Verifies zero-for-one exact-output swaps gross up output-side protocol fees.
    /// @dev Covers output-side fee gross-up logic for exact-output swaps.
    function testSwapPass_ZeroForOneExactOutput_OutputSideProtocolFeeGrossesUp() external {
        _setProtocolFeeCurrency(key.currency1);
        uint256 balance0Before = token0.balanceOf(address(this));
        uint256 balance1Before = token1.balanceOf(address(this));
        uint256 treasury1Before = token1.balanceOf(treasury);
        uint160 priceLimit = uint160((uint256(SQRT_PRICE_1_1) * 99) / 100);

        BalanceDelta delta = router.swap(
            key,
            SwapParams({zeroForOne: true, amountSpecified: 100 ether, sqrtPriceLimitX96: priceLimit}),
            address(this),
            address(this),
            block.timestamp,
            0,
            300 ether,
            ""
        );

        assertEq(token1.balanceOf(address(this)) - balance1Before, 100 ether, "exact net output");
        assertGt(balance0Before - token0.balanceOf(address(this)), 200 ether, "gross-up raises input");
        assertEq(delta.amount1(), int128(int256(100 ether)), "delta1 net output");
        assertGt(token1.balanceOf(treasury), treasury1Before, "treasury collected token1");
    }

    /// @notice Verifies one-for-zero exact-output swaps gross up output-side protocol fees.
    /// @dev Covers output-side fee gross-up logic for exact-output swaps.
    function testSwapPass_OneForZeroExactOutput_OutputSideProtocolFeeGrossesUp() external {
        _setProtocolFeeCurrency(key.currency0);
        uint256 balance0Before = token0.balanceOf(address(this));
        uint256 balance1Before = token1.balanceOf(address(this));
        uint256 treasury0Before = token0.balanceOf(treasury);
        uint160 priceLimit = uint160((uint256(SQRT_PRICE_1_1) * 101) / 100);

        BalanceDelta delta = router.swap(
            key,
            SwapParams({zeroForOne: false, amountSpecified: 100 ether, sqrtPriceLimitX96: priceLimit}),
            address(this),
            address(this),
            block.timestamp,
            0,
            300 ether,
            ""
        );

        assertEq(token0.balanceOf(address(this)) - balance0Before, 100 ether, "exact net output");
        assertGt(balance1Before - token1.balanceOf(address(this)), 200 ether, "gross-up raises input");
        assertEq(delta.amount0(), int128(int256(100 ether)), "delta0 net output");
        assertGt(token0.balanceOf(treasury), treasury0Before, "treasury collected token0");
    }

    /// @notice Verifies swaps skip attempt recording after the anti-snipe window ends.
    /// @dev Covers the post-window fast path.
    function testSwapPass_AfterAntiSnipeWindow_SkipsAttemptRecording() external {
        _setProtocolFeeCurrency(key.currency0);
        _matureLaunchWindow();
        vm.roll(block.number + 11);

        uint256 balance0Before = token0.balanceOf(address(this));
        uint256 balance1Before = token1.balanceOf(address(this));

        BalanceDelta delta = router.swap(
            key,
            SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}),
            address(this),
            address(this),
            block.timestamp,
            40 ether,
            100 ether,
            ""
        );

        assertLt(token0.balanceOf(address(this)), balance0Before, "token0 spent");
        assertGt(token1.balanceOf(address(this)), balance1Before, "token1 received");
        assertLt(delta.amount0(), 0, "delta0");
        assertGt(delta.amount1(), 0, "delta1");
    }

    /// @notice Verifies exact-output swaps revert when the required input exceeds the maximum.
    /// @dev Covers router slippage protection.
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

    /// @notice Verifies exact-input swaps revert when output falls below the minimum.
    /// @dev Covers router slippage protection.
    function testSwapReverts_WhenExactInputFallsBelowAmountOutMinimum() external {
        _setProtocolFeeCurrency(key.currency0);
        _matureLaunchWindow();
        uint160 priceLimit = uint160((uint256(SQRT_PRICE_1_1) * 99) / 100);

        vm.expectRevert(
            abi.encodeWithSelector(IMemeverseSwapRouter.OutputAmountBelowMinimum.selector, 49.5 ether, 60 ether)
        );
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

    /// @notice Verifies exact-output quotes include input-side fees in the user input amount.
    /// @dev Covers quote semantics for exact-output swaps.
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

    /// @notice Verifies router quotes proxy directly to the hook quote logic.
    /// @dev Covers the router quote passthrough surface.
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

    /// @notice Verifies native-input exact-output swaps execute successfully.
    /// @dev Covers native input routing in the exact-output path.
    function testSwapPass_NativeInputExactOutputExecutes() external {
        PoolKey memory nativeKey = _dynamicPoolKey(CurrencyLibrary.ADDRESS_ZERO, Currency.wrap(address(token1)));
        _dealAndInitializeNativePool(nativeKey, true);
        _setProtocolFeeCurrency(nativeKey.currency0);

        uint160 priceLimit = uint160((uint256(SQRT_PRICE_1_1) * 99) / 100);
        uint256 token1Before = token1.balanceOf(address(this));

        BalanceDelta delta = router.swap{value: 300 ether}(
            nativeKey,
            SwapParams({zeroForOne: true, amountSpecified: 100 ether, sqrtPriceLimitX96: priceLimit}),
            address(this),
            address(this),
            block.timestamp,
            0,
            300 ether,
            ""
        );

        assertEq(token1.balanceOf(address(this)) - token1Before, 100 ether, "native exact output received");
        assertEq(delta.amount1(), int128(int256(100 ether)), "delta1");
    }

    /// @notice Verifies router fee claims relay through the hook core with a signature.
    /// @dev Covers router-mediated LP fee claiming.
    function testRouterClaimFees_UsesHookCoreWithSignature() external {
        _setProtocolFeeCurrency(key.currency0);

        vm.prank(alice);
        router.addLiquidity(
            key.currency0, key.currency1, 100 ether, 100 ether, 90 ether, 90 ether, alice, alice, block.timestamp
        );
        _matureLaunchWindow();

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

    /// @notice Verifies claimable-fee previews match claims and do not mutate state.
    /// @dev Covers the router preview surface for LP fees.
    function testClaimableFees_ViewMatchesClaimAndDoesNotMutateState() external {
        _setProtocolFeeCurrency(key.currency0);

        vm.prank(alice);
        router.addLiquidity(
            key.currency0, key.currency1, 100 ether, 100 ether, 90 ether, 90 ether, alice, alice, block.timestamp
        );
        _matureLaunchWindow();

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

    /// @notice Verifies the router derives the expected dynamic-fee hook pool key.
    /// @dev Covers pair normalization and hook wiring.
    function testRouterGetHookPoolKey_ReturnsDynamicHookKey() external view {
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

    /// @notice Verifies router fee previews match the hook claimable-fee view.
    /// @dev Covers router passthrough behavior for pair fee previews.
    function testRouterPreviewClaimableFees_MatchesHookClaimableFees() external {
        _setProtocolFeeCurrency(key.currency0);

        vm.prank(alice);
        router.addLiquidity(
            key.currency0, key.currency1, 100 ether, 100 ether, 90 ether, 90 ether, alice, alice, block.timestamp
        );
        _matureLaunchWindow();

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

    /// @notice Verifies the router returns the hook LP token for a pair.
    /// @dev Covers the new pair-to-LP-token view helper.
    function testRouterLpToken_ReturnsHookPoolLpTokenAddress() external {
        PoolKey memory normalizedKey = router.getHookPoolKey(address(token0), address(token1));
        manager.initialize(normalizedKey, SQRT_PRICE_1_1);

        (address poolLpToken,,) = hook.poolInfo(normalizedKey.toId());
        assertEq(router.lpToken(address(token0), address(token1)), poolLpToken, "lp token");
    }

    /// @notice Verifies the router quotes the required pair amounts for a target liquidity.
    /// @dev Covers the new exact-liquidity read helper.
    function testRouterQuoteAmountsForLiquidity_ReturnsRequiredPairAmounts() external {
        uint128 liquidityDesired = 10 ether;
        PoolKey memory normalizedKey = router.getHookPoolKey(address(token0), address(token1));
        manager.initialize(normalizedKey, SQRT_PRICE_1_1);

        (uint160 sqrtPriceX96,,,) = manager.getSlot0(normalizedKey.toId());
        (uint256 amount0Required, uint256 amount1Required) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96, FULL_RANGE_MIN_SQRT_PRICE_X96, FULL_RANGE_MAX_SQRT_PRICE_X96, liquidityDesired
        );

        (uint256 amountToken0, uint256 amountToken1) =
            router.quoteAmountsForLiquidity(address(token0), address(token1), liquidityDesired);

        assertEq(amountToken0, amount0Required, "token0 required");
        assertEq(amountToken1, amount1Required, "token1 required");
    }

    /// @notice Verifies liquidity-related router selectors remain aligned with the public interface.
    /// @dev Guards ABI stability while internal parameter plumbing is refactored.
    function testRouterLiquiditySelectors_MatchInterface() external pure {
        assertEq(MemeverseSwapRouter.addLiquidity.selector, IMemeverseSwapRouter.addLiquidity.selector, "add");
        assertEq(
            MemeverseSwapRouter.addLiquidityWithPermit2.selector,
            IMemeverseSwapRouter.addLiquidityWithPermit2.selector,
            "add permit2"
        );
        assertEq(MemeverseSwapRouter.removeLiquidity.selector, IMemeverseSwapRouter.removeLiquidity.selector, "remove");
        assertEq(
            MemeverseSwapRouter.removeLiquidityWithPermit2.selector,
            IMemeverseSwapRouter.removeLiquidityWithPermit2.selector,
            "remove permit2"
        );
        assertEq(
            MemeverseSwapRouter.createPoolAndAddLiquidity.selector,
            IMemeverseSwapRouter.createPoolAndAddLiquidity.selector,
            "create"
        );
        assertEq(
            MemeverseSwapRouter.createPoolAndAddLiquidityWithPermit2.selector,
            IMemeverseSwapRouter.createPoolAndAddLiquidityWithPermit2.selector,
            "create permit2"
        );
    }

    /// @notice Verifies pool bootstrap and initial liquidity use the hook core path.
    /// @dev Covers the router bootstrap helper.
    function testRouterCreatePoolAndAddLiquidity_UsesHookCore() external {
        MockERC20 tokenA = new MockERC20("A", "A", 18);
        MockERC20 tokenB = new MockERC20("B", "B", 18);
        tokenA.mint(address(this), 1_000_000 ether);
        tokenB.mint(address(this), 1_000_000 ether);
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);

        (uint128 liquidity, PoolKey memory createdKey) = router.createPoolAndAddLiquidity(
            address(tokenA),
            address(tokenB),
            100 ether,
            100 ether,
            SQRT_PRICE_1_1,
            address(this),
            address(this),
            block.timestamp
        );

        (address liquidityToken,,) = hook.poolInfo(createdKey.toId());
        assertEq(address(createdKey.hooks), address(hook), "hook");
        assertEq(createdKey.fee, 0x800000, "dynamic fee");
        assertGt(liquidity, 0, "liquidity");
        assertGt(UniswapLP(liquidityToken).balanceOf(address(this)), 0, "lp balance");
    }

    /// @notice Verifies pool bootstrap uses the caller-provided start price.
    /// @dev Confirms the router no longer derives a bootstrap price from token budgets.
    function testRouterCreatePoolAndAddLiquidity_UsesProvidedStartPrice() external {
        MockERC20 token18 = new MockERC20("Token18", "T18", 18);
        MockERC20 token6 = new MockERC20("Token6", "T6", 6);
        uint160 startPrice = SQRT_PRICE_1_1 / 2;
        token18.mint(address(this), 1_000_000 ether);
        token6.mint(address(this), 1_000_000 * 1e6);
        token18.approve(address(router), type(uint256).max);
        token6.approve(address(router), type(uint256).max);

        (, PoolKey memory createdKey) = router.createPoolAndAddLiquidity(
            address(token18),
            address(token6),
            100 ether,
            100 * 1e6,
            startPrice,
            address(this),
            address(this),
            block.timestamp
        );

        (uint160 sqrtPriceX96,,,) = manager.getSlot0(createdKey.toId());
        assertEq(sqrtPriceX96, startPrice, "provided sqrt price");
    }

    /// @notice Verifies addLiquidity rejects expired deadlines.
    /// @dev Covers the router deadline guard before any liquidity side effects happen.
    function testAddLiquidityReverts_WhenDeadlineExpired() external {
        vm.expectRevert(IMemeverseSwapRouter.ExpiredPastDeadline.selector);
        router.addLiquidity(
            key.currency0,
            key.currency1,
            100 ether,
            100 ether,
            90 ether,
            90 ether,
            address(this),
            address(this),
            block.timestamp - 1
        );
    }

    /// @notice Verifies native-input addLiquidity requires a refund recipient.
    /// @dev Covers the invalid native refund recipient branch.
    function testAddLiquidityReverts_WhenNativeRefundRecipientMissing() external {
        PoolKey memory nativeKey = _dynamicPoolKey(CurrencyLibrary.ADDRESS_ZERO, Currency.wrap(address(token1)));
        _dealAndInitializeNativePool(nativeKey, false);

        vm.expectRevert(IMemeverseSwapRouter.InvalidNativeRefundRecipient.selector);
        router.addLiquidity{value: 100 ether}(
            nativeKey.currency0,
            nativeKey.currency1,
            100 ether,
            100 ether,
            90 ether,
            90 ether,
            address(this),
            address(0),
            block.timestamp
        );
    }

    /// @notice Verifies removeLiquidity rejects expired deadlines.
    /// @dev Covers the router deadline guard on liquidity removal.
    function testRemoveLiquidityReverts_WhenDeadlineExpired() external {
        vm.prank(alice);
        router.addLiquidity(
            key.currency0, key.currency1, 100 ether, 100 ether, 90 ether, 90 ether, alice, alice, block.timestamp
        );
        (address liquidityToken,,) = hook.poolInfo(poolId);
        uint128 liquidity = uint128(UniswapLP(liquidityToken).balanceOf(alice));

        vm.prank(alice);
        vm.expectRevert(IMemeverseSwapRouter.ExpiredPastDeadline.selector);
        router.removeLiquidity(key.currency0, key.currency1, liquidity, 0, 0, alice, block.timestamp - 1);
    }

    /// @notice Verifies pool bootstrap rejects identical token pairs.
    /// @dev Covers router validation that a pool must contain two distinct assets.
    function testCreatePoolAndAddLiquidityReverts_WhenTokenPairIsIdentical() external {
        vm.expectRevert(IMemeverseSwapRouter.InvalidTokenPair.selector);
        router.createPoolAndAddLiquidity(
            address(token0),
            address(token0),
            100 ether,
            100 ether,
            SQRT_PRICE_1_1,
            address(this),
            address(this),
            block.timestamp
        );
    }

    /// @notice Verifies pool bootstrap rejects expired deadlines.
    /// @dev Covers the router deadline guard on create-and-add flows.
    function testCreatePoolAndAddLiquidityReverts_WhenDeadlineExpired() external {
        MockERC20 tokenA = new MockERC20("A", "A", 18);
        MockERC20 tokenB = new MockERC20("B", "B", 18);
        tokenA.mint(address(this), 1_000 ether);
        tokenB.mint(address(this), 1_000 ether);
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);

        vm.expectRevert(IMemeverseSwapRouter.ExpiredPastDeadline.selector);
        router.createPoolAndAddLiquidity(
            address(tokenA),
            address(tokenB),
            100 ether,
            100 ether,
            SQRT_PRICE_1_1,
            address(this),
            address(this),
            block.timestamp - 1
        );
    }

    /// @notice Builds a normalized pool key wired to the test hook.
    /// @dev Encapsulates the pair ordering and hook wiring shared by the router tests.
    function _dynamicPoolKey(Currency currency0, Currency currency1) internal view returns (PoolKey memory) {
        return PoolKey({
            currency0: currency0, currency1: currency1, fee: 0x800000, tickSpacing: 200, hooks: IHooks(address(hook))
        });
    }

    /// @notice Funds and initializes a native-input pool fixture.
    /// @dev Controls both caller and manager balances before seeding liquidity.
    function _dealAndInitializeNativePool(PoolKey memory nativeKey, bool fundManager) internal {
        vm.deal(address(this), 1_000_000 ether);
        if (fundManager) vm.deal(address(manager), 1_000_000 ether);
        manager.initialize(nativeKey, SQRT_PRICE_1_1);
    }

    /// @notice Accepts native refunds delivered during router tests.
    /// @dev Lets the test contract receive ETH when the router funnels leftover native funds.
    receive() external payable {}
}
