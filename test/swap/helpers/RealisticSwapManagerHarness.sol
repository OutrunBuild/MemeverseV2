// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IPoolManager, ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta, BalanceDeltaLibrary, toBalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {SqrtPriceMath} from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {BaseHook} from "@uniswap/v4-hooks-public/src/base/BaseHook.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {ISignatureTransfer} from "permit2/src/interfaces/ISignatureTransfer.sol";

import {LiquidityAmounts} from "../../../src/swap/libraries/LiquidityAmounts.sol";
import {MemeverseSwapRouter} from "../../../src/swap/MemeverseSwapRouter.sol";
import {MemeverseUniswapHook} from "../../../src/swap/MemeverseUniswapHook.sol";
import {IMemeverseSwapRouter} from "../../../src/swap/interfaces/IMemeverseSwapRouter.sol";
import {IMemeverseUniswapHook} from "../../../src/swap/interfaces/IMemeverseUniswapHook.sol";

contract RealisticSwapManagerHarness {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using BeforeSwapDeltaLibrary for BeforeSwapDelta;

    error ManagerLocked();
    error AlreadyUnlocked();
    error CurrencyNotSettled();
    error PriceLimitAlreadyExceeded(uint160 sqrtPriceCurrentX96, uint160 sqrtPriceLimitX96);
    error PriceLimitOutOfBounds(uint160 sqrtPriceLimitX96);

    struct Slot0State {
        uint160 sqrtPriceX96;
        int24 tick;
        uint24 protocolFee;
        uint24 lpFee;
    }

    bytes internal constant ZERO_BYTES = bytes("");
    bytes32 internal constant POOLS_SLOT = bytes32(uint256(6));
    uint256 internal constant LIQUIDITY_OFFSET = 3;

    bool internal unlocked;
    mapping(bytes32 => bytes32) internal extStorage;
    mapping(bytes32 => bool) internal isPoolStateSlot;
    mapping(bytes32 => PoolId) internal poolIdForStateSlot;
    mapping(PoolId => Slot0State) internal slot0State;
    mapping(PoolId => uint128) internal liquidityState;
    mapping(PoolId => uint256) internal nextExactInputPoolInputAmount;
    mapping(PoolId => uint256) internal nextExactOutputAmount;
    mapping(PoolId => uint160) internal nextSwapSqrtPriceX96;
    mapping(PoolId => mapping(address => uint160)) internal callerSlot0OverrideX96;
    mapping(bytes32 => int256) internal currencyDeltaState;
    bool internal syncedCurrencySet;
    Currency internal syncedCurrency;
    uint256 internal syncedReserves;
    uint256 internal nonzeroDeltaCount;

    function initialize(PoolKey memory key, uint160 sqrtPriceX96) external returns (int24 tick) {
        PoolId poolId = key.toId();
        slot0State[poolId] = Slot0State({sqrtPriceX96: sqrtPriceX96, tick: 0, protocolFee: 0, lpFee: 0});
        _syncPoolStorage(poolId);
        key.hooks.beforeInitialize(msg.sender, key, sqrtPriceX96);
        return 0;
    }

    function unlock(bytes calldata data) external returns (bytes memory result) {
        if (unlocked) revert AlreadyUnlocked();
        unlocked = true;
        result = IUnlockCallback(msg.sender).unlockCallback(data);
        if (nonzeroDeltaCount != 0) revert CurrencyNotSettled();
        unlocked = false;
        syncedCurrencySet = false;
        syncedCurrency = Currency.wrap(address(0));
        syncedReserves = 0;
    }

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
                TickMath.MIN_SQRT_PRICE + 1,
                TickMath.MAX_SQRT_PRICE - 1,
                uint128(uint256(params.liquidityDelta))
            );
            delta = toBalanceDelta(-int128(int256(amount0Used)), -int128(int256(amount1Used)));
            _accountPoolBalanceDelta(key, delta, msg.sender);
            return (delta, feesAccrued);
        }

        liquidityState[key.toId()] -= uint128(uint256(-params.liquidityDelta));
        _syncPoolStorage(key.toId());
        (amount0Used, amount1Used) = LiquidityAmounts.getAmountsForLiquidity(
            slot0State[key.toId()].sqrtPriceX96,
            TickMath.MIN_SQRT_PRICE + 1,
            TickMath.MAX_SQRT_PRICE - 1,
            uint128(uint256(-params.liquidityDelta))
        );
        delta = toBalanceDelta(int128(int256(amount0Used)), int128(int256(amount1Used)));
        _accountPoolBalanceDelta(key, delta, msg.sender);
    }

    function swap(PoolKey memory key, SwapParams memory params, bytes calldata hookData)
        external
        returns (BalanceDelta delta)
    {
        if (!unlocked) revert ManagerLocked();

        PoolId poolId = key.toId();
        Slot0State memory state = slot0State[poolId];
        _validatePriceLimit(state.sqrtPriceX96, params);

        bool skipHookCallbacks = msg.sender == address(key.hooks);
        BeforeSwapDelta beforeSwapDelta = BeforeSwapDeltaLibrary.ZERO_DELTA;
        int256 amountToSwap = params.amountSpecified;
        if (!skipHookCallbacks) {
            (, beforeSwapDelta,) = key.hooks.beforeSwap(msg.sender, key, params, hookData);
            amountToSwap += beforeSwapDelta.getSpecifiedDelta();
        }

        BalanceDelta poolDelta = BalanceDeltaLibrary.ZERO_DELTA;
        if (amountToSwap != 0) {
            if (params.amountSpecified < 0) {
                poolDelta = _exactInputDelta(poolId, state.sqrtPriceX96, params.zeroForOne, uint256(-amountToSwap));
            } else {
                poolDelta = _exactOutputDelta(poolId, state.sqrtPriceX96, params.zeroForOne, uint256(amountToSwap));
            }
        }

        _applyNextSwapPriceOverride(poolId);

        if (skipHookCallbacks) {
            _accountPoolBalanceDelta(key, poolDelta, msg.sender);
            return poolDelta;
        }

        (, int128 afterSwapUnspecifiedDelta) = key.hooks.afterSwap(msg.sender, key, params, poolDelta, hookData);

        int128 hookDeltaSpecified = beforeSwapDelta.getSpecifiedDelta();
        int128 hookDeltaUnspecified = beforeSwapDelta.getUnspecifiedDelta() + afterSwapUnspecifiedDelta;
        BalanceDelta callerDelta = poolDelta;
        if (hookDeltaSpecified != 0 || hookDeltaUnspecified != 0) {
            BalanceDelta hookDelta = (params.amountSpecified < 0 == params.zeroForOne)
                ? toBalanceDelta(hookDeltaSpecified, hookDeltaUnspecified)
                : toBalanceDelta(hookDeltaUnspecified, hookDeltaSpecified);
            _accountPoolBalanceDelta(key, hookDelta, address(key.hooks));
            callerDelta = poolDelta - hookDelta;
        }

        _accountPoolBalanceDelta(key, callerDelta, msg.sender);
        return callerDelta;
    }

    function take(Currency currency, address to, uint256 amount) external {
        if (!unlocked) revert ManagerLocked();
        _accountDelta(currency, -int128(int256(amount)), msg.sender);
        if (currency.isAddressZero()) {
            (bool success,) = to.call{value: amount}("");
            require(success, "native take");
        } else {
            require(MockERC20(Currency.unwrap(currency)).transfer(to, amount), "erc20 take");
        }
    }

    function sync(Currency currency) external {
        if (!unlocked) revert ManagerLocked();
        syncedCurrencySet = true;
        syncedCurrency = currency;
        syncedReserves = currency.isAddressZero() ? 0 : IERC20(Currency.unwrap(currency)).balanceOf(address(this));
    }

    function settle() external payable returns (uint256) {
        if (!unlocked) revert ManagerLocked();

        Currency currency = syncedCurrencySet ? syncedCurrency : Currency.wrap(address(0));
        uint256 paid;
        if (currency.isAddressZero()) {
            paid = msg.value;
        } else {
            uint256 reservesNow = IERC20(Currency.unwrap(currency)).balanceOf(address(this));
            paid = reservesNow - syncedReserves;
        }

        syncedCurrencySet = false;
        syncedCurrency = Currency.wrap(address(0));
        syncedReserves = 0;
        _accountDelta(currency, int128(int256(paid)), msg.sender);
        return paid;
    }

    function extsload(bytes32 slot) external view returns (bytes32 value) {
        if (isPoolStateSlot[slot]) {
            uint160 overridePriceX96 = callerSlot0OverrideX96[poolIdForStateSlot[slot]][msg.sender];
            if (overridePriceX96 != 0) {
                return bytes32(uint256(overridePriceX96));
            }
        }
        return extStorage[slot];
    }

    function extsload(bytes32 startSlot, uint256 nSlots) external view returns (bytes32[] memory values) {
        values = new bytes32[](nSlots);
        for (uint256 i = 0; i < nSlots; ++i) {
            values[i] = extStorage[bytes32(uint256(startSlot) + i)];
        }
    }

    function extsload(bytes32[] calldata slots) external view returns (bytes32[] memory values) {
        values = new bytes32[](slots.length);
        for (uint256 i = 0; i < slots.length; ++i) {
            values[i] = extStorage[slots[i]];
        }
    }

    function setNextExactInputPoolInputAmount(PoolId poolId, uint256 amount) external {
        nextExactInputPoolInputAmount[poolId] = amount;
    }

    function setNextExactOutputAmount(PoolId poolId, uint256 amount) external {
        nextExactOutputAmount[poolId] = amount;
    }

    function setNextSwapSqrtPriceX96(PoolId poolId, uint160 sqrtPriceX96) external {
        nextSwapSqrtPriceX96[poolId] = sqrtPriceX96;
    }

    function setCallerSlot0OverrideX96(PoolId poolId, address caller, uint160 sqrtPriceX96) external {
        callerSlot0OverrideX96[poolId][caller] = sqrtPriceX96;
    }

    function getSlot0(PoolId poolId)
        external
        view
        returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee)
    {
        Slot0State memory state = slot0State[poolId];
        return (state.sqrtPriceX96, state.tick, state.protocolFee, state.lpFee);
    }

    function _validatePriceLimit(uint160 sqrtPriceCurrentX96, SwapParams memory params) internal pure {
        if (params.zeroForOne) {
            if (params.sqrtPriceLimitX96 >= sqrtPriceCurrentX96) {
                revert PriceLimitAlreadyExceeded(sqrtPriceCurrentX96, params.sqrtPriceLimitX96);
            }
            if (params.sqrtPriceLimitX96 <= TickMath.MIN_SQRT_PRICE) {
                revert PriceLimitOutOfBounds(params.sqrtPriceLimitX96);
            }
            return;
        }

        if (params.sqrtPriceLimitX96 <= sqrtPriceCurrentX96) {
            revert PriceLimitAlreadyExceeded(sqrtPriceCurrentX96, params.sqrtPriceLimitX96);
        }
        if (params.sqrtPriceLimitX96 >= TickMath.MAX_SQRT_PRICE) {
            revert PriceLimitOutOfBounds(params.sqrtPriceLimitX96);
        }
    }

    function _exactInputDelta(PoolId poolId, uint160 sqrtPriceCurrentX96, bool zeroForOne, uint256 inputAmount)
        internal
        returns (BalanceDelta delta)
    {
        uint256 configuredInputAmount = nextExactInputPoolInputAmount[poolId];
        if (configuredInputAmount != 0) {
            inputAmount = configuredInputAmount;
            delete nextExactInputPoolInputAmount[poolId];
        }

        uint128 liquidity = liquidityState[poolId];
        uint160 nextSqrtPriceX96 =
            SqrtPriceMath.getNextSqrtPriceFromInput(sqrtPriceCurrentX96, liquidity, inputAmount, zeroForOne);
        uint256 outputAmount = zeroForOne
            ? SqrtPriceMath.getAmount1Delta(nextSqrtPriceX96, sqrtPriceCurrentX96, liquidity, false)
            : SqrtPriceMath.getAmount0Delta(sqrtPriceCurrentX96, nextSqrtPriceX96, liquidity, false);

        slot0State[poolId].sqrtPriceX96 = nextSqrtPriceX96;
        _syncPoolStorage(poolId);

        return zeroForOne
            ? toBalanceDelta(-int128(int256(inputAmount)), int128(int256(outputAmount)))
            : toBalanceDelta(int128(int256(outputAmount)), -int128(int256(inputAmount)));
    }

    function _exactOutputDelta(PoolId poolId, uint160 sqrtPriceCurrentX96, bool zeroForOne, uint256 outputAmount)
        internal
        returns (BalanceDelta delta)
    {
        uint256 configuredOutputAmount = nextExactOutputAmount[poolId];
        if (configuredOutputAmount != 0) {
            outputAmount = configuredOutputAmount;
            delete nextExactOutputAmount[poolId];
        }

        uint128 liquidity = liquidityState[poolId];
        uint160 nextSqrtPriceX96 =
            SqrtPriceMath.getNextSqrtPriceFromOutput(sqrtPriceCurrentX96, liquidity, outputAmount, zeroForOne);
        uint256 inputAmount = zeroForOne
            ? SqrtPriceMath.getAmount0Delta(nextSqrtPriceX96, sqrtPriceCurrentX96, liquidity, true)
            : SqrtPriceMath.getAmount1Delta(sqrtPriceCurrentX96, nextSqrtPriceX96, liquidity, true);

        slot0State[poolId].sqrtPriceX96 = nextSqrtPriceX96;
        _syncPoolStorage(poolId);

        return zeroForOne
            ? toBalanceDelta(-int128(int256(inputAmount)), int128(int256(outputAmount)))
            : toBalanceDelta(int128(int256(outputAmount)), -int128(int256(inputAmount)));
    }

    function _applyNextSwapPriceOverride(PoolId poolId) internal {
        uint160 overridePriceX96 = nextSwapSqrtPriceX96[poolId];
        if (overridePriceX96 == 0) return;

        slot0State[poolId].sqrtPriceX96 = overridePriceX96;
        _syncPoolStorage(poolId);
        delete nextSwapSqrtPriceX96[poolId];
    }

    function _syncPoolStorage(PoolId poolId) internal {
        bytes32 stateSlot = keccak256(abi.encodePacked(PoolId.unwrap(poolId), POOLS_SLOT));
        Slot0State memory state = slot0State[poolId];

        if (!isPoolStateSlot[stateSlot]) {
            isPoolStateSlot[stateSlot] = true;
            poolIdForStateSlot[stateSlot] = poolId;
        }
        extStorage[stateSlot] = bytes32(uint256(state.sqrtPriceX96));
        extStorage[bytes32(uint256(stateSlot) + LIQUIDITY_OFFSET)] = bytes32(uint256(liquidityState[poolId]));
    }

    function _accountPoolBalanceDelta(PoolKey memory key, BalanceDelta delta, address target) internal {
        _accountDelta(key.currency0, delta.amount0(), target);
        _accountDelta(key.currency1, delta.amount1(), target);
    }

    function _accountDelta(Currency currency, int128 delta, address target) internal {
        if (delta == 0) return;

        bytes32 slot = keccak256(abi.encode(target, Currency.unwrap(currency)));
        int256 previous = currencyDeltaState[slot];
        int256 next = previous + delta;
        currencyDeltaState[slot] = next;

        if (next == 0) {
            unchecked {
                --nonzeroDeltaCount;
            }
        } else if (previous == 0) {
            unchecked {
                ++nonzeroDeltaCount;
            }
        }
    }

    receive() external payable {}
}

