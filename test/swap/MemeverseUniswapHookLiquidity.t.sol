// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager, ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta, toBalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {LiquidityAmounts} from "../../src/swap/libraries/LiquidityAmounts.sol";
import {BaseHook} from "@uniswap/v4-hooks-public/src/base/BaseHook.sol";

import {MemeverseDynamicFeeEngine} from "../../src/swap/MemeverseDynamicFeeEngine.sol";
import {MemeverseUniswapHook} from "../../src/swap/MemeverseUniswapHook.sol";
import {MemeverseSwapRouter} from "../../src/swap/MemeverseSwapRouter.sol";
import {IMemeverseDynamicFeeEngine} from "../../src/swap/interfaces/IMemeverseDynamicFeeEngine.sol";
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
    constructor(IPoolManager _manager) MemeverseUniswapHook(_manager) {}

    function validateHookAddress(BaseHook) internal pure override {}

    function _validateProxyHookAddress() internal view virtual override {}

    function exposedBaseFeeBps() external pure returns (uint256) {
        return FEE_BASE_BPS;
    }

    function exposedCachedLpTotalSupply(PoolId poolId) external view returns (uint256) {
        return _getMemeverseUniswapHookStorage().cachedLpTotalSupply[poolId];
    }
}

contract TestableMemeverseUniswapHookV2 is TestableMemeverseUniswapHook {
    constructor(IPoolManager _manager) TestableMemeverseUniswapHook(_manager) {}

    function version() external pure returns (uint256) {
        return 2;
    }
}

