// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager, ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
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
import {LiquidityQuote} from "../../src/swap/libraries/LiquidityQuote.sol";
import {UniswapLP} from "../../src/swap/tokens/UniswapLP.sol";

contract MockPoolManagerForHookLiquidity {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

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
}

contract MemeverseUniswapHookLiquidityTest is Test {
    uint160 internal constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

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

    /// @notice Executes test add liquidity supports native input.
    /// @dev Covers the native-input branching path in the hook's addLiquidityCore helper.
    function testAddLiquidity_SupportsNativeInput() external {
        PoolKey memory nativeKey = _dynamicPoolKey(CurrencyLibrary.ADDRESS_ZERO, Currency.wrap(address(token1)));
        PoolId nativePoolId = nativeKey.toId();
        vm.deal(address(this), 1_000_000 ether);

        mockManager.initialize(nativeKey, SQRT_PRICE_1_1);
        (, uint256 requiredNative,) = LiquidityQuote.quote(SQRT_PRICE_1_1, 100 ether, 100 ether);

        (uint128 liquidity,) = hook.addLiquidityCore{value: requiredNative}(
            IMemeverseUniswapHook.AddLiquidityCoreParams({
                currency0: nativeKey.currency0,
                currency1: nativeKey.currency1,
                amount0Desired: 100 ether,
                amount1Desired: 100 ether,
                to: address(this)
            })
        );

        (address liquidityToken,,) = hook.poolInfo(nativePoolId);
        assertGt(liquidity, 0, "liquidity");
        assertGt(UniswapLP(liquidityToken).balanceOf(address(this)), 0, "lp balance");
        assertEq(address(hook).balance, 0, "no stranded native");
    }

    /// @notice Executes test add liquidity reverts on excess native value.
    /// @dev Validates the hook rejects users that send more native ETH than quoted.
    function testAddLiquidity_RevertsOnExcessNativeValue() external {
        PoolKey memory nativeKey = _dynamicPoolKey(CurrencyLibrary.ADDRESS_ZERO, Currency.wrap(address(token1)));
        _dealAndInitializeNativePool(nativeKey);
        (, uint256 requiredNative,) = LiquidityQuote.quote(SQRT_PRICE_1_1, 300 ether, 100 ether);

        vm.expectRevert(
            abi.encodeWithSelector(IMemeverseUniswapHook.InvalidNativeValue.selector, requiredNative, 300 ether)
        );
        hook.addLiquidityCore{value: 300 ether}(
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

    /// @notice Executes test remove liquidity supports native output.
    /// @dev Ensures native output is forwarded through the take helper and recorded on the mock manager.
    function testRemoveLiquidity_SupportsNativeOutput() external {
        PoolKey memory nativeKey = _dynamicPoolKey(CurrencyLibrary.ADDRESS_ZERO, Currency.wrap(address(token1)));
        PoolId nativePoolId = nativeKey.toId();
        vm.deal(address(this), 1_000_000 ether);
        mockManager.initialize(nativeKey, SQRT_PRICE_1_1);
        (, uint256 requiredNative,) = LiquidityQuote.quote(SQRT_PRICE_1_1, 100 ether, 100 ether);

        (uint128 liquidity,) = hook.addLiquidityCore{value: requiredNative}(
            IMemeverseUniswapHook.AddLiquidityCoreParams({
                currency0: nativeKey.currency0,
                currency1: nativeKey.currency1,
                amount0Desired: 100 ether,
                amount1Desired: 100 ether,
                to: address(this)
            })
        );

        uint256 nativeBefore = address(this).balance;
        uint256 token1Before = token1.balanceOf(address(this));

        BalanceDelta delta = hook.removeLiquidityCore(
            IMemeverseUniswapHook.RemoveLiquidityCoreParams({
                currency0: nativeKey.currency0,
                currency1: nativeKey.currency1,
                liquidity: liquidity,
                recipient: address(this)
            })
        );

        uint256 nativeOut = uint256(uint128(delta.amount0()));
        uint256 token1Out = uint256(uint128(delta.amount1()));

        assertGt(nativeOut, 0, "native out");
        assertGt(token1Out, 0, "token1 out");
        assertEq(mockManager.lastTakeRecipientAddress(), address(this), "take recipient");
        assertEq(address(this).balance, nativeBefore + nativeOut, "native returned");
        assertEq(token1.balanceOf(address(this)), token1Before + token1Out, "token1 returned");
        assertEq(address(hook).balance, 0, "hook keeps no native");
        assertEq(address(mockManager).balance, 1000, "manager keeps minimum-liquidity native dust");
        assertEq(mockManager.getLiquidity(nativePoolId), 1000, "minimum liquidity remains locked");
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
    /// @dev Covers the `_forwardLiquidityOutputs` branch in the hook.
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

    /// @notice Executes test router add liquidity refunds unused native budget.
    /// @dev Verifies the router refund path returns quoted native ETH back to the caller.
    function testRouterAddLiquidity_RefundsUnusedNativeBudget() external {
        PoolKey memory nativeKey = _dynamicPoolKey(CurrencyLibrary.ADDRESS_ZERO, Currency.wrap(address(token1)));
        PoolId nativePoolId = nativeKey.toId();
        _dealAndInitializeNativePool(nativeKey);
        (, uint256 requiredNative,) = LiquidityQuote.quote(SQRT_PRICE_1_1, 300 ether, 100 ether);

        uint256 nativeBefore = address(this).balance;
        uint128 liquidity = router.addLiquidity{value: 300 ether}(
            nativeKey.currency0,
            nativeKey.currency1,
            300 ether,
            100 ether,
            90 ether,
            90 ether,
            address(this),
            block.timestamp
        );

        (address liquidityToken,,) = hook.poolInfo(nativePoolId);
        assertGt(liquidity, 0, "liquidity");
        assertGt(UniswapLP(liquidityToken).balanceOf(address(this)), 0, "lp balance");
        assertEq(address(this).balance, nativeBefore - requiredNative, "only spent quoted native");
        assertEq(address(router).balance, 0, "router keeps no native");
        assertEq(address(hook).balance, 0, "hook keeps no native");
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
        hook.claimFeesCore(
            IMemeverseUniswapHook.ClaimFeesCoreParams({
                key: uninitializedKey,
                owner: address(this),
                recipient: address(this),
                deadline: block.timestamp,
                v: 0,
                r: bytes32(0),
                s: bytes32(0)
            })
        );
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

    /// @notice Verifies relayed claims reject expired signatures.
    /// @dev Covers the `ExpiredPastDeadline` branch in claim authorization.
    function testClaimFeesCoreReverts_WhenSignatureExpired() external {
        router.addLiquidity(
            key.currency0, key.currency1, 100 ether, 100 ether, 90 ether, 90 ether, address(this), block.timestamp
        );

        vm.prank(address(0xCAFE));
        vm.expectRevert(IMemeverseUniswapHook.ExpiredPastDeadline.selector);
        hook.claimFeesCore(
            IMemeverseUniswapHook.ClaimFeesCoreParams({
                key: key,
                owner: address(this),
                recipient: address(this),
                deadline: block.timestamp - 1,
                v: 27,
                r: bytes32(0),
                s: bytes32(0)
            })
        );
    }

    /// @notice Verifies relayed claims reject invalid signatures.
    /// @dev Covers the invalid-recovery branch in claim authorization.
    function testClaimFeesCoreReverts_WhenSignatureInvalid() external {
        router.addLiquidity(
            key.currency0, key.currency1, 100 ether, 100 ether, 90 ether, 90 ether, address(this), block.timestamp
        );

        vm.prank(address(0xCAFE));
        vm.expectRevert(IMemeverseUniswapHook.InvalidClaimSignature.selector);
        hook.claimFeesCore(
            IMemeverseUniswapHook.ClaimFeesCoreParams({
                key: key,
                owner: address(this),
                recipient: address(this),
                deadline: block.timestamp,
                v: 27,
                r: bytes32(0),
                s: bytes32(0)
            })
        );
    }

    /// @notice Verifies owner config setters reject invalid inputs and update state.
    /// @dev Covers treasury and launch-fee configuration branches on the hook.
    function testOwnerSetters_UpdateStateAndRejectInvalidInputs() external {
        vm.expectRevert(IMemeverseUniswapHook.ZeroAddress.selector);
        hook.setTreasury(address(0));

        hook.setTreasury(address(0xBEEF));
        assertEq(hook.treasury(), address(0xBEEF), "treasury");
    }

    /// @notice Verifies swap quoting reverts when neither side is enabled for protocol fees.
    /// @dev Covers the `CurrencyNotSupported` branch in fee-context resolution.
    function testQuoteSwapReverts_WhenProtocolFeeCurrencyUnsupported() external {
        vm.expectRevert(IMemeverseUniswapHook.CurrencyNotSupported.selector);
        hook.quoteSwap(key, SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}));
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

    /// @notice Verifies launch settlement can only be initiated by the bound launcher.
    function testExecuteLaunchSettlement_RevertsWhenCallerNotLauncher() external {
        hook.setProtocolFeeCurrency(key.currency0);
        hook.setLauncher(address(0xABCD));

        vm.expectRevert(IMemeverseUniswapHook.Unauthorized.selector);
        hook.executeLaunchSettlement(
            IMemeverseUniswapHook.LaunchSettlementParams({
                key: key,
                params: SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}),
                recipient: address(this),
                amountInMaximum: 100 ether
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
                recipient: address(this),
                amountInMaximum: 100 ether
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
