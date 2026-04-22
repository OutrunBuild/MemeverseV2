// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager, ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta, toBalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {LiquidityAmounts} from "../../src/swap/libraries/LiquidityAmounts.sol";
import {BaseHook} from "@uniswap/v4-hooks-public/src/base/BaseHook.sol";

import {MemeverseUniswapHook} from "../../src/swap/MemeverseUniswapHook.sol";
import {MemeverseSwapRouter} from "../../src/swap/MemeverseSwapRouter.sol";
import {IMemeverseUniswapHook} from "../../src/swap/interfaces/IMemeverseUniswapHook.sol";
import {UniswapLP} from "../../src/swap/tokens/UniswapLP.sol";

/// @dev Mock-harness boundary:
/// - This file's local hook-liquidity manager mock only covers plumbing, local revert surface,
///   deterministic branch coverage, and rollback witnesses inside the hook-local harness.
/// - The newer integration tests only cover a narrow direct-manager exact-input subset under a stricter manager
///   harness. One-for-zero symmetry beyond that subset, launch-settlement swap semantics, and broader fee-side
///   execution claims are not proven by this file and must not be inferred from this mock manager.
contract MockPoolManagerForHookLiquidity {
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
    address internal hookAddress;
    address internal lastTakeRecipient;

    mapping(bytes32 => bytes32) internal extStorage;
    mapping(PoolId => Slot0State) internal slot0State;
    mapping(PoolId => uint128) internal liquidityState;
    mapping(PoolId => uint256) internal nextExactInputPoolInputAmount;

    /// @notice Initializes a mock pool and notifies the hook.
    /// @dev Seeds slot0 and liquidity-related storage so the hook sees the pool as configured.
    /// @param key Pool key being initialized.
    /// @param sqrtPriceX96 Initial sqrt price for the pool.
    function initialize(PoolKey memory key, uint160 sqrtPriceX96) external {
        PoolId poolId = key.toId();
        slot0State[poolId] = Slot0State({sqrtPriceX96: sqrtPriceX96, tick: 0, protocolFee: 0, lpFee: 0});
        _syncPoolStorage(poolId);
        hookAddress = address(key.hooks);
        key.hooks.beforeInitialize(msg.sender, key, sqrtPriceX96);
    }

    /// @notice Opens a temporary unlock window and forwards the callback payload.
    /// @dev Mimics the pool-manager unlock pattern expected by router and hook tests.
    /// @param data Encoded callback payload.
    /// @return result Callback return data.
    function unlock(bytes calldata data) external returns (bytes memory result) {
        unlocked = true;
        result = IUnlockCallback(msg.sender).unlockCallback(data);
        unlocked = false;
    }

    function swapAsUnlocked(PoolKey memory key, SwapParams memory params, bytes calldata hookData)
        external
        returns (BalanceDelta delta)
    {
        unlocked = true;
        delta = this.swap(key, params, hookData);
        unlocked = false;
    }

    /// @notice Applies a mocked liquidity modification for the pool.
    /// @dev Returns deterministic deltas while enforcing the unlock-window guard used by the hook.
    /// @param key Pool key being modified.
    /// @param params Liquidity change parameters.
    /// @param hookData Hook payload forwarded by the caller.
    /// @return delta Principal token delta for the modification.
    /// @return feesAccrued Fee delta, left empty in this mock.
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

    /// @notice Executes a mocked swap during hook-controlled unlock callbacks.
    /// @dev Produces deterministic hook-local branch coverage only; it does not model real swap economics.
    function swap(PoolKey memory key, SwapParams memory params, bytes calldata hookData)
        external
        returns (BalanceDelta delta)
    {
        if (!unlocked) revert ManagerLocked();

        (, BeforeSwapDelta beforeSwapDelta,) = key.hooks.beforeSwap(msg.sender, key, params, hookData);
        int256 amountToSwap = params.amountSpecified + beforeSwapDelta.getSpecifiedDelta();

        if (amountToSwap < 0) {
            uint256 exactInputAmount = uint256(-amountToSwap);
            uint256 configuredInputAmount = nextExactInputPoolInputAmount[key.toId()];
            if (configuredInputAmount != 0) {
                exactInputAmount = configuredInputAmount;
                delete nextExactInputPoolInputAmount[key.toId()];
            }
            uint256 exactOutputAmount = exactInputAmount / 2;
            if (params.zeroForOne) {
                delta = toBalanceDelta(-int128(int256(exactInputAmount)), int128(int256(exactOutputAmount)));
            } else {
                delta = toBalanceDelta(int128(int256(exactOutputAmount)), -int128(int256(exactInputAmount)));
            }
        } else {
            uint256 requestedOutputAmount = uint256(amountToSwap);
            uint256 requiredInputAmount = requestedOutputAmount * 2;
            if (params.zeroForOne) {
                delta = toBalanceDelta(-int128(int256(requiredInputAmount)), int128(int256(requestedOutputAmount)));
            } else {
                delta = toBalanceDelta(int128(int256(requestedOutputAmount)), -int128(int256(requiredInputAmount)));
            }
        }

        key.hooks.afterSwap(msg.sender, key, params, delta, hookData);
    }

    /// @notice Pays tokens or native currency out of the mock manager.
    /// @dev Records the recipient so tests can assert router settlement targets.
    /// @param currency Currency being paid out.
    /// @param to Recipient address.
    /// @param amount Amount to transfer.
    function take(Currency currency, address to, uint256 amount) external {
        lastTakeRecipient = to;
        if (currency.isAddressZero()) {
            (bool success,) = to.call{value: amount}("");
            require(success, "native take");
        } else {
            require(MockERC20(Currency.unwrap(currency)).transfer(to, amount), "erc20 take");
        }
    }

    /// @notice Accepts a sync call from the hook test harness.
    /// @dev This mock treats sync as a no-op while preserving interface compatibility.
    /// @param currency Currency being synced.
    function sync(Currency currency) external pure {
        currency;
    }

    /// @notice Accepts settlement value from the router or hook.
    /// @dev Mirrors the real pool-manager settle entry so ETH bookkeeping can be validated.
    /// @return paidAmount Amount considered settled by the mock.
    function settle() external payable returns (uint256) {
        return msg.value;
    }

    /// @notice Returns extsload.
    /// @dev Exposes the mock storage slot values used by the hook.
    /// @param slot slot.
    /// @return Returned value.
    function extsload(bytes32 slot) external view returns (bytes32) {
        return extStorage[slot];
    }

    /// @notice Returns get slot0.
    /// @dev Lets tests observe price and fee state returned by the mock manager.
    /// @param poolId pool id.
    /// @return Returned value.
    /// @return Returned value.
    /// @return Returned value.
    /// @return Returned value.
    function getSlot0(PoolId poolId) external view returns (uint160, int24, uint24, uint24) {
        Slot0State memory state = slot0State[poolId];
        return (state.sqrtPriceX96, state.tick, state.protocolFee, state.lpFee);
    }

    /// @notice Returns get liquidity.
    /// @dev Allows tests to assert pool liquidity matches the hook view.
    /// @param poolId pool id.
    /// @return Returned value.
    function getLiquidity(PoolId poolId) external view returns (uint128) {
        return liquidityState[poolId];
    }

    function setNextExactInputPoolInputAmount(PoolId poolId, uint256 inputAmount) external {
        nextExactInputPoolInputAmount[poolId] = inputAmount;
    }

    /// @notice Returns last take recipient address.
    /// @dev Observes which recipient the hook forwarded liquidity outputs to.
    /// @return Returned value.
    function lastTakeRecipientAddress() external view returns (address) {
        return lastTakeRecipient;
    }

    function _syncPoolStorage(PoolId poolId) internal {
        bytes32 stateSlot = keccak256(abi.encodePacked(PoolId.unwrap(poolId), POOLS_SLOT));
        Slot0State memory state = slot0State[poolId];

        extStorage[stateSlot] = bytes32(uint256(state.sqrtPriceX96));
        extStorage[bytes32(uint256(stateSlot) + LIQUIDITY_OFFSET)] = bytes32(uint256(liquidityState[poolId]));
    }
}

contract TestableMemeverseUniswapHook is MemeverseUniswapHook {
    constructor(IPoolManager _manager, address _owner, address _treasury)
        MemeverseUniswapHook(_manager, _owner, _treasury)
    {}

    function validateHookAddress(BaseHook) internal pure override {}

    function exposedBaseFeeBps() external pure returns (uint256) {
        return FEE_BASE_BPS;
    }

    function exposedSpotX18FromSqrtPrice(uint160 sqrtPriceX96) external pure returns (uint256) {
        return _spotX18FromSqrtPrice(sqrtPriceX96);
    }

    function exposedPriceMovePpmCappedToShort(uint160 preSqrtPriceX96, uint160 postSqrtPriceX96)
        external
        pure
        returns (uint256)
    {
        return _priceMovePpmCappedToShort(preSqrtPriceX96, postSqrtPriceX96);
    }

    function exposedCachedLpTotalSupply(PoolId poolId) external view returns (uint256) {
        return cachedLpTotalSupply[poolId];
    }

    function exposedPopulateDynamicFeeQuote(
        uint256 pifPpm,
        uint256 spotBeforeX18,
        uint256 spotAfterX18,
        uint256 weightedVolume0,
        uint256 ewVWAPX18,
        uint24 volDeviationAccumulator,
        uint24 shortImpactPpm,
        uint40 shortLastTs
    ) external view returns (DynamicFeeQuote memory quote) {
        quote.feeBps = FEE_BASE_BPS;
        quote.pifPpm = pifPpm;
        quote.spotBeforeX18 = spotBeforeX18;
        quote.spotAfterX18 = spotAfterX18;

        EWVWAPParams memory state;
        state.weightedVolume0 = weightedVolume0;
        state.ewVWAPX18 = ewVWAPX18;
        state.volDeviationAccumulator = volDeviationAccumulator;
        state.shortImpactPpm = shortImpactPpm;
        state.shortLastTs = shortLastTs;

        _populateDynamicFeeQuoteFromState(quote, state);
    }
}

