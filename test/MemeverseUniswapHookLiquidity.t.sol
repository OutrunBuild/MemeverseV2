// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager, ModifyLiquidityParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta, toBalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {LiquidityAmounts} from "../src/swap/libraries/LiquidityAmounts.sol";
import {BaseHook} from "@uniswap/v4-hooks-public/src/base/BaseHook.sol";

import {MemeverseUniswapHook} from "../src/swap/MemeverseUniswapHook.sol";
import {MemeverseSwapRouter} from "../src/swap/MemeverseSwapRouter.sol";
import {IMemeverseUniswapHook} from "../src/swap/interfaces/IMemeverseUniswapHook.sol";
import {LiquidityQuote} from "../src/swap/libraries/LiquidityQuote.sol";
import {UniswapLP} from "../src/swap/tokens/UniswapLP.sol";

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

    /// @notice Executes initialize.
    /// @dev See the implementation for behavior details.
    /// @param key The key value.
    /// @param sqrtPriceX96 The sqrtPriceX96 value.
    function initialize(PoolKey memory key, uint160 sqrtPriceX96) external {
        PoolId poolId = key.toId();
        slot0State[poolId] = Slot0State({sqrtPriceX96: sqrtPriceX96, tick: 0, protocolFee: 0, lpFee: 0});
        _syncPoolStorage(poolId);
        hookAddress = address(key.hooks);
        key.hooks.beforeInitialize(msg.sender, key, sqrtPriceX96);
    }

    /// @notice Executes unlock.
    /// @dev See the implementation for behavior details.
    /// @param data The data value.
    /// @return result The result value.
    function unlock(bytes calldata data) external returns (bytes memory result) {
        unlocked = true;
        result = IUnlockCallback(msg.sender).unlockCallback(data);
        unlocked = false;
    }

    /// @notice Executes modify liquidity.
    /// @dev See the implementation for behavior details.
    /// @param key The key value.
    /// @param params The params value.
    /// @param hookData The hookData value.
    /// @return delta The delta value.
    /// @return feesAccrued The feesAccrued value.
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

    /// @notice Executes take.
    /// @dev See the implementation for behavior details.
    /// @param currency The currency value.
    /// @param to The to value.
    /// @param amount The amount value.
    function take(Currency currency, address to, uint256 amount) external {
        lastTakeRecipient = to;
        if (currency.isAddressZero()) {
            (bool success,) = to.call{value: amount}("");
            require(success, "native take");
        } else {
            require(MockERC20(Currency.unwrap(currency)).transfer(to, amount), "erc20 take");
        }
    }

    /// @notice Executes sync.
    /// @dev See the implementation for behavior details.
    /// @param currency The currency value.
    function sync(Currency currency) external pure {
        currency;
    }

    /// @notice Executes settle.
    /// @dev See the implementation for behavior details.
    /// @return uint256 The uint256 value.
    function settle() external payable returns (uint256) {
        return msg.value;
    }

    /// @notice Returns extsload.
    /// @dev See the implementation for behavior details.
    /// @param slot The slot value.
    /// @return bytes32 The bytes32 value.
    function extsload(bytes32 slot) external view returns (bytes32) {
        return extStorage[slot];
    }

    /// @notice Returns get slot0.
    /// @dev See the implementation for behavior details.
    /// @param poolId The poolId value.
    /// @return uint160 The uint160 value.
    /// @return int24 The int24 value.
    /// @return uint24 The uint24 value.
    /// @return uint24 The uint24 value.
    function getSlot0(PoolId poolId) external view returns (uint160, int24, uint24, uint24) {
        Slot0State memory state = slot0State[poolId];
        return (state.sqrtPriceX96, state.tick, state.protocolFee, state.lpFee);
    }

    /// @notice Returns get liquidity.
    /// @dev See the implementation for behavior details.
    /// @param poolId The poolId value.
    /// @return uint128 The uint128 value.
    function getLiquidity(PoolId poolId) external view returns (uint128) {
        return liquidityState[poolId];
    }

    /// @notice Returns last take recipient address.
    /// @dev See the implementation for behavior details.
    /// @return address The address value.
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
    constructor(
        IPoolManager _manager,
        address _owner,
        address _treasury,
        uint256 _antiSnipeDurationBlocks,
        uint256 _maxAntiSnipeProbabilityBase
    ) MemeverseUniswapHook(_manager, _owner, _treasury, _antiSnipeDurationBlocks, _maxAntiSnipeProbabilityBase) {}

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
    /// @dev See the implementation for behavior details.
    function setUp() public {
        mockManager = new MockPoolManagerForHookLiquidity();
        token0 = new MockERC20("Token0", "TK0", 18);
        token1 = new MockERC20("Token1", "TK1", 18);
        token0.mint(address(this), 1_000_000 ether);
        token1.mint(address(this), 1_000_000 ether);

        hook = new TestableMemeverseUniswapHook(IPoolManager(address(mockManager)), address(this), address(this), 0, 1);
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

    /// @notice Executes test add liquidity uses unlock flow.
    /// @dev See the implementation for behavior details.
    function testAddLiquidity_UsesUnlockFlow() external {
        uint128 liquidity = _addLiquidity();
        (address liquidityToken,,,) = hook.poolInfo(poolId);

        assertGt(liquidity, 0, "liquidity");
        assertGt(UniswapLP(liquidityToken).balanceOf(address(this)), 0, "lp balance");
        assertGt(mockManager.getLiquidity(poolId), 0, "pool liquidity");
    }

    /// @notice Executes test remove liquidity uses original sender for take.
    /// @dev See the implementation for behavior details.
    function testRemoveLiquidity_UsesOriginalSenderForTake() external {
        uint128 liquidity = _addLiquidity();
        (address liquidityToken,,,) = hook.poolInfo(poolId);

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
    /// @dev See the implementation for behavior details.
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

        (address liquidityToken,,,) = hook.poolInfo(nativePoolId);
        assertGt(liquidity, 0, "liquidity");
        assertGt(UniswapLP(liquidityToken).balanceOf(address(this)), 0, "lp balance");
        assertEq(address(hook).balance, 0, "no stranded native");
    }

    /// @notice Executes test add liquidity reverts on excess native value.
    /// @dev See the implementation for behavior details.
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

    /// @notice Executes test remove liquidity supports native output.
    /// @dev See the implementation for behavior details.
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

    /// @notice Executes test router add liquidity uses hook core.
    /// @dev See the implementation for behavior details.
    function testRouterAddLiquidity_UsesHookCore() external {
        uint128 liquidity = router.addLiquidity(
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

        (address liquidityToken,,,) = hook.poolInfo(poolId);
        assertGt(liquidity, 0, "liquidity");
        assertGt(UniswapLP(liquidityToken).balanceOf(address(this)), 0, "lp balance");
    }

    /// @notice Executes test router add liquidity refunds unused native budget.
    /// @dev See the implementation for behavior details.
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
            address(this),
            block.timestamp
        );

        (address liquidityToken,,,) = hook.poolInfo(nativePoolId);
        assertGt(liquidity, 0, "liquidity");
        assertGt(UniswapLP(liquidityToken).balanceOf(address(this)), 0, "lp balance");
        assertEq(address(this).balance, nativeBefore - requiredNative, "only spent quoted native");
        assertEq(address(router).balance, 0, "router keeps no native");
        assertEq(address(hook).balance, 0, "hook keeps no native");
    }

    /// @notice Executes test router remove liquidity uses hook core.
    /// @dev See the implementation for behavior details.
    function testRouterRemoveLiquidity_UsesHookCore() external {
        uint128 liquidity = router.addLiquidity(
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
        (address liquidityToken,,,) = hook.poolInfo(poolId);
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

    function _dynamicPoolKey(Currency currency0, Currency currency1) internal view returns (PoolKey memory) {
        return PoolKey({
            currency0: currency0, currency1: currency1, fee: 0x800000, tickSpacing: 200, hooks: IHooks(address(hook))
        });
    }

    function _dealAndInitializeNativePool(PoolKey memory nativeKey) internal {
        vm.deal(address(this), 1_000_000 ether);
        mockManager.initialize(nativeKey, SQRT_PRICE_1_1);
    }

    receive() external payable {}
}
