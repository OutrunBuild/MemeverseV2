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
import {SqrtPriceMath} from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {LiquidityAmounts} from "../../src/swap/libraries/LiquidityAmounts.sol";
import {BaseHook} from "@uniswap/v4-hooks-public/src/base/BaseHook.sol";

import {MemeverseUniswapHook} from "../../src/swap/MemeverseUniswapHook.sol";
import {MemeverseSwapRouter} from "../../src/swap/MemeverseSwapRouter.sol";
import {IMemeverseUniswapHook} from "../../src/swap/interfaces/IMemeverseUniswapHook.sol";
import {IMemeverseSwapRouter} from "../../src/swap/interfaces/IMemeverseSwapRouter.sol";
import {UniswapLP} from "../../src/swap/tokens/UniswapLP.sol";

/// @dev Mock-harness boundary:
/// - This file's mock manager and routed tests only cover local plumbing, witness/deadline handling,
///   local revert surface, and deterministic branch coverage.
/// - The newer integration tests only cover a narrow exact-input subset under a stricter manager harness.
///   Exact-output, one-for-zero symmetry outside that subset, and other broader swap economics claims are not
///   proven by this file and must not be inferred from this mock manager.
contract MockPoolManagerForRouterTest {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using BeforeSwapDeltaLibrary for BeforeSwapDelta;

    error ManagerLocked();
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
    uint160 internal constant SQRT_PRICE_LOWER_X96 = 4_310_618_292;
    uint160 internal constant SQRT_PRICE_UPPER_X96 = 1_456_195_216_270_955_103_206_513_029_158_776_779_468_408_838_535;

    bool internal unlocked;
    bool internal quoteAlignedSwapMath;
    bool internal enforceV4PriceLimitValidation;
    address internal lastUnlockCallbackPayer;
    mapping(bytes32 => bytes32) internal extStorage;
    mapping(PoolId => Slot0State) internal slot0State;
    mapping(PoolId => uint128) internal liquidityState;
    mapping(PoolId => uint160) internal nextSwapSqrtPriceX96;
    mapping(PoolId => uint256) internal nextExactInputPoolInputAmount;
    mapping(PoolId => uint256) internal nextExactOutputAmount;

    struct RouterCallbackPreview {
        address payer;
        address recipient;
        PoolKey key;
        SwapParams params;
        bytes hookData;
    }

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
        bytes32 headWord;
        assembly {
            headWord := calldataload(data.offset)
        }
        if (headWord == bytes32(uint256(0x20))) {
            RouterCallbackPreview memory preview = abi.decode(data, (RouterCallbackPreview));
            lastUnlockCallbackPayer = preview.payer;
        }
        unlocked = true;
        result = IUnlockCallbackLike(msg.sender).unlockCallback(data);
        unlocked = false;
    }

    function setQuoteAlignedSwapMath(bool enabled) external {
        quoteAlignedSwapMath = enabled;
    }

    function setEnforceV4PriceLimitValidation(bool enabled) external {
        enforceV4PriceLimitValidation = enabled;
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
    /// @dev Produces deterministic deltas for local router-harness branch coverage only.
    /// @param key Pool key to swap against.
    /// @param params Swap parameters.
    /// @param hookData Opaque hook data forwarded into the mock hook callbacks.
    /// @return delta Mock balance delta for the swap.
    function swap(PoolKey memory key, SwapParams memory params, bytes calldata hookData)
        external
        returns (BalanceDelta delta)
    {
        if (!unlocked) revert ManagerLocked();

        PoolId poolId = key.toId();
        // Intentionally matches vendored v4 `Hooks.sol` self-call skip semantics when `msg.sender == address(self)`.
        bool skipHookCallbacks = msg.sender == address(key.hooks);
        BeforeSwapDelta beforeSwapDelta = BeforeSwapDeltaLibrary.ZERO_DELTA;
        int256 amountToSwap = params.amountSpecified;
        if (!skipHookCallbacks) {
            (, beforeSwapDelta,) = key.hooks.beforeSwap(msg.sender, key, params, hookData);
            amountToSwap += beforeSwapDelta.getSpecifiedDelta();
        }

        if (enforceV4PriceLimitValidation) {
            Slot0State memory state = slot0State[poolId];
            if (params.zeroForOne) {
                if (params.sqrtPriceLimitX96 >= state.sqrtPriceX96) {
                    revert PriceLimitAlreadyExceeded(state.sqrtPriceX96, params.sqrtPriceLimitX96);
                }
                if (params.sqrtPriceLimitX96 <= SQRT_PRICE_LOWER_X96) {
                    revert PriceLimitOutOfBounds(params.sqrtPriceLimitX96);
                }
            } else {
                if (params.sqrtPriceLimitX96 <= state.sqrtPriceX96) {
                    revert PriceLimitAlreadyExceeded(state.sqrtPriceX96, params.sqrtPriceLimitX96);
                }
                if (params.sqrtPriceLimitX96 >= SQRT_PRICE_UPPER_X96) {
                    revert PriceLimitOutOfBounds(params.sqrtPriceLimitX96);
                }
            }
        }

        BalanceDelta poolDelta = BalanceDeltaLibrary.ZERO_DELTA;
        if (amountToSwap != 0) {
            if (quoteAlignedSwapMath) {
                Slot0State memory state = slot0State[poolId];
                uint128 liquidity = liquidityState[poolId];
                if (params.amountSpecified < 0) {
                    uint256 inputAmount = uint256(-amountToSwap);
                    uint256 configuredInputAmount = nextExactInputPoolInputAmount[poolId];
                    if (configuredInputAmount != 0) {
                        inputAmount = configuredInputAmount;
                        delete nextExactInputPoolInputAmount[poolId];
                    }
                    uint160 alignedNextSqrtPriceX96 = SqrtPriceMath.getNextSqrtPriceFromInput(
                        state.sqrtPriceX96, liquidity, inputAmount, params.zeroForOne
                    );
                    uint256 outputAmount = params.zeroForOne
                        ? SqrtPriceMath.getAmount1Delta(alignedNextSqrtPriceX96, state.sqrtPriceX96, liquidity, false)
                        : SqrtPriceMath.getAmount0Delta(state.sqrtPriceX96, alignedNextSqrtPriceX96, liquidity, false);
                    poolDelta = params.zeroForOne
                        ? toBalanceDelta(-int128(int256(inputAmount)), int128(int256(outputAmount)))
                        : toBalanceDelta(int128(int256(outputAmount)), -int128(int256(inputAmount)));
                    slot0State[poolId].sqrtPriceX96 = alignedNextSqrtPriceX96;
                    _syncPoolStorage(poolId);
                } else {
                    uint256 outputAmount = uint256(amountToSwap);
                    uint160 alignedNextSqrtPriceX96 = SqrtPriceMath.getNextSqrtPriceFromOutput(
                        state.sqrtPriceX96, liquidity, outputAmount, params.zeroForOne
                    );
                    uint256 inputAmount = params.zeroForOne
                        ? SqrtPriceMath.getAmount0Delta(alignedNextSqrtPriceX96, state.sqrtPriceX96, liquidity, true)
                        : SqrtPriceMath.getAmount1Delta(state.sqrtPriceX96, alignedNextSqrtPriceX96, liquidity, true);
                    poolDelta = params.zeroForOne
                        ? toBalanceDelta(-int128(int256(inputAmount)), int128(int256(outputAmount)))
                        : toBalanceDelta(int128(int256(outputAmount)), -int128(int256(inputAmount)));
                    slot0State[poolId].sqrtPriceX96 = alignedNextSqrtPriceX96;
                    _syncPoolStorage(poolId);
                }
            } else if (params.amountSpecified < 0) {
                uint256 inputAmount = uint256(-amountToSwap);
                uint256 configuredInputAmount = nextExactInputPoolInputAmount[poolId];
                if (configuredInputAmount != 0) {
                    inputAmount = configuredInputAmount;
                    delete nextExactInputPoolInputAmount[poolId];
                }
                uint256 outputAmount = inputAmount / 2;
                if (params.zeroForOne) {
                    poolDelta = toBalanceDelta(-int128(int256(inputAmount)), int128(int256(outputAmount)));
                } else {
                    poolDelta = toBalanceDelta(int128(int256(outputAmount)), -int128(int256(inputAmount)));
                }
            } else {
                uint256 outputAmount = uint256(amountToSwap);
                uint256 configuredOutputAmount = nextExactOutputAmount[poolId];
                if (configuredOutputAmount != 0) {
                    outputAmount = configuredOutputAmount;
                    delete nextExactOutputAmount[poolId];
                }
                uint256 inputAmount = outputAmount * 2;
                if (params.zeroForOne) {
                    poolDelta = toBalanceDelta(-int128(int256(inputAmount)), int128(int256(outputAmount)));
                } else {
                    poolDelta = toBalanceDelta(int128(int256(outputAmount)), -int128(int256(inputAmount)));
                }
            }
        }

        uint160 nextSqrtPriceX96 = nextSwapSqrtPriceX96[poolId];
        if (nextSqrtPriceX96 != 0) {
            slot0State[poolId].sqrtPriceX96 = nextSqrtPriceX96;
            _syncPoolStorage(poolId);
            delete nextSwapSqrtPriceX96[poolId];
        }

        if (skipHookCallbacks) {
            return poolDelta;
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

    /// @notice Overrides the mocked active liquidity for a pool.
    /// @dev Used by router regression tests that need an initialized pool with zero active liquidity.
    /// @param poolId Pool id whose liquidity should be updated.
    /// @param liquidity New mocked active liquidity.
    function setLiquidity(PoolId poolId, uint128 liquidity) external {
        liquidityState[poolId] = liquidity;
        _syncPoolStorage(poolId);
    }

    /// @notice Configures the next post-swap price written into slot0 for a pool.
    /// @dev Used by settlement regression tests to simulate realized price movement.
    /// @param poolId Pool whose next swap should update price.
    /// @param sqrtPriceX96 Price to write after the next swap.
    function setNextSwapSqrtPriceX96(PoolId poolId, uint160 sqrtPriceX96) external {
        nextSwapSqrtPriceX96[poolId] = sqrtPriceX96;
    }

    function setNextExactInputPoolInputAmount(PoolId poolId, uint256 inputAmount) external {
        nextExactInputPoolInputAmount[poolId] = inputAmount;
    }

    function setNextExactOutputAmount(PoolId poolId, uint256 outputAmount) external {
        nextExactOutputAmount[poolId] = outputAmount;
    }

    function lastUnlockPayer() external view returns (address payer) {
        return lastUnlockCallbackPayer;
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
    constructor(IPoolManager _manager, address _owner, address _treasury)
        MemeverseUniswapHook(_manager, _owner, _treasury)
    {}

    function seedActiveLiquidityShares(PoolKey memory key, address owner, uint256 activeShares) external {
        PoolId id = key.toId();
        address liquidityToken = poolInfo[id].liquidityToken;
        if (liquidityToken == address(0)) revert PoolNotInitialized();

        if (cachedLpTotalSupply[id] == 0) {
            UniswapLP(liquidityToken).mint(address(0), MINIMUM_LIQUIDITY);
            cachedLpTotalSupply[id] = MINIMUM_LIQUIDITY;
        }

        UniswapLP(liquidityToken).mint(owner, activeShares);
        cachedLpTotalSupply[id] += activeShares;
    }

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
    /// @param deadline Latest valid timestamp for the call.
    /// @param amountOutMinimum Minimum acceptable output amount.
    /// @param amountInMaximum Maximum acceptable input amount.
    /// @param hookData Opaque hook data forwarded to the router.
    /// @return delta Final swap delta returned by the router.
    function attemptSwap(
        PoolKey calldata key,
        SwapParams calldata params,
        address recipient,
        uint256 deadline,
        uint256 amountOutMinimum,
        uint256 amountInMaximum,
        bytes calldata hookData
    ) external returns (BalanceDelta delta) {
        return router.swap(key, params, recipient, deadline, amountOutMinimum, amountInMaximum, hookData);
    }
}

contract MockLauncherForRouterProtectionTest {
    mapping(bytes32 => bool) internal blockedPairs;

    function setPublicSwapBlocked(address tokenA, address tokenB, bool blocked) external {
        blockedPairs[_pairKey(tokenA, tokenB)] = blocked;
    }

    function isPublicSwapAllowed(address tokenA, address tokenB) external view returns (bool) {
        return !blockedPairs[_pairKey(tokenA, tokenB)];
    }

    function _pairKey(address tokenA, address tokenB) internal pure returns (bytes32) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        return keccak256(abi.encode(token0, token1));
    }
}

contract DirectProtectedSwapCaller {
    MockPoolManagerForRouterTest internal immutable manager;

    constructor(MockPoolManagerForRouterTest _manager) {
        manager = _manager;
    }

    function swapDirect(PoolKey calldata key, SwapParams calldata params) external returns (BalanceDelta delta) {
        delta = abi.decode(manager.unlock(abi.encode(key, params)), (BalanceDelta));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory result) {
        (PoolKey memory key, SwapParams memory params) = abi.decode(data, (PoolKey, SwapParams));
        result = abi.encode(manager.swap(key, params, ""));
    }
}

/// @dev Test boundary:
/// - These cases lock router-side behavior under the local manager mock.
/// - They do not establish real market execution, partial-fill economics, rollback guarantees,
///   or fee-side correctness beyond this deterministic harness.
contract MemeverseSwapRouterTest is Test {
    using PoolIdLibrary for PoolKey;

    event EmergencyFlagUpdated(bool oldFlag, bool newFlag);

    uint160 internal constant SQRT_PRICE_1_1 = 79228162514264337593543950336;
    uint160 internal constant FULL_RANGE_MIN_SQRT_PRICE_X96 = 4_310_618_292;
    uint160 internal constant FULL_RANGE_MAX_SQRT_PRICE_X96 =
        1_456_195_216_270_955_103_206_513_029_158_776_779_468_408_838_535;
    uint256 internal constant ALICE_PK = 0xA11CE;
    bytes4 internal constant PUBLIC_SWAP_DISABLED_SELECTOR = bytes4(keccak256("PublicSwapDisabled()"));

    MockPoolManagerForRouterTest internal manager;
    TestableMemeverseUniswapHookForRouter internal hook;
    MemeverseSwapRouter internal router;
    MockERC20 internal token0;
    MockERC20 internal token1;
    address internal treasury;
    address internal alice;
    PoolKey internal key;
    PoolId internal poolId;

    function _setPublicSwapResumeTime(address targetHook, address tokenA, address tokenB, uint40 resumeTime)
        internal
        returns (bool ok, bytes memory data)
    {
        return targetHook.call(
            abi.encodeWithSignature("setPublicSwapResumeTime(address,address,uint40)", tokenA, tokenB, resumeTime)
        );
    }

    function _readPublicSwapResumeTime(address targetHook, PoolId targetPoolId)
        internal
        view
        returns (bool ok, uint40 resumeTime)
    {
        (bool success, bytes memory data) =
            targetHook.staticcall(abi.encodeWithSignature("publicSwapResumeTime(bytes32)", targetPoolId));
        if (!success || data.length != 32) return (false, 0);
        return (true, abi.decode(data, (uint40)));
    }

    /// @notice Deploys the mock manager, hook, router, and test tokens.
    /// @dev Seeds balances and approvals used throughout the router test suite.
    function setUp() public {
        manager = new MockPoolManagerForRouterTest();
        treasury = makeAddr("treasury");
        alice = vm.addr(ALICE_PK);
        hook = new TestableMemeverseUniswapHookForRouter(IPoolManager(address(manager)), address(this), treasury);
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
        hook.seedActiveLiquidityShares(key, address(this), 1e18);
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

    function _validExecutionPriceLimit(bool zeroForOne) internal pure returns (uint160) {
        return zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;
    }

    function _dynamicPoolKeyForHook(address hookAddress, Currency currency0, Currency currency1)
        internal
        pure
        returns (PoolKey memory)
    {
        return PoolKey({
            currency0: currency0, currency1: currency1, fee: 0x800000, tickSpacing: 200, hooks: IHooks(hookAddress)
        });
    }

    /// @notice Verifies hook deployment rejects a zero treasury address.
    /// @dev Covers constructor validation.
    function testConstructor_RevertsWhenTreasuryIsZeroAddress() external {
        vm.expectRevert(IMemeverseUniswapHook.ZeroAddress.selector);
        new TestableMemeverseUniswapHookForRouter(IPoolManager(address(manager)), address(this), address(0));
    }

    /// @notice Verifies explicit launcher binding rejects the zero address.
    /// @dev Launch settlement authorization now depends only on the launcher binding.
    function testSetLauncher_RevertsOnZeroAddress() external {
        vm.expectRevert(IMemeverseUniswapHook.ZeroAddress.selector);
        hook.setLauncher(address(0));
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
            block.timestamp,
            0,
            100 ether,
            ""
        );
    }

    /// @notice Covers the local manager revert surface for execution swaps that pass a zero price limit.
    /// @dev Locks that the router forwards `sqrtPriceLimitX96` into the mock execution path instead of silently bypassing it.
    function testSwapReverts_WhenExecutionPriceLimitIsZero() external {
        _setProtocolFeeCurrency(key.currency0);
        _matureLaunchWindow();
        manager.setEnforceV4PriceLimitValidation(true);

        vm.expectRevert(abi.encodeWithSelector(MockPoolManagerForRouterTest.PriceLimitOutOfBounds.selector, uint160(0)));
        router.swap(
            key,
            SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}),
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

    /// @notice Verifies emergency mode still allows healthy-pool exact-output execution at the base fee.
    /// @dev Protects the `beforeSwap` emergency fallback from routing exact-output swaps into the zero-liquidity quick return.
    function testSwapPass_WhenEmergencyFlagEnabled_ExactOutputStillExecutes() external {
        _setProtocolFeeCurrency(key.currency0);
        _matureLaunchWindow();
        hook.setEmergencyFlag(true);
        manager.setQuoteAlignedSwapMath(true);

        IMemeverseUniswapHook.SwapQuote memory quote =
            hook.quoteSwap(key, SwapParams({zeroForOne: true, amountSpecified: 100 ether, sqrtPriceLimitX96: 0}));
        uint256 balance0Before = token0.balanceOf(address(this));
        uint256 balance1Before = token1.balanceOf(address(this));
        uint256 treasury0Before = token0.balanceOf(treasury);
        uint160 priceLimit = uint160((uint256(SQRT_PRICE_1_1) * 99) / 100);

        BalanceDelta delta = router.swap(
            key,
            SwapParams({zeroForOne: true, amountSpecified: 100 ether, sqrtPriceLimitX96: priceLimit}),
            address(this),
            block.timestamp,
            0,
            quote.estimatedUserInputAmount,
            ""
        );

        assertEq(quote.feeBps, 100, "base fee only");
        assertEq(token1.balanceOf(address(this)) - balance1Before, 100 ether, "exact output received");
        assertEq(balance0Before - token0.balanceOf(address(this)), quote.estimatedUserInputAmount, "quote guardrail");
        assertGt(token0.balanceOf(treasury) - treasury0Before, 0, "treasury collected");
        assertEq(delta.amount1(), int128(int256(100 ether)), "delta1");
    }

    /// @notice Covers the emergency exact-output branch where the local harness still routes output-side fee accounting.
    /// @dev Locks router-side handling under the local manager harness; integration tests cover real output-fee execution semantics.
    function testSwapPass_WhenEmergencyFlagEnabled_ZeroForOneExactOutput_OutputSideProtocolFeeStillGrossesUp()
        external
    {
        _setProtocolFeeCurrency(key.currency1);
        _matureLaunchWindow();
        hook.setEmergencyFlag(true);
        manager.setQuoteAlignedSwapMath(true);

        IMemeverseUniswapHook.SwapQuote memory quote =
            hook.quoteSwap(key, SwapParams({zeroForOne: true, amountSpecified: 100 ether, sqrtPriceLimitX96: 0}));
        uint256 balance0Before = token0.balanceOf(address(this));
        uint256 balance1Before = token1.balanceOf(address(this));
        uint256 treasury1Before = token1.balanceOf(treasury);
        uint160 priceLimit = uint160((uint256(SQRT_PRICE_1_1) * 99) / 100);

        BalanceDelta delta = router.swap(
            key,
            SwapParams({zeroForOne: true, amountSpecified: 100 ether, sqrtPriceLimitX96: priceLimit}),
            address(this),
            block.timestamp,
            0,
            quote.estimatedUserInputAmount,
            ""
        );

        assertEq(quote.feeBps, 100, "base fee only");
        assertFalse(quote.protocolFeeOnInput, "protocolFeeOnInput");
        assertGt(quote.estimatedProtocolFeeAmount, 0, "output fee quoted");
        assertEq(quote.estimatedUserOutputAmount, 100 ether, "quoted net output");
        assertEq(token1.balanceOf(address(this)) - balance1Before, 100 ether, "exact net output");
        assertEq(balance0Before - token0.balanceOf(address(this)), quote.estimatedUserInputAmount, "quote guardrail");
        assertEq(token1.balanceOf(treasury) - treasury1Before, quote.estimatedProtocolFeeAmount, "treasury collected");
        assertEq(delta.amount1(), int128(int256(100 ether)), "delta1 net output");
    }

    /// @notice Verifies the emergency output-side fee exact-output path is symmetric for one-for-zero swaps.
    /// @dev Locks gross-output quoting for pools that charge protocol fees in currency0.
    function testSwapPass_WhenEmergencyFlagEnabled_OneForZeroExactOutput_OutputSideProtocolFeeStillGrossesUp()
        external
    {
        _setProtocolFeeCurrency(key.currency0);
        _matureLaunchWindow();
        manager.setQuoteAlignedSwapMath(true);
        router.swap(
            key,
            SwapParams({
                zeroForOne: false, amountSpecified: -10_000 ether, sqrtPriceLimitX96: _validExecutionPriceLimit(false)
            }),
            address(this),
            block.timestamp,
            0,
            10_000 ether,
            ""
        );

        IMemeverseUniswapHook.SwapQuote memory normalQuote =
            hook.quoteSwap(key, SwapParams({zeroForOne: false, amountSpecified: 100 ether, sqrtPriceLimitX96: 0}));
        hook.setEmergencyFlag(true);
        IMemeverseUniswapHook.SwapQuote memory emergencyQuote =
            hook.quoteSwap(key, SwapParams({zeroForOne: false, amountSpecified: 100 ether, sqrtPriceLimitX96: 0}));
        uint256 balance0Before = token0.balanceOf(address(this));
        uint256 balance1Before = token1.balanceOf(address(this));
        uint256 treasury0Before = token0.balanceOf(treasury);
        uint160 priceLimit = uint160((uint256(SQRT_PRICE_1_1) * 101) / 100);

        BalanceDelta delta = router.swap(
            key,
            SwapParams({zeroForOne: false, amountSpecified: 100 ether, sqrtPriceLimitX96: priceLimit}),
            address(this),
            block.timestamp,
            0,
            emergencyQuote.estimatedUserInputAmount,
            ""
        );

        assertGt(normalQuote.feeBps, emergencyQuote.feeBps, "emergency fee should collapse to base");
        assertEq(emergencyQuote.feeBps, 100, "base fee only");
        assertFalse(emergencyQuote.protocolFeeOnInput, "protocolFeeOnInput");
        assertGt(emergencyQuote.estimatedProtocolFeeAmount, 0, "output fee quoted");
        assertEq(emergencyQuote.estimatedUserOutputAmount, 100 ether, "quoted net output");
        assertEq(token0.balanceOf(address(this)) - balance0Before, 100 ether, "exact net output");
        assertEq(
            balance1Before - token1.balanceOf(address(this)), emergencyQuote.estimatedUserInputAmount, "quote guardrail"
        );
        assertEq(
            token0.balanceOf(treasury) - treasury0Before,
            emergencyQuote.estimatedProtocolFeeAmount,
            "treasury collected"
        );
        assertEq(delta.amount0(), int128(int256(100 ether)), "delta0 net output");
    }

    /// @notice Verifies emergency-mode exact-output output-side fees stay aligned while a non-base launch floor is active.
    /// @dev Locks the case where normal-mode dynamic fee rises above the configured launch floor but emergency collapses back to it.
    function testSwapPass_WhenEmergencyFlagEnabled_ExactOutput_OutputSideProtocolFeeStaysAlignedUnderLaunchFloor()
        external
    {
        SwapParams memory params = SwapParams({zeroForOne: true, amountSpecified: 10_000 ether, sqrtPriceLimitX96: 0});
        hook.setDefaultLaunchFeeConfig(
            IMemeverseUniswapHook.LaunchFeeConfig({startFeeBps: 300, minFeeBps: 300, decayDurationSeconds: 900})
        );
        _setProtocolFeeCurrency(key.currency1);
        manager.setQuoteAlignedSwapMath(true);
        hook.setLauncher(address(this));
        token0.approve(address(hook), type(uint256).max);
        manager.setNextSwapSqrtPriceX96(poolId, uint160((uint256(SQRT_PRICE_1_1) * 120) / 100));
        hook.executeLaunchSettlement(
            IMemeverseUniswapHook.LaunchSettlementParams({
                key: key,
                params: SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}),
                recipient: address(this)
            })
        );

        IMemeverseUniswapHook.SwapQuote memory normalQuote = hook.quoteSwap(key, params);
        hook.setEmergencyFlag(true);
        IMemeverseUniswapHook.SwapQuote memory emergencyQuote = hook.quoteSwap(key, params);
        uint256 balance0Before = token0.balanceOf(address(this));
        uint256 balance1Before = token1.balanceOf(address(this));
        uint256 treasury1Before = token1.balanceOf(treasury);

        BalanceDelta delta =
            router.swap(key, params, address(this), block.timestamp, 0, emergencyQuote.estimatedUserInputAmount, "");

        assertGt(normalQuote.feeBps, emergencyQuote.feeBps, "emergency fee should collapse to launch floor");
        assertFalse(emergencyQuote.protocolFeeOnInput, "protocolFeeOnInput");
        assertEq(emergencyQuote.feeBps, 300, "launch fee floor");
        assertGt(emergencyQuote.estimatedProtocolFeeAmount, 0, "output fee quoted");
        assertEq(emergencyQuote.estimatedUserOutputAmount, 10_000 ether, "quoted net output");
        assertEq(token1.balanceOf(address(this)) - balance1Before, 10_000 ether, "exact net output");
        assertEq(
            balance0Before - token0.balanceOf(address(this)), emergencyQuote.estimatedUserInputAmount, "quote guardrail"
        );
        assertEq(
            token1.balanceOf(treasury) - treasury1Before,
            emergencyQuote.estimatedProtocolFeeAmount,
            "treasury collected"
        );
        assertEq(delta.amount1(), int128(int256(10_000 ether)), "delta1 net output");
    }

    /// @notice Verifies native protocol-fee pools now fail before reaching treasury handling.
    function testSwapReverts_WhenProtocolFeePoolUsesNativeCurrency() external {
        PoolKey memory nativeKey = _dynamicPoolKey(CurrencyLibrary.ADDRESS_ZERO, Currency.wrap(address(token1)));
        vm.expectRevert();
        router.swap(
            nativeKey,
            SwapParams({zeroForOne: true, amountSpecified: 100 ether, sqrtPriceLimitX96: 0}),
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

    /// @notice Verifies direct ERC20 swaps enter the manager unlock with router-prefunded input.
    /// @dev The simplified shared `_swap()` core should use router balance for regular swaps too.
    function testSwap_RegularPathUsesRouterAsUnlockPayer() external {
        _setProtocolFeeCurrency(key.currency0);
        _matureLaunchWindow();

        router.swap(
            key,
            SwapParams({
                zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: _validExecutionPriceLimit(true)
            }),
            address(this),
            block.timestamp,
            0,
            100 ether,
            ""
        );

        assertEq(manager.lastUnlockPayer(), address(router), "router should prefund regular swaps");
        assertEq(token0.balanceOf(address(router)), 0, "router should not retain input");
    }

    /// @notice Verifies the regular ERC20 swap path stays below the current gas ceiling.
    /// @dev This captures the router-only gas cleanup target without changing swap semantics.
    function testSwap_RegularPathGasStaysBelowCeiling() external {
        _setProtocolFeeCurrency(key.currency0);
        _matureLaunchWindow();

        uint256 gasBefore = gasleft();
        BalanceDelta delta = router.swap(
            key,
            SwapParams({
                zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: _validExecutionPriceLimit(true)
            }),
            address(this),
            block.timestamp,
            0,
            100 ether,
            ""
        );
        uint256 gasUsed = gasBefore - gasleft();

        assertLt(int256(delta.amount0()), 0, "delta0");
        assertGt(int256(delta.amount1()), 0, "delta1");
        assertLt(gasUsed, 555_000, "swap gas ceiling");
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
            block.timestamp,
            40 ether,
            100 ether,
            ""
        );

        assertLt(delta.amount0(), 0, "delta0");
        assertGt(delta.amount1(), 0, "delta1");
    }

    /// @notice Verifies router swaps revert during the post-unlock protection window.
    /// @dev Protection now comes from hook-local pool state, not a launcher pair verdict.
    function testSwap_RevertsDuringPostUnlockProtectionWindow() external {
        MockPoolManagerForRouterTest guardedManager = new MockPoolManagerForRouterTest();
        TestableMemeverseUniswapHookForRouter guardedHook =
            new TestableMemeverseUniswapHookForRouter(IPoolManager(address(guardedManager)), address(this), treasury);
        MemeverseSwapRouter guardedRouter = new MemeverseSwapRouter(
            IPoolManager(address(guardedManager)),
            IMemeverseUniswapHook(address(guardedHook)),
            IPermit2(address(0xBEEF))
        );
        PoolKey memory guardedKey = _dynamicPoolKeyForHook(
            address(guardedHook), Currency.wrap(address(token0)), Currency.wrap(address(token1))
        );

        guardedHook.setLauncher(address(this));
        guardedManager.initialize(guardedKey, SQRT_PRICE_1_1);
        guardedHook.setProtocolFeeCurrency(guardedKey.currency0);
        (bool setOk, bytes memory setData) = _setPublicSwapResumeTime(
            address(guardedHook), address(token0), address(token1), uint40(block.timestamp + 1 hours)
        );
        assertTrue(setOk, string(setData));
        token0.mint(address(guardedManager), 1_000_000 ether);
        token1.mint(address(guardedManager), 1_000_000 ether);
        token0.approve(address(guardedRouter), type(uint256).max);
        token1.approve(address(guardedRouter), type(uint256).max);

        uint160 priceLimit = uint160((uint256(SQRT_PRICE_1_1) * 99) / 100);
        vm.expectRevert(PUBLIC_SWAP_DISABLED_SELECTOR);
        guardedRouter.swap(
            guardedKey,
            SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: priceLimit}),
            address(this),
            block.timestamp,
            0,
            100 ether,
            ""
        );
    }

    /// @notice Verifies a blocked pool does not leak protection to unrelated pools.
    /// @dev `publicSwapResumeTime == 0` must remain a no-op for other pool ids.
    function testSwap_LocalProtectionBlocksOnlyTargetPool() external {
        MockPoolManagerForRouterTest guardedManager = new MockPoolManagerForRouterTest();
        TestableMemeverseUniswapHookForRouter guardedHook =
            new TestableMemeverseUniswapHookForRouter(IPoolManager(address(guardedManager)), address(this), treasury);
        MemeverseSwapRouter guardedRouter = new MemeverseSwapRouter(
            IPoolManager(address(guardedManager)),
            IMemeverseUniswapHook(address(guardedHook)),
            IPermit2(address(0xBEEF))
        );
        MockERC20 otherToken = new MockERC20("Token2", "TK2", 18);
        otherToken.mint(address(this), 1_000_000 ether);
        otherToken.mint(address(guardedManager), 1_000_000 ether);

        PoolKey memory blockedKey = _dynamicPoolKeyForHook(
            address(guardedHook), Currency.wrap(address(token0)), Currency.wrap(address(token1))
        );
        PoolKey memory openKey = _dynamicPoolKeyForHook(
            address(guardedHook), Currency.wrap(address(otherToken)), Currency.wrap(address(token1))
        );

        guardedHook.setLauncher(address(this));
        guardedManager.initialize(blockedKey, SQRT_PRICE_1_1);
        guardedManager.initialize(openKey, SQRT_PRICE_1_1);
        guardedHook.seedActiveLiquidityShares(blockedKey, address(this), 1e18);
        guardedHook.seedActiveLiquidityShares(openKey, address(this), 1e18);
        guardedHook.setProtocolFeeCurrency(blockedKey.currency0);
        guardedHook.setProtocolFeeCurrency(openKey.currency0);
        (bool setOk, bytes memory setData) = _setPublicSwapResumeTime(
            address(guardedHook), address(token0), address(token1), uint40(block.timestamp + 1 hours)
        );
        assertTrue(setOk, string(setData));
        (bool readOk, uint40 resumeTime) = _readPublicSwapResumeTime(address(guardedHook), blockedKey.toId());
        assertTrue(readOk, "resume getter missing");
        assertEq(resumeTime, uint40(block.timestamp + 1 hours), "resume time stored");

        token0.mint(address(guardedManager), 1_000_000 ether);
        token1.mint(address(guardedManager), 1_000_000 ether);
        token0.approve(address(guardedRouter), type(uint256).max);
        token1.approve(address(guardedRouter), type(uint256).max);
        otherToken.approve(address(guardedRouter), type(uint256).max);

        vm.expectRevert(PUBLIC_SWAP_DISABLED_SELECTOR);
        guardedRouter.swap(
            blockedKey,
            SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}),
            address(this),
            block.timestamp,
            0,
            100 ether,
            ""
        );

        BalanceDelta openDelta = guardedRouter.swap(
            openKey,
            SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}),
            address(this),
            block.timestamp,
            0,
            100 ether,
            ""
        );
        assertLt(openDelta.amount0(), 0, "open pool should swap");
        assertGt(openDelta.amount1(), 0, "open pool output");
    }

    /// @notice Verifies explicit launch settlement can only be initiated by the configured launcher.
    /// @dev Settlement no longer routes through router marker swap mode.
    function testExecuteLaunchSettlement_RevertsWhenCallerIsNotLauncher() external {
        _setProtocolFeeCurrency(key.currency0);
        uint160 priceLimit = uint160((uint256(SQRT_PRICE_1_1) * 99) / 100);
        hook.setLauncher(address(this));

        vm.prank(alice);
        vm.expectRevert(IMemeverseUniswapHook.Unauthorized.selector);
        hook.executeLaunchSettlement(
            IMemeverseUniswapHook.LaunchSettlementParams({
                key: key,
                params: SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: priceLimit}),
                recipient: address(this)
            })
        );
    }

    /// @notice Verifies explicit launch settlement uses fixed 1% economics.
    /// @dev Confirms the treasury receives the 30% protocol slice of the fixed fee.
    function testExecuteLaunchSettlement_UsesFixedOnePercentFee() external {
        _setProtocolFeeCurrency(key.currency0);
        uint160 priceLimit = uint160((uint256(SQRT_PRICE_1_1) * 99) / 100);
        uint256 treasury0Before = token0.balanceOf(treasury);
        hook.setLauncher(address(this));
        token0.approve(address(hook), type(uint256).max);

        IMemeverseUniswapHook.SwapQuote memory quoteAtLaunch = hook.quoteSwap(
            key, SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: priceLimit})
        );
        assertEq(quoteAtLaunch.feeBps, 5000, "public launch fee");

        BalanceDelta delta = hook.executeLaunchSettlement(
            IMemeverseUniswapHook.LaunchSettlementParams({
                key: key,
                params: SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: priceLimit}),
                recipient: address(this)
            })
        );

        assertLt(delta.amount0(), 0, "delta0");
        assertGt(delta.amount1(), 0, "delta1");
        assertEq(token0.balanceOf(treasury) - treasury0Before, 0.3 ether, "fixed 1% protocol fee");
    }

    /// @notice Verifies explicit launch settlement on an output-fee pool only collects the output-side protocol fee once.
    /// @dev The treasury/output balances should match a single 30 bps output fee on the post-LP-fee swap output.
    function testExecuteLaunchSettlement_OutputSideProtocolFeeCollectedExactlyOnce() external {
        _setProtocolFeeCurrency(key.currency1);
        hook.setLauncher(address(this));
        token0.approve(address(hook), type(uint256).max);

        uint256 sender1Before = token1.balanceOf(address(this));
        uint256 treasury0Before = token0.balanceOf(treasury);
        uint256 treasury1Before = token1.balanceOf(treasury);
        uint160 priceLimit = uint160((uint256(SQRT_PRICE_1_1) * 99) / 100);

        BalanceDelta delta = hook.executeLaunchSettlement(
            IMemeverseUniswapHook.LaunchSettlementParams({
                key: key,
                params: SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: priceLimit}),
                recipient: address(this)
            })
        );

        assertEq(token0.balanceOf(treasury) - treasury0Before, 0, "no input-side protocol fee");
        assertEq(token1.balanceOf(treasury) - treasury1Before, 0.14895 ether, "single output-side protocol fee");
        assertEq(token1.balanceOf(address(this)) - sender1Before, 49.50105 ether, "recipient gets net output once");
        assertEq(delta.amount0(), -int128(int256(99.3 ether)), "delta0 tracks post-LP-fee swap input");
        assertEq(delta.amount1(), int128(int256(49.50105 ether)), "delta1 reduced by one output-side fee");
    }

    /// @notice Verifies changing launch-fee floor does not change explicit settlement pricing.
    /// @dev Settlement remains fixed-fee while public swaps still use launch fee schedule.
    function testExecuteLaunchSettlement_IgnoresConfigurableLaunchFeeFloor() external {
        _setProtocolFeeCurrency(key.currency0);
        hook.setDefaultLaunchFeeConfig(
            IMemeverseUniswapHook.LaunchFeeConfig({startFeeBps: 4000, minFeeBps: 300, decayDurationSeconds: 900})
        );
        hook.setLauncher(address(this));
        token0.approve(address(hook), type(uint256).max);

        uint160 priceLimit = uint160((uint256(SQRT_PRICE_1_1) * 99) / 100);
        uint256 treasury0Before = token0.balanceOf(treasury);

        BalanceDelta delta = hook.executeLaunchSettlement(
            IMemeverseUniswapHook.LaunchSettlementParams({
                key: key,
                params: SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: priceLimit}),
                recipient: address(this)
            })
        );

        assertLt(delta.amount0(), 0, "delta0");
        assertGt(delta.amount1(), 0, "delta1");
        assertEq(token0.balanceOf(treasury) - treasury0Before, 0.3 ether, "settlement remains fixed 1%");
    }

    /// @notice Verifies explicit settlement updates dynamic-fee state even though the pool-manager self-call skips hook callbacks.
    /// @dev The immediate follow-up quote should observe carried short/volatility state, not a pristine fee engine.
    function testExecuteLaunchSettlement_UpdatesDynamicFeeStateAndSubsequentQuote() external {
        _setProtocolFeeCurrency(key.currency0);
        hook.setLauncher(address(this));
        hook.setDefaultLaunchFeeConfig(
            IMemeverseUniswapHook.LaunchFeeConfig({startFeeBps: 100, minFeeBps: 100, decayDurationSeconds: 1})
        );
        token0.approve(address(hook), type(uint256).max);

        uint160 postSettlementPrice = uint160((uint256(SQRT_PRICE_1_1) * 120) / 100);
        manager.setNextSwapSqrtPriceX96(poolId, postSettlementPrice);

        hook.executeLaunchSettlement(
            IMemeverseUniswapHook.LaunchSettlementParams({
                key: key,
                params: SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}),
                recipient: address(this)
            })
        );

        (
            uint256 weightedVolume0,
            uint256 weightedPriceVolume0,
            uint256 ewVWAPX18,,,
            uint24 volDeviationAccumulator,,
            uint24 shortImpactPpm,
        ) = hook.poolEWVWAPParams(poolId);

        assertGt(weightedVolume0, 0, "weighted volume");
        assertGt(weightedPriceVolume0, 0, "weighted price volume");
        assertGt(ewVWAPX18, 0, "ewvwap");
        assertGt(volDeviationAccumulator, 0, "volatility accumulator");
        assertGt(shortImpactPpm, 0, "short impact");

        MockPoolManagerForRouterTest pristineManager = new MockPoolManagerForRouterTest();
        TestableMemeverseUniswapHookForRouter pristineHook =
            new TestableMemeverseUniswapHookForRouter(IPoolManager(address(pristineManager)), address(this), treasury);
        PoolKey memory pristineKey = _dynamicPoolKeyForHook(
            address(pristineHook), Currency.wrap(address(token0)), Currency.wrap(address(token1))
        );
        pristineManager.initialize(pristineKey, postSettlementPrice);
        pristineHook.seedActiveLiquidityShares(pristineKey, address(this), 1e18);
        pristineHook.setProtocolFeeCurrency(pristineKey.currency0);
        pristineHook.setDefaultLaunchFeeConfig(
            IMemeverseUniswapHook.LaunchFeeConfig({startFeeBps: 100, minFeeBps: 100, decayDurationSeconds: 1})
        );

        SwapParams memory followUpParams =
            SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0});
        IMemeverseUniswapHook.SwapQuote memory settledQuote = hook.quoteSwap(key, followUpParams);
        IMemeverseUniswapHook.SwapQuote memory pristineQuote = pristineHook.quoteSwap(pristineKey, followUpParams);

        assertGt(settledQuote.feeBps, pristineQuote.feeBps, "settlement quote should carry dynamic state");
    }

    /// @notice Verifies direct/custom swap paths are also blocked during the protection window.
    /// @dev This adversarial path bypasses the router and proves the hook gate is the true enforcement layer.
    function testDirectPoolManagerSwap_RevertsDuringPostUnlockProtectionWindow() external {
        MockPoolManagerForRouterTest guardedManager = new MockPoolManagerForRouterTest();
        TestableMemeverseUniswapHookForRouter guardedHook =
            new TestableMemeverseUniswapHookForRouter(IPoolManager(address(guardedManager)), address(this), treasury);
        new MemeverseSwapRouter(
            IPoolManager(address(guardedManager)),
            IMemeverseUniswapHook(address(guardedHook)),
            IPermit2(address(0xBEEF))
        );
        PoolKey memory guardedKey = _dynamicPoolKeyForHook(
            address(guardedHook), Currency.wrap(address(token0)), Currency.wrap(address(token1))
        );
        DirectProtectedSwapCaller directCaller = new DirectProtectedSwapCaller(guardedManager);

        guardedHook.setLauncher(address(this));
        guardedManager.initialize(guardedKey, SQRT_PRICE_1_1);
        guardedHook.setProtocolFeeCurrency(guardedKey.currency0);
        (bool setOk, bytes memory setData) = _setPublicSwapResumeTime(
            address(guardedHook), address(token0), address(token1), uint40(block.timestamp + 1 hours)
        );
        assertTrue(setOk, string(setData));
        token0.mint(address(guardedManager), 1_000_000 ether);
        token1.mint(address(guardedManager), 1_000_000 ether);

        uint160 priceLimit = uint160((uint256(SQRT_PRICE_1_1) * 99) / 100);
        vm.expectRevert(PUBLIC_SWAP_DISABLED_SELECTOR);
        directCaller.swapDirect(
            guardedKey, SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: priceLimit})
        );
    }

    /// @notice Covers the basic one-for-zero exact-input routing branch under the local manager harness.
    /// @dev This is plumbing coverage for the routed mock path, not proof of production execution quality.
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

    /// @notice Covers the mock harness branch for zero-for-one exact-input output-side fee accounting.
    /// @dev Locks router-side handling under deterministic local manager deltas.
    function testSwapPass_ZeroForOneExactInput_OutputSideProtocolFee() external {
        _setProtocolFeeCurrency(key.currency1);
        uint256 balance1Before = token1.balanceOf(address(this));
        uint256 treasury1Before = token1.balanceOf(treasury);
        uint160 priceLimit = uint160((uint256(SQRT_PRICE_1_1) * 99) / 100);

        BalanceDelta delta = router.swap(
            key,
            SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: priceLimit}),
            address(this),
            block.timestamp,
            20 ether,
            100 ether,
            ""
        );

        assertGt(token1.balanceOf(address(this)), balance1Before, "token1 received");
        assertLt(delta.amount1(), int128(int256(50 ether)), "output reduced by output-side fee");
        assertGt(token1.balanceOf(treasury), treasury1Before, "treasury collected token1");
    }

    /// @notice Covers the mock harness branch for one-for-zero exact-input output-side fee accounting.
    /// @dev Locks router-side handling under deterministic local manager deltas.
    function testSwapPass_OneForZeroExactInput_OutputSideProtocolFee() external {
        _setProtocolFeeCurrency(key.currency0);
        uint256 balance0Before = token0.balanceOf(address(this));
        uint256 treasury0Before = token0.balanceOf(treasury);
        uint160 priceLimit = uint160((uint256(SQRT_PRICE_1_1) * 101) / 100);

        BalanceDelta delta = router.swap(
            key,
            SwapParams({zeroForOne: false, amountSpecified: -100 ether, sqrtPriceLimitX96: priceLimit}),
            address(this),
            block.timestamp,
            20 ether,
            100 ether,
            ""
        );

        assertGt(token0.balanceOf(address(this)), balance0Before, "token0 received");
        assertLt(delta.amount0(), int128(int256(50 ether)), "output reduced by output-side fee");
        assertGt(token0.balanceOf(treasury), treasury0Before, "treasury collected token0");
    }

    /// @notice Covers the zero-for-one exact-output branch with input-side fee handling under the local manager harness.
    /// @dev This locks router bookkeeping against deterministic mock deltas rather than proving real execution economics.
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

    /// @notice Verifies exact-output ERC20 swaps refund unused prefunded input.
    /// @dev The router should prefund `amountInMaximum`, spend only the realized input, then return the remainder.
    function testSwap_ExactOutputRefundsUnusedPrefundedInput() external {
        _setProtocolFeeCurrency(key.currency0);
        uint256 balance0Before = token0.balanceOf(address(this));
        uint256 amountInMaximum = 500 ether;

        router.swap(
            key,
            SwapParams({
                zeroForOne: true, amountSpecified: 100 ether, sqrtPriceLimitX96: _validExecutionPriceLimit(true)
            }),
            address(this),
            block.timestamp,
            0,
            amountInMaximum,
            ""
        );

        assertEq(manager.lastUnlockPayer(), address(router), "router should pay exact-output input");
        assertEq(balance0Before - token0.balanceOf(address(this)), 300 ether, "unused input refunded");
        assertEq(token0.balanceOf(address(router)), 0, "router should not retain refunded input");
    }

    /// @notice Covers the one-for-zero exact-output branch with input-side fee handling under the local manager harness.
    /// @dev This locks router bookkeeping against deterministic mock deltas rather than proving real execution economics.
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

    /// @notice Covers the mock harness branch for zero-for-one exact-output output-side fee gross-up handling.
    /// @dev Locks router-side gross-up bookkeeping under deterministic local manager deltas.
    function testSwapPass_ZeroForOneExactOutput_OutputSideProtocolFeeGrossesUp() external {
        _setProtocolFeeCurrency(key.currency1);
        _matureLaunchWindow();
        uint256 balance0Before = token0.balanceOf(address(this));
        uint256 balance1Before = token1.balanceOf(address(this));
        uint256 treasury1Before = token1.balanceOf(treasury);
        uint160 priceLimit = uint160((uint256(SQRT_PRICE_1_1) * 99) / 100);

        BalanceDelta delta = router.swap(
            key,
            SwapParams({zeroForOne: true, amountSpecified: 100 ether, sqrtPriceLimitX96: priceLimit}),
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

    /// @notice Covers the mock harness branch for one-for-zero exact-output output-side fee gross-up handling.
    /// @dev Locks router-side gross-up bookkeeping under deterministic local manager deltas.
    function testSwapPass_OneForZeroExactOutput_OutputSideProtocolFeeGrossesUp() external {
        _setProtocolFeeCurrency(key.currency0);
        _matureLaunchWindow();
        uint256 balance0Before = token0.balanceOf(address(this));
        uint256 balance1Before = token1.balanceOf(address(this));
        uint256 treasury0Before = token0.balanceOf(treasury);
        uint160 priceLimit = uint160((uint256(SQRT_PRICE_1_1) * 101) / 100);

        BalanceDelta delta = router.swap(
            key,
            SwapParams({zeroForOne: false, amountSpecified: 100 ether, sqrtPriceLimitX96: priceLimit}),
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

    /// @notice Verifies launch-floor-dominant exact-output swaps can execute with the hook quote guardrail.
    /// @dev Locks quote/output-side floor gross-up so `estimatedUserInputAmount` stays aligned with real swap execution.
    function testSwapPass_ZeroForOneExactOutput_OutputSideLaunchFloorQuoteGuardrailExecutes() external {
        SwapParams memory params = SwapParams({
            zeroForOne: true, amountSpecified: 1 ether, sqrtPriceLimitX96: _validExecutionPriceLimit(true)
        });
        _setProtocolFeeCurrency(key.currency1);
        manager.setQuoteAlignedSwapMath(true);
        IMemeverseUniswapHook.SwapQuote memory quote = hook.quoteSwap(key, params);
        uint256 balance0Before = token0.balanceOf(address(this));
        uint256 balance1Before = token1.balanceOf(address(this));
        uint256 treasury1Before = token1.balanceOf(treasury);

        BalanceDelta delta =
            router.swap(key, params, address(this), block.timestamp, 0, quote.estimatedUserInputAmount, "");

        assertFalse(quote.protocolFeeOnInput, "protocolFeeOnInput");
        assertEq(quote.feeBps, 5000, "launch fee floor");
        assertEq(token1.balanceOf(address(this)) - balance1Before, 1 ether, "exact net output");
        assertEq(balance0Before - token0.balanceOf(address(this)), quote.estimatedUserInputAmount, "quote guardrail");
        assertEq(token1.balanceOf(treasury) - treasury1Before, quote.estimatedProtocolFeeAmount, "floored protocol fee");
        assertEq(delta.amount1(), int128(int256(1 ether)), "delta1 net output");
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
            SwapParams({
                zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: _validExecutionPriceLimit(true)
            }),
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
            block.timestamp,
            0,
            200 ether,
            ""
        );
    }

    /// @notice Covers the local underfill revert surface when the mock execution path returns less than the requested output.
    /// @dev Locks router-side exact-output checks against deterministic harness output instead of caller-provided `amountOutMinimum`.
    function testSwapReverts_WhenExactOutputUnderfillsRequestedAmount() external {
        _setProtocolFeeCurrency(key.currency0);
        manager.setNextExactOutputAmount(poolId, 80 ether);
        uint160 priceLimit = uint160((uint256(SQRT_PRICE_1_1) * 99) / 100);

        vm.expectRevert(
            abi.encodeWithSelector(IMemeverseSwapRouter.OutputAmountBelowMinimum.selector, 80 ether, 100 ether)
        );
        router.swap(
            key,
            SwapParams({zeroForOne: true, amountSpecified: 100 ether, sqrtPriceLimitX96: priceLimit}),
            address(this),
            block.timestamp,
            0,
            300 ether,
            ""
        );
    }

    /// @notice Verifies swaps reject expired deadlines.
    /// @dev Covers the router deadline guard before any swap side effects happen.
    function testSwapReverts_WhenDeadlineExpired() external {
        _setProtocolFeeCurrency(key.currency0);
        vm.expectRevert(IMemeverseSwapRouter.ExpiredPastDeadline.selector);
        router.swap(
            key,
            SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}),
            address(this),
            block.timestamp - 1,
            0,
            100 ether,
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
            block.timestamp,
            60 ether,
            100 ether,
            ""
        );
    }

    /// @notice Covers the local fail-closed branch for exact-input underfills on input-side fee pools.
    /// @dev Uses the mock harness to witness router-facing rollback of payer, treasury, and LP-fee state.
    function testSwapReverts_WhenExactInputPartialFillsOnInputFeePool() external {
        _setProtocolFeeCurrency(key.currency0);
        // Seed non-zero EWVWAP state so rollback assertions are non-trivial.
        router.swap(
            key,
            SwapParams({
                zeroForOne: true, amountSpecified: -10 ether, sqrtPriceLimitX96: _validExecutionPriceLimit(true)
            }),
            address(this),
            block.timestamp,
            0,
            10 ether,
            ""
        );
        _matureLaunchWindow();

        // Scope 1: balances + fee-per-share unchanged (swap reverts, so state is safe to re-check)
        {
            uint256 payer0Before = token0.balanceOf(address(this));
            uint256 payer1Before = token1.balanceOf(address(this));
            uint256 treasury0Before = token0.balanceOf(treasury);
            uint256 treasury1Before = token1.balanceOf(treasury);
            (, uint256 fee0PerShareBefore, uint256 fee1PerShareBefore) = hook.poolInfo(poolId);

            manager.setNextExactInputPoolInputAmount(poolId, 98 ether);
            vm.expectRevert(IMemeverseUniswapHook.ExactInputPartialFill.selector);
            router.swap(
                key,
                SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}),
                address(this),
                block.timestamp,
                0,
                100 ether,
                ""
            );

            assertEq(token0.balanceOf(address(this)), payer0Before, "payer token0 unchanged");
            assertEq(token1.balanceOf(address(this)), payer1Before, "payer token1 unchanged");
            assertEq(token0.balanceOf(treasury), treasury0Before, "treasury token0 unchanged");
            assertEq(token1.balanceOf(treasury), treasury1Before, "treasury token1 unchanged");
            (, uint256 fee0After, uint256 fee1After) = hook.poolInfo(poolId);
            assertEq(fee0After, fee0PerShareBefore, "fee0 per share unchanged");
            assertEq(fee1After, fee1PerShareBefore, "fee1 per share unchanged");
        }

        // Scope 2: EWVWAP state unchanged
        {
            (
                uint256 wv0Before,,
                uint256 ewVWAPBefore,
                uint160 volAnchorBefore,,
                uint24 volDevBefore,,
                uint24 shortImpactBefore,
            ) = hook.poolEWVWAPParams(poolId);

            manager.setNextExactInputPoolInputAmount(poolId, 98 ether);
            vm.expectRevert(IMemeverseUniswapHook.ExactInputPartialFill.selector);
            router.swap(
                key,
                SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}),
                address(this),
                block.timestamp,
                0,
                100 ether,
                ""
            );

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
    }

    /// @notice Covers the mirrored local fail-closed branch for one-for-zero exact-input underfills on input-fee pools.
    /// @dev Uses the mock harness to witness routed rollback symmetry rather than proving full production partial-fill semantics.
    function testSwapReverts_WhenOneForZeroExactInputPartialFillsOnInputFeePool() external {
        _setProtocolFeeCurrency(key.currency1);
        // Seed non-zero EWVWAP state so rollback assertions are non-trivial.
        router.swap(
            key,
            SwapParams({
                zeroForOne: false, amountSpecified: -10 ether, sqrtPriceLimitX96: _validExecutionPriceLimit(false)
            }),
            address(this),
            block.timestamp,
            0,
            10 ether,
            ""
        );
        _matureLaunchWindow();

        // Scope 1: balances + fee-per-share unchanged
        {
            uint256 payer0Before = token0.balanceOf(address(this));
            uint256 payer1Before = token1.balanceOf(address(this));
            uint256 treasury0Before = token0.balanceOf(treasury);
            uint256 treasury1Before = token1.balanceOf(treasury);
            (, uint256 fee0PerShareBefore, uint256 fee1PerShareBefore) = hook.poolInfo(poolId);

            manager.setNextExactInputPoolInputAmount(poolId, 98 ether);
            vm.expectRevert(IMemeverseUniswapHook.ExactInputPartialFill.selector);
            router.swap(
                key,
                SwapParams({zeroForOne: false, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}),
                address(this),
                block.timestamp,
                0,
                100 ether,
                ""
            );

            assertEq(token0.balanceOf(address(this)), payer0Before, "payer token0 unchanged");
            assertEq(token1.balanceOf(address(this)), payer1Before, "payer token1 unchanged");
            assertEq(token0.balanceOf(treasury), treasury0Before, "treasury token0 unchanged");
            assertEq(token1.balanceOf(treasury), treasury1Before, "treasury token1 unchanged");
            (, uint256 fee0After, uint256 fee1After) = hook.poolInfo(poolId);
            assertEq(fee0After, fee0PerShareBefore, "fee0 per share unchanged");
            assertEq(fee1After, fee1PerShareBefore, "fee1 per share unchanged");
        }

        // Scope 2: EWVWAP state unchanged
        {
            (
                uint256 wv0Before,,
                uint256 ewVWAPBefore,
                uint160 volAnchorBefore,,
                uint24 volDevBefore,,
                uint24 shortImpactBefore,
            ) = hook.poolEWVWAPParams(poolId);

            manager.setNextExactInputPoolInputAmount(poolId, 98 ether);
            vm.expectRevert(IMemeverseUniswapHook.ExactInputPartialFill.selector);
            router.swap(
                key,
                SwapParams({zeroForOne: false, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}),
                address(this),
                block.timestamp,
                0,
                100 ether,
                ""
            );

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

    /// @notice Verifies native-input native-pair swaps fail locally in the router prefund step.
    /// @dev With router-side `erc20Pair` removed, the native-input direction now dies on `address(0).transferFrom(...)`
    /// before reaching hook validation. The test proves this stays router-local by showing unlock never starts.
    function testSwapRevertsLocally_WhenNativePairUsesNativeInputCurrency() external {
        PoolKey memory nativeKey = _dynamicPoolKey(CurrencyLibrary.ADDRESS_ZERO, Currency.wrap(address(token1)));
        (bool success,) = address(router)
            .call(
                abi.encodeWithSelector(
                    MemeverseSwapRouter.swap.selector,
                    nativeKey,
                    SwapParams({zeroForOne: true, amountSpecified: 100 ether, sqrtPriceLimitX96: 0}),
                    address(this),
                    block.timestamp,
                    0,
                    300 ether,
                    bytes("")
                )
            );
        assertFalse(success, "call should revert");
        assertEq(manager.lastUnlockPayer(), address(0), "router-local failure should not enter unlock");
    }

    /// @notice Verifies ERC20-input native-pair swaps still fail downstream at hook validation.
    /// @dev This is the opposite direction of the router-local failure path above and locks the current asymmetry.
    function testSwapRevertsInHook_WhenNativePairUsesErc20InputCurrency() external {
        PoolKey memory nativeKey = _dynamicPoolKey(CurrencyLibrary.ADDRESS_ZERO, Currency.wrap(address(token1)));
        vm.expectRevert(IMemeverseUniswapHook.NativeCurrencyUnsupported.selector);
        router.swap(
            nativeKey,
            SwapParams({zeroForOne: false, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}),
            address(this),
            block.timestamp,
            0,
            100 ether,
            ""
        );
    }

    /// @notice Verifies createPoolAndAddLiquidity fails closed for native pairs.
    function testCreatePoolAndAddLiquidityReverts_WhenPairUsesNativeCurrency() external {
        vm.expectRevert(IMemeverseUniswapHook.NativeCurrencyUnsupported.selector);
        router.createPoolAndAddLiquidity(
            address(0), address(token1), 300 ether, 100 ether, SQRT_PRICE_1_1, address(this), block.timestamp
        );
    }

    /// @notice Verifies addLiquidity fails closed for native pairs.
    function testAddLiquidityReverts_WhenPairUsesNativeCurrency() external {
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

    /// @notice Verifies router-accrued LP fees are claimed directly through the hook without router relays.
    /// @dev Covers the new owner-direct claim flow while keeping router swap/liquidity integration in scope.
    function testClaimFeesCore_DirectOwnerClaimCanRedirectRecipient() external {
        _setProtocolFeeCurrency(key.currency0);

        vm.prank(alice);
        router.addLiquidity(
            key.currency0, key.currency1, 100 ether, 100 ether, 90 ether, 90 ether, alice, block.timestamp
        );
        _matureLaunchWindow();

        uint160 priceLimit = uint160((uint256(SQRT_PRICE_1_1) * 99) / 100);
        router.swap(
            key,
            SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: priceLimit}),
            address(this),
            block.timestamp,
            40 ether,
            100 ether,
            ""
        );

        address recipient = address(0xCAFE);
        uint256 balanceBefore = token0.balanceOf(recipient);

        vm.prank(alice);
        (uint256 fee0Amount, uint256 fee1Amount) =
            hook.claimFeesCore(IMemeverseUniswapHook.ClaimFeesCoreParams({key: key, recipient: recipient}));

        assertGt(fee0Amount, 0, "fee0 claimed");
        assertEq(fee1Amount, 0, "fee1 claimed");
        assertEq(token0.balanceOf(recipient), balanceBefore + fee0Amount, "recipient received claimed fee");
    }

    /// @notice Verifies claimable-fee previews match claims and do not mutate state.
    /// @dev Covers the router preview surface for LP fees.
    function testClaimableFees_ViewMatchesClaimAndDoesNotMutateState() external {
        _setProtocolFeeCurrency(key.currency0);

        vm.prank(alice);
        router.addLiquidity(
            key.currency0, key.currency1, 100 ether, 100 ether, 90 ether, 90 ether, alice, block.timestamp
        );
        _matureLaunchWindow();

        uint160 priceLimit = uint160((uint256(SQRT_PRICE_1_1) * 99) / 100);
        router.swap(
            key,
            SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: priceLimit}),
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
        (uint256 claimedFee0, uint256 claimedFee1) =
            hook.claimFeesCore(IMemeverseUniswapHook.ClaimFeesCoreParams({key: key, recipient: alice}));

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
            key.currency0, key.currency1, 100 ether, 100 ether, 90 ether, 90 ether, alice, block.timestamp
        );
        _matureLaunchWindow();

        uint160 priceLimit = uint160((uint256(SQRT_PRICE_1_1) * 99) / 100);
        router.swap(
            key,
            SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: priceLimit}),
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

    /// @notice Verifies the router quotes enough pair amounts to mint at least the target liquidity.
    /// @dev The quote is an upper bound for exact-liquidity callers, not a floor-rounded under-estimate.
    function testRouterQuoteAmountsForLiquidity_ReturnsAmountsThatCoverTargetLiquidity() external {
        uint128 liquidityDesired = 10 ether;
        PoolKey memory normalizedKey = router.getHookPoolKey(address(token0), address(token1));
        manager.initialize(normalizedKey, SQRT_PRICE_1_1);

        (uint160 sqrtPriceX96,,,) = manager.getSlot0(normalizedKey.toId());
        (uint256 amount0Floor, uint256 amount1Floor) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96, FULL_RANGE_MIN_SQRT_PRICE_X96, FULL_RANGE_MAX_SQRT_PRICE_X96, liquidityDesired
        );

        (uint256 amountToken0, uint256 amountToken1) =
            router.quoteAmountsForLiquidity(address(token0), address(token1), liquidityDesired);

        uint128 quotedLiquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96, FULL_RANGE_MIN_SQRT_PRICE_X96, FULL_RANGE_MAX_SQRT_PRICE_X96, amountToken0, amountToken1
        );

        assertGe(amountToken0, amount0Floor, "token0 floor");
        assertGe(amountToken1, amount1Floor, "token1 floor");
        assertGe(quotedLiquidity, liquidityDesired, "quoted liquidity covers target");
    }

    /// @notice Verifies quoting a single unit of liquidity does not hang and still covers the request.
    /// @dev Guards the exact-liquidity boundary used by launcher-side POL minting.
    function testRouterQuoteAmountsForLiquidity_SingleUnitCoverageAtParity() external {
        uint128 liquidityDesired = 1;
        PoolKey memory normalizedKey = router.getHookPoolKey(address(token0), address(token1));
        manager.initialize(normalizedKey, SQRT_PRICE_1_1);

        (uint160 sqrtPriceX96,,,) = manager.getSlot0(normalizedKey.toId());
        (uint256 amountToken0, uint256 amountToken1) =
            router.quoteAmountsForLiquidity(address(token0), address(token1), liquidityDesired);

        uint128 quotedLiquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96, FULL_RANGE_MIN_SQRT_PRICE_X96, FULL_RANGE_MAX_SQRT_PRICE_X96, amountToken0, amountToken1
        );

        assertGe(quotedLiquidity, liquidityDesired, "quoted liquidity covers unit target");
    }

    /// @notice Verifies the exact-liquidity quote can be used verbatim for addLiquidityDetailed at an unchanged price.
    /// @dev Guards the launcher exact-liquidity flow against underfunding when using the router's exact quote path.
    function testQuoteExactAmountsForLiquidity_FeedsDetailedAddLiquidityAtUnchangedPrice() external {
        uint128 liquidityDesired = 10 ether;
        PoolKey memory normalizedKey = router.getHookPoolKey(address(token0), address(token1));
        manager.initialize(normalizedKey, SQRT_PRICE_1_1);

        (uint256 amountToken0, uint256 amountToken1) =
            router.quoteExactAmountsForLiquidity(address(token0), address(token1), liquidityDesired);
        (uint128 liquidity,,) = router.addLiquidityDetailed(
            normalizedKey.currency0,
            normalizedKey.currency1,
            amountToken0,
            amountToken1,
            0,
            0,
            address(this),
            block.timestamp
        );

        assertEq(liquidity, liquidityDesired, "exact quote mints target liquidity");
    }

    /// @notice Verifies the exact-liquidity quote also covers the hook's first-mint burn on an initialized empty pool.
    /// @dev Guards exact-liquidity callers that quote against a fresh pool before any active LP shares exist.
    function testQuoteExactAmountsForLiquidity_FeedsDetailedAddLiquidityOnInitializedEmptyPool() external {
        uint128 liquidityDesired = 10 ether;
        MockERC20 freshToken0 = new MockERC20("Fresh0", "F0", 18);
        MockERC20 freshToken1 = new MockERC20("Fresh1", "F1", 18);
        freshToken0.mint(address(this), 1_000_000 ether);
        freshToken1.mint(address(this), 1_000_000 ether);
        freshToken0.mint(address(manager), 1_000_000 ether);
        freshToken1.mint(address(manager), 1_000_000 ether);
        freshToken0.approve(address(router), type(uint256).max);
        freshToken1.approve(address(router), type(uint256).max);

        PoolKey memory freshKey = router.getHookPoolKey(address(freshToken0), address(freshToken1));
        PoolId freshPoolId = freshKey.toId();
        manager.initialize(freshKey, SQRT_PRICE_1_1);
        manager.setLiquidity(freshPoolId, 0);

        (uint256 amountToken0, uint256 amountToken1) =
            router.quoteExactAmountsForLiquidity(address(freshToken0), address(freshToken1), liquidityDesired);
        (uint128 liquidity,,) = router.addLiquidityDetailed(
            freshKey.currency0, freshKey.currency1, amountToken0, amountToken1, 0, 0, address(this), block.timestamp
        );

        assertEq(liquidity, liquidityDesired, "exact quote mints target liquidity after first-mint burn");
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
            address(tokenA), address(tokenB), 100 ether, 100 ether, SQRT_PRICE_1_1, address(this), block.timestamp
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
            address(token18), address(token6), 100 ether, 100 * 1e6, startPrice, address(this), block.timestamp
        );

        (uint160 sqrtPriceX96,,,) = manager.getSlot0(createdKey.toId());
        assertEq(sqrtPriceX96, startPrice, "provided sqrt price");
    }

    /// @notice Verifies addLiquidity rejects expired deadlines.
    /// @dev Covers the router deadline guard before any liquidity side effects happen.
    function testAddLiquidityReverts_WhenDeadlineExpired() external {
        vm.expectRevert(IMemeverseSwapRouter.ExpiredPastDeadline.selector);
        router.addLiquidity(
            key.currency0, key.currency1, 100 ether, 100 ether, 90 ether, 90 ether, address(this), block.timestamp - 1
        );
    }

    /// @notice Verifies the detailed add-liquidity entrypoint reports actual spend in pool-currency order.
    /// @dev Locks the new router surface that Launcher exact-liquidity now relies on to avoid balance snapshots.
    function testAddLiquidityDetailed_ReturnsActualUsageInPoolCurrencyOrder() external {
        uint256 token0Before = token0.balanceOf(address(this));
        uint256 token1Before = token1.balanceOf(address(this));

        (uint128 liquidity, uint256 amount0Used, uint256 amount1Used) = router.addLiquidityDetailed(
            key.currency0, key.currency1, 100 ether, 100 ether, 90 ether, 90 ether, address(this), block.timestamp
        );

        assertGt(liquidity, 0, "liquidity");
        assertEq(token0Before - token0.balanceOf(address(this)), amount0Used, "amount0 used");
        assertEq(token1Before - token1.balanceOf(address(this)), amount1Used, "amount1 used");
        assertLe(amount0Used, 100 ether, "amount0 budget");
        assertLe(amount1Used, 100 ether, "amount1 budget");
    }

    /// @notice Verifies unsorted addLiquidityDetailed inputs still report spend in caller order.
    /// @dev Guards the launcher path that now passes `(UPT, memecoin)` directly and relies on router-side normalization.
    function testAddLiquidityDetailed_ReturnsActualUsageInCallerOrderWhenInputsAreUnsorted() external {
        manager.initialize(key, SQRT_PRICE_1_1 / 2);

        uint256 token0Before = token0.balanceOf(address(this));
        uint256 token1Before = token1.balanceOf(address(this));

        (uint128 liquidity, uint256 amountFirstCurrencyUsed, uint256 amountSecondCurrencyUsed) = router.addLiquidityDetailed(
            key.currency1, key.currency0, 100 ether, 150 ether, 0, 0, address(this), block.timestamp
        );

        assertGt(liquidity, 0, "liquidity");
        assertEq(token1Before - token1.balanceOf(address(this)), amountFirstCurrencyUsed, "first currency used");
        assertEq(token0Before - token0.balanceOf(address(this)), amountSecondCurrencyUsed, "second currency used");
        assertNotEq(amountFirstCurrencyUsed, amountSecondCurrencyUsed, "price skew ensures caller-order coverage");
    }

    /// @notice Verifies removeLiquidity rejects expired deadlines.
    /// @dev Covers the router deadline guard on liquidity removal.
    function testRemoveLiquidityReverts_WhenDeadlineExpired() external {
        vm.prank(alice);
        router.addLiquidity(
            key.currency0, key.currency1, 100 ether, 100 ether, 90 ether, 90 ether, alice, block.timestamp
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
            address(token0), address(token0), 100 ether, 100 ether, SQRT_PRICE_1_1, address(this), block.timestamp
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
            address(tokenA), address(tokenB), 100 ether, 100 ether, SQRT_PRICE_1_1, address(this), block.timestamp - 1
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