contract ReentrantExitRecipient {
    IMemeverseUniswapHook internal immutable hook;
    MockERC20 internal immutable token;
    Currency internal immutable currency0;
    Currency internal immutable currency1;

    bool internal hasReentered;
    bool internal quoteSucceeded;

    constructor(IMemeverseUniswapHook _hook, MockERC20 _token, Currency _currency0, Currency _currency1) {
        hook = _hook;
        token = _token;
        currency0 = _currency0;
        currency1 = _currency1;
        token.approve(address(_hook), type(uint256).max);
    }

    function addLiquidity(uint256 amount0Desired, uint256 amount1Desired) external returns (uint128 liquidity) {
        (liquidity,) = hook.addLiquidityCore(
            IMemeverseUniswapHook.AddLiquidityCoreParams({
                currency0: currency0,
                currency1: currency1,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                to: address(this)
            })
        );
    }

    function removeLiquidity(uint128 liquidity) external {
        hook.removeLiquidityCore(
            IMemeverseUniswapHook.RemoveLiquidityCoreParams({
                currency0: currency0, currency1: currency1, liquidity: liquidity, recipient: address(this)
            })
        );
    }

    function quoteSucceededDuringReceive() external view returns (bool) {
        return quoteSucceeded;
    }

    function callbackTriggered() external view returns (bool) {
        return hasReentered;
    }

    receive() external payable {
        if (hasReentered) return;
        hasReentered = true;

        try hook.quoteSwap(
            PoolKey({
                currency0: currency0,
                currency1: currency1,
                fee: 0x800000,
                tickSpacing: 200,
                hooks: IHooks(address(hook))
            }),
            SwapParams({zeroForOne: true, amountSpecified: -1 ether, sqrtPriceLimitX96: 0})
        ) returns (
            IMemeverseUniswapHook.SwapQuote memory
        ) {
            quoteSucceeded = true;
        } catch {
            quoteSucceeded = false;
        }
    }
}