contract TestableMemeverseUniswapHookForIntegration is MemeverseUniswapHook {
    constructor(IPoolManager _manager, address _owner, address _treasury)
        MemeverseUniswapHook(_manager, _owner, _treasury)
    {}

    function validateHookAddress(BaseHook) internal pure override {}
}

contract MockPermit2ForRouterIntegration {
    using SafeERC20 for IERC20;

    address public lastOwner;
    address public lastRecipient;
    address public lastToken;
    uint256 public lastRequestedAmount;
    bytes32 public lastWitness;
    string public lastWitnessTypeString;
    bytes public lastSignature;

    function permitWitnessTransferFrom(
        ISignatureTransfer.PermitTransferFrom memory permit,
        ISignatureTransfer.SignatureTransferDetails calldata transferDetails,
        address owner,
        bytes32 witness,
        string calldata witnessTypeString,
        bytes calldata signature
    ) external {
        lastOwner = owner;
        lastRecipient = transferDetails.to;
        lastToken = permit.permitted.token;
        lastRequestedAmount = transferDetails.requestedAmount;
        lastWitness = witness;
        lastWitnessTypeString = witnessTypeString;
        lastSignature = signature;

        IERC20(permit.permitted.token).safeTransferFrom(owner, transferDetails.to, transferDetails.requestedAmount);
    }
}