contract TestableMemeverseDynamicFeeEngineV2 is MemeverseDynamicFeeEngine {
    bytes32 private constant MEMEVERSE_DYNAMIC_FEE_ENGINE_STORAGE_LOCATION =
        0xb7b6769a89985fd739eb1342563b5dbd4d11da8b84d601f10d877057788e0e00;
    uint256 private constant AUTHORIZED_HOOK_OFFSET = 2;

    constructor(IPoolManager _poolManager) MemeverseDynamicFeeEngine(_poolManager) {}

    function version() external pure returns (uint256) {
        return 2;
    }

    function migrateAuthorizedHook(address badAuthorizedHook) external {
        bytes32 slot = bytes32(uint256(MEMEVERSE_DYNAMIC_FEE_ENGINE_STORAGE_LOCATION) + AUTHORIZED_HOOK_OFFSET);
        assembly {
            sstore(slot, badAuthorizedHook)
        }
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
            SwapParams({zeroForOne: true, amountSpecified: -1 ether, sqrtPriceLimitX96: 0}),
            address(this)
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
    uint256 internal constant SHORT_CAP_PPM = 100_000;
    uint256 internal constant SHORT_FLOOR_PPM = 20_000;
    uint256 internal constant SHORT_COEFF_BPS = 2_500;
    uint256 internal constant PIF_CAP_PPM = 150_000;
    uint256 internal constant FEE_BASE_BPS = 100;
    uint256 internal constant FEE_DFF_MAX_PPM = 800_000;
    uint256 internal constant BPS_BASE = 10_000;
    bytes4 internal constant TOTAL_SUPPLY_SELECTOR = bytes4(keccak256("totalSupply()"));
    bytes4 internal constant UNAUTHORIZED_POOL_INITIALIZER_SELECTOR =
        bytes4(keccak256("UnauthorizedPoolInitializer()"));
    bytes4 internal constant UPGRADE_POOL_MANAGER_MISMATCH_SELECTOR =
        bytes4(keccak256("UpgradePoolManagerMismatch(address,address)"));
    bytes4 internal constant DYNAMIC_FEE_ENGINE_POOL_MANAGER_MISMATCH_SELECTOR =
        bytes4(keccak256("DynamicFeeEnginePoolManagerMismatch(address,address)"));
    bytes4 internal constant DYNAMIC_FEE_ENGINE_OWNER_MISMATCH_SELECTOR =
        bytes4(keccak256("DynamicFeeEngineOwnerMismatch(address,address,address)"));
    event DynamicFeeEngineUpdated(address oldEngine, address newEngine);

    MockPoolManagerForHookLiquidity internal mockManager;
    TestableMemeverseUniswapHook internal hook;
    MemeverseSwapRouter internal router;
    MockERC20 internal token0;
    MockERC20 internal token1;
    PoolKey internal key;
    PoolId internal poolId;

    function _deployHookProxyForManager(IPoolManager manager_, address owner_, address treasury_)
        internal
        returns (TestableMemeverseUniswapHook deployed)
    {
        // Hook proxy is 3 CREATEs away: engine impl (+1), engine proxy (+2), hook impl (+3), hook proxy (+4).
        address predictedHook = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 3);
        MemeverseDynamicFeeEngine engine = _deployEngineProxyForManager(manager_, predictedHook, predictedHook);
        TestableMemeverseUniswapHook implementation = new TestableMemeverseUniswapHook(manager_);
        bytes memory data = abi.encodeCall(MemeverseUniswapHook.initialize, (owner_, treasury_, engine));
        deployed = TestableMemeverseUniswapHook(address(new ERC1967Proxy(address(implementation), data)));
    }

    function _deployEngineProxyForManager(IPoolManager manager_, address owner_)
        internal
        returns (MemeverseDynamicFeeEngine deployed)
    {
        deployed = _deployEngineProxyForManager(manager_, owner_, address(0xBAD));
    }

    function _deployEngineProxyForManager(IPoolManager manager_, address owner_, address authorizedHook_)
        internal
        returns (MemeverseDynamicFeeEngine deployed)
    {
        MemeverseDynamicFeeEngine implementation = new MemeverseDynamicFeeEngine(manager_);
        deployed = MemeverseDynamicFeeEngine(
            address(
                new ERC1967Proxy(
                    address(implementation),
                    abi.encodeCall(MemeverseDynamicFeeEngine.initialize, (owner_, authorizedHook_))
                )
            )
        );
    }

    function _deployHookProxy(address owner_, address treasury_)
        internal
        returns (TestableMemeverseUniswapHook deployed)
    {
        deployed = _deployHookProxyForManager(IPoolManager(address(mockManager)), owner_, treasury_);
    }

    function _hasExpectedHookPermissions(address hookAddress) internal pure returns (bool) {
        uint160 flags = uint160(hookAddress) & uint160((1 << 14) - 1);
        uint160 expectedFlags = uint160(1 << 13) // beforeInitialize
            | uint160(1 << 11) // beforeAddLiquidity
            | uint160(1 << 7) // beforeSwap
            | uint160(1 << 6) // afterSwap
            | uint160(1 << 3) // beforeSwapReturnDelta
            | uint160(1 << 2); // afterSwapReturnDelta
        return flags == expectedFlags;
    }

    function _nextInvalidProductionHookProxyAddress() internal returns (address predictedProxy) {
        // Hook proxy is 3 CREATEs away: engine impl, engine proxy, hook impl, then hook proxy.
        predictedProxy = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 3);
        for (uint256 i = 0; _hasExpectedHookPermissions(predictedProxy); i++) {
            require(i < 256, "ProxyDeploy: max burns exceeded");
            new MockERC20("DUMMY", "DUMMY", 18);
            predictedProxy = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 3);
        }

        require(!_hasExpectedHookPermissions(predictedProxy), "hook-valid proxy");
    }

    /// @notice Executes set up.
    /// @dev Deploys the hook, router, tokens, and approvals shared by the liquidity tests.
    function setUp() public {
        mockManager = new MockPoolManagerForHookLiquidity();
        token0 = new MockERC20("Token0", "TK0", 18);
        token1 = new MockERC20("Token1", "TK1", 18);
        token0.mint(address(this), 1_000_000 ether);
        token1.mint(address(this), 1_000_000 ether);

        hook = _deployHookProxyForManager(IPoolManager(address(mockManager)), address(this), address(this));
        router = new MemeverseSwapRouter(
            IPoolManager(address(mockManager)), IMemeverseUniswapHook(address(hook)), IPermit2(address(0xBEEF))
        );

        token0.approve(address(hook), type(uint256).max);
        token1.approve(address(hook), type(uint256).max);
        token0.approve(address(router), type(uint256).max);
        token1.approve(address(router), type(uint256).max);

        key = _dynamicPoolKey(Currency.wrap(address(token0)), Currency.wrap(address(token1)));
        poolId = key.toId();

        hook.setPoolInitializer(address(this));
        hook.authorizePoolInitialization(key, SQRT_PRICE_1_1);
        mockManager.initialize(key, SQRT_PRICE_1_1);
        hook.setPoolInitializer(address(router));
    }

    function _initializePoolDirect(PoolKey memory targetKey, uint160 sqrtPriceX96) internal {
        hook.setPoolInitializer(address(this));
        hook.authorizePoolInitialization(targetKey, sqrtPriceX96);
        mockManager.initialize(targetKey, sqrtPriceX96);
        hook.setPoolInitializer(address(router));
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

    function testBeforeInitialize_RevertsWithoutAuthorizedInitializer() external {
        MockPoolManagerForHookLiquidity freshManager = new MockPoolManagerForHookLiquidity();
        TestableMemeverseUniswapHook freshHook =
            _deployHookProxyForManager(IPoolManager(address(freshManager)), address(this), address(this));
        MockERC20 freshToken0 = new MockERC20("Fresh0", "F0", 18);
        MockERC20 freshToken1 = new MockERC20("Fresh1", "F1", 18);
        PoolKey memory freshKey = PoolKey({
            currency0: Currency.wrap(address(freshToken0)),
            currency1: Currency.wrap(address(freshToken1)),
            fee: 0x800000,
            tickSpacing: 200,
            hooks: IHooks(address(freshHook))
        });

        vm.expectRevert(UNAUTHORIZED_POOL_INITIALIZER_SELECTOR);
        freshManager.initialize(freshKey, SQRT_PRICE_1_1);
    }

    function testBeforeInitialize_RevertsWhenNoPreAuthorization() external {
        hook.setPoolInitializer(address(this));
        PoolKey memory freshKey =
            _dynamicPoolKey(Currency.wrap(address(new MockERC20("X0", "X0", 18))), Currency.wrap(address(token1)));

        vm.expectRevert(IMemeverseUniswapHook.UnauthorizedPoolInitialization.selector);
        mockManager.initialize(freshKey, SQRT_PRICE_1_1);

        hook.setPoolInitializer(address(router));
    }

    function testBeforeInitialize_RevertsWhenPriceMismatchesAuthorization() external {
        hook.setPoolInitializer(address(this));
        PoolKey memory freshKey =
            _dynamicPoolKey(Currency.wrap(address(new MockERC20("X0", "X0", 18))), Currency.wrap(address(token1)));
        hook.authorizePoolInitialization(freshKey, SQRT_PRICE_1_1);

        uint160 wrongPrice = SQRT_PRICE_1_1 + 100;
        vm.expectRevert(IMemeverseUniswapHook.InvalidInitialPrice.selector);
        mockManager.initialize(freshKey, wrongPrice);

        hook.setPoolInitializer(address(router));
    }

    function testBeforeInitialize_AuthorizationConsumedAfterUse() external {
        hook.setPoolInitializer(address(this));
        PoolKey memory freshKey =
            _dynamicPoolKey(Currency.wrap(address(new MockERC20("X0", "X0", 18))), Currency.wrap(address(token1)));
        hook.authorizePoolInitialization(freshKey, SQRT_PRICE_1_1);
        mockManager.initialize(freshKey, SQRT_PRICE_1_1);

        // After successful init, auth is deleted. Re-initializing the same pool reverts.
        vm.expectRevert(IMemeverseUniswapHook.UnauthorizedPoolInitialization.selector);
        mockManager.initialize(freshKey, SQRT_PRICE_1_1);

        hook.setPoolInitializer(address(router));
    }

    function testAuthorizePoolInitialization_RevertsWhenAuthorizationAlreadyActive() external {
        hook.setPoolInitializer(address(this));
        PoolKey memory freshKey =
            _dynamicPoolKey(Currency.wrap(address(new MockERC20("X0", "X0", 18))), Currency.wrap(address(token1)));
        hook.authorizePoolInitialization(freshKey, SQRT_PRICE_1_1);

        vm.expectRevert(IMemeverseUniswapHook.PoolInitializationAlreadyAuthorized.selector);
        hook.authorizePoolInitialization(freshKey, SQRT_PRICE_1_1 + 1);

        hook.setPoolInitializer(address(router));
    }

    function testBeforeInitialize_FailedInitDoesNotConsumeAuth() external {
        hook.setPoolInitializer(address(this));
        PoolKey memory freshKey =
            _dynamicPoolKey(Currency.wrap(address(new MockERC20("X0", "X0", 18))), Currency.wrap(address(token1)));
        hook.authorizePoolInitialization(freshKey, SQRT_PRICE_1_1);

        // Init with wrong price reverts. The revert unwinds the entire call so auth remains.
        uint160 wrongPrice = SQRT_PRICE_1_1 + 100;
        vm.expectRevert(IMemeverseUniswapHook.InvalidInitialPrice.selector);
        mockManager.initialize(freshKey, wrongPrice);

        // Auth is still active after the reverted attempt; retry with correct price succeeds.
        mockManager.initialize(freshKey, SQRT_PRICE_1_1);

        hook.setPoolInitializer(address(router));
    }

    /// @notice Verifies hook-local protection state is keyed only by `PoolId`.
    /// @dev The new unlock gate must not need token-pair guessing or launcher verdict helpers.
    function testPublicSwapResumeTime_StoresPerPoolWithoutAffectingOtherPools() external {
        hook.setLauncher(address(this));

        PoolKey memory secondKey =
            _dynamicPoolKey(Currency.wrap(address(new MockERC20("Token2", "TK2", 18))), Currency.wrap(address(token1)));
        PoolId secondPoolId = secondKey.toId();
        _initializePoolDirect(secondKey, SQRT_PRICE_1_1);

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

    function testPublicSwapResumeTime_StoresAndReadsResumeTime() external {
        hook.setLauncher(address(this));

        uint40 resumeTime = uint40(block.timestamp + 1 hours);
        (bool setOk, bytes memory setData) = _setPublicSwapResumeTime(address(token0), address(token1), resumeTime);
        assertTrue(setOk, string(setData));

        (bool resumeOk, uint40 storedResumeTime) = _readPublicSwapResumeTime(poolId);
        assertTrue(resumeOk, "resume getter missing");
        assertEq(storedResumeTime, resumeTime, "resumeTime");
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
    /// @dev With no permanently locked LP, all minted liquidity participates in fee growth.
    function testLpFeeGrowth_UsesEffectiveSupplyAndQ128Accumulator() external {
        uint128 liquidity = _addLiquidity();
        hook.setProtocolFeeCurrency(key.currency0);

        IMemeverseUniswapHook.SwapQuote memory quote = hook.quoteSwap(
            key, SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}), address(this)
        );

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

    /// @notice Verifies all LP shares and pool liquidity can be removed after the final burn.
    /// @dev Removing the last user position must not leave protocol-locked LP dust behind.
    function testFullRemovalLeavesNoLockedLiquidityOrSupply() external {
        uint128 liquidity = _addLiquidity();
        (address lpToken,,) = hook.poolInfo(poolId);

        hook.removeLiquidityCore(
            IMemeverseUniswapHook.RemoveLiquidityCoreParams({
                currency0: key.currency0, currency1: key.currency1, liquidity: liquidity, recipient: address(this)
            })
        );

        assertEq(UniswapLP(lpToken).totalSupply(), 0, "no locked LP supply");
        assertEq(UniswapLP(lpToken).balanceOf(address(0)), 0, "zero address LP balance");
        assertEq(hook.exposedCachedLpTotalSupply(poolId), 0, "cached supply");
        assertEq(mockManager.getLiquidity(poolId), 0, "pool liquidity");
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

        // After full removal: still in sync with no permanently locked supply
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
        assertEq(actualSupply, 0, "no locked supply remains");
        assertEq(mockManager.getLiquidity(poolId), 0, "pool liquidity after full remove");
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

    /// @notice Verifies the first liquidity add does not mint permanently locked LP shares.
    /// @dev Zero address remains fee-neutral because it receives no LP balance.
    function testFirstLiquidityAdd_DoesNotMintLockedZeroAddressShares() external {
        _addLiquidity();
        hook.setProtocolFeeCurrency(key.currency0);
        (address lpToken,,) = hook.poolInfo(poolId);

        vm.prank(address(mockManager));
        hook.beforeSwap(
            address(this),
            key,
            SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}),
            bytes("")
        );

        assertEq(UniswapLP(lpToken).balanceOf(address(0)), 0, "zero address LP balance");

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
        hook.quoteSwap(
            key, SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}), address(this)
        );
    }

    function testQuoteSwapReverts_WhenPairUsesNativeCurrency() external {
        PoolKey memory nativeKey = _dynamicPoolKey(CurrencyLibrary.ADDRESS_ZERO, Currency.wrap(address(token1)));
        vm.expectRevert(IMemeverseUniswapHook.NativeCurrencyUnsupported.selector);
        hook.quoteSwap(
            nativeKey, SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}), address(this)
        );
    }

    function testQuoteSwapReverts_WhenPoolKeyUsesDifferentHook() external {
        hook.setProtocolFeeCurrency(key.currency0);

        PoolKey memory mismatchedKey = PoolKey({
            currency0: key.currency0,
            currency1: key.currency1,
            fee: key.fee,
            tickSpacing: key.tickSpacing,
            hooks: IHooks(address(0xBEEF))
        });

        vm.expectRevert(IMemeverseUniswapHook.HookAddressMismatch.selector);
        hook.quoteSwap(
            mismatchedKey,
            SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}),
            address(this)
        );
    }

    function testDirectManagerSwapReverts_WhenPairUsesNativeCurrency() external {
        PoolKey memory nativeKey = _dynamicPoolKey(CurrencyLibrary.ADDRESS_ZERO, Currency.wrap(address(token1)));

        vm.expectRevert(IMemeverseUniswapHook.NativeCurrencyUnsupported.selector);
        mockManager.swapAsUnlocked(
            nativeKey, SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}), bytes("")
        );
    }

    /// @notice Covers the local direct/core fail-closed branch for exact-input underfills without router checks.
    /// @custom:dev-only-harness Uses the hook-liquidity manager mock to witness fee-accounting rollback on revert.
    function testDirectManagerSwapReverts_WhenExactInputPartialFills() external {
        _addLiquidity();
        hook.setProtocolFeeCurrency(key.currency1);
        // Seed non-zero EWVWAP state so rollback assertions are non-trivial.
        mockManager.swapAsUnlocked(
            key, SwapParams({zeroForOne: true, amountSpecified: -10 ether, sqrtPriceLimitX96: 0}), bytes("")
        );
        vm.warp(block.timestamp + 900);
        mockManager.setNextExactInputPoolInputAmount(poolId, 99 ether);

        RollbackSnapshot memory s = _snapshotRollback();

        vm.expectRevert(IMemeverseUniswapHook.ExactInputPartialFill.selector);
        mockManager.swapAsUnlocked(
            key, SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}), bytes("")
        );

        _assertRollbackUnchanged(s);
    }

    /// @notice Covers the local direct/core branch where output-fee exact-input swaps consume the net pool input from `beforeSwap`.
    /// @custom:dev-only-harness Locks hook-side handling under the local hook-liquidity manager mock instead of proving full v4 execution semantics.
    function testDirectManagerSwapPasses_WhenOneForZeroExactInputUsesNetPoolInputOnOutputFeePool() external {
        _addLiquidity();
        hook.setProtocolFeeCurrency(key.currency0);
        vm.warp(block.timestamp + 900);

        IMemeverseUniswapHook.SwapQuote memory quote = hook.quoteSwap(
            key, SwapParams({zeroForOne: false, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}), address(this)
        );
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
    /// @custom:dev-only-harness Uses the hook-liquidity manager mock to witness atomic rollback instead of proving production partial-fill semantics.
    function testDirectManagerSwapReverts_WhenExactInputPartialFillsOnInputFeePool() external {
        _addLiquidity();
        hook.setProtocolFeeCurrency(key.currency0); // input-side fee for zeroForOne=true
        // Seed non-zero EWVWAP state so rollback assertions are non-trivial.
        mockManager.swapAsUnlocked(
            key, SwapParams({zeroForOne: true, amountSpecified: -10 ether, sqrtPriceLimitX96: 0}), bytes("")
        );
        vm.warp(block.timestamp + 900);
        mockManager.setNextExactInputPoolInputAmount(poolId, 99 ether);

        RollbackSnapshot memory s = _snapshotRollback();

        vm.expectRevert(IMemeverseUniswapHook.ExactInputPartialFill.selector);
        mockManager.swapAsUnlocked(
            key, SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}), bytes("")
        );

        _assertRollbackUnchanged(s);
    }

    /// @notice Covers the mirrored local direct/core fail-closed branch for one-for-zero exact-input underfills on output-fee pools.
    /// @custom:dev-only-harness Uses the hook-liquidity manager mock to witness rollback symmetry instead of proving production partial-fill semantics.
    function testDirectManagerSwapReverts_WhenOneForZeroExactInputPartialFillsOnOutputFeePool() external {
        _addLiquidity();
        hook.setProtocolFeeCurrency(key.currency0);
        // Seed non-zero EWVWAP state so rollback assertions are non-trivial.
        mockManager.swapAsUnlocked(
            key, SwapParams({zeroForOne: false, amountSpecified: -10 ether, sqrtPriceLimitX96: 0}), bytes("")
        );
        vm.warp(block.timestamp + 900);
        mockManager.setNextExactInputPoolInputAmount(poolId, 99 ether);

        RollbackSnapshot memory s = _snapshotRollback();

        vm.expectRevert(IMemeverseUniswapHook.ExactInputPartialFill.selector);
        mockManager.swapAsUnlocked(
            key, SwapParams({zeroForOne: false, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}), bytes("")
        );

        _assertRollbackUnchanged(s);
    }

    /// @notice Covers the local launch-settlement fail-closed branch for exact-input underfills.
    /// @custom:dev-only-harness Uses the hook-liquidity manager mock to witness rollback for balances, fee growth, and dynamic state.
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

        RollbackSnapshot memory s = _snapshotRollback();
        uint256 hookToken0Before = token0.balanceOf(address(hook));

        vm.expectRevert(IMemeverseUniswapHook.ExactInputPartialFill.selector);
        hook.executeLaunchSettlement(
            IMemeverseUniswapHook.LaunchSettlementParams({
                key: key,
                params: SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}),
                recipient: address(this)
            })
        );

        _assertRollbackUnchanged(s);
        assertEq(token0.balanceOf(address(hook)), hookToken0Before, "hook token0 unchanged");
    }

    function testExecuteLaunchSettlement_RevertsWhenDynamicFeeEngineUnauthorized() external {
        _addLiquidity();
        hook.setProtocolFeeCurrency(key.currency0);
        hook.setLauncher(address(this));
        token0.approve(address(hook), type(uint256).max);

        // Bypass the admin guard so settlement exercises a broken bound engine directly.
        MemeverseDynamicFeeEngine newEngine =
            _deployEngineProxyForManager(IPoolManager(address(mockManager)), address(this));
        bytes32 baseSlot = 0x9f27a56b97c42ac08d93ff5a852851d11eb052b06dc4c041fc6bfa4414f7e000;
        vm.store(address(hook), bytes32(uint256(baseSlot) + 11), bytes32(uint256(uint160(address(newEngine)))));

        vm.expectRevert(abi.encodeWithSelector(IMemeverseDynamicFeeEngine.UnauthorizedCaller.selector, address(hook)));
        hook.executeLaunchSettlement(
            IMemeverseUniswapHook.LaunchSettlementParams({
                key: key,
                params: SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}),
                recipient: address(this)
            })
        );
    }

    /// @notice Verifies launch fee floor dominates immediately after pool initialization and decays to the minimum fee.
    /// @dev Covers the new launch fee scheduler on top of the existing dynamic fee engine.
    function testQuoteSwap_UsesLaunchFeeFloorAndDecaysToMinFee() external {
        hook.setProtocolFeeCurrency(key.currency0);

        IMemeverseUniswapHook.SwapQuote memory initialQuote = hook.quoteSwap(
            key, SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}), address(this)
        );
        assertEq(initialQuote.feeBps, 5000, "initial launch fee");

        vm.warp(block.timestamp + 900);

        IMemeverseUniswapHook.SwapQuote memory maturedQuote = hook.quoteSwap(
            key, SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}), address(this)
        );
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
            _deployHookProxyForManager(IPoolManager(address(uninitializedManager)), address(this), address(this));
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
            IMemeverseDynamicFeeEngine.LaunchFeeConfig({startFeeBps: 5000, minFeeBps: 100, decayDurationSeconds: 0})
        );

        vm.expectRevert(IMemeverseUniswapHook.ZeroValue.selector);
        hook.setDefaultLaunchFeeConfig(
            IMemeverseDynamicFeeEngine.LaunchFeeConfig({startFeeBps: 99, minFeeBps: 100, decayDurationSeconds: 900})
        );

        vm.expectRevert(IMemeverseUniswapHook.ZeroValue.selector);
        hook.setDefaultLaunchFeeConfig(
            IMemeverseDynamicFeeEngine.LaunchFeeConfig({startFeeBps: 10_001, minFeeBps: 100, decayDurationSeconds: 900})
        );

        vm.expectRevert(IMemeverseUniswapHook.ZeroValue.selector);
        hook.setDefaultLaunchFeeConfig(
            IMemeverseDynamicFeeEngine.LaunchFeeConfig({
                startFeeBps: 5_000, minFeeBps: 10_001, decayDurationSeconds: 900
            })
        );

        hook.setDefaultLaunchFeeConfig(
            IMemeverseDynamicFeeEngine.LaunchFeeConfig({startFeeBps: 4000, minFeeBps: 100, decayDurationSeconds: 900})
        );

        (uint24 startFeeBps, uint24 minFeeBps, uint32 decayDurationSeconds) = hook.defaultLaunchFeeConfig();
        assertEq(startFeeBps, 4000, "start fee");
        assertEq(minFeeBps, 100, "min fee");
        assertEq(decayDurationSeconds, 900, "duration");
    }

    function testImplementationInitializeReverts() external {
        MemeverseDynamicFeeEngine engineImpl = new MemeverseDynamicFeeEngine(IPoolManager(address(mockManager)));
        MemeverseDynamicFeeEngine engine = MemeverseDynamicFeeEngine(
            address(
                new ERC1967Proxy(
                    address(engineImpl),
                    abi.encodeCall(MemeverseDynamicFeeEngine.initialize, (address(this), address(this)))
                )
            )
        );
        TestableMemeverseUniswapHook implementation =
            new TestableMemeverseUniswapHook(IPoolManager(address(mockManager)));

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementation.initialize(address(this), address(this), engine);
    }

    function testProxyInitializeSetsOwnerTreasuryAndLaunchFeeConfig() external {
        TestableMemeverseUniswapHook initialized = _deployHookProxy(address(0xA11CE), address(0xFEE));

        assertEq(initialized.owner(), address(0xA11CE), "owner");
        assertEq(initialized.treasury(), address(0xFEE), "treasury");

        (uint24 startFeeBps, uint24 minFeeBps, uint32 decayDurationSeconds) = initialized.defaultLaunchFeeConfig();
        assertEq(startFeeBps, 5000, "start fee");
        assertEq(minFeeBps, 100, "min fee");
        assertEq(decayDurationSeconds, 900, "duration");
    }

    function testProductionProxyInitializeRevertsWhenProxyAddressHasInvalidHookFlags() external {
        address predictedProxy = _nextInvalidProductionHookProxyAddress();
        MemeverseDynamicFeeEngine engine =
            _deployEngineProxyForManager(IPoolManager(address(mockManager)), predictedProxy, predictedProxy);
        MemeverseUniswapHook implementation = new MemeverseUniswapHook(IPoolManager(address(mockManager)));
        bytes memory data = abi.encodeCall(MemeverseUniswapHook.initialize, (address(this), address(this), engine));

        vm.expectRevert(abi.encodeWithSelector(Hooks.HookAddressNotValid.selector, predictedProxy));
        new ERC1967Proxy(address(implementation), data);
    }

    function testProxyInitializeRevertsWhenEngineOwnerIsNotHook() external {
        address predictedHook = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 3);
        MemeverseDynamicFeeEngine engine =
            _deployEngineProxyForManager(IPoolManager(address(mockManager)), address(this), predictedHook);
        TestableMemeverseUniswapHook implementation =
            new TestableMemeverseUniswapHook(IPoolManager(address(mockManager)));

        vm.expectRevert(
            abi.encodeWithSelector(
                DYNAMIC_FEE_ENGINE_OWNER_MISMATCH_SELECTOR, address(engine), predictedHook, address(this)
            )
        );
        new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(MemeverseUniswapHook.initialize, (address(this), address(this), engine))
        );
    }

    function testNonOwnerCannotUpgrade() external {
        TestableMemeverseUniswapHook initialized = _deployHookProxy(address(this), address(this));
        TestableMemeverseUniswapHookV2 newImplementation =
            new TestableMemeverseUniswapHookV2(IPoolManager(address(mockManager)));

        vm.prank(address(0xB0B));
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(0xB0B)));
        initialized.upgradeToAndCall(address(newImplementation), bytes(""));
    }

    function testOwnerCanUpgradeAndPreserveStorage() external {
        TestableMemeverseUniswapHook initialized = _deployHookProxy(address(this), address(0xFEE));
        initialized.setLauncher(address(0xD00D));
        initialized.setPoolInitializer(address(0xBEEF));

        TestableMemeverseUniswapHookV2 newImplementation =
            new TestableMemeverseUniswapHookV2(IPoolManager(address(mockManager)));

        initialized.upgradeToAndCall(address(newImplementation), bytes(""));

        assertEq(TestableMemeverseUniswapHookV2(address(initialized)).version(), 2, "version");
        assertEq(initialized.owner(), address(this), "owner");
        assertEq(initialized.treasury(), address(0xFEE), "treasury");
        assertEq(initialized.launcher(), address(0xD00D), "launcher");
        assertEq(initialized.poolInitializer(), address(0xBEEF), "poolInitializer");
    }

    function testOwnerCannotUpgradeToImplementationWithDifferentPoolManager() external {
        TestableMemeverseUniswapHook initialized = _deployHookProxy(address(this), address(this));
        MockPoolManagerForHookLiquidity differentManager = new MockPoolManagerForHookLiquidity();
        TestableMemeverseUniswapHookV2 newImplementation =
            new TestableMemeverseUniswapHookV2(IPoolManager(address(differentManager)));

        vm.expectRevert(
            abi.encodeWithSelector(
                UPGRADE_POOL_MANAGER_MISMATCH_SELECTOR, address(mockManager), address(differentManager)
            )
        );
        initialized.upgradeToAndCall(address(newImplementation), bytes(""));
    }

    function testConstructorRevertsWhenPoolManagerIsZero() external {
        vm.expectRevert(IMemeverseUniswapHook.ZeroAddress.selector);
        new TestableMemeverseUniswapHook(IPoolManager(address(0)));
    }

    function testProxyInitializeRevertsOnSecondCall() external {
        TestableMemeverseUniswapHook initialized = _deployHookProxy(address(this), address(0xFEE));
        IMemeverseDynamicFeeEngine engine = IMemeverseDynamicFeeEngine(address(initialized.dynamicFeeEngine()));

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        initialized.initialize(address(0xABCD), address(0xBEEF), engine);
    }

    function testUpgradeDynamicFeeEngineRevertsForInvalidEngine() external {
        vm.expectRevert(IMemeverseUniswapHook.ZeroAddress.selector);
        hook.upgradeDynamicFeeEngine(IMemeverseDynamicFeeEngine(address(0)));

        MockPoolManagerForHookLiquidity differentManager = new MockPoolManagerForHookLiquidity();
        MemeverseDynamicFeeEngine differentEngine =
            _deployEngineProxyForManager(IPoolManager(address(differentManager)), address(this));

        vm.expectRevert(
            abi.encodeWithSelector(
                DYNAMIC_FEE_ENGINE_POOL_MANAGER_MISMATCH_SELECTOR, address(mockManager), address(differentManager)
            )
        );
        hook.upgradeDynamicFeeEngine(differentEngine);
    }

    function testUpgradeDynamicFeeEngineRevertsForNonOwner() external {
        MemeverseDynamicFeeEngine newEngine =
            _deployEngineProxyForManager(IPoolManager(address(mockManager)), address(this));

        vm.prank(address(0xB0B));
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, address(0xB0B)));
        hook.upgradeDynamicFeeEngine(newEngine);
    }

    function testUpgradeDynamicFeeEngineUpdatesPointerAndEmitsEvent() external {
        address oldEngine = address(hook.dynamicFeeEngine());
        MemeverseDynamicFeeEngine newEngine =
            _deployEngineProxyForManager(IPoolManager(address(mockManager)), address(hook), address(hook));

        vm.expectEmit(false, false, false, true);
        emit DynamicFeeEngineUpdated(oldEngine, address(newEngine));
        hook.upgradeDynamicFeeEngine(newEngine);

        assertEq(address(hook.dynamicFeeEngine()), address(newEngine), "engine pointer");
    }

    function testHookUpgradePreservesDynamicFeeEnginePointer() external {
        MemeverseDynamicFeeEngine newEngine =
            _deployEngineProxyForManager(IPoolManager(address(mockManager)), address(hook), address(hook));
        hook.upgradeDynamicFeeEngine(newEngine);

        TestableMemeverseUniswapHookV2 newImplementation =
            new TestableMemeverseUniswapHookV2(IPoolManager(address(mockManager)));
        hook.upgradeToAndCall(address(newImplementation), bytes(""));

        assertEq(TestableMemeverseUniswapHookV2(address(hook)).version(), 2, "version");
        assertEq(address(hook.dynamicFeeEngine()), address(newEngine), "engine pointer");
    }

    /// @notice Regression: upgrading to an engine that hasn't authorized this hook must revert.
    /// @dev Without this guard, all subsequent swaps and settlements revert with UnauthorizedCaller.
    function testUpgradeDynamicFeeEngineRevertsForUnauthorizedEngine() external {
        // Deploy engine that authorizes a different address (not this hook).
        MemeverseDynamicFeeEngine newEngine =
            _deployEngineProxyForManager(IPoolManager(address(mockManager)), address(this));

        vm.expectRevert(
            abi.encodeWithSelector(IMemeverseUniswapHook.EngineNotAuthorizedCaller.selector, address(newEngine))
        );
        hook.upgradeDynamicFeeEngine(newEngine);
    }

    function testUpgradeDynamicFeeEngineRejectsBareImplementationAddress() external {
        MemeverseDynamicFeeEngine bareImplementation = new MemeverseDynamicFeeEngine(IPoolManager(address(mockManager)));

        vm.expectRevert(
            abi.encodeWithSelector(
                IMemeverseUniswapHook.EngineNotAuthorizedCaller.selector, address(bareImplementation)
            )
        );
        hook.upgradeDynamicFeeEngine(bareImplementation);
    }

    function testUpgradeDynamicFeeEngineRevertsWhenEngineOwnerIsNotHook() external {
        MemeverseDynamicFeeEngine newEngine =
            _deployEngineProxyForManager(IPoolManager(address(mockManager)), address(this), address(hook));

        vm.expectRevert(
            abi.encodeWithSelector(
                DYNAMIC_FEE_ENGINE_OWNER_MISMATCH_SELECTOR, address(newEngine), address(hook), address(this)
            )
        );
        hook.upgradeDynamicFeeEngine(newEngine);
    }

    function testTransferredHookOwnerControlsCurrentEngineImplementationUpgradeThroughHookOnly() external {
        address oldOwner = address(this);
        address newOwner = address(0xA11CE);
        MemeverseDynamicFeeEngine currentEngine = MemeverseDynamicFeeEngine(address(hook.dynamicFeeEngine()));
        TestableMemeverseDynamicFeeEngineV2 newImplementation =
            new TestableMemeverseDynamicFeeEngineV2(IPoolManager(address(mockManager)));

        hook.transferOwnership(newOwner);

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, oldOwner));
        currentEngine.upgradeToAndCall(address(newImplementation), bytes(""));

        (bool oldOwnerHookUpgradeSucceeded, bytes memory oldOwnerHookUpgradeData) = address(hook)
            .call(
                abi.encodeWithSignature(
                    "upgradeDynamicFeeEngineImplementation(address,bytes)", address(newImplementation), bytes("")
                )
            );
        assertFalse(oldOwnerHookUpgradeSucceeded, string(oldOwnerHookUpgradeData));

        vm.prank(newOwner);
        (bool newOwnerHookUpgradeSucceeded, bytes memory newOwnerHookUpgradeData) = address(hook)
            .call(
                abi.encodeWithSignature(
                    "upgradeDynamicFeeEngineImplementation(address,bytes)", address(newImplementation), bytes("")
                )
            );
        assertTrue(newOwnerHookUpgradeSucceeded, string(newOwnerHookUpgradeData));
        assertEq(TestableMemeverseDynamicFeeEngineV2(address(currentEngine)).version(), 2, "engine version");
    }

    function testUpgradeDynamicFeeEngineImplementationRevertsWhenMigrationBreaksAuthorizedHook() external {
        MemeverseDynamicFeeEngine currentEngine = MemeverseDynamicFeeEngine(address(hook.dynamicFeeEngine()));
        TestableMemeverseDynamicFeeEngineV2 newImplementation =
            new TestableMemeverseDynamicFeeEngineV2(IPoolManager(address(mockManager)));
        address badAuthorizedHook = address(0xB0B);
        bytes memory migrationData =
            abi.encodeCall(TestableMemeverseDynamicFeeEngineV2.migrateAuthorizedHook, (badAuthorizedHook));

        vm.expectRevert(
            abi.encodeWithSelector(IMemeverseUniswapHook.EngineNotAuthorizedCaller.selector, address(currentEngine))
        );
        hook.upgradeDynamicFeeEngineImplementation(address(newImplementation), migrationData);

        assertEq(currentEngine.authorizedHook(), address(hook), "authorized hook unchanged");
    }

    // ── Upgrade regression: real engine swap after upgrade ──────────

    function test_UpgradeEngine_ThenSwap_SucceedsWithRealFeeMath() external {
        MemeverseDynamicFeeEngine newEngine =
            _deployEngineProxyForManager(IPoolManager(address(mockManager)), address(hook), address(hook));
        hook.upgradeDynamicFeeEngine(newEngine);

        assertEq(address(hook.dynamicFeeEngine()), address(newEngine), "engine pointer");

        _addLiquidity();
        hook.setProtocolFeeCurrency(key.currency0);
        vm.warp(block.timestamp + 900);

        BalanceDelta delta = mockManager.swapAsUnlocked(
            key, SwapParams({zeroForOne: true, amountSpecified: -10 ether, sqrtPriceLimitX96: 0}), bytes("")
        );

        assertTrue(delta.amount0() < 0, "consumed input");
        assertTrue(delta.amount1() > 0, "produced output");

        // Real engine must have written EWVWAP state — proves full fee math path executed.
        IMemeverseDynamicFeeEngine.DynamicFeeState memory state = newEngine.getDynamicFeeState(address(hook), poolId);
        assertTrue(state.weightedVolume0 > 0, "EWVWAP state accumulated");
    }

    function test_UpgradeEngine_MultipleSwaps_StateAccumulates() external {
        MemeverseDynamicFeeEngine newEngine =
            _deployEngineProxyForManager(IPoolManager(address(mockManager)), address(hook), address(hook));
        hook.upgradeDynamicFeeEngine(newEngine);

        _addLiquidity();
        hook.setProtocolFeeCurrency(key.currency0);
        vm.warp(block.timestamp + 900);

        // First swap — engine state starts accumulating
        mockManager.swapAsUnlocked(
            key, SwapParams({zeroForOne: true, amountSpecified: -10 ether, sqrtPriceLimitX96: 0}), bytes("")
        );
        IMemeverseDynamicFeeEngine.DynamicFeeState memory state1 = newEngine.getDynamicFeeState(address(hook), poolId);
        assertTrue(state1.weightedVolume0 > 0, "first swap wrote EWVWAP state");

        // Second swap — engine still active, state remains non-zero
        vm.warp(block.timestamp + 1);
        mockManager.swapAsUnlocked(
            key, SwapParams({zeroForOne: true, amountSpecified: -10 ether, sqrtPriceLimitX96: 0}), bytes("")
        );
        IMemeverseDynamicFeeEngine.DynamicFeeState memory state2 = newEngine.getDynamicFeeState(address(hook), poolId);
        assertTrue(state2.weightedVolume0 > 0, "second swap preserved EWVWAP state");
        assertTrue(state2.shortLastTs > state1.shortLastTs, "short impact timestamp advanced");
    }

    /// @notice Deploy engine with a different authorized hook — engine rejects the hot-path call.
    function test_UpgradeEngine_UnauthorizedHook_SwapReverts() external {
        // Deploy engine authorized to a different address, not this hook.
        // Use vm.store to bypass upgradeDynamicFeeEngine's authorization check.
        MemeverseDynamicFeeEngine newEngine =
            _deployEngineProxyForManager(IPoolManager(address(mockManager)), address(this));
        bytes32 baseSlot = 0x9f27a56b97c42ac08d93ff5a852851d11eb052b06dc4c041fc6bfa4414f7e000;
        vm.store(address(hook), bytes32(uint256(baseSlot) + 11), bytes32(uint256(uint160(address(newEngine)))));

        _addLiquidity();
        hook.setProtocolFeeCurrency(key.currency0);
        vm.warp(block.timestamp + 900);

        vm.expectRevert(abi.encodeWithSelector(IMemeverseDynamicFeeEngine.UnauthorizedCaller.selector, address(hook)));
        mockManager.swapAsUnlocked(
            key, SwapParams({zeroForOne: true, amountSpecified: -10 ether, sqrtPriceLimitX96: 0}), bytes("")
        );
    }

    struct RollbackSnapshot {
        uint256 payer0;
        uint256 payer1;
        uint256 treasury0;
        uint256 treasury1;
        uint256 fee0PerShare;
        uint256 fee1PerShare;
        uint256 wv0;
        uint256 ewVWAP;
        uint160 volAnchor;
        uint24 volDev;
        uint24 shortImpact;
    }

    function _snapshotRollback() internal view returns (RollbackSnapshot memory s) {
        s.payer0 = token0.balanceOf(address(this));
        s.payer1 = token1.balanceOf(address(this));
        s.treasury0 = token0.balanceOf(hook.treasury());
        s.treasury1 = token1.balanceOf(hook.treasury());
        (, s.fee0PerShare, s.fee1PerShare) = hook.poolInfo(poolId);
        (s.wv0,, s.ewVWAP, s.volAnchor,, s.volDev,, s.shortImpact,) = hook.poolDynamicFeeState(poolId);
    }

    function _assertRollbackUnchanged(RollbackSnapshot memory s) internal view {
        assertEq(token0.balanceOf(address(this)), s.payer0, "payer token0 unchanged");
        assertEq(token1.balanceOf(address(this)), s.payer1, "payer token1 unchanged");
        assertEq(token0.balanceOf(hook.treasury()), s.treasury0, "treasury token0 unchanged");
        assertEq(token1.balanceOf(hook.treasury()), s.treasury1, "treasury token1 unchanged");
        (, uint256 fee0, uint256 fee1) = hook.poolInfo(poolId);
        assertEq(fee0, s.fee0PerShare, "fee0 per share unchanged");
        assertEq(fee1, s.fee1PerShare, "fee1 per share unchanged");
        (uint256 wv0,, uint256 ewvwap, uint160 volAnchor,, uint24 volDev,, uint24 shortImpact,) =
            hook.poolDynamicFeeState(poolId);
        assertEq(wv0, s.wv0, "ewvwap weightedVolume0 unchanged");
        assertEq(ewvwap, s.ewVWAP, "ewvwap unchanged");
        assertEq(volAnchor, s.volAnchor, "vol anchor unchanged");
        assertEq(volDev, s.volDev, "volatility unchanged");
        assertEq(shortImpact, s.shortImpact, "short impact unchanged");
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
        uint256 satPpm = FullMath.mulDiv(pifPpm, PPM_BASE, pifPpm + PIF_CAP_PPM);
        uint256 dffPpm = FullMath.mulDiv(FEE_DFF_MAX_PPM, satPpm, PPM_BASE);
        uint256 dynamicPpm = FullMath.mulDiv(dffPpm, pifPpm, PPM_BASE);
        return dynamicPpm / (PPM_BASE / BPS_BASE);
    }

    function _expectedShortBps(uint256 pifPpm) internal pure returns (uint256) {
        uint256 projected = pifPpm > SHORT_CAP_PPM ? SHORT_CAP_PPM : pifPpm;
        uint256 chargeable = projected > SHORT_FLOOR_PPM ? projected - SHORT_FLOOR_PPM : 0;
        return FullMath.mulDiv(chargeable, SHORT_COEFF_BPS, PPM_BASE);
    }

    function _expectedFeeBps(uint256 pifPpm) internal pure returns (uint256) {
        return FEE_BASE_BPS + _expectedAdverseFeeBps(pifPpm) + _expectedShortBps(pifPpm);
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