/// @dev Test boundary:
/// - These cases lock hook-side handling under the local hook-liquidity manager mock.
/// - They do not establish real market execution, partial-fill economics, rollback guarantees,
///   or fee-side correctness beyond this deterministic harness.
contract MemeverseUniswapHookLiquidityTest is Test {
    uint160 internal constant SQRT_PRICE_1_1 = 79228162514264337593543950336;
    uint160 internal constant PRICE_MOVE_59_999_UP_POST = 81570347323081481549928488305;
    uint160 internal constant PRICE_MOVE_60_000_UP_POST = 81570385799687631547685037519;
    uint160 internal constant PRICE_MOVE_59_999_DOWN_POST = 76814594370895530393110659596;
    uint160 internal constant PRICE_MOVE_60_000_DOWN_POST = 76814553512101337462432816780;
    uint160 internal constant PRICE_MOVE_149_999_UP_POST = 84962701926156676880859777928;
    uint160 internal constant PRICE_MOVE_150_000_UP_POST = 84962738866485953687210797630;
    uint160 internal constant PRICE_MOVE_149_999_DOWN_POST = 73044799624479866430778194544;
    uint160 internal constant PRICE_MOVE_150_000_DOWN_POST = 73044756656988588048856075193;
    uint160 internal constant PRICE_MOVE_AMBIGUOUS_POST = 79267766696949822951113378805;
    uint160 internal constant SPOT_VECTOR_128_PLUS_1 = uint160((uint256(1) << 128) + 1);
    uint160 internal constant SPOT_VECTOR_128_64_12345 = uint160((uint256(1) << 128) + (uint256(1) << 64) + 12345);
    uint160 internal constant SPOT_VECTOR_128_127_PLUS_1 = uint160((uint256(1) << 128) + (uint256(1) << 127) + 1);
    uint160 internal constant SPOT_VECTOR_129_MINUS_1 = uint160((uint256(1) << 129) - 1);
    uint160 internal constant SPOT_VECTOR_140_PLUS_987654321 = uint160((uint256(1) << 140) + 987654321);
    uint256 internal constant Q128 = uint256(1) << 128;
    uint256 internal constant E18 = 1e18;
    uint256 internal constant PPM_BASE = 1_000_000;
    uint256 internal constant SHORT_CAP_PPM = 150_000;
    uint256 internal constant SHORT_FLOOR_PPM = 20_000;
    uint256 internal constant SHORT_COEFF_BPS = 2_000;
    uint256 internal constant PIF_CAP_PPM = 60_000;
    uint256 internal constant FEE_BASE_BPS = 100;
    uint256 internal constant FEE_DFF_MAX_PPM = 800_000;
    uint256 internal constant BPS_BASE = 10_000;
    bytes4 internal constant TOTAL_SUPPLY_SELECTOR = bytes4(keccak256("totalSupply()"));

    MockPoolManagerForHookLiquidity internal mockManager;
    TestableMemeverseUniswapHook internal hook;
    MemeverseSwapRouter internal router;
    MockERC20 internal token0;
    MockERC20 internal token1;
    PoolKey internal key;
    PoolId internal poolId;

    /// @notice Executes set up.
    /// @dev Deploys the hook, router, tokens, and approvals shared by the liquidity tests.
    function setUp() public {
        mockManager = new MockPoolManagerForHookLiquidity();
        token0 = new MockERC20("Token0", "TK0", 18);
        token1 = new MockERC20("Token1", "TK1", 18);
        token0.mint(address(this), 1_000_000 ether);
        token1.mint(address(this), 1_000_000 ether);

        hook = new TestableMemeverseUniswapHook(IPoolManager(address(mockManager)), address(this), address(this));
        router = new MemeverseSwapRouter(
            IPoolManager(address(mockManager)), IMemeverseUniswapHook(address(hook)), IPermit2(address(0xBEEF))
        );

        token0.approve(address(hook), type(uint256).max);
        token1.approve(address(hook), type(uint256).max);
        token0.approve(address(router), type(uint256).max);
        token1.approve(address(router), type(uint256).max);

        key = _dynamicPoolKey(Currency.wrap(address(token0)), Currency.wrap(address(token1)));
        poolId = key.toId();

        mockManager.initialize(key, SQRT_PRICE_1_1);
    }

    /// @notice Calls the hook-local pair-based public-swap protection setter.
    /// @dev Mirrors the launcher-side unlock-protection write path without depending on router helpers.
    function _setPublicSwapResumeTime(address tokenA, address tokenB, uint40 resumeTime)
        internal
        returns (bool ok, bytes memory data)
    {
        return address(hook)
            .call(
                abi.encodeWithSignature("setPublicSwapResumeTime(address,address,uint40)", tokenA, tokenB, resumeTime)
            );
    }

    function _readPublicSwapResumeTime(PoolId targetPoolId) internal view returns (bool ok, uint40 resumeTime) {
        (bool success, bytes memory data) =
            address(hook).staticcall(abi.encodeWithSignature("publicSwapResumeTime(bytes32)", targetPoolId));
        if (!success || data.length != 32) return (false, 0);
        return (true, abi.decode(data, (uint40)));
    }

    /// @notice Verifies hook-local protection state is keyed only by `PoolId`.
    /// @dev The new unlock gate must not need token-pair guessing or launcher verdict helpers.
    function testPublicSwapResumeTime_StoresPerPoolWithoutAffectingOtherPools() external {
        hook.setLauncher(address(this));

        PoolKey memory secondKey =
            _dynamicPoolKey(Currency.wrap(address(new MockERC20("Token2", "TK2", 18))), Currency.wrap(address(token1)));
        PoolId secondPoolId = secondKey.toId();
        mockManager.initialize(secondKey, SQRT_PRICE_1_1);

        (bool initialOk, uint40 initialResumeTime) = _readPublicSwapResumeTime(poolId);
        assertTrue(initialOk, "getter missing");
        assertEq(initialResumeTime, 0, "default resume time");

        (bool setOk, bytes memory setData) =
            _setPublicSwapResumeTime(address(token0), address(token1), uint40(block.timestamp + 1 hours));
        assertTrue(setOk, string(setData));

        (bool firstOk, uint40 firstResumeTime) = _readPublicSwapResumeTime(poolId);
        (bool secondOk, uint40 secondResumeTime) = _readPublicSwapResumeTime(secondPoolId);
        assertTrue(firstOk, "first getter missing");
        assertTrue(secondOk, "second getter missing");
        assertEq(firstResumeTime, uint40(block.timestamp + 1 hours), "first pool resume time");
        assertEq(secondResumeTime, 0, "second pool unchanged");
    }

    /// @notice Verifies hook-local protection can be cleared by writing zero.
    /// @dev `0` is the canonical "no active post-unlock public-swap protection" value.
    function testPublicSwapResumeTime_CanBeClearedBackToZero() external {
        hook.setLauncher(address(this));

        (bool setOk, bytes memory setData) =
            _setPublicSwapResumeTime(address(token0), address(token1), uint40(block.timestamp + 2 hours));
        assertTrue(setOk, string(setData));

        (bool clearOk, bytes memory clearData) = _setPublicSwapResumeTime(address(token0), address(token1), 0);
        assertTrue(clearOk, string(clearData));

        (bool readOk, uint40 resumeTime) = _readPublicSwapResumeTime(poolId);
        assertTrue(readOk, "getter missing");
        assertEq(resumeTime, 0, "resume time cleared");
    }

    /// @notice Executes test add liquidity uses unlock flow.
    /// @dev Confirms the hook uses the unlock flow before minting liquidity.
    function testAddLiquidity_UsesUnlockFlow() external {
        uint128 liquidity = _addLiquidity();
        (address liquidityToken,,) = hook.poolInfo(poolId);

        assertGt(liquidity, 0, "liquidity");
        assertGt(UniswapLP(liquidityToken).balanceOf(address(this)), 0, "lp balance");
        assertGt(mockManager.getLiquidity(poolId), 0, "pool liquidity");
    }

    /// @notice Executes test remove liquidity uses original sender for take.
    /// @dev Ensures liquidity outputs still go back to the txn sender when no custom recipient is provided.
    function testRemoveLiquidity_UsesOriginalSenderForTake() external {
        uint128 liquidity = _addLiquidity();
        (address liquidityToken,,) = hook.poolInfo(poolId);

        uint256 balance0Before = token0.balanceOf(address(this));
        uint256 balance1Before = token1.balanceOf(address(this));

        BalanceDelta delta = hook.removeLiquidityCore(
            IMemeverseUniswapHook.RemoveLiquidityCoreParams({
                currency0: key.currency0, currency1: key.currency1, liquidity: liquidity, recipient: address(this)
            })
        );

        uint256 amount0Out = uint256(uint128(delta.amount0()));
        uint256 amount1Out = uint256(uint128(delta.amount1()));

        assertGt(amount0Out, 0, "amount0 out");
        assertGt(amount1Out, 0, "amount1 out");
        assertEq(mockManager.lastTakeRecipientAddress(), address(this), "take recipient");
        assertEq(UniswapLP(liquidityToken).balanceOf(address(this)), 0, "lp burned");
        assertEq(token0.balanceOf(address(this)), balance0Before + amount0Out, "token0 returned");
        assertEq(token1.balanceOf(address(this)), balance1Before + amount1Out, "token1 returned");
    }

    /// @notice Verifies native pairs are rejected during hook-managed pool initialization.
    function testInitializeReverts_WhenPairUsesNativeCurrency() external {
        PoolKey memory nativeKey = _dynamicPoolKey(CurrencyLibrary.ADDRESS_ZERO, Currency.wrap(address(token1)));
        vm.expectRevert(IMemeverseUniswapHook.NativeCurrencyUnsupported.selector);
        mockManager.initialize(nativeKey, SQRT_PRICE_1_1);
    }

    /// @notice Verifies addLiquidityCore rejects native pairs.
    function testAddLiquidityCoreReverts_WhenPairUsesNativeCurrency() external {
        PoolKey memory nativeKey = _dynamicPoolKey(CurrencyLibrary.ADDRESS_ZERO, Currency.wrap(address(token1)));
        vm.expectRevert(IMemeverseUniswapHook.NativeCurrencyUnsupported.selector);
        hook.addLiquidityCore(
            IMemeverseUniswapHook.AddLiquidityCoreParams({
                currency0: nativeKey.currency0,
                currency1: nativeKey.currency1,
                amount0Desired: 300 ether,
                amount1Desired: 100 ether,
                to: address(this)
            })
        );
    }

    /// @notice Verifies pool initialization rejects non-default tick spacing.
    /// @dev Covers the hook's beforeInitialize validation for unsupported pool config.
    function testInitializeReverts_WhenTickSpacingIsNotDefault() external {
        PoolKey memory invalidKey = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            fee: 0x800000,
            tickSpacing: 1,
            hooks: IHooks(address(hook))
        });

        vm.expectRevert(IMemeverseUniswapHook.TickSpacingNotDefault.selector);
        mockManager.initialize(invalidKey, SQRT_PRICE_1_1);
    }

    /// @notice Verifies pool initialization rejects non-dynamic fees.
    /// @dev Covers the hook's beforeInitialize validation for static-fee pools.
    function testInitializeReverts_WhenFeeIsNotDynamic() external {
        PoolKey memory invalidKey = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            fee: 3000,
            tickSpacing: 200,
            hooks: IHooks(address(hook))
        });

        vm.expectRevert(IMemeverseUniswapHook.FeeMustBeDynamic.selector);
        mockManager.initialize(invalidKey, SQRT_PRICE_1_1);
    }

    /// @notice Verifies removeLiquidityCore rejects native pairs.
    function testRemoveLiquidityCoreReverts_WhenPairUsesNativeCurrency() external {
        PoolKey memory nativeKey = _dynamicPoolKey(CurrencyLibrary.ADDRESS_ZERO, Currency.wrap(address(token1)));
        vm.expectRevert(IMemeverseUniswapHook.NativeCurrencyUnsupported.selector);
        hook.removeLiquidityCore(
            IMemeverseUniswapHook.RemoveLiquidityCoreParams({
                currency0: nativeKey.currency0,
                currency1: nativeKey.currency1,
                liquidity: 1 ether,
                recipient: address(this)
            })
        );
    }

    /// @notice Verifies addLiquidity rejects pools that have not been initialized.
    /// @dev Covers the `PoolNotInitialized` branch before any quote or settlement logic.
    function testAddLiquidityCoreReverts_WhenPoolNotInitialized() external {
        PoolKey memory uninitializedKey =
            _dynamicPoolKey(Currency.wrap(address(new MockERC20("X", "X", 18))), Currency.wrap(address(token1)));

        vm.expectRevert(IMemeverseUniswapHook.PoolNotInitialized.selector);
        hook.addLiquidityCore(
            IMemeverseUniswapHook.AddLiquidityCoreParams({
                currency0: uninitializedKey.currency0,
                currency1: uninitializedKey.currency1,
                amount0Desired: 1 ether,
                amount1Desired: 1 ether,
                to: address(this)
            })
        );
    }

    /// @notice Verifies removeLiquidity rejects pools with no initialized liquidity.
    /// @dev Covers the `PoolNotInitialized` branch on liquidity exit.
    function testRemoveLiquidityCoreReverts_WhenPoolNotInitialized() external {
        PoolKey memory uninitializedKey =
            _dynamicPoolKey(Currency.wrap(address(new MockERC20("X", "X", 18))), Currency.wrap(address(token1)));

        vm.expectRevert(IMemeverseUniswapHook.PoolNotInitialized.selector);
        hook.removeLiquidityCore(
            IMemeverseUniswapHook.RemoveLiquidityCoreParams({
                currency0: uninitializedKey.currency0,
                currency1: uninitializedKey.currency1,
                liquidity: 1 ether,
                recipient: address(this)
            })
        );
    }

    /// @notice Verifies direct removeLiquidityCore forwards assets when recipient differs from sender.
    /// @dev Covers the direct output-forwarding path inside `removeLiquidityCore`.
    function testRemoveLiquidityCore_ForwardsOutputsToDifferentRecipient() external {
        uint128 liquidity = _addLiquidity();
        (address liquidityToken,,) = hook.poolInfo(poolId);
        address recipient = address(0xCAFE);

        uint256 recipient0Before = token0.balanceOf(recipient);
        uint256 recipient1Before = token1.balanceOf(recipient);

        BalanceDelta delta = hook.removeLiquidityCore(
            IMemeverseUniswapHook.RemoveLiquidityCoreParams({
                currency0: key.currency0, currency1: key.currency1, liquidity: liquidity, recipient: recipient
            })
        );

        assertEq(UniswapLP(liquidityToken).balanceOf(address(this)), 0, "lp burned");
        assertGt(token0.balanceOf(recipient), recipient0Before, "recipient token0");
        assertGt(token1.balanceOf(recipient), recipient1Before, "recipient token1");
        assertGt(delta.amount0(), 0, "delta0");
        assertGt(delta.amount1(), 0, "delta1");
    }

    /// @notice Executes test router add liquidity uses hook core.
    /// @dev Confirms the router add-liquidity helper goes through the hook's liquidity plumbing.
    function testRouterAddLiquidity_UsesHookCore() external {
        uint128 liquidity = router.addLiquidity(
            key.currency0, key.currency1, 100 ether, 100 ether, 90 ether, 90 ether, address(this), block.timestamp
        );

        (address liquidityToken,,) = hook.poolInfo(poolId);
        assertGt(liquidity, 0, "liquidity");
        assertGt(UniswapLP(liquidityToken).balanceOf(address(this)), 0, "lp balance");
    }

    /// @notice Verifies router-mediated addLiquidity rejects native pairs.
    function testRouterAddLiquidityReverts_WhenPairUsesNativeCurrency() external {
        PoolKey memory nativeKey = _dynamicPoolKey(CurrencyLibrary.ADDRESS_ZERO, Currency.wrap(address(token1)));
        vm.expectRevert(IMemeverseUniswapHook.NativeCurrencyUnsupported.selector);
        router.addLiquidity(
            nativeKey.currency0,
            nativeKey.currency1,
            300 ether,
            100 ether,
            90 ether,
            90 ether,
            address(this),
            block.timestamp
        );
    }

    /// @notice Executes test router remove liquidity uses hook core.
    /// @dev Ensures the router remove path reuses the hook core logic for exits.
    function testRouterRemoveLiquidity_UsesHookCore() external {
        uint128 liquidity = router.addLiquidity(
            key.currency0, key.currency1, 100 ether, 100 ether, 90 ether, 90 ether, address(this), block.timestamp
        );
        (address liquidityToken,,) = hook.poolInfo(poolId);
        UniswapLP(liquidityToken).approve(address(router), liquidity);

        uint256 balance0Before = token0.balanceOf(address(this));
        uint256 balance1Before = token1.balanceOf(address(this));

        BalanceDelta delta =
            router.removeLiquidity(key.currency0, key.currency1, liquidity, 1, 1, address(this), block.timestamp);

        assertGt(delta.amount0(), 0, "delta0");
        assertGt(delta.amount1(), 0, "delta1");
        assertGt(token0.balanceOf(address(this)), balance0Before, "token0 returned");
        assertGt(token1.balanceOf(address(this)), balance1Before, "token1 returned");
    }

    /// @notice Verifies claiming fees on an uninitialized pool reverts.
    /// @dev Covers the `PoolNotInitialized` branch in the low-level claim flow.
    function testClaimFeesCoreReverts_WhenPoolNotInitialized() external {
        PoolKey memory uninitializedKey =
            _dynamicPoolKey(Currency.wrap(address(new MockERC20("X", "X", 18))), Currency.wrap(address(token1)));

        vm.expectRevert(IMemeverseUniswapHook.PoolNotInitialized.selector);
        hook.claimFeesCore(IMemeverseUniswapHook.ClaimFeesCoreParams({key: uninitializedKey, recipient: address(this)}));
    }

    /// @notice Verifies `updateUserSnapshot` handles zero LP balances by only moving offsets.
    /// @dev Covers the zero-balance early branch without accruing pending fees.
    function testUpdateUserSnapshot_ZeroBalanceOnlyUpdatesOffsets() external {
        hook.setProtocolFeeCurrency(key.currency0);
        router.addLiquidity(
            key.currency0, key.currency1, 100 ether, 100 ether, 90 ether, 90 ether, address(this), block.timestamp
        );

        (address lpToken,,) = hook.poolInfo(poolId);
        uint256 lpBalance = UniswapLP(lpToken).balanceOf(address(this));
        assertTrue(UniswapLP(lpToken).transfer(address(0xCAFE), lpBalance));

        hook.updateUserSnapshot(poolId, address(this));

        (uint256 fee0Offset, uint256 fee1Offset, uint256 pendingFee0, uint256 pendingFee1) =
            hook.userFeeState(poolId, address(this));
        (, uint256 fee0PerShare, uint256 fee1PerShare) = hook.poolInfo(poolId);
        assertEq(fee0Offset, fee0PerShare, "fee0 offset");
        assertEq(fee1Offset, fee1PerShare, "fee1 offset");
        assertEq(pendingFee0, 0, "pending fee0");
        assertEq(pendingFee1, 0, "pending fee1");
    }

    /// @notice Verifies direct LP transfers cannot target the zero address.
    /// @dev Users must exit through hook-managed burn paths so total supply stays synchronized with fee accounting.
    function testUniswapLPTransfer_RevertsToZeroAddress() external {
        _addLiquidity();

        (address lpToken,,) = hook.poolInfo(poolId);
        vm.expectRevert();
        /// forge-lint: disable-next-line(erc20-unchecked-transfer)
        UniswapLP(lpToken).transfer(address(0), 1);
    }

    /// @notice Verifies delegated LP transfers cannot target the zero address.
    /// @dev Prevents `transferFrom` from acting like an unsynchronized user burn.
    function testUniswapLPTransferFrom_RevertsToZeroAddress() external {
        _addLiquidity();

        (address lpToken,,) = hook.poolInfo(poolId);
        UniswapLP(lpToken).approve(address(0xBEEF), 1);

        vm.prank(address(0xBEEF));
        vm.expectRevert();
        /// forge-lint: disable-next-line(erc20-unchecked-transfer)
        UniswapLP(lpToken).transferFrom(address(this), address(0), 1);
    }

    /// @notice Verifies LP fee growth uses the live-share supply and Q128 precision.
    /// @dev The protocol-locked `MINIMUM_LIQUIDITY` must not dilute fee growth for the first real LP.
    function testLpFeeGrowth_UsesEffectiveSupplyAndQ128Accumulator() external {
        uint128 liquidity = _addLiquidity();
        hook.setProtocolFeeCurrency(key.currency0);

        IMemeverseUniswapHook.SwapQuote memory quote =
            hook.quoteSwap(key, SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}));

        vm.prank(address(mockManager));
        hook.beforeSwap(
            address(this),
            key,
            SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}),
            bytes("")
        );

        (, uint256 fee0PerShare, uint256 fee1PerShare) = hook.poolInfo(poolId);
        uint256 expectedFeeGrowthX128 = FullMath.mulDiv(quote.estimatedLpFeeAmount, Q128, liquidity);

        assertEq(fee0PerShare, expectedFeeGrowthX128, "fee0 growth");
        assertEq(fee1PerShare, 0, "fee1 growth");
    }

    /// @notice Verifies LP-fee hot paths do not call the LP token's external `totalSupply()`.
    /// @dev Locks both public swap fee collection and launch-settlement LP fee credit to the hook-side cached supply path.
    function testLpFeeHotPaths_UseCachedSupplyInsteadOfExternalTotalSupply() external {
        _addLiquidity();
        hook.setProtocolFeeCurrency(key.currency0);

        (address lpToken,,) = hook.poolInfo(poolId);
        vm.mockCallRevert(lpToken, abi.encodeWithSelector(TOTAL_SUPPLY_SELECTOR), bytes("unexpected totalSupply"));

        vm.prank(address(mockManager));
        hook.beforeSwap(
            address(this),
            key,
            SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}),
            bytes("")
        );

        vm.clearMockedCalls();
        vm.mockCallRevert(lpToken, abi.encodeWithSelector(TOTAL_SUPPLY_SELECTOR), bytes("unexpected totalSupply"));

        hook.setLauncher(address(this));
        token1.mint(address(mockManager), 1_000_000 ether);

        hook.executeLaunchSettlement(
            IMemeverseUniswapHook.LaunchSettlementParams({
                key: key,
                params: SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}),
                recipient: address(this)
            })
        );
    }

    /// @notice Verifies swaps and launch settlement fail closed when only protocol-locked minimum liquidity remains.
    /// @dev Once effective LP supply is zero, charging LP fees would strand funds because no claimable shares remain.
    function testFeeChargingReverts_WhenOnlyMinimumLiquidityRemains() external {
        uint128 liquidity = _addLiquidity();
        hook.setProtocolFeeCurrency(key.currency0);

        hook.removeLiquidityCore(
            IMemeverseUniswapHook.RemoveLiquidityCoreParams({
                currency0: key.currency0, currency1: key.currency1, liquidity: liquidity, recipient: address(this)
            })
        );

        vm.expectRevert(IMemeverseUniswapHook.NoActiveLiquidityShares.selector);
        hook.quoteSwap(key, SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}));

        vm.prank(address(mockManager));
        vm.expectRevert(IMemeverseUniswapHook.NoActiveLiquidityShares.selector);
        hook.beforeSwap(
            address(this),
            key,
            SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}),
            bytes("")
        );

        hook.setLauncher(address(this));
        token1.mint(address(mockManager), 1_000_000 ether);

        vm.expectRevert(IMemeverseUniswapHook.NoActiveLiquidityShares.selector);
        hook.executeLaunchSettlement(
            IMemeverseUniswapHook.LaunchSettlementParams({
                key: key,
                params: SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}),
                recipient: address(this)
            })
        );
    }

    /// @notice Verifies the hook's cached LP total supply stays in sync with the actual LP token contract.
    /// @dev A mismatch would corrupt fee-per-share accounting.
    function testCachedLpTotalSupply_MatchesActualTotalSupply() external {
        // After addLiquidity: cached should equal LP token totalSupply
        uint128 liquidity = _addLiquidity();
        (address lpToken,,) = hook.poolInfo(poolId);

        uint256 actualSupply = UniswapLP(lpToken).totalSupply();
        uint256 cachedSupply = hook.exposedCachedLpTotalSupply(poolId);
        assertEq(cachedSupply, actualSupply, "cached supply after add");

        // After partial removal: still in sync
        uint128 halfLiquidity = liquidity / 2;
        hook.removeLiquidityCore(
            IMemeverseUniswapHook.RemoveLiquidityCoreParams({
                currency0: key.currency0, currency1: key.currency1, liquidity: halfLiquidity, recipient: address(this)
            })
        );

        actualSupply = UniswapLP(lpToken).totalSupply();
        cachedSupply = hook.exposedCachedLpTotalSupply(poolId);
        assertEq(cachedSupply, actualSupply, "cached supply after partial remove");

        // After full removal: still in sync (only MINIMUM_LIQUIDITY remains)
        hook.removeLiquidityCore(
            IMemeverseUniswapHook.RemoveLiquidityCoreParams({
                currency0: key.currency0,
                currency1: key.currency1,
                liquidity: liquidity - halfLiquidity,
                recipient: address(this)
            })
        );

        actualSupply = UniswapLP(lpToken).totalSupply();
        cachedSupply = hook.exposedCachedLpTotalSupply(poolId);
        assertEq(cachedSupply, actualSupply, "cached supply after full remove");
        assertEq(actualSupply, 1000, "only MINIMUM_LIQUIDITY remains"); // 1000 = MINIMUM_LIQUIDITY constant
    }

    /// @notice Verifies liquidity cannot be minted directly to the zero address.
    /// @dev Only hook-managed burn paths may move LP supply out of circulation.
    function testAddLiquidityCoreReverts_WhenRecipientIsZeroAddress() external {
        vm.expectRevert(IMemeverseUniswapHook.ZeroAddress.selector);
        hook.addLiquidityCore(
            IMemeverseUniswapHook.AddLiquidityCoreParams({
                currency0: key.currency0,
                currency1: key.currency1,
                amount0Desired: 100 ether,
                amount1Desired: 100 ether,
                to: address(0)
            })
        );
    }

    /// @notice Verifies the protocol-locked zero address LP balance never becomes fee-earning state.
    /// @dev The `MINIMUM_LIQUIDITY` lock should not surface as claimable fees or pending fee accrual.
    function testZeroAddressLockedLiquidity_DoesNotAccrueClaimableOrPendingFees() external {
        _addLiquidity();
        hook.setProtocolFeeCurrency(key.currency0);

        vm.prank(address(mockManager));
        hook.beforeSwap(
            address(this),
            key,
            SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}),
            bytes("")
        );

        (uint256 fee0Amount, uint256 fee1Amount) = hook.claimableFees(key, address(0));
        assertEq(fee0Amount, 0, "zero address claimable fee0");
        assertEq(fee1Amount, 0, "zero address claimable fee1");

        hook.updateUserSnapshot(poolId, address(0));

        (uint256 fee0Offset, uint256 fee1Offset, uint256 pendingFee0, uint256 pendingFee1) =
            hook.userFeeState(poolId, address(0));
        (, uint256 fee0PerShare, uint256 fee1PerShare) = hook.poolInfo(poolId);

        assertEq(fee0Offset, fee0PerShare, "zero address fee0 offset");
        assertEq(fee1Offset, fee1PerShare, "zero address fee1 offset");
        assertEq(pendingFee0, 0, "zero address pending fee0");
        assertEq(pendingFee1, 0, "zero address pending fee1");
    }

    /// @notice Verifies callers can redirect claimed fees to a different recipient without signatures.
    /// @dev Covers the owner-direct claim surface after relay support was removed.
    function testClaimFeesCore_DirectClaimCanRedirectRecipient() external {
        router.addLiquidity(
            key.currency0, key.currency1, 100 ether, 100 ether, 90 ether, 90 ether, address(this), block.timestamp
        );
        hook.setProtocolFeeCurrency(key.currency0);

        vm.prank(address(mockManager));
        hook.beforeSwap(
            address(this),
            key,
            SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}),
            bytes("")
        );

        address recipient = address(0xCAFE);
        uint256 balanceBefore = token0.balanceOf(recipient);
        (uint256 fee0Amount, uint256 fee1Amount) =
            hook.claimFeesCore(IMemeverseUniswapHook.ClaimFeesCoreParams({key: key, recipient: recipient}));

        assertGt(fee0Amount, 0, "fee0 claimed");
        assertEq(fee1Amount, 0, "fee1 claimed");
        assertEq(token0.balanceOf(recipient), balanceBefore + fee0Amount, "recipient received fee");
    }

    function testClaimFeesCoreReverts_WhenPairUsesNativeCurrency() external {
        PoolKey memory nativeKey = _dynamicPoolKey(CurrencyLibrary.ADDRESS_ZERO, Currency.wrap(address(token1)));
        vm.expectRevert(IMemeverseUniswapHook.NativeCurrencyUnsupported.selector);
        hook.claimFeesCore(IMemeverseUniswapHook.ClaimFeesCoreParams({key: nativeKey, recipient: address(this)}));
    }

    /// @notice Verifies owner config setters reject invalid inputs and update state.
    /// @dev Covers treasury and launch-fee configuration branches on the hook.
    function testOwnerSetters_UpdateStateAndRejectInvalidInputs() external {
        vm.expectRevert(IMemeverseUniswapHook.ZeroAddress.selector);
        hook.setTreasury(address(0));

        hook.setTreasury(address(0xBEEF));
        assertEq(hook.treasury(), address(0xBEEF), "treasury");

        vm.expectRevert(IMemeverseUniswapHook.NativeCurrencyUnsupported.selector);
        hook.setProtocolFeeCurrency(CurrencyLibrary.ADDRESS_ZERO);

        vm.expectRevert(IMemeverseUniswapHook.NativeCurrencyUnsupported.selector);
        hook.setProtocolFeeCurrencySupport(CurrencyLibrary.ADDRESS_ZERO, true);
    }

    /// @notice Verifies swap quoting reverts when neither side is enabled for protocol fees.
    /// @dev Covers the `CurrencyNotSupported` branch in fee-context resolution.
    function testQuoteSwapReverts_WhenProtocolFeeCurrencyUnsupported() external {
        vm.expectRevert(IMemeverseUniswapHook.CurrencyNotSupported.selector);
        hook.quoteSwap(key, SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}));
    }

    function testQuoteSwapReverts_WhenPairUsesNativeCurrency() external {
        PoolKey memory nativeKey = _dynamicPoolKey(CurrencyLibrary.ADDRESS_ZERO, Currency.wrap(address(token1)));
        vm.expectRevert(IMemeverseUniswapHook.NativeCurrencyUnsupported.selector);
        hook.quoteSwap(nativeKey, SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}));
    }

    function testDirectManagerSwapReverts_WhenPairUsesNativeCurrency() external {
        PoolKey memory nativeKey = _dynamicPoolKey(CurrencyLibrary.ADDRESS_ZERO, Currency.wrap(address(token1)));

        vm.expectRevert(IMemeverseUniswapHook.NativeCurrencyUnsupported.selector);
        mockManager.swapAsUnlocked(
            nativeKey, SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}), bytes("")
        );
    }

    /// @notice Covers the local direct/core fail-closed branch for exact-input underfills without router checks.
    /// @dev Uses the hook-liquidity manager mock to witness fee-accounting rollback on revert.
    function testDirectManagerSwapReverts_WhenExactInputPartialFills() external {
        _addLiquidity();
        hook.setProtocolFeeCurrency(key.currency1);
        // Seed non-zero EWVWAP state so rollback assertions are non-trivial.
        mockManager.swapAsUnlocked(
            key, SwapParams({zeroForOne: true, amountSpecified: -10 ether, sqrtPriceLimitX96: 0}), bytes("")
        );
        vm.warp(block.timestamp + 900);
        mockManager.setNextExactInputPoolInputAmount(poolId, 99 ether);

        uint256 payer0Before = token0.balanceOf(address(this));
        uint256 payer1Before = token1.balanceOf(address(this));
        uint256 treasury0Before = token0.balanceOf(hook.treasury());
        uint256 treasury1Before = token1.balanceOf(hook.treasury());
        (, uint256 fee0PerShareBefore, uint256 fee1PerShareBefore) = hook.poolInfo(poolId);
        (
            uint256 wv0Before,,
            uint256 ewVWAPBefore,
            uint160 volAnchorBefore,,
            uint24 volDevBefore,,
            uint24 shortImpactBefore,
        ) = hook.poolEWVWAPParams(poolId);

        vm.expectRevert(IMemeverseUniswapHook.ExactInputPartialFill.selector);
        mockManager.swapAsUnlocked(
            key, SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}), bytes("")
        );

        (, uint256 fee0PerShareAfter, uint256 fee1PerShareAfter) = hook.poolInfo(poolId);
        assertEq(token0.balanceOf(address(this)), payer0Before, "payer token0 unchanged");
        assertEq(token1.balanceOf(address(this)), payer1Before, "payer token1 unchanged");
        assertEq(token0.balanceOf(hook.treasury()), treasury0Before, "treasury token0 unchanged");
        assertEq(token1.balanceOf(hook.treasury()), treasury1Before, "treasury token1 unchanged");
        assertEq(fee0PerShareAfter, fee0PerShareBefore, "fee0 per share unchanged");
        assertEq(fee1PerShareAfter, fee1PerShareBefore, "fee1 per share unchanged");

        (
            uint256 wv0After,,
            uint256 ewVWAPAfter,
            uint160 volAnchorAfter,,
            uint24 volDevAfter,,
            uint24 shortImpactAfter,
        ) = hook.poolEWVWAPParams(poolId);
        assertEq(wv0After, wv0Before, "ewvwap weightedVolume0 unchanged");
        assertEq(ewVWAPAfter, ewVWAPBefore, "ewvwap unchanged");
        assertEq(volAnchorAfter, volAnchorBefore, "vol anchor unchanged");
        assertEq(volDevAfter, volDevBefore, "volatility unchanged");
        assertEq(shortImpactAfter, shortImpactBefore, "short impact unchanged");
    }

    /// @notice Covers the local direct/core branch where output-fee exact-input swaps consume the net pool input from `beforeSwap`.
    /// @dev Locks hook-side handling under the local hook-liquidity manager mock instead of proving full v4 execution semantics.
    function testDirectManagerSwapPasses_WhenOneForZeroExactInputUsesNetPoolInputOnOutputFeePool() external {
        _addLiquidity();
        hook.setProtocolFeeCurrency(key.currency0);
        vm.warp(block.timestamp + 900);

        IMemeverseUniswapHook.SwapQuote memory quote =
            hook.quoteSwap(key, SwapParams({zeroForOne: false, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}));
        uint256 expectedPoolInput = quote.estimatedUserInputAmount - quote.estimatedLpFeeAmount;
        uint256 treasury0Before = token0.balanceOf(hook.treasury());

        mockManager.setNextExactInputPoolInputAmount(poolId, expectedPoolInput);
        BalanceDelta delta = mockManager.swapAsUnlocked(
            key, SwapParams({zeroForOne: false, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}), bytes("")
        );

        assertEq(uint256(uint128(-delta.amount1())), expectedPoolInput, "pool input net of lp fee");
        assertGt(uint256(uint128(delta.amount0())), 0, "output received");
        assertGt(token0.balanceOf(hook.treasury()), treasury0Before, "output-side protocol fee collected");
    }

    /// @notice Covers the local direct/core fail-closed branch for exact-input underfills on input-side fee pools.
    /// @dev Uses the hook-liquidity manager mock to witness atomic rollback instead of proving production partial-fill semantics.
    function testDirectManagerSwapReverts_WhenExactInputPartialFillsOnInputFeePool() external {
        _addLiquidity();
        hook.setProtocolFeeCurrency(key.currency0); // input-side fee for zeroForOne=true
        // Seed non-zero EWVWAP state so rollback assertions are non-trivial.
        mockManager.swapAsUnlocked(
            key, SwapParams({zeroForOne: true, amountSpecified: -10 ether, sqrtPriceLimitX96: 0}), bytes("")
        );
        vm.warp(block.timestamp + 900);
        mockManager.setNextExactInputPoolInputAmount(poolId, 99 ether);

        uint256 payer0Before = token0.balanceOf(address(this));
        uint256 payer1Before = token1.balanceOf(address(this));
        uint256 treasury0Before = token0.balanceOf(hook.treasury());
        (, uint256 fee0PerShareBefore, uint256 fee1PerShareBefore) = hook.poolInfo(poolId);
        (
            uint256 wv0Before,,
            uint256 ewVWAPBefore,
            uint160 volAnchorBefore,,
            uint24 volDevBefore,,
            uint24 shortImpactBefore,
        ) = hook.poolEWVWAPParams(poolId);

        vm.expectRevert(IMemeverseUniswapHook.ExactInputPartialFill.selector);
        mockManager.swapAsUnlocked(
            key, SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}), bytes("")
        );

        assertEq(token0.balanceOf(address(this)), payer0Before, "payer token0 unchanged");
        assertEq(token1.balanceOf(address(this)), payer1Before, "payer token1 unchanged");
        assertEq(token0.balanceOf(hook.treasury()), treasury0Before, "treasury token0 unchanged");
        (, uint256 fee0PerShareAfter, uint256 fee1PerShareAfter) = hook.poolInfo(poolId);
        assertEq(fee0PerShareAfter, fee0PerShareBefore, "fee0 per share unchanged");
        assertEq(fee1PerShareAfter, fee1PerShareBefore, "fee1 per share unchanged");

        (
            uint256 wv0After,,
            uint256 ewVWAPAfter,
            uint160 volAnchorAfter,,
            uint24 volDevAfter,,
            uint24 shortImpactAfter,
        ) = hook.poolEWVWAPParams(poolId);
        assertEq(wv0After, wv0Before, "ewvwap weightedVolume0 unchanged");
        assertEq(ewVWAPAfter, ewVWAPBefore, "ewvwap unchanged");
        assertEq(volAnchorAfter, volAnchorBefore, "vol anchor unchanged");
        assertEq(volDevAfter, volDevBefore, "volatility unchanged");
        assertEq(shortImpactAfter, shortImpactBefore, "short impact unchanged");
    }

    /// @notice Covers the mirrored local direct/core fail-closed branch for one-for-zero exact-input underfills on output-fee pools.
    /// @dev Uses the hook-liquidity manager mock to witness rollback symmetry instead of proving production partial-fill semantics.
    function testDirectManagerSwapReverts_WhenOneForZeroExactInputPartialFillsOnOutputFeePool() external {
        _addLiquidity();
        hook.setProtocolFeeCurrency(key.currency0);
        // Seed non-zero EWVWAP state so rollback assertions are non-trivial.
        mockManager.swapAsUnlocked(
            key, SwapParams({zeroForOne: false, amountSpecified: -10 ether, sqrtPriceLimitX96: 0}), bytes("")
        );
        vm.warp(block.timestamp + 900);
        mockManager.setNextExactInputPoolInputAmount(poolId, 99 ether);

        uint256 payer0Before = token0.balanceOf(address(this));
        uint256 payer1Before = token1.balanceOf(address(this));
        uint256 treasury0Before = token0.balanceOf(hook.treasury());
        uint256 treasury1Before = token1.balanceOf(hook.treasury());
        (, uint256 fee0PerShareBefore, uint256 fee1PerShareBefore) = hook.poolInfo(poolId);
        (
            uint256 wv0Before,,
            uint256 ewVWAPBefore,
            uint160 volAnchorBefore,,
            uint24 volDevBefore,,
            uint24 shortImpactBefore,
        ) = hook.poolEWVWAPParams(poolId);

        vm.expectRevert(IMemeverseUniswapHook.ExactInputPartialFill.selector);
        mockManager.swapAsUnlocked(
            key, SwapParams({zeroForOne: false, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}), bytes("")
        );

        (, uint256 fee0PerShareAfter, uint256 fee1PerShareAfter) = hook.poolInfo(poolId);
        assertEq(token0.balanceOf(address(this)), payer0Before, "payer token0 unchanged");
        assertEq(token1.balanceOf(address(this)), payer1Before, "payer token1 unchanged");
        assertEq(token0.balanceOf(hook.treasury()), treasury0Before, "treasury token0 unchanged");
        assertEq(token1.balanceOf(hook.treasury()), treasury1Before, "treasury token1 unchanged");
        assertEq(fee0PerShareAfter, fee0PerShareBefore, "fee0 per share unchanged");
        assertEq(fee1PerShareAfter, fee1PerShareBefore, "fee1 per share unchanged");

        (
            uint256 wv0After,,
            uint256 ewVWAPAfter,
            uint160 volAnchorAfter,,
            uint24 volDevAfter,,
            uint24 shortImpactAfter,
        ) = hook.poolEWVWAPParams(poolId);
        assertEq(wv0After, wv0Before, "ewvwap weightedVolume0 unchanged");
        assertEq(ewVWAPAfter, ewVWAPBefore, "ewvwap unchanged");
        assertEq(volAnchorAfter, volAnchorBefore, "vol anchor unchanged");
        assertEq(volDevAfter, volDevBefore, "volatility unchanged");
        assertEq(shortImpactAfter, shortImpactBefore, "short impact unchanged");
    }

    /// @notice Covers the local launch-settlement fail-closed branch for exact-input underfills.
    /// @dev Uses the hook-liquidity manager mock to witness rollback for balances, fee growth, and dynamic state.
    function testExecuteLaunchSettlement_RevertsWhenExactInputPartiallyFills() external {
        _addLiquidity();
        hook.setProtocolFeeCurrency(key.currency0);
        hook.setLauncher(address(this));
        token0.approve(address(hook), type(uint256).max);
        // Seed non-zero EWVWAP state so rollback assertions are non-trivial.
        mockManager.swapAsUnlocked(
            key, SwapParams({zeroForOne: true, amountSpecified: -10 ether, sqrtPriceLimitX96: 0}), bytes("")
        );
        mockManager.setNextExactInputPoolInputAmount(poolId, 98 ether);

        uint256 payer0Before = token0.balanceOf(address(this));
        uint256 payer1Before = token1.balanceOf(address(this));
        uint256 treasury0Before = token0.balanceOf(hook.treasury());
        uint256 treasury1Before = token1.balanceOf(hook.treasury());
        uint256 hookToken0Before = token0.balanceOf(address(hook));
        (, uint256 fee0PerShareBefore, uint256 fee1PerShareBefore) = hook.poolInfo(poolId);
        (
            uint256 wv0Before,,
            uint256 ewVWAPBefore,
            uint160 volAnchorBefore,,
            uint24 volDevBefore,,
            uint24 shortImpactBefore,
        ) = hook.poolEWVWAPParams(poolId);

        vm.expectRevert(IMemeverseUniswapHook.ExactInputPartialFill.selector);
        hook.executeLaunchSettlement(
            IMemeverseUniswapHook.LaunchSettlementParams({
                key: key,
                params: SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}),
                recipient: address(this)
            })
        );

        (, uint256 fee0PerShareAfter, uint256 fee1PerShareAfter) = hook.poolInfo(poolId);
        assertEq(token0.balanceOf(address(this)), payer0Before, "payer token0 unchanged");
        assertEq(token1.balanceOf(address(this)), payer1Before, "payer token1 unchanged");
        assertEq(token0.balanceOf(hook.treasury()), treasury0Before, "treasury token0 unchanged");
        assertEq(token1.balanceOf(hook.treasury()), treasury1Before, "treasury token1 unchanged");
        assertEq(token0.balanceOf(address(hook)), hookToken0Before, "hook token0 unchanged");
        assertEq(fee0PerShareAfter, fee0PerShareBefore, "fee0 per share unchanged");
        assertEq(fee1PerShareAfter, fee1PerShareBefore, "fee1 per share unchanged");

        (
            uint256 wv0After,,
            uint256 ewVWAPAfter,
            uint160 volAnchorAfter,,
            uint24 volDevAfter,,
            uint24 shortImpactAfter,
        ) = hook.poolEWVWAPParams(poolId);
        assertEq(wv0After, wv0Before, "ewvwap weightedVolume0 unchanged");
        assertEq(ewVWAPAfter, ewVWAPBefore, "ewvwap unchanged");
        assertEq(volAnchorAfter, volAnchorBefore, "vol anchor unchanged");
        assertEq(volDevAfter, volDevBefore, "volatility unchanged");
        assertEq(shortImpactAfter, shortImpactBefore, "short impact unchanged");
    }

    /// @notice Verifies launch fee floor dominates immediately after pool initialization and decays to the minimum fee.
    /// @dev Covers the new launch fee scheduler on top of the existing dynamic fee engine.
    function testQuoteSwap_UsesLaunchFeeFloorAndDecaysToMinFee() external {
        hook.setProtocolFeeCurrency(key.currency0);

        IMemeverseUniswapHook.SwapQuote memory initialQuote =
            hook.quoteSwap(key, SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}));
        assertEq(initialQuote.feeBps, 5000, "initial launch fee");

        vm.warp(block.timestamp + 900);

        IMemeverseUniswapHook.SwapQuote memory maturedQuote =
            hook.quoteSwap(key, SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}));
        assertEq(maturedQuote.feeBps, 100, "matured fee");
    }

    function testDynamicFeeQuote_RevertingTradeStillPaysVolatilityAndShortImpact() external view {
        MemeverseUniswapHook.DynamicFeeQuote memory quote = hook.exposedPopulateDynamicFeeQuote({
            pifPpm: 50_000,
            spotBeforeX18: 1.3e18,
            spotAfterX18: 1.15e18,
            weightedVolume0: 1,
            ewVWAPX18: 1e18,
            volDeviationAccumulator: 100_000,
            shortImpactPpm: 50_000,
            shortLastTs: uint40(block.timestamp)
        });

        assertFalse(quote.isAdverse, "reverting quote should not be adverse");
        assertEq(quote.adverseImpactPartBps, 0, "reverting quote adverse impact");
        assertGt(quote.volatilityPartBps, 0, "reverting quote volatility surcharge");
        assertGt(quote.shortImpactPartBps, 0, "reverting quote short-impact surcharge");
        assertEq(
            quote.feeBps,
            hook.exposedBaseFeeBps() + quote.volatilityPartBps + quote.shortImpactPartBps,
            "reverting quote fee composition"
        );
    }

    function testDynamicFeeQuote_AdverseTradeStillPaysAllThreeSurcharges() external view {
        MemeverseUniswapHook.DynamicFeeQuote memory quote = hook.exposedPopulateDynamicFeeQuote({
            pifPpm: 50_000,
            spotBeforeX18: 1.3e18,
            spotAfterX18: 1.45e18,
            weightedVolume0: 1,
            ewVWAPX18: 1e18,
            volDeviationAccumulator: 100_000,
            shortImpactPpm: 50_000,
            shortLastTs: uint40(block.timestamp)
        });

        assertTrue(quote.isAdverse, "adverse quote flag");
        assertGt(quote.adverseImpactPartBps, 0, "adverse impact surcharge");
        assertGt(quote.volatilityPartBps, 0, "volatility surcharge");
        assertGt(quote.shortImpactPartBps, 0, "short-impact surcharge");
        assertEq(
            quote.feeBps,
            hook.exposedBaseFeeBps() + quote.adverseImpactPartBps + quote.volatilityPartBps + quote.shortImpactPartBps,
            "adverse quote fee composition"
        );
    }

    function testDynamicFeeQuote_RevertingTradeCostsLessThanAdverseButMoreThanBase() external view {
        MemeverseUniswapHook.DynamicFeeQuote memory revertingQuote = hook.exposedPopulateDynamicFeeQuote({
            pifPpm: 50_000,
            spotBeforeX18: 1.3e18,
            spotAfterX18: 1.15e18,
            weightedVolume0: 1,
            ewVWAPX18: 1e18,
            volDeviationAccumulator: 100_000,
            shortImpactPpm: 50_000,
            shortLastTs: uint40(block.timestamp)
        });
        MemeverseUniswapHook.DynamicFeeQuote memory adverseQuote = hook.exposedPopulateDynamicFeeQuote({
            pifPpm: 50_000,
            spotBeforeX18: 1.3e18,
            spotAfterX18: 1.45e18,
            weightedVolume0: 1,
            ewVWAPX18: 1e18,
            volDeviationAccumulator: 100_000,
            shortImpactPpm: 50_000,
            shortLastTs: uint40(block.timestamp)
        });

        uint256 baseFeeBps = hook.exposedBaseFeeBps();
        assertGt(revertingQuote.feeBps, baseFeeBps, "reverting quote above base");
        assertLt(revertingQuote.feeBps, adverseQuote.feeBps, "reverting quote below adverse");
    }

    function testMath_SpotX18FromSqrtPrice_ExactAtReferencePoints() external view {
        assertEq(hook.exposedSpotX18FromSqrtPrice(SQRT_PRICE_1_1), 1e18, "q96");
        assertEq(hook.exposedSpotX18FromSqrtPrice(SQRT_PRICE_1_1 - 1), 999999999999999999, "q96-1");
        assertEq(hook.exposedSpotX18FromSqrtPrice(SQRT_PRICE_1_1 + 1), 1e18, "q96+1");
        assertEq(hook.exposedSpotX18FromSqrtPrice(TickMath.MIN_SQRT_PRICE + 1), 0, "min+1");
        assertEq(
            hook.exposedSpotX18FromSqrtPrice(TickMath.MAX_SQRT_PRICE - 1),
            340256786836388094070642339899681172762184831912254825631,
            "max-1"
        );
        assertEq(
            hook.exposedSpotX18FromSqrtPrice(SPOT_VECTOR_128_PLUS_1), 18446744073709551616000000000000000000, "2^128+1"
        );
        assertEq(
            hook.exposedSpotX18FromSqrtPrice(SPOT_VECTOR_128_64_12345),
            18446744073709551618000000000000001338,
            "2^128+2^64+12345"
        );
        assertEq(
            hook.exposedSpotX18FromSqrtPrice(SPOT_VECTOR_128_127_PLUS_1),
            41505174165846491136000000000000000000,
            "2^128+2^127+1"
        );
        assertEq(
            hook.exposedSpotX18FromSqrtPrice(SPOT_VECTOR_129_MINUS_1), 73786976294838206463999999999999999999, "2^129-1"
        );
        assertEq(
            hook.exposedSpotX18FromSqrtPrice(SPOT_VECTOR_140_PLUS_987654321),
            309485009821345068724781056000000438606627017,
            "2^140+987654321"
        );
    }

    function testMath_PriceMovePpmCappedToShort_ReturnsZeroWhenUnchanged() external view {
        assertEq(hook.exposedPriceMovePpmCappedToShort(SQRT_PRICE_1_1, SQRT_PRICE_1_1), 0, "unchanged");
    }

    function testMath_PriceMovePpmCappedToShort_MatchesKnownLowerBoundSample() external view {
        uint160 pre = TickMath.MIN_SQRT_PRICE + 1;
        uint160 post = pre + 500_000;

        assertEq(hook.exposedPriceMovePpmCappedToShort(pre, post), 232, "hook lower bound");
    }

    function testMath_PriceMovePpmCappedToShort_SaturatesAtCapInBothDirections() external view {
        uint160 pre = SQRT_PRICE_1_1;

        assertEq(hook.exposedPriceMovePpmCappedToShort(pre, TickMath.MAX_SQRT_PRICE - 1), SHORT_CAP_PPM, "up saturates");
        assertEq(
            hook.exposedPriceMovePpmCappedToShort(pre, TickMath.MIN_SQRT_PRICE + 1), SHORT_CAP_PPM, "down saturates"
        );
    }

    function testMath_PriceMovePpmCappedToShort_Preserves59999And60000BoundariesUp() external view {
        uint160 pre = SQRT_PRICE_1_1;

        assertEq(hook.exposedPriceMovePpmCappedToShort(pre, PRICE_MOVE_59_999_UP_POST), 59_999, "hook 59999 up");
        assertEq(hook.exposedPriceMovePpmCappedToShort(pre, PRICE_MOVE_60_000_UP_POST), 60_000, "hook 60000 up");
    }

    function testMath_PriceMovePpmCappedToShort_Preserves59999And60000BoundariesDown() external view {
        uint160 pre = SQRT_PRICE_1_1;

        assertEq(hook.exposedPriceMovePpmCappedToShort(pre, PRICE_MOVE_59_999_DOWN_POST), 59_999, "hook 59999 down");
        assertEq(hook.exposedPriceMovePpmCappedToShort(pre, PRICE_MOVE_60_000_DOWN_POST), 60_000, "hook 60000 down");
    }

    function testMath_PriceMovePpmCappedToShort_Preserves149999And150000BoundariesUp() external view {
        uint160 pre = SQRT_PRICE_1_1;

        assertEq(hook.exposedPriceMovePpmCappedToShort(pre, PRICE_MOVE_149_999_UP_POST), 149_999, "hook 149999 up");
        assertEq(hook.exposedPriceMovePpmCappedToShort(pre, PRICE_MOVE_150_000_UP_POST), 150_000, "hook 150000 up");
    }

    function testMath_PriceMovePpmCappedToShort_Preserves149999And150000BoundariesDown() external view {
        uint160 pre = SQRT_PRICE_1_1;

        assertEq(hook.exposedPriceMovePpmCappedToShort(pre, PRICE_MOVE_149_999_DOWN_POST), 149_999, "hook 149999 down");
        assertEq(hook.exposedPriceMovePpmCappedToShort(pre, PRICE_MOVE_150_000_DOWN_POST), 150_000, "hook 150000 down");
    }

    function testMath_PriceMovePpmCappedToShort_UsesExactFallbackOutsideCapEdges() external view {
        uint160 pre = SQRT_PRICE_1_1;
        uint160 post = PRICE_MOVE_AMBIGUOUS_POST;

        assertEq(_approxRatioMovePpm(pre, post), 999, "approx candidate");
        assertEq(hook.exposedPriceMovePpmCappedToShort(pre, post), 1000, "hook exact");
    }

    function testMath_DynamicFeeQuote_Tracks59999And60000AdverseFeeBoundary() external view {
        uint160 pre = SQRT_PRICE_1_1;
        uint256 spotBefore = hook.exposedSpotX18FromSqrtPrice(pre);

        MemeverseUniswapHook.DynamicFeeQuote memory quote59999 = hook.exposedPopulateDynamicFeeQuote({
            pifPpm: hook.exposedPriceMovePpmCappedToShort(pre, PRICE_MOVE_59_999_UP_POST),
            spotBeforeX18: spotBefore,
            spotAfterX18: hook.exposedSpotX18FromSqrtPrice(PRICE_MOVE_59_999_UP_POST),
            weightedVolume0: 0,
            ewVWAPX18: 0,
            volDeviationAccumulator: 0,
            shortImpactPpm: 0,
            shortLastTs: 0
        });
        MemeverseUniswapHook.DynamicFeeQuote memory quote60000 = hook.exposedPopulateDynamicFeeQuote({
            pifPpm: hook.exposedPriceMovePpmCappedToShort(pre, PRICE_MOVE_60_000_UP_POST),
            spotBeforeX18: spotBefore,
            spotAfterX18: hook.exposedSpotX18FromSqrtPrice(PRICE_MOVE_60_000_UP_POST),
            weightedVolume0: 0,
            ewVWAPX18: 0,
            volDeviationAccumulator: 0,
            shortImpactPpm: 0,
            shortLastTs: 0
        });

        assertEq(quote59999.pifPpm, 59_999, "pif 59999");
        assertEq(quote60000.pifPpm, 60_000, "pif 60000");
        assertEq(quote59999.feeBps, _expectedAdverseFeeBps(59_999), "fee 59999");
        assertEq(quote60000.feeBps, _expectedAdverseFeeBps(60_000), "fee 60000");
        assertLt(quote59999.feeBps, quote60000.feeBps, "fee boundary ordering");
    }

    function testMath_DynamicFeeQuote_Tracks149999And150000ShortImpactBoundary() external view {
        uint160 pre = SQRT_PRICE_1_1;
        uint256 spotBefore = hook.exposedSpotX18FromSqrtPrice(pre);
        uint256 spot149999 = hook.exposedSpotX18FromSqrtPrice(PRICE_MOVE_149_999_UP_POST);
        uint256 spot150000 = hook.exposedSpotX18FromSqrtPrice(PRICE_MOVE_150_000_UP_POST);

        MemeverseUniswapHook.DynamicFeeQuote memory quote149999 = hook.exposedPopulateDynamicFeeQuote({
            pifPpm: hook.exposedPriceMovePpmCappedToShort(pre, PRICE_MOVE_149_999_UP_POST),
            spotBeforeX18: spotBefore,
            spotAfterX18: spot149999,
            weightedVolume0: 1,
            ewVWAPX18: spot149999,
            volDeviationAccumulator: 0,
            shortImpactPpm: 0,
            shortLastTs: 0
        });
        MemeverseUniswapHook.DynamicFeeQuote memory quote150000 = hook.exposedPopulateDynamicFeeQuote({
            pifPpm: hook.exposedPriceMovePpmCappedToShort(pre, PRICE_MOVE_150_000_UP_POST),
            spotBeforeX18: spotBefore,
            spotAfterX18: spot150000,
            weightedVolume0: 1,
            ewVWAPX18: spot150000,
            volDeviationAccumulator: 0,
            shortImpactPpm: 0,
            shortLastTs: 0
        });

        assertEq(quote149999.pifPpm, 149_999, "pif 149999");
        assertEq(quote150000.pifPpm, 150_000, "pif 150000");
        assertEq(quote149999.shortImpactPartBps, 259, "short 149999");
        assertEq(quote150000.shortImpactPartBps, 260, "short 150000");
    }

    /// @notice Verifies launch settlement can only be initiated by the bound launcher.
    function testExecuteLaunchSettlement_RevertsWhenCallerNotLauncher() external {
        hook.setProtocolFeeCurrency(key.currency0);
        hook.setLauncher(address(0xABCD));

        vm.expectRevert(IMemeverseUniswapHook.Unauthorized.selector);
        hook.executeLaunchSettlement(
            IMemeverseUniswapHook.LaunchSettlementParams({
                key: key,
                params: SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}),
                recipient: address(this)
            })
        );
    }

    function testExecuteLaunchSettlement_RevertsWhenPairUsesNativeCurrency() external {
        PoolKey memory nativeKey = _dynamicPoolKey(CurrencyLibrary.ADDRESS_ZERO, Currency.wrap(address(token1)));
        hook.setProtocolFeeCurrency(key.currency0);
        hook.setLauncher(address(this));

        vm.expectRevert(IMemeverseUniswapHook.NativeCurrencyUnsupported.selector);
        hook.executeLaunchSettlement(
            IMemeverseUniswapHook.LaunchSettlementParams({
                key: nativeKey,
                params: SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}),
                recipient: address(this)
            })
        );
    }

    /// @notice Verifies launch settlement requires the pool to be initialized.
    function testExecuteLaunchSettlement_RevertsWhenPoolNotInitialized() external {
        MockPoolManagerForHookLiquidity uninitializedManager = new MockPoolManagerForHookLiquidity();
        TestableMemeverseUniswapHook uninitializedHook =
            new TestableMemeverseUniswapHook(IPoolManager(address(uninitializedManager)), address(this), address(this));
        PoolKey memory uninitializedKey = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            fee: 0x800000,
            tickSpacing: 200,
            hooks: IHooks(address(uninitializedHook))
        });
        uninitializedHook.setProtocolFeeCurrency(uninitializedKey.currency0);
        uninitializedHook.setLauncher(address(this));

        vm.expectRevert(IMemeverseUniswapHook.PoolNotInitialized.selector);
        uninitializedHook.executeLaunchSettlement(
            IMemeverseUniswapHook.LaunchSettlementParams({
                key: uninitializedKey,
                params: SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}),
                recipient: address(this)
            })
        );
    }

    /// @notice Verifies owner launch-fee and launcher setters update state and reject invalid inputs.
    /// @dev Covers the launch scheduler plus explicit launcher binding configuration surface.
    function testOwnerSetters_UpdateLaunchFeeConfigAndLauncher() external {
        vm.expectRevert(IMemeverseUniswapHook.ZeroAddress.selector);
        hook.setLauncher(address(0));

        hook.setLauncher(address(0xD00D));
        assertEq(hook.launcher(), address(0xD00D), "launcher");

        vm.expectRevert(IMemeverseUniswapHook.ZeroValue.selector);
        hook.setDefaultLaunchFeeConfig(
            IMemeverseUniswapHook.LaunchFeeConfig({startFeeBps: 5000, minFeeBps: 100, decayDurationSeconds: 0})
        );

        vm.expectRevert(IMemeverseUniswapHook.ZeroValue.selector);
        hook.setDefaultLaunchFeeConfig(
            IMemeverseUniswapHook.LaunchFeeConfig({startFeeBps: 99, minFeeBps: 100, decayDurationSeconds: 900})
        );

        vm.expectRevert(IMemeverseUniswapHook.ZeroValue.selector);
        hook.setDefaultLaunchFeeConfig(
            IMemeverseUniswapHook.LaunchFeeConfig({startFeeBps: 10_001, minFeeBps: 100, decayDurationSeconds: 900})
        );

        vm.expectRevert(IMemeverseUniswapHook.ZeroValue.selector);
        hook.setDefaultLaunchFeeConfig(
            IMemeverseUniswapHook.LaunchFeeConfig({startFeeBps: 5_000, minFeeBps: 10_001, decayDurationSeconds: 900})
        );

        hook.setDefaultLaunchFeeConfig(
            IMemeverseUniswapHook.LaunchFeeConfig({startFeeBps: 4000, minFeeBps: 100, decayDurationSeconds: 900})
        );

        (uint24 startFeeBps, uint24 minFeeBps, uint32 decayDurationSeconds) = hook.defaultLaunchFeeConfig();
        assertEq(startFeeBps, 4000, "start fee");
        assertEq(minFeeBps, 100, "min fee");
        assertEq(decayDurationSeconds, 900, "duration");
    }

    /// @notice Adds liquidity via the hook core to seed tests.
    /// @dev Wraps `addLiquidityCore` to centralize the single-step liquidity setup.
    function _addLiquidity() internal returns (uint128 liquidity) {
        (liquidity,) = hook.addLiquidityCore(
            IMemeverseUniswapHook.AddLiquidityCoreParams({
                currency0: key.currency0,
                currency1: key.currency1,
                amount0Desired: 100 ether,
                amount1Desired: 100 ether,
                to: address(this)
            })
        );
    }

    /// @notice Constructs the normalized pool key used throughout the tests.
    /// @dev Mirrors the hook's expected pair ordering and hook wiring.
    function _dynamicPoolKey(Currency currency0, Currency currency1) internal view returns (PoolKey memory) {
        return PoolKey({
            currency0: currency0, currency1: currency1, fee: 0x800000, tickSpacing: 200, hooks: IHooks(address(hook))
        });
    }

    function _approxRatioMovePpm(uint160 preSqrtPriceX96, uint160 postSqrtPriceX96) internal pure returns (uint256) {
        uint256 ratioX18 = FullMath.mulDiv(uint256(postSqrtPriceX96), E18, uint256(preSqrtPriceX96));
        uint256 squaredRatioX18 = FullMath.mulDiv(ratioX18, ratioX18, E18);
        uint256 movePpm =
            postSqrtPriceX96 >= preSqrtPriceX96 ? (squaredRatioX18 - E18) / 1e12 : (E18 - squaredRatioX18) / 1e12;
        return movePpm > SHORT_CAP_PPM ? SHORT_CAP_PPM : movePpm;
    }

    function _expectedAdverseFeeBps(uint256 pifPpm) internal pure returns (uint256) {
        uint256 cappedPif = pifPpm > PIF_CAP_PPM ? PIF_CAP_PPM : pifPpm;
        uint256 satPpm = FullMath.mulDiv(cappedPif, PPM_BASE, cappedPif + PIF_CAP_PPM);
        uint256 dffPpm = FullMath.mulDiv(FEE_DFF_MAX_PPM, satPpm, PPM_BASE);
        uint256 dynamicPpm = FullMath.mulDiv(dffPpm, cappedPif, PPM_BASE);
        uint256 shortPpm = pifPpm > SHORT_FLOOR_PPM ? pifPpm - SHORT_FLOOR_PPM : 0;
        uint256 shortImpactPartBps = FullMath.mulDiv(shortPpm, SHORT_COEFF_BPS, PPM_BASE);
        return FEE_BASE_BPS + (dynamicPpm / (PPM_BASE / BPS_BASE)) + shortImpactPartBps;
    }

    /// @notice Funds the test account and initializes a native-input pool.
    /// @dev Ensures the hook can consume native quotes without hitting balance issues.
    function _dealAndInitializeNativePool(PoolKey memory nativeKey) internal {
        vm.deal(address(this), 1_000_000 ether);
        mockManager.initialize(nativeKey, SQRT_PRICE_1_1);
    }

    /// @notice Allows the test contract to receive native refunds for hook operations.
    /// @dev Mirrors the payable fallback path the hook might call during tests.
    receive() external payable {}
}