contract UnlockSwapIntegrator is IUnlockCallback {
    using SafeERC20 for IERC20;

    RealisticSwapManagerHarness internal immutable manager;

    struct CallbackData {
        address payer;
        address recipient;
        PoolKey key;
        SwapParams params;
        bytes hookData;
    }

    constructor(RealisticSwapManagerHarness manager_) {
        manager = manager_;
    }

    function swap(PoolKey memory key, SwapParams memory params, address recipient, bytes memory hookData)
        external
        returns (BalanceDelta delta)
    {
        delta = abi.decode(
            manager.unlock(
                abi.encode(
                    CallbackData({
                        payer: msg.sender, recipient: recipient, key: key, params: params, hookData: hookData
                    })
                )
            ),
            (BalanceDelta)
        );
    }

    function unlockCallback(bytes calldata rawData) external returns (bytes memory result) {
        require(msg.sender == address(manager), "only manager");

        CallbackData memory data = abi.decode(rawData, (CallbackData));
        BalanceDelta delta = manager.swap(data.key, data.params, data.hookData);

        if (delta.amount0() < 0) {
            manager.sync(data.key.currency0);
            IERC20(Currency.unwrap(data.key.currency0))
                .safeTransferFrom(data.payer, address(manager), uint256(int256(-delta.amount0())));
            manager.settle();
        }
        if (delta.amount1() < 0) {
            manager.sync(data.key.currency1);
            IERC20(Currency.unwrap(data.key.currency1))
                .safeTransferFrom(data.payer, address(manager), uint256(int256(-delta.amount1())));
            manager.settle();
        }
        if (delta.amount0() > 0) {
            manager.take(data.key.currency0, data.recipient, uint256(int256(delta.amount0())));
        }
        if (delta.amount1() > 0) {
            manager.take(data.key.currency1, data.recipient, uint256(int256(delta.amount1())));
        }

        return abi.encode(delta);
    }
}

contract RawTransferSwapIntegrator is IUnlockCallback {
    using SafeERC20 for IERC20;

    RealisticSwapManagerHarness internal immutable manager;

    struct CallbackData {
        address payer;
        address recipient;
        PoolKey key;
        SwapParams params;
        bytes hookData;
    }

    constructor(RealisticSwapManagerHarness manager_) {
        manager = manager_;
    }

    function swap(PoolKey memory key, SwapParams memory params, address recipient, bytes memory hookData)
        external
        returns (BalanceDelta delta)
    {
        delta = abi.decode(
            manager.unlock(
                abi.encode(
                    CallbackData({
                        payer: msg.sender, recipient: recipient, key: key, params: params, hookData: hookData
                    })
                )
            ),
            (BalanceDelta)
        );
    }

    function unlockCallback(bytes calldata rawData) external returns (bytes memory result) {
        require(msg.sender == address(manager), "only manager");

        CallbackData memory data = abi.decode(rawData, (CallbackData));
        BalanceDelta delta = manager.swap(data.key, data.params, data.hookData);

        if (delta.amount0() < 0) {
            IERC20(Currency.unwrap(data.key.currency0))
                .safeTransferFrom(data.payer, address(manager), uint256(int256(-delta.amount0())));
        }
        if (delta.amount1() < 0) {
            IERC20(Currency.unwrap(data.key.currency1))
                .safeTransferFrom(data.payer, address(manager), uint256(int256(-delta.amount1())));
        }

        return abi.encode(delta);
    }
}

abstract contract RealisticSwapIntegrationBase is Test {
    using PoolIdLibrary for PoolKey;

    uint160 internal constant SQRT_PRICE_1_1 = 79228162514264337593543950336;
    uint256 internal constant ALICE_PK = 0xA11CE;
    uint256 internal constant FEE_GROWTH_Q128 = uint256(1) << 128;
    bytes32 internal constant SWAP_WITNESS_TYPEHASH = keccak256(
        "MemeverseSwapWitness(bytes32 poolId,bool zeroForOne,int256 amountSpecified,uint160 sqrtPriceLimitX96,address recipient,uint256 deadline,uint256 amountOutMinimum,uint256 amountInMaximum,bytes32 hookDataHash)"
    );
    string internal constant SWAP_WITNESS_TYPE_STRING =
        "MemeverseSwapWitness witness)MemeverseSwapWitness(bytes32 poolId,bool zeroForOne,int256 amountSpecified,uint160 sqrtPriceLimitX96,address recipient,uint256 deadline,uint256 amountOutMinimum,uint256 amountInMaximum,bytes32 hookDataHash)TokenPermissions(address token,uint256 amount)";

    struct RollbackSnapshot {
        uint256 payer0;
        uint256 payer1;
        uint256 treasury0;
        uint256 treasury1;
        uint256 fee0PerShare;
        uint256 fee1PerShare;
        uint256 weightedVolume0;
        uint256 ewVWAPX18;
        uint160 volAnchorSqrtPriceX96;
        uint24 volDeviationAccumulator;
        uint24 shortImpactPpm;
    }

    RealisticSwapManagerHarness internal manager;
    TestableMemeverseUniswapHookForIntegration internal hook;
    MemeverseSwapRouter internal router;
    UnlockSwapIntegrator internal integrator;
    RawTransferSwapIntegrator internal rawTransferIntegrator;
    MockERC20 internal token0;
    MockERC20 internal token1;
    address internal treasury;
    address internal alice;
    PoolKey internal key;
    PoolId internal poolId;

    function _setUpIntegration(IPermit2 permit2_) internal {
        manager = new RealisticSwapManagerHarness();
        treasury = makeAddr("treasury");
        alice = vm.addr(ALICE_PK);

        token0 = new MockERC20("Token0", "TK0", 18);
        token1 = new MockERC20("Token1", "TK1", 18);
        token0.mint(address(this), 1_000_000 ether);
        token1.mint(address(this), 1_000_000 ether);
        token0.mint(alice, 1_000_000 ether);
        token1.mint(alice, 1_000_000 ether);

        hook = new TestableMemeverseUniswapHookForIntegration(IPoolManager(address(manager)), address(this), treasury);
        router = new MemeverseSwapRouter(IPoolManager(address(manager)), IMemeverseUniswapHook(address(hook)), permit2_);
        integrator = new UnlockSwapIntegrator(manager);
        rawTransferIntegrator = new RawTransferSwapIntegrator(manager);

        token0.approve(address(hook), type(uint256).max);
        token1.approve(address(hook), type(uint256).max);
        token0.approve(address(router), type(uint256).max);
        token1.approve(address(router), type(uint256).max);
        token0.approve(address(integrator), type(uint256).max);
        token1.approve(address(integrator), type(uint256).max);
        token0.approve(address(rawTransferIntegrator), type(uint256).max);
        token1.approve(address(rawTransferIntegrator), type(uint256).max);

        key = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            fee: 0x800000,
            tickSpacing: 200,
            hooks: IHooks(address(hook))
        });
        poolId = key.toId();

        manager.initialize(key, SQRT_PRICE_1_1);
        _addLiquidity(address(this));
    }

    function _addLiquidity(address recipient) internal returns (uint128 liquidity) {
        (liquidity,) = hook.addLiquidityCore(
            IMemeverseUniswapHook.AddLiquidityCoreParams({
                currency0: key.currency0,
                currency1: key.currency1,
                amount0Desired: 100 ether,
                amount1Desired: 100 ether,
                to: recipient
            })
        );
    }

    function _matureLaunchWindow() internal {
        vm.warp(block.timestamp + 900);
    }

    function _validExecutionPriceLimit(bool zeroForOne) internal pure returns (uint160) {
        return zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;
    }

    function _rollbackSnapshot(address payer) internal view returns (RollbackSnapshot memory snapshot) {
        snapshot.payer0 = token0.balanceOf(payer);
        snapshot.payer1 = token1.balanceOf(payer);
        snapshot.treasury0 = token0.balanceOf(treasury);
        snapshot.treasury1 = token1.balanceOf(treasury);
        (, snapshot.fee0PerShare, snapshot.fee1PerShare) = hook.poolInfo(poolId);
        (
            snapshot.weightedVolume0,,
            snapshot.ewVWAPX18,
            snapshot.volAnchorSqrtPriceX96,,
            snapshot.volDeviationAccumulator,,
            snapshot.shortImpactPpm,
        ) = hook.poolEWVWAPParams(poolId);
    }

    function _assertRollback(address payer, RollbackSnapshot memory before_) internal view {
        assertEq(token0.balanceOf(payer), before_.payer0, "payer token0 rollback");
        assertEq(token1.balanceOf(payer), before_.payer1, "payer token1 rollback");
        assertEq(token0.balanceOf(treasury), before_.treasury0, "treasury token0 rollback");
        assertEq(token1.balanceOf(treasury), before_.treasury1, "treasury token1 rollback");

        (, uint256 fee0PerShareAfter, uint256 fee1PerShareAfter) = hook.poolInfo(poolId);
        assertEq(fee0PerShareAfter, before_.fee0PerShare, "fee0 per share rollback");
        assertEq(fee1PerShareAfter, before_.fee1PerShare, "fee1 per share rollback");

        (
            uint256 weightedVolume0After,,
            uint256 ewVWAPX18After,
            uint160 volAnchorSqrtPriceX96After,,
            uint24 volDeviationAccumulatorAfter,,
            uint24 shortImpactPpmAfter,
        ) = hook.poolEWVWAPParams(poolId);
        assertEq(weightedVolume0After, before_.weightedVolume0, "weightedVolume0 rollback");
        assertEq(ewVWAPX18After, before_.ewVWAPX18, "ewvwap rollback");
        assertEq(volAnchorSqrtPriceX96After, before_.volAnchorSqrtPriceX96, "vol anchor rollback");
        assertEq(volDeviationAccumulatorAfter, before_.volDeviationAccumulator, "vol deviation rollback");
        assertEq(shortImpactPpmAfter, before_.shortImpactPpm, "short impact rollback");
    }

    function _singlePermit(address token, uint256 amount)
        internal
        view
        returns (IMemeverseSwapRouter.Permit2SingleParams memory permitParams)
    {
        permitParams = IMemeverseSwapRouter.Permit2SingleParams({
            permit: ISignatureTransfer.PermitTransferFrom({
                permitted: ISignatureTransfer.TokenPermissions({token: token, amount: amount}),
                nonce: 1,
                deadline: block.timestamp
            }),
            transferDetails: ISignatureTransfer.SignatureTransferDetails({
                to: address(router), requestedAmount: amount
            }),
            signature: hex"1234"
        });
    }

    function _swapWitness(
        PoolKey memory key_,
        SwapParams memory params,
        address recipient,
        uint256 deadline,
        uint256 amountOutMinimum,
        uint256 amountInMaximum,
        bytes memory hookData
    ) internal pure returns (bytes32 witness) {
        witness = keccak256(
            abi.encode(
                SWAP_WITNESS_TYPEHASH,
                key_.toId(),
                params.zeroForOne,
                params.amountSpecified,
                params.sqrtPriceLimitX96,
                recipient,
                deadline,
                amountOutMinimum,
                amountInMaximum,
                keccak256(hookData)
            )
        );
    }

    function _expectedLpFeeGrowth(uint256 lpFeeAmount) internal view returns (uint256) {
        (address liquidityToken,,) = hook.poolInfo(poolId);
        uint256 activeSupply = IERC20(liquidityToken).balanceOf(address(this));
        return lpFeeAmount == 0 ? 0 : (lpFeeAmount * FEE_GROWTH_Q128) / activeSupply;
    }
}
