// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IERC20Minimal} from "@uniswap/v4-core/src/interfaces/external/IERC20Minimal.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {SqrtPriceMath} from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {IPoolManager, SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BalanceDelta, toBalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {
    BeforeSwapDelta,
    BeforeSwapDeltaLibrary,
    toBeforeSwapDelta
} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {BaseHook} from "@uniswap/v4-hooks-public/src/base/BaseHook.sol";
import {wadExp} from "solmate/utils/SignedWadMath.sol";

import {SafeCast} from "./libraries/SafeCast.sol";
import {LiquidityQuote} from "./libraries/LiquidityQuote.sol";
import {MemeverseTransientState} from "./libraries/MemeverseTransientState.sol";
import {CurrencySettler} from "./libraries/CurrencySettler.sol";
import {UniswapLP} from "./tokens/UniswapLP.sol";
import {ReentrancyGuard} from "../common/access/ReentrancyGuard.sol";
import {IMemeverseUniswapHook} from "./interfaces/IMemeverseUniswapHook.sol";

/**
 * @title MemeverseUniswapHook
 * @notice A Uniswap v4 hook implementing:
 * - Full-range liquidity management (single position from MIN_TICK to MAX_TICK)
 * - A custom ERC20 LP token per pool
 * - Dynamic fees for adverse swaps (based on projected price impact, an EWMA volatility signal,
 *   and a linearly decayed short-term cumulative impact signal)
 * - Launch-time fee scheduling during the initial trading window after pool initialization
 *
 * @dev High-level flow:
 * - This contract is the Core engine for the Memeverse v4 integration.
 * - End-user and SDK-facing flows are expected to enter via `MemeverseSwapRouter`.
 * - The external Core APIs on this contract remain intentionally open for custom routers and advanced integrators.
 * - The configured `treasury` is expected to be a passive fee receiver.
 * - `beforeInitialize`: validates pool settings and deploys the pool-specific LP token.
 * - `beforeSwap`: computes public-swap fees and accrues fee accounting.
 * - `afterSwap`: updates ewVWAP, reference-price volatility state, and short-term impact state, and optionally takes protocol fees.
 * - `addLiquidityCore` / `removeLiquidityCore`: mint/burn LP tokens while adding/removing full-range liquidity.
 * - `claimFeesCore`: lets the calling LP claim its own accrued fees to a chosen recipient
 *   (tracked via per-share accounting).
 */
contract MemeverseUniswapHook is
    IMemeverseUniswapHook,
    IUnlockCallback,
    BaseHook,
    ReentrancyGuard,
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    using CurrencyLibrary for Currency;
    using CurrencySettler for Currency;
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using SafeCast for uint256;
    using SafeCast for uint128;
    using SafeCast for int256;
    using SafeCast for int128;
    bytes internal constant ZERO_BYTES = bytes("");

    int24 internal constant MIN_TICK = -887200;
    int24 internal constant MAX_TICK = 887200;
    int24 internal constant TICK_SPACING = 200;
    uint256 internal constant EWVWAP_PRECISION = 1e18;
    uint256 internal constant FEE_GROWTH_Q128 = uint256(1) << 128;
    uint256 internal constant Q96 = 1 << 96;
    uint256 internal constant Q192 = uint256(1) << 192;
    uint256 internal constant Q192_MASK = Q192 - 1;

    uint256 public constant PROTOCOL_FEE_RATIO_BPS = 3000;
    uint256 public constant BPS_BASE = 10000;
    uint256 public constant PPM_BASE = 1_000_000;
    uint24 internal constant FEE_ALPHA = 500_000; // ewVWAP EWMA weight, ppm domain.
    uint24 internal constant FEE_DFF_MAX_PPM = 800_000; // Upper bound of dynamic fee factor, ppm domain.
    int256 internal constant LAUNCH_FEE_EXP_SHAPE_WAD = 4e18;
    uint24 internal constant FEE_BASE_BPS = 100; // Minimum fee in bps.
    uint24 internal constant LAUNCH_SETTLEMENT_FEE_BPS = 100; // Fixed fee for preorder settlement swaps.
    uint24 internal constant FEE_MAX_BPS = 10_000; // Maximum fee in bps.
    uint24 internal constant PIF_CAP_PPM = 150_000; // PIF cap for fee growth, ppm domain.
    uint24 internal constant VOL_DEVIATION_STEP_BPS = 1; // Reference-price deviation step in bps.
    uint24 internal constant VOL_FILTER_PERIOD_SEC = 10; // Time below this keeps current volatility anchor/carry.
    uint24 internal constant VOL_DECAY_PERIOD_SEC = 60; // Time above this fully clears carried volatility state.
    uint24 internal constant VOL_DECAY_FACTOR_BPS = 5_000; // Partial carry-over factor inside decay window.
    uint24 internal constant VOL_MAX_FEE_BPS = 50; // Max volatility fee when accumulator is at cap.
    uint24 internal constant VOL_MAX_DEVIATION_ACCUMULATOR = 1_500_000; // Cap for volatility deviation state.
    uint24 internal constant SHORT_DECAY_WINDOW_SEC = 15; // Linear decay window for short-term impact state.
    uint24 internal constant SHORT_COEFF_BPS = 2_500; // Short-term impact surcharge coefficient.
    uint24 internal constant SHORT_FLOOR_PPM = 20_000; // Free short-impact allowance before charging starts.
    uint24 internal constant SHORT_CAP_PPM = 100_000; // Cap for short-term impact accumulator.
    uint24 internal constant VOL_INCREMENT_PER_STEP = 1_000;
    uint256 internal constant ADDRESS_BATCH_WINDOW_SEC = 3;
    uint256 internal constant UP_SHORT_BUCKET = 1072380529476360830;
    uint256 internal constant DOWN_SHORT_BUCKET = 921954445729288731;
    uint8 internal constant UNLOCK_ACTION_MODIFY_LIQUIDITY = 0;
    uint8 internal constant UNLOCK_ACTION_LAUNCH_SETTLEMENT = 1;

    struct AddressBatchState {
        uint192 batchAccumPpm;
        uint64 batchStartTs;
    }

    struct DynamicFeeQuote {
        uint256 feeBps;
        uint256 pifPpm;
        uint256 adverseImpactPartBps;
        uint256 volatilityPartBps;
        uint256 shortImpactPartBps;
        uint256 estimatedInputAmount;
        uint256 estimatedOutputAmount;
        uint256 estimatedGrossOutputAmount;
        uint256 spotBeforeX18;
        uint256 spotAfterX18;
        bool isAdverse;
    }

    struct ModifyLiquidityCallbackData {
        address sender;
        PoolKey key;
        ModifyLiquidityParams params;
    }

    struct LaunchSettlementCallbackData {
        address payer;
        address recipient;
        PoolKey key;
        SwapParams params;
        bool protocolFeeOnInput;
    }

    struct PoolInitializationAuth {
        uint160 startPriceX96;
        bool active;
    }

    struct SwapFeeContext {
        Currency currencyIn;
        Currency currencyOut;
        bool protocolFeeOnInput;
        bool inputIsCurrency0;
    }

    /// @notice Storage layout for the MemeverseUniswapHook ERC7201 namespace.
    ///         When adding fields in upgrades, append only at the end.
    ///         Never reorder or insert fields between existing ones.
    /// @custom:storage-location erc7201:outrun.storage.MemeverseUniswapHook
    struct MemeverseUniswapHookStorage {
        address treasury;
        address launcher;
        mapping(address => bool) supportedProtocolFeeCurrencies;
        mapping(PoolId => PoolInfo) poolInfo;
        mapping(PoolId => uint256) cachedLpTotalSupply;
        mapping(PoolId => uint40) poolLaunchTimestamp;
        mapping(PoolId => uint40) publicSwapResumeTime;
        mapping(PoolId => mapping(address => UserFeeState)) userFeeState;
        LaunchFeeConfig defaultLaunchFeeConfig;
        bool emergencyFlag;
        address poolInitializer;
        mapping(PoolId => EWVWAPParams) poolEWVWAPParams;
        mapping(address => mapping(PoolId => AddressBatchState)) addressBatchState;
        mapping(PoolId => PoolInitializationAuth) poolInitializationAuth;
    }

    // keccak256(abi.encode(uint256(keccak256("outrun.storage.MemeverseUniswapHook")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant MEMEVERSE_UNISWAP_HOOK_STORAGE_LOCATION =
        0x9f27a56b97c42ac08d93ff5a852851d11eb052b06dc4c041fc6bfa4414f7e000;

    function _getMemeverseUniswapHookStorage() internal pure returns (MemeverseUniswapHookStorage storage $) {
        assembly {
            $.slot := MEMEVERSE_UNISWAP_HOOK_STORAGE_LOCATION
        }
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    /// @param _manager Uniswap v4 pool manager stored by `BaseHook` as immutable implementation bytecode state.
    constructor(IPoolManager _manager) BaseHook(_manager) {
        _disableInitializers();
    }

    /// @notice Initializes owner-controlled hook state for an ERC1967 proxy.
    /// @dev The proxy address is the real Uniswap hook address, so hook permission flags are validated here.
    /// @param initialOwner Initial owner authorized to configure and upgrade the hook.
    /// @param treasury_ Treasury receiving protocol fees.
    function initialize(address initialOwner, address treasury_) external initializer {
        if (initialOwner == address(0) || treasury_ == address(0)) revert ZeroAddress();
        _validateProxyHookAddress();
        __Ownable_init(initialOwner);

        MemeverseUniswapHookStorage storage $ = _getMemeverseUniswapHookStorage();
        $.treasury = treasury_;
        emit TreasuryUpdated(address(0), treasury_);
        $.defaultLaunchFeeConfig =
            LaunchFeeConfig({startFeeBps: 5000, minFeeBps: FEE_BASE_BPS, decayDurationSeconds: 900});
        emit DefaultLaunchFeeConfigUpdated(0, 0, 0, 5000, FEE_BASE_BPS, 900);
    }

    function validateHookAddress(BaseHook) internal pure virtual override {}

    /// @dev Only test subclasses may override this to skip hook-address validation.
    /// Production deployments must not override — the proxy address must carry the correct flags.
    function _validateProxyHookAddress() internal view virtual {
        Hooks.validateHookPermissions(IHooks(address(this)), getHookPermissions());
    }

    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner {
        address currentPoolManager = address(poolManager);
        address newPoolManager = address(MemeverseUniswapHook(newImplementation).poolManager());
        // Operational guardrail, not a security boundary: the external poolManager() call trusts the new
        // implementation to self-report honestly. A malicious owner can bypass this by deploying an
        // implementation with a custom poolManager() getter that returns the expected address. This check
        // protects against accidental mismatches (wrong PoolManager constructor arg) during honest upgrades.
        if (newPoolManager != currentPoolManager) {
            revert UpgradePoolManagerMismatch(currentPoolManager, newPoolManager);
        }
    }

    function treasury() external view returns (address) {
        return _getMemeverseUniswapHookStorage().treasury;
    }

    function launcher() external view override returns (address) {
        return _getMemeverseUniswapHookStorage().launcher;
    }

    function supportedProtocolFeeCurrencies(address currency) external view returns (bool) {
        return _getMemeverseUniswapHookStorage().supportedProtocolFeeCurrencies[currency];
    }

    function poolInfo(PoolId poolId)
        external
        view
        override
        returns (address liquidityToken, uint256 fee0PerShare, uint256 fee1PerShare)
    {
        PoolInfo storage info = _getMemeverseUniswapHookStorage().poolInfo[poolId];
        return (info.liquidityToken, info.fee0PerShare, info.fee1PerShare);
    }

    function poolLaunchTimestamp(PoolId poolId) external view override returns (uint40) {
        return _getMemeverseUniswapHookStorage().poolLaunchTimestamp[poolId];
    }

    function publicSwapResumeTime(PoolId poolId) external view override returns (uint40) {
        return _getMemeverseUniswapHookStorage().publicSwapResumeTime[poolId];
    }

    function userFeeState(PoolId poolId, address user)
        external
        view
        returns (uint256 fee0Offset, uint256 fee1Offset, uint256 pendingFee0, uint256 pendingFee1)
    {
        UserFeeState storage state = _getMemeverseUniswapHookStorage().userFeeState[poolId][user];
        return (state.fee0Offset, state.fee1Offset, state.pendingFee0, state.pendingFee1);
    }

    function defaultLaunchFeeConfig()
        external
        view
        override
        returns (uint24 startFeeBps, uint24 minFeeBps, uint32 decayDurationSeconds)
    {
        LaunchFeeConfig storage config = _getMemeverseUniswapHookStorage().defaultLaunchFeeConfig;
        return (config.startFeeBps, config.minFeeBps, config.decayDurationSeconds);
    }

    function emergencyFlag() external view returns (bool) {
        return _getMemeverseUniswapHookStorage().emergencyFlag;
    }

    function poolInitializer() external view override returns (address) {
        return _getMemeverseUniswapHookStorage().poolInitializer;
    }

    function poolEWVWAPParams(PoolId poolId)
        external
        view
        returns (
            uint256 weightedVolume0,
            uint256 weightedPriceVolume0,
            uint256 ewVWAPX18,
            uint160 volAnchorSqrtPriceX96,
            uint40 volLastMoveTs,
            uint24 volDeviationAccumulator,
            uint24 volCarryAccumulator,
            uint24 shortImpactPpm,
            uint40 shortLastTs
        )
    {
        EWVWAPParams storage params = _getMemeverseUniswapHookStorage().poolEWVWAPParams[poolId];
        return (
            params.weightedVolume0,
            params.weightedPriceVolume0,
            params.ewVWAPX18,
            params.volAnchorSqrtPriceX96,
            params.volLastMoveTs,
            params.volDeviationAccumulator,
            params.volCarryAccumulator,
            params.shortImpactPpm,
            params.shortLastTs
        );
    }

    modifier onlyLauncher() {
        if (msg.sender != _getMemeverseUniswapHookStorage().launcher) revert Unauthorized();
        _;
    }

    modifier erc20Pair(Currency currency0, Currency currency1) {
        _revertIfNativeCurrencyUnsupported(currency0, currency1);
        _;
    }

    /// @notice Declares which hook callbacks are enabled for this hook.
    /// @dev Memeverse uses only `beforeInitialize`, `beforeAddLiquidity`, `beforeSwap`, and `afterSwap`.
    /// @return permissions The callback permission bitmap consumed by the Uniswap v4 hook framework.
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: false,
            beforeAddLiquidity: true,
            beforeRemoveLiquidity: false,
            afterAddLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: true,
            afterSwapReturnDelta: true,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    /// @notice Quote the hook's current swap fee preview, including LP and protocol slices plus user-facing amounts.
    /// @dev The preview separates LP-fee and protocol-fee amounts because they may settle in different currencies:
    /// LP fees always accrue in the input currency, while protocol fees settle in the supported fee currency selected
    /// for this swap path (input side preferred, otherwise output side). For exact-output swaps, `estimatedUserInputAmount`
    /// is the intended router-side guardrail candidate for `amountInMaximum`.
    /// @param key The pool key being quoted.
    /// @param params The swap parameters being quoted.
    /// @param trader Address whose per-address batch state determines the adverse fee component.
    /// @return quote The projected fee side, user flows, and fee split.
    function quoteSwap(PoolKey calldata key, SwapParams calldata params, address trader)
        external
        view
        override
        erc20Pair(key.currency0, key.currency1)
        returns (SwapQuote memory quote)
    {
        PoolId poolId = key.toId();
        _revertIfNoActiveLiquidityShares(poolId, params.amountSpecified);
        _revertIfPublicSwapBlocked(poolId);
        SwapFeeContext memory ctx = _resolveSwapFeeContext(key, params.zeroForOne);

        (uint160 preSqrtPriceX96,,,) = poolManager.getSlot0(poolId);
        DynamicFeeQuote memory feeQuote =
            _quoteDynamicFee(poolId, params, preSqrtPriceX96, ctx.protocolFeeOnInput, trader);
        uint256 lpFeeBps = _lpFeeBps(feeQuote.feeBps);
        uint256 protocolFeeBps = _protocolFeeBps(feeQuote.feeBps);

        quote.feeBps = feeQuote.feeBps;
        quote.protocolFeeOnInput = ctx.protocolFeeOnInput;

        if (params.amountSpecified < 0) {
            uint256 userInputAmount = uint256(-params.amountSpecified);
            quote.estimatedUserInputAmount = userInputAmount;
            quote.estimatedLpFeeAmount = FullMath.mulDiv(userInputAmount, lpFeeBps, BPS_BASE);
            if (ctx.protocolFeeOnInput) {
                quote.estimatedProtocolFeeAmount = FullMath.mulDiv(userInputAmount, protocolFeeBps, BPS_BASE);
                quote.estimatedUserOutputAmount = feeQuote.estimatedOutputAmount;
            } else {
                quote.estimatedProtocolFeeAmount =
                    FullMath.mulDiv(feeQuote.estimatedGrossOutputAmount, protocolFeeBps, BPS_BASE);
                quote.estimatedUserOutputAmount = feeQuote.estimatedGrossOutputAmount - quote.estimatedProtocolFeeAmount;
            }
        } else {
            uint256 requestedOutputAmount = uint256(params.amountSpecified);
            quote.estimatedUserOutputAmount = requestedOutputAmount;
            quote.estimatedLpFeeAmount = FullMath.mulDiv(feeQuote.estimatedInputAmount, lpFeeBps, BPS_BASE);
            if (ctx.protocolFeeOnInput) {
                quote.estimatedProtocolFeeAmount =
                    FullMath.mulDiv(feeQuote.estimatedInputAmount, protocolFeeBps, BPS_BASE);
                quote.estimatedUserInputAmount =
                    feeQuote.estimatedInputAmount + quote.estimatedLpFeeAmount + quote.estimatedProtocolFeeAmount;
            } else {
                quote.estimatedProtocolFeeAmount = feeQuote.estimatedGrossOutputAmount - requestedOutputAmount;
                quote.estimatedUserInputAmount = feeQuote.estimatedInputAmount + quote.estimatedLpFeeAmount;
            }
        }
    }

    /// @notice Return the LP token address for a hook-managed pool key, or `address(0)` when the pool is not initialized.
    /// @dev Convenience helper for integrators that already operate with `PoolKey`.
    /// @param key The pool key to query.
    /// @return liquidityToken The deployed LP token, or `address(0)` when the pool is not initialized.
    function lpToken(PoolKey calldata key)
        external
        view
        override
        erc20Pair(key.currency0, key.currency1)
        returns (address liquidityToken)
    {
        return _getMemeverseUniswapHookStorage().poolInfo[key.toId()].liquidityToken;
    }

    /// @notice Preview the current claimable LP fees for an owner without mutating accounting state.
    /// @dev Mirrors the same fee accrual math used by `updateUserSnapshot` and `claimFeesCore`, but keeps storage
    /// unchanged so routers and frontends can safely preview claim results.
    /// @param key The pool key whose fee accounting is queried.
    /// @param owner The owner address for the fee preview.
    /// @return fee0Amount The preview claimable amount in currency0.
    /// @return fee1Amount The preview claimable amount in currency1.
    function claimableFees(PoolKey calldata key, address owner)
        external
        view
        override
        erc20Pair(key.currency0, key.currency1)
        returns (uint256 fee0Amount, uint256 fee1Amount)
    {
        PoolId poolId = key.toId();
        MemeverseUniswapHookStorage storage $ = _getMemeverseUniswapHookStorage();
        PoolInfo storage pool = $.poolInfo[poolId];
        if (pool.liquidityToken == address(0) || owner == address(0)) return (0, 0);

        UserFeeState storage state = $.userFeeState[poolId][owner];
        fee0Amount = state.pendingFee0;
        fee1Amount = state.pendingFee1;

        uint256 balance = UniswapLP(pool.liquidityToken).balanceOf(owner);
        if (balance == 0) return (fee0Amount, fee1Amount);

        if (pool.fee0PerShare > state.fee0Offset) {
            fee0Amount += FullMath.mulDiv(balance, pool.fee0PerShare - state.fee0Offset, FEE_GROWTH_Q128);
        }
        if (pool.fee1PerShare > state.fee1Offset) {
            fee1Amount += FullMath.mulDiv(balance, pool.fee1PerShare - state.fee1Offset, FEE_GROWTH_Q128);
        }
    }

    function _beforeInitialize(address sender, PoolKey calldata key, uint160 sqrtPriceX96)
        internal
        override
        erc20Pair(key.currency0, key.currency1)
        returns (bytes4)
    {
        if (key.tickSpacing != TICK_SPACING) revert TickSpacingNotDefault();
        if (!LPFeeLibrary.isDynamicFee(key.fee)) revert FeeMustBeDynamic();

        PoolId poolId = key.toId();
        MemeverseUniswapHookStorage storage $ = _getMemeverseUniswapHookStorage();
        if (sender != $.poolInitializer) revert UnauthorizedPoolInitializer();

        PoolInitializationAuth memory auth = $.poolInitializationAuth[poolId];
        if (!auth.active) revert UnauthorizedPoolInitialization();
        if (auth.startPriceX96 != sqrtPriceX96) revert InvalidInitialPrice();
        delete $.poolInitializationAuth[poolId];

        string memory tokenSymbol = string(
            abi.encodePacked("Outrun", "-", _currencySymbol(key.currency0), "-", _currencySymbol(key.currency1), "-LP")
        );
        address liquidityToken = address(new UniswapLP(tokenSymbol, tokenSymbol, 18, poolId, address(this)));

        $.poolInfo[poolId].liquidityToken = liquidityToken;
        $.poolLaunchTimestamp[poolId] = uint40(block.timestamp);

        emit PoolInitialized(poolId, liquidityToken, key.currency0, key.currency1);

        return IHooks.beforeInitialize.selector;
    }

    /// @dev Computes the dynamic fee, collects any exact-input input-side fees, and stores swap context for `afterSwap`.
    function _beforeSwap(address sender, PoolKey calldata key, SwapParams calldata params, bytes calldata)
        internal
        override
        erc20Pair(key.currency0, key.currency1)
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        PoolId poolId = key.toId();
        // Launch settlement executes via `executeLaunchSettlement(...)` and self-initiates pool swaps.
        // If a non-standard pool manager mock still routes self-swaps through callbacks, keep this branch fee-neutral.
        if (sender == address(this)) {
            return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }
        _revertIfPublicSwapBlocked(poolId);
        uint256 effectiveSupply = _activeLpSupplyForSwap(poolId, params.amountSpecified);

        uint256 absSpecified = uint256(params.amountSpecified < 0 ? -params.amountSpecified : params.amountSpecified);
        SwapFeeContext memory ctx = _resolveSwapFeeContext(key, params.zeroForOne);

        (uint160 preSqrtPriceX96,,,) = poolManager.getSlot0(poolId);
        _refreshVolatilityAnchorAndCarry(poolId, preSqrtPriceX96);
        DynamicFeeQuote memory quote =
        // solhint-disable-next-line avoid-tx-origin
        _quoteDynamicFee(poolId, params, preSqrtPriceX96, ctx.protocolFeeOnInput, tx.origin);
        uint256 dynamicFeeBps = quote.feeBps;

        uint256 lpFeeBps = _lpFeeBps(dynamicFeeBps);
        uint256 protocolFeeBps = _protocolFeeBps(dynamicFeeBps);

        uint256 lpFeeInputAmount = 0;
        uint256 protocolFeeInputAmount = 0;
        if (params.amountSpecified < 0) {
            // Exact-input swaps can charge input-side fees immediately because the user's budget is already known up front.
            // Fee amounts below are mirrored in _afterSwap exact-input branch — keep in sync.
            lpFeeInputAmount = FullMath.mulDiv(absSpecified, lpFeeBps, BPS_BASE);
            if (ctx.protocolFeeOnInput) {
                protocolFeeInputAmount = FullMath.mulDiv(absSpecified, protocolFeeBps, BPS_BASE);
            }
        }

        uint256 swapContextDepth = MemeverseTransientState.pushSwapContext(poolId, dynamicFeeBps, preSqrtPriceX96);
        uint256 exactOutputProtocolFeeOutputAmount = 0;
        if (params.amountSpecified > 0 && !ctx.protocolFeeOnInput) {
            // This exact rounded amount was reserved in beforeSwap, so afterSwap must not skim any overfill surplus.
            exactOutputProtocolFeeOutputAmount = quote.estimatedGrossOutputAmount - absSpecified;
            MemeverseTransientState.storeExactOutputProtocolFee(
                poolId, swapContextDepth, exactOutputProtocolFeeOutputAmount
            );
        }

        if (lpFeeInputAmount > 0) {
            _collectLpFee(poolId, ctx.currencyIn, ctx.inputIsCurrency0, lpFeeInputAmount, effectiveSupply);
        }
        if (protocolFeeInputAmount > 0) {
            _collectProtocolFee(poolId, ctx.currencyIn, protocolFeeInputAmount);
        }

        if (params.amountSpecified > 0 && !ctx.protocolFeeOnInput) {
            // Exact-output with output-side protocol fees asks the pool for the gross output now; the hook keeps the fee delta later.
            return (
                IHooks.beforeSwap.selector,
                toBeforeSwapDelta(exactOutputProtocolFeeOutputAmount.toInt128(), int128(0)),
                0
            );
        }

        if (params.amountSpecified > 0) {
            return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }

        int128 specifiedDeltaInput = (lpFeeInputAmount + protocolFeeInputAmount).toInt128();
        if (specifiedDeltaInput == 0) {
            return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }
        return (IHooks.beforeSwap.selector, toBeforeSwapDelta(specifiedDeltaInput, int128(0)), 0);
    }

    function _revertIfPublicSwapBlocked(PoolId poolId) internal view {
        uint40 resumeTime = _getMemeverseUniswapHookStorage().publicSwapResumeTime[poolId];
        if (resumeTime != 0 && block.timestamp < resumeTime) revert PublicSwapDisabled();
    }

    function _afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata
    ) internal override returns (bytes4, int128) {
        if (sender == address(this)) {
            return (IHooks.afterSwap.selector, 0);
        }

        PoolId poolId = key.toId();
        SwapFeeContext memory ctx = _resolveSwapFeeContext(key, params.zeroForOne);
        (uint256 feeBps, uint160 preSqrtPriceX96, uint256 swapContextDepth) =
            MemeverseTransientState.consumeCurrentSwapContext(poolId);
        if (!_getMemeverseUniswapHookStorage().emergencyFlag) {
            // solhint-disable-next-line avoid-tx-origin
            _updateDynamicStateAfterSwap(poolId, delta, preSqrtPriceX96, tx.origin);
        }

        uint256 lpFeeBps = _lpFeeBps(feeBps);
        uint256 protocolFeeBps = _protocolFeeBps(feeBps);

        if (params.amountSpecified < 0) {
            uint256 absSpecified = uint256(-params.amountSpecified);
            // These must match the _beforeSwap computation for the partial-fill guard to work.
            uint256 lpFeeInputAmount = FullMath.mulDiv(absSpecified, lpFeeBps, BPS_BASE);
            uint256 protocolFeeInputAmount =
                ctx.protocolFeeOnInput ? FullMath.mulDiv(absSpecified, protocolFeeBps, BPS_BASE) : 0;
            uint256 expectedPoolInput = absSpecified - lpFeeInputAmount - protocolFeeInputAmount;
            uint256 actualPoolInput = _actualInputAmount(delta, params.zeroForOne);
            if (actualPoolInput != expectedPoolInput) revert ExactInputPartialFill();

            if (!ctx.protocolFeeOnInput) {
                uint256 actualOutputAbs = _actualOutputAmount(delta, params.zeroForOne);
                uint256 exactInputProtocolFeeOutputAmount = FullMath.mulDiv(actualOutputAbs, protocolFeeBps, BPS_BASE);
                if (exactInputProtocolFeeOutputAmount > 0) {
                    _collectProtocolFee(poolId, ctx.currencyOut, exactInputProtocolFeeOutputAmount);
                }
                return (IHooks.afterSwap.selector, int128(int256(exactInputProtocolFeeOutputAmount)));
            }

            return (IHooks.afterSwap.selector, 0);
        }

        if (params.amountSpecified > 0) {
            // Exact-output fees settle against the actual fill, so only `afterSwap` knows the final input amount to charge.
            uint256 requestedOutputAbs = uint256(params.amountSpecified);
            uint256 actualOutputAbs = _actualOutputAmount(delta, params.zeroForOne);
            uint256 minimumOutputAbs = requestedOutputAbs;
            uint256 reservedProtocolFeeOutputAmount = 0;
            if (!ctx.protocolFeeOnInput) {
                reservedProtocolFeeOutputAmount =
                    MemeverseTransientState.consumeExactOutputProtocolFee(poolId, swapContextDepth);
                // Match the exact beforeSwap reservation so overfills are delivered to the recipient instead of skimmed.
                minimumOutputAbs += reservedProtocolFeeOutputAmount;
            }
            if (actualOutputAbs < minimumOutputAbs) revert ExactOutputPartialFill();

            uint256 actualInputAbs = _actualInputAmount(delta, params.zeroForOne);

            uint256 exactOutputLpFeeInputAmount = FullMath.mulDiv(actualInputAbs, lpFeeBps, BPS_BASE);
            if (exactOutputLpFeeInputAmount > 0) {
                uint256 effectiveSupply = _getMemeverseUniswapHookStorage().cachedLpTotalSupply[poolId];
                _collectLpFee(
                    poolId, ctx.currencyIn, ctx.inputIsCurrency0, exactOutputLpFeeInputAmount, effectiveSupply
                );
            }

            uint256 unspecifiedDelta;
            if (ctx.protocolFeeOnInput) {
                uint256 exactOutputProtocolFeeInputAmount = FullMath.mulDiv(actualInputAbs, protocolFeeBps, BPS_BASE);
                if (exactOutputProtocolFeeInputAmount > 0) {
                    _collectProtocolFee(poolId, ctx.currencyIn, exactOutputProtocolFeeInputAmount);
                }
                unspecifiedDelta = exactOutputLpFeeInputAmount + exactOutputProtocolFeeInputAmount;
            } else {
                // Output-side protocol fee was grossed up in `beforeSwap`; here the hook withholds the realized output fee from the taker.
                if (reservedProtocolFeeOutputAmount > 0) {
                    _collectProtocolFee(poolId, ctx.currencyOut, reservedProtocolFeeOutputAmount);
                }
                unspecifiedDelta = exactOutputLpFeeInputAmount;
            }

            return (IHooks.afterSwap.selector, int128(int256(unspecifiedDelta)));
        }
        return (IHooks.afterSwap.selector, 0);
    }

    /// @dev Restricts add-liquidity modifications to calls coming from this hook itself.
    function _beforeAddLiquidity(address sender, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
        internal
        view
        override
        returns (bytes4)
    {
        if (sender != address(this)) revert SenderMustBeHook();
        return IHooks.beforeAddLiquidity.selector;
    }

    /// @notice Add full-range liquidity while the caller funds the assets and receives LP shares at `params.to`.
    /// @dev This is the low-level liquidity entrypoint intended for routers and other on-chain integrators.
    /// It omits deadline and min-amount checks and returns the settled delta to the caller.
    /// @param params The core liquidity-add parameters.
    /// @return liquidity The LP liquidity minted by the operation.
    /// @return delta The balance delta settled against the caller.
    function addLiquidityCore(AddLiquidityCoreParams calldata params)
        external
        override
        nonReentrant
        returns (uint128 liquidity, BalanceDelta delta)
    {
        return _addLiquidityCore(params, msg.sender);
    }

    function _addLiquidityCore(AddLiquidityCoreParams memory params, address payer)
        internal
        returns (uint128 liquidity, BalanceDelta addedDelta)
    {
        if (params.to == address(0)) revert ZeroAddress();
        PoolKey memory key = _poolKey(params.currency0, params.currency1);
        PoolId poolId = key.toId();
        MemeverseUniswapHookStorage storage $ = _getMemeverseUniswapHookStorage();
        PoolInfo storage pool = $.poolInfo[poolId];
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(poolId);
        if (pool.liquidityToken == address(0) || sqrtPriceX96 == 0) revert PoolNotInitialized();

        updateUserSnapshot(poolId, params.to);

        (liquidity,,) = LiquidityQuote.quote(sqrtPriceX96, params.amount0Desired, params.amount1Desired);

        addedDelta = _modifyLiquidity(
            payer,
            key,
            ModifyLiquidityParams({
                tickLower: MIN_TICK, tickUpper: MAX_TICK, liquidityDelta: liquidity.toInt256(), salt: 0
            })
        );

        UniswapLP(pool.liquidityToken).mint(params.to, liquidity);
        $.cachedLpTotalSupply[poolId] += liquidity;

        emit LiquidityAdded(
            poolId,
            payer,
            params.to,
            liquidity,
            uint256((-addedDelta.amount0()).toUint128()),
            uint256((-addedDelta.amount1()).toUint128())
        );
    }

    /// @notice Removes full-range liquidity owned by the caller and sends the underlying assets to `params.recipient`.
    /// @dev This is the low-level liquidity exit entrypoint intended for routers and other on-chain integrators.
    /// It omits deadline and min-amount checks.
    /// @param params The core liquidity-remove parameters.
    /// @return delta The balance delta returned by the liquidity removal.
    function removeLiquidityCore(RemoveLiquidityCoreParams calldata params)
        external
        override
        nonReentrant
        returns (BalanceDelta delta)
    {
        return _removeLiquidityCore(params);
    }

    function _removeLiquidityCore(RemoveLiquidityCoreParams memory params) internal returns (BalanceDelta delta) {
        if (params.recipient == address(0)) revert ZeroAddress();
        PoolKey memory key = _poolKey(params.currency0, params.currency1);
        PoolId poolId = key.toId();
        if (poolManager.getLiquidity(poolId) == 0) revert PoolNotInitialized();

        updateUserSnapshot(poolId, msg.sender);

        MemeverseUniswapHookStorage storage $ = _getMemeverseUniswapHookStorage();
        UniswapLP lp = UniswapLP($.poolInfo[poolId].liquidityToken);
        lp.burn(msg.sender, params.liquidity);
        $.cachedLpTotalSupply[poolId] -= params.liquidity;

        delta = _modifyLiquidity(
            params.recipient,
            key,
            ModifyLiquidityParams({
                tickLower: MIN_TICK, tickUpper: MAX_TICK, liquidityDelta: -(params.liquidity.toInt256()), salt: 0
            })
        );

        emit LiquidityRemoved(
            poolId,
            msg.sender,
            params.liquidity,
            uint256(delta.amount0().toUint128()),
            uint256(delta.amount1().toUint128())
        );
    }

    /// @notice Claims the caller's pending LP fees and sends them to the requested recipient.
    /// @dev Fee ownership is derived strictly from `msg.sender`; relayed or signature-based claims are unsupported.
    /// @param params The core fee-claim parameters.
    /// @return fee0Amount The claimed amount of currency0 fees.
    /// @return fee1Amount The claimed amount of currency1 fees.
    function claimFeesCore(ClaimFeesCoreParams calldata params)
        external
        override
        nonReentrant
        returns (uint256 fee0Amount, uint256 fee1Amount)
    {
        return _claimFees(params.key, msg.sender, params.recipient);
    }

    /// @notice Execute launch preorder settlement through a dedicated hook path.
    /// @dev Callable only by the configured launcher. Uses fixed 1% settlement economics and does not rely on
    /// `beforeSwap/afterSwap` marker branches.
    /// @param params Launch settlement request.
    /// @return delta Net settlement delta consumed by the launcher accounting path.
    function executeLaunchSettlement(LaunchSettlementParams calldata params)
        external
        override
        nonReentrant
        onlyLauncher
        erc20Pair(params.key.currency0, params.key.currency1)
        returns (BalanceDelta delta)
    {
        PoolId poolId = params.key.toId();
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(poolId);
        if (_getMemeverseUniswapHookStorage().poolInfo[poolId].liquidityToken == address(0) || sqrtPriceX96 == 0) {
            revert PoolNotInitialized();
        }
        if (params.params.amountSpecified >= 0) revert ZeroValue();

        _revertIfNoActiveLiquidityShares(poolId, params.params.amountSpecified);

        uint256 grossInputAmount = uint256(-params.params.amountSpecified);
        if (grossInputAmount == 0) revert ZeroValue();
        SwapFeeContext memory feeContext = _resolveSwapFeeContext(params.key, params.params.zeroForOne);
        // Vendored Uniswap v4 `Hooks.beforeSwap/afterSwap` short-circuit self-calls when `msg.sender == address(self)`.
        // Explicit settlement therefore bypasses hook callbacks on the real pool manager, so refresh the volatility
        // anchor here and replay the dynamic-state bookkeeping in the settlement callback using a pre-swap price
        // captured immediately before the actual self-swap executes.
        _refreshVolatilityAnchorAndCarry(poolId, sqrtPriceX96);
        uint256 lpFeeBps = _lpFeeBps(LAUNCH_SETTLEMENT_FEE_BPS);
        uint256 protocolFeeBps = _protocolFeeBps(LAUNCH_SETTLEMENT_FEE_BPS);
        uint256 lpFeeInputAmount = FullMath.mulDiv(grossInputAmount, lpFeeBps, BPS_BASE);
        uint256 protocolFeeInputAmount =
            feeContext.protocolFeeOnInput ? FullMath.mulDiv(grossInputAmount, protocolFeeBps, BPS_BASE) : 0;
        uint256 netInputAmount = grossInputAmount - lpFeeInputAmount - protocolFeeInputAmount;
        if (netInputAmount == 0) revert ZeroValue();

        // Regular hook callbacks are bypassed for this launcher-owned path, so settlement collects input fees explicitly here.
        _collectLaunchSettlementInputFees(msg.sender, poolId, feeContext, lpFeeInputAmount, protocolFeeInputAmount);

        SwapParams memory settlementParams = params.params;
        settlementParams.amountSpecified = -int256(netInputAmount);

        delta = abi.decode(
            poolManager.unlock(
                abi.encode(
                    UNLOCK_ACTION_LAUNCH_SETTLEMENT,
                    abi.encode(
                        LaunchSettlementCallbackData({
                            payer: msg.sender,
                            recipient: params.recipient,
                            key: params.key,
                            params: settlementParams,
                            protocolFeeOnInput: feeContext.protocolFeeOnInput
                        })
                    )
                )
            ),
            (BalanceDelta)
        );
        if (_actualInputAmount(delta, params.params.zeroForOne) != netInputAmount) revert ExactInputPartialFill();
    }

    function _modifyLiquidity(address sender, PoolKey memory key, ModifyLiquidityParams memory params)
        internal
        returns (BalanceDelta delta)
    {
        delta = abi.decode(
            poolManager.unlock(
                abi.encode(
                    UNLOCK_ACTION_MODIFY_LIQUIDITY,
                    abi.encode(ModifyLiquidityCallbackData({sender: sender, key: key, params: params}))
                )
            ),
            (BalanceDelta)
        );
    }

    /// @notice Callback invoked by the PoolManager during `unlock` flow.
    /// @dev Only callable by the PoolManager.
    /// @param rawData Encoded liquidity callback payload produced by `_modifyLiquidity`.
    /// @return result Encoded `BalanceDelta` returned back to the pool manager.
    function unlockCallback(bytes calldata rawData) external override onlyPoolManager returns (bytes memory) {
        (uint8 action, bytes memory payload) = abi.decode(rawData, (uint8, bytes));
        if (action == UNLOCK_ACTION_MODIFY_LIQUIDITY) {
            return _handleModifyLiquidityCallback(payload);
        }
        if (action == UNLOCK_ACTION_LAUNCH_SETTLEMENT) {
            return _handleLaunchSettlementCallback(payload);
        }
        revert Unauthorized();
    }

    function _handleModifyLiquidityCallback(bytes memory payload) internal returns (bytes memory) {
        ModifyLiquidityCallbackData memory data = abi.decode(payload, (ModifyLiquidityCallbackData));

        BalanceDelta delta;
        (delta,) = poolManager.modifyLiquidity(data.key, data.params, ZERO_BYTES);

        if (data.params.liquidityDelta < 0) {
            _takeDeltas(data.sender, data.key, delta);
        } else {
            _settleDeltas(data.sender, data.key, delta);
        }

        return abi.encode(delta);
    }

    function _handleLaunchSettlementCallback(bytes memory payload) internal returns (bytes memory) {
        LaunchSettlementCallbackData memory data = abi.decode(payload, (LaunchSettlementCallbackData));
        PoolId poolId = data.key.toId();
        uint256 protocolFeeBps = _protocolFeeBps(LAUNCH_SETTLEMENT_FEE_BPS);
        (uint160 preSwapSqrtPriceX96,,,) = poolManager.getSlot0(poolId);

        BalanceDelta swapDelta = poolManager.swap(data.key, data.params, ZERO_BYTES);
        _updateDynamicStateAfterSwap(poolId, swapDelta, preSwapSqrtPriceX96, data.payer);
        int128 amount0 = swapDelta.amount0();
        int128 amount1 = swapDelta.amount1();

        if (amount0 < 0) {
            data.key.currency0.settle(poolManager, data.payer, uint256((-amount0).toUint128()), false);
        }
        if (amount1 < 0) {
            data.key.currency1.settle(poolManager, data.payer, uint256((-amount1).toUint128()), false);
        }

        uint256 protocolFeeOutputAmount = 0;
        if (!data.protocolFeeOnInput) {
            // When protocol fee is charged on output, the pool pays gross proceeds first and the hook skims treasury share before forwarding.
            uint256 grossOutputAmount = _actualOutputAmount(swapDelta, data.params.zeroForOne);
            protocolFeeOutputAmount = FullMath.mulDiv(grossOutputAmount, protocolFeeBps, BPS_BASE);
            Currency outputCurrency = data.params.zeroForOne ? data.key.currency1 : data.key.currency0;
            _collectProtocolFee(poolId, outputCurrency, protocolFeeOutputAmount);
        }

        uint256 takeAmount0 = amount0 > 0 ? uint256(amount0.toUint128()) : 0;
        uint256 takeAmount1 = amount1 > 0 ? uint256(amount1.toUint128()) : 0;
        if (protocolFeeOutputAmount > 0) {
            if (data.params.zeroForOne) {
                takeAmount1 -= protocolFeeOutputAmount;
            } else {
                takeAmount0 -= protocolFeeOutputAmount;
            }
        }

        if (takeAmount0 > 0) {
            poolManager.take(data.key.currency0, data.recipient, takeAmount0);
        }
        if (takeAmount1 > 0) {
            poolManager.take(data.key.currency1, data.recipient, takeAmount1);
        }

        int128 adjustedAmount0 = amount0 > 0 ? int128(int256(takeAmount0)) : amount0;
        int128 adjustedAmount1 = amount1 > 0 ? int128(int256(takeAmount1)) : amount1;
        return abi.encode(toBalanceDelta(adjustedAmount0, adjustedAmount1));
    }

    /// @dev Transfers `amount` of `currency` to `to`.
    function _transferCurrency(Currency currency, address to, uint256 amount) internal {
        if (amount == 0) return;
        if (to == address(0)) revert ZeroAddress();
        if (!IERC20Minimal(Currency.unwrap(currency)).transfer(to, amount)) revert ERC20TransferFailed();
    }

    function _settleDeltas(address sender, PoolKey memory key, BalanceDelta delta) internal {
        key.currency0.settle(poolManager, sender, uint256((-delta.amount0()).toUint128()), false);
        key.currency1.settle(poolManager, sender, uint256((-delta.amount1()).toUint128()), false);
    }

    function _takeDeltas(address recipient, PoolKey memory key, BalanceDelta delta) internal {
        poolManager.take(key.currency0, recipient, uint256(delta.amount0().toUint128()));
        poolManager.take(key.currency1, recipient, uint256(delta.amount1().toUint128()));
    }

    function _claimFees(PoolKey memory key, address owner, address recipient)
        internal
        erc20Pair(key.currency0, key.currency1)
        returns (uint256 fee0Amount, uint256 fee1Amount)
    {
        PoolId poolId = key.toId();
        MemeverseUniswapHookStorage storage $ = _getMemeverseUniswapHookStorage();
        if ($.poolInfo[poolId].liquidityToken == address(0)) revert PoolNotInitialized();

        updateUserSnapshot(poolId, owner);

        UserFeeState storage state = $.userFeeState[poolId][owner];
        fee0Amount = state.pendingFee0;
        fee1Amount = state.pendingFee1;

        if (fee0Amount > 0) {
            state.pendingFee0 = 0;
            _transferCurrency(key.currency0, recipient, fee0Amount);
        }
        if (fee1Amount > 0) {
            state.pendingFee1 = 0;
            _transferCurrency(key.currency1, recipient, fee1Amount);
        }

        if (fee0Amount > 0 || fee1Amount > 0) {
            emit FeesClaimed(poolId, owner, key.currency0, key.currency1, fee0Amount, fee1Amount);
        }
    }

    function _poolKey(Currency currency0, Currency currency1)
        internal
        view
        erc20Pair(currency0, currency1)
        returns (PoolKey memory key)
    {
        key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(this))
        });
    }

    function _poolIdForTokens(address tokenA, address tokenB) internal view returns (PoolId poolId) {
        (Currency currency0, Currency currency1) = tokenA < tokenB
            ? (Currency.wrap(tokenA), Currency.wrap(tokenB))
            : (Currency.wrap(tokenB), Currency.wrap(tokenA));
        poolId = _poolKey(currency0, currency1).toId();
    }

    function _resolveSwapFeeContext(PoolKey memory key, bool zeroForOne)
        internal
        view
        returns (SwapFeeContext memory ctx)
    {
        ctx.currencyIn = zeroForOne ? key.currency0 : key.currency1;
        ctx.currencyOut = zeroForOne ? key.currency1 : key.currency0;
        if (_isProtocolFeeCurrencySupported(ctx.currencyIn)) {
            ctx.protocolFeeOnInput = true;
        } else if (_isProtocolFeeCurrencySupported(ctx.currencyOut)) {
            ctx.protocolFeeOnInput = false;
        } else {
            revert CurrencyNotSupported();
        }
        ctx.inputIsCurrency0 = zeroForOne;
    }

    function _collectProtocolFee(PoolId poolId, Currency feeCurrency, uint256 protocolFeeAmount) internal {
        if (protocolFeeAmount == 0) return;
        address treasury_ = _takeToTreasury(feeCurrency, protocolFeeAmount);
        emit ProtocolFeeCollected(poolId, feeCurrency, treasury_, protocolFeeAmount, block.number);
    }

    function _collectLpFee(
        PoolId poolId,
        Currency feeCurrency,
        bool feeCurrencyIsCurrency0,
        uint256 lpFeeAmount,
        uint256 effectiveSupply
    ) internal {
        if (lpFeeAmount == 0) return;
        if (effectiveSupply == 0) return;

        poolManager.take(feeCurrency, address(this), lpFeeAmount);
        _creditLpFee(poolId, feeCurrency, feeCurrencyIsCurrency0, lpFeeAmount, effectiveSupply);
    }

    function _collectLaunchSettlementInputFees(
        address payer,
        PoolId poolId,
        SwapFeeContext memory ctx,
        uint256 lpFeeInputAmount,
        uint256 protocolFeeInputAmount
    ) internal {
        MemeverseUniswapHookStorage storage $ = _getMemeverseUniswapHookStorage();
        if (lpFeeInputAmount > 0) {
            uint256 effectiveSupply = $.cachedLpTotalSupply[poolId];
            if (effectiveSupply == 0) revert NoActiveLiquidityShares();
            // Launcher settlement pulls ERC20 fees directly from the payer because there is no public-swap callback collection step.
            if (!IERC20Minimal(Currency.unwrap(ctx.currencyIn)).transferFrom(payer, address(this), lpFeeInputAmount)) {
                revert ERC20TransferFailed();
            }
            _creditLpFee(poolId, ctx.currencyIn, ctx.inputIsCurrency0, lpFeeInputAmount, effectiveSupply);
        }

        if (protocolFeeInputAmount > 0) {
            address treasury_ = $.treasury;
            if (!IERC20Minimal(Currency.unwrap(ctx.currencyIn)).transferFrom(payer, treasury_, protocolFeeInputAmount))
            {
                revert ERC20TransferFailed();
            }
            emit ProtocolFeeCollected(poolId, ctx.currencyIn, treasury_, protocolFeeInputAmount, block.number);
        }
    }

    function _takeToTreasury(Currency feeCurrency, uint256 amount) internal returns (address treasury_) {
        treasury_ = _getMemeverseUniswapHookStorage().treasury;
        if (treasury_ == address(0)) revert Unauthorized();
        poolManager.take(feeCurrency, treasury_, amount);
    }

    function _setProtocolFeeCurrencySupport(Currency currency, bool supported) internal {
        if (currency.isAddressZero()) revert NativeCurrencyUnsupported();
        _getMemeverseUniswapHookStorage().supportedProtocolFeeCurrencies[Currency.unwrap(currency)] = supported;
        emit ProtocolFeeCurrencySupportUpdated(currency, supported);
    }

    function _isProtocolFeeCurrencySupported(Currency currency) internal view returns (bool) {
        return _getMemeverseUniswapHookStorage().supportedProtocolFeeCurrencies[Currency.unwrap(currency)];
    }

    function _creditLpFee(
        PoolId poolId,
        Currency feeCurrency,
        bool feeCurrencyIsCurrency0,
        uint256 lpFeeAmount,
        uint256 effectiveSupply
    ) internal {
        PoolInfo storage pool = _getMemeverseUniswapHookStorage().poolInfo[poolId];
        uint256 feePerShare = FullMath.mulDiv(lpFeeAmount, FEE_GROWTH_Q128, effectiveSupply);
        if (feeCurrencyIsCurrency0) {
            uint256 newFee0PerShare = pool.fee0PerShare + feePerShare;
            pool.fee0PerShare = newFee0PerShare;
            emit LPFeeCollected(poolId, feeCurrency, lpFeeAmount, newFee0PerShare, block.number);
        } else {
            uint256 newFee1PerShare = pool.fee1PerShare + feePerShare;
            pool.fee1PerShare = newFee1PerShare;
            emit LPFeeCollected(poolId, feeCurrency, lpFeeAmount, newFee1PerShare, block.number);
        }
    }

    function _actualInputAmount(BalanceDelta delta, bool zeroForOne) internal pure returns (uint256) {
        return zeroForOne ? uint256((-delta.amount0()).toUint128()) : uint256((-delta.amount1()).toUint128());
    }

    function _actualOutputAmount(BalanceDelta delta, bool zeroForOne) internal pure returns (uint256) {
        return zeroForOne ? uint256(delta.amount1().toUint128()) : uint256(delta.amount0().toUint128());
    }

    function _protocolFeeBps(uint256 feeBps) internal pure returns (uint256) {
        return FullMath.mulDiv(feeBps, PROTOCOL_FEE_RATIO_BPS, BPS_BASE);
    }

    function _lpFeeBps(uint256 feeBps) internal pure returns (uint256) {
        // Safe: PROTOCOL_FEE_RATIO_BPS = 3000 < BPS_BASE = 10000, so _protocolFeeBps(feeBps) <= feeBps * 3 / 10 < feeBps.
        unchecked {
            return feeBps - _protocolFeeBps(feeBps);
        }
    }

    /// @notice Updates the user fee accounting snapshot for a pool.
    /// @dev Requires the pool LP token to exist. Accrues newly earned fees into `pendingFee0/1`
    /// and updates per-share offsets for `user`.
    /// @param id The hook-managed pool id.
    /// @param user The user whose fee snapshot is synchronized.
    function updateUserSnapshot(PoolId id, address user) public override {
        MemeverseUniswapHookStorage storage $ = _getMemeverseUniswapHookStorage();
        PoolInfo storage pool = $.poolInfo[id];
        UserFeeState storage state = $.userFeeState[id][user];

        if (user == address(0)) {
            state.fee0Offset = pool.fee0PerShare;
            state.fee1Offset = pool.fee1PerShare;
            return;
        }

        uint256 balance = UniswapLP(pool.liquidityToken).balanceOf(user);
        if (balance == 0) {
            // A zero-balance account should not retain stale offsets; advancing them prevents future mint recipients from inheriting old fees.
            state.fee0Offset = pool.fee0PerShare;
            state.fee1Offset = pool.fee1PerShare;
            return;
        }

        unchecked {
            // Crystallize accrued fees before any mint/burn changes the user's LP balance baseline.
            uint256 fee0Claimable = FullMath.mulDiv(balance, pool.fee0PerShare - state.fee0Offset, FEE_GROWTH_Q128);
            uint256 fee1Claimable = FullMath.mulDiv(balance, pool.fee1PerShare - state.fee1Offset, FEE_GROWTH_Q128);

            if (fee0Claimable > 0) state.pendingFee0 += fee0Claimable;
            if (fee1Claimable > 0) state.pendingFee1 += fee1Claimable;
        }

        state.fee0Offset = pool.fee0PerShare;
        state.fee1Offset = pool.fee1PerShare;
    }

    function _activeLpSupplyForSwap(PoolId poolId, int256 amountSpecified)
        internal
        view
        returns (uint256 effectiveSupply)
    {
        if (amountSpecified == 0) return 0;

        effectiveSupply = _getMemeverseUniswapHookStorage().cachedLpTotalSupply[poolId];
        if (effectiveSupply != 0) return effectiveSupply;
        // A fully drained pool returns 0 to preserve zero-liquidity quote semantics.
        if (poolManager.getLiquidity(poolId) == 0) return 0;
        revert NoActiveLiquidityShares();
    }

    function _revertIfNoActiveLiquidityShares(PoolId poolId, int256 amountSpecified) internal view {
        _activeLpSupplyForSwap(poolId, amountSpecified);
    }

    /// @notice Updates the treasury address.
    /// @dev Only callable by the owner. Zero address is rejected because protocol fees require a concrete recipient.
    /// The configured treasury is expected to be a passive receiver and must not use fee receipts to trigger
    /// reentrant swap or liquidity actions.
    /// @param _treasury The new treasury address.
    function setTreasury(address _treasury) external onlyOwner {
        if (_treasury == address(0)) revert ZeroAddress();
        MemeverseUniswapHookStorage storage $ = _getMemeverseUniswapHookStorage();
        address old = $.treasury;
        $.treasury = _treasury;
        emit TreasuryUpdated(old, _treasury);
    }

    /// @notice Enables a currency as a supported protocol-fee settlement currency.
    /// @dev This is a convenience wrapper for `setProtocolFeeCurrencySupport(currency, true)`.
    /// @param currency The currency to enable for protocol-fee settlement.
    function setProtocolFeeCurrency(Currency currency) external onlyOwner {
        _setProtocolFeeCurrencySupport(currency, true);
    }

    /// @notice Updates whether a currency is eligible to receive protocol fees.
    /// @dev If both pool sides are supported, the swap path will prefer charging protocol fees on the input side.
    /// @param currency The currency whose support flag is being updated.
    /// @param supported Whether protocol fees may settle in `currency`.
    function setProtocolFeeCurrencySupport(Currency currency, bool supported) external onlyOwner {
        _setProtocolFeeCurrencySupport(currency, supported);
    }

    /// @notice Emergency switch: if enabled, dynamic fee charging falls back to base fee only.
    /// @dev Intended as an owner-controlled safety valve for fee logic incidents.
    /// @param flag Whether emergency fixed-fee mode should be enabled.
    function setEmergencyFlag(bool flag) external onlyOwner {
        MemeverseUniswapHookStorage storage $ = _getMemeverseUniswapHookStorage();
        bool old = $.emergencyFlag;
        $.emergencyFlag = flag;
        emit EmergencyFlagUpdated(old, flag);
    }

    /// @notice Sets the launcher consulted for post-unlock public-swap protection.
    /// @dev Only callable by the owner. Zero address is rejected to avoid accidental fail-open reconfiguration.
    /// @param launcher_ The launcher binding used for `isPublicSwapAllowed` checks.
    function setLauncher(address launcher_) external onlyOwner {
        if (launcher_ == address(0)) revert ZeroAddress();
        MemeverseUniswapHookStorage storage $ = _getMemeverseUniswapHookStorage();
        address oldLauncher = $.launcher;
        $.launcher = launcher_;
        emit LauncherUpdated(oldLauncher, launcher_);
    }

    /// @notice Sets the router authorized to initialize hook-managed pools.
    /// @dev Pool initialization remains blocked unless this router writes a matching one-time authorization.
    /// @param initializer The authorized pool-initializer router.
    function setPoolInitializer(address initializer) external onlyOwner {
        if (initializer == address(0)) revert ZeroAddress();
        MemeverseUniswapHookStorage storage $ = _getMemeverseUniswapHookStorage();
        address oldInitializer = $.poolInitializer;
        $.poolInitializer = initializer;
        emit PoolInitializerUpdated(oldInitializer, initializer);
    }

    /// @notice Authorizes the configured pool initializer to initialize one pool at one exact start price.
    /// @dev The authorization is consumed in `beforeInitialize`.
    /// @param key Pool key being authorized.
    /// @param startPriceX96 Expected initial pool price.
    function authorizePoolInitialization(PoolKey calldata key, uint160 startPriceX96)
        external
        erc20Pair(key.currency0, key.currency1)
    {
        MemeverseUniswapHookStorage storage $ = _getMemeverseUniswapHookStorage();
        if (msg.sender != $.poolInitializer) revert UnauthorizedPoolInitializer();
        PoolId poolId = key.toId();
        if ($.poolInitializationAuth[poolId].active) revert PoolInitializationAlreadyAuthorized();
        $.poolInitializationAuth[poolId] = PoolInitializationAuth({startPriceX96: startPriceX96, active: true});
        emit PoolInitializationAuthorized(poolId, startPriceX96);
    }

    /// @notice Sets the pool-level public-swap resume time written by the launcher.
    /// @dev Only the configured launcher may snapshot post-unlock protection windows onto pools.
    /// The hook resolves the pool identity locally from the token pair so launcher-side protection writes do not
    /// depend on mutable router helpers.
    /// @param tokenA One token in the protected pool.
    /// @param tokenB The other token in the protected pool.
    /// @param resumeTime New public-swap resume timestamp for the pool.
    function setPublicSwapResumeTime(address tokenA, address tokenB, uint40 resumeTime) external onlyLauncher {
        MemeverseUniswapHookStorage storage $ = _getMemeverseUniswapHookStorage();
        PoolId poolId = _poolIdForTokens(tokenA, tokenB);
        uint40 oldResumeTime = $.publicSwapResumeTime[poolId];
        $.publicSwapResumeTime[poolId] = resumeTime;
        emit PublicSwapResumeTimeUpdated(poolId, oldResumeTime, resumeTime);
    }

    /// @notice Sets the default launch fee configuration.
    /// @dev Only callable by the owner. Zero values and out-of-range schedules are rejected.
    /// @param config The new default launch fee configuration.
    function setDefaultLaunchFeeConfig(LaunchFeeConfig calldata config) external onlyOwner {
        if (config.startFeeBps == 0 || config.minFeeBps == 0 || config.decayDurationSeconds == 0) revert ZeroValue();
        if (config.startFeeBps > BPS_BASE || config.minFeeBps > BPS_BASE || config.minFeeBps > config.startFeeBps) {
            revert ZeroValue();
        }
        MemeverseUniswapHookStorage storage $ = _getMemeverseUniswapHookStorage();
        LaunchFeeConfig memory oldConfig = $.defaultLaunchFeeConfig;
        $.defaultLaunchFeeConfig = config;
        emit DefaultLaunchFeeConfigUpdated(
            oldConfig.startFeeBps,
            oldConfig.minFeeBps,
            oldConfig.decayDurationSeconds,
            config.startFeeBps,
            config.minFeeBps,
            config.decayDurationSeconds
        );
    }

    // -----------------------------------------------------------------------------
    // Dynamic fee computation
    // -----------------------------------------------------------------------------

    /// @dev Dynamic fee quote. Returns base-fee pricing in emergency mode and for zero-sized/zero-liquidity cases.
    /// Still estimates swap flow in emergency mode so exact-output callers receive usable input/output guardrails.
    function _quoteDynamicFee(
        PoolId poolId,
        SwapParams calldata params,
        uint160 preSqrtPriceX96,
        bool feeOnInput,
        address sender
    ) internal view returns (DynamicFeeQuote memory quote) {
        MemeverseUniswapHookStorage storage $ = _getMemeverseUniswapHookStorage();
        uint256 launchFeeBps = _quoteLaunchFeeBps($, poolId);
        quote.feeBps = launchFeeBps > FEE_BASE_BPS ? launchFeeBps : FEE_BASE_BPS;
        if (params.amountSpecified == 0) return quote;

        uint128 liquidity = poolManager.getLiquidity(poolId);
        if (liquidity == 0) return quote;

        if ($.emergencyFlag) {
            EWVWAPParams memory emptyState;
            return _estimateDynamicFeeQuote(
                emptyState,
                liquidity,
                preSqrtPriceX96,
                params.zeroForOne,
                params.amountSpecified,
                feeOnInput,
                true,
                launchFeeBps,
                poolId,
                sender
            );
        }

        return _estimateDynamicFeeQuote(
            $.poolEWVWAPParams[poolId],
            liquidity,
            preSqrtPriceX96,
            params.zeroForOne,
            params.amountSpecified,
            feeOnInput,
            false,
            launchFeeBps,
            poolId,
            sender
        );
    }

    function _quoteLaunchFeeBps(MemeverseUniswapHookStorage storage $, PoolId poolId)
        internal
        view
        returns (uint256 feeBps)
    {
        LaunchFeeConfig memory config = $.defaultLaunchFeeConfig;
        uint40 launchTimestamp = $.poolLaunchTimestamp[poolId];
        if (launchTimestamp == 0) return config.minFeeBps;

        uint256 elapsed = block.timestamp > launchTimestamp ? block.timestamp - launchTimestamp : 0;
        if (elapsed >= config.decayDurationSeconds) return config.minFeeBps;

        uint256 decayWad = _normalizedLaunchDecayWad(elapsed, config.decayDurationSeconds);
        feeBps = config.minFeeBps + FullMath.mulDiv(config.startFeeBps - config.minFeeBps, decayWad, 1e18);
    }

    function _normalizedLaunchDecayWad(uint256 elapsed, uint256 duration) internal pure returns (uint256 decayWad) {
        int256 expAtElapsedWad = wadExp(-int256(FullMath.mulDiv(elapsed, uint256(LAUNCH_FEE_EXP_SHAPE_WAD), duration)));
        int256 expAtEndWad = wadExp(-LAUNCH_FEE_EXP_SHAPE_WAD);
        decayWad = uint256((expAtElapsedWad - expAtEndWad) * 1e18 / (1e18 - expAtEndWad));
    }

    function _estimateDynamicFeeQuote(
        EWVWAPParams memory state,
        uint128 liquidity,
        uint160 preSqrtPriceX96,
        bool zeroForOne,
        int256 amountSpecified,
        bool feeOnInput,
        bool emergencyMode,
        uint256 launchFeeBps,
        PoolId poolId,
        address sender
    ) internal view returns (DynamicFeeQuote memory quote) {
        quote.feeBps = launchFeeBps > FEE_BASE_BPS ? launchFeeBps : FEE_BASE_BPS;
        if (amountSpecified == 0 || liquidity == 0) return quote;

        int256 workingAmountSpecified = amountSpecified;
        uint256 userInputAmount = amountSpecified < 0 ? uint256(-amountSpecified) : 0;
        uint256 requestedNetOutputAmount = amountSpecified > 0 ? uint256(amountSpecified) : 0;

        uint256 spotBeforeX18;
        uint256 preVolatilityPartBps;
        uint256 preDecayedShortPpm;
        AddressBatchState memory senderBatchState;
        if (!emergencyMode) {
            spotBeforeX18 = _spotX18FromSqrtPrice(preSqrtPriceX96);
            senderBatchState = _getMemeverseUniswapHookStorage().addressBatchState[sender][poolId];
            preVolatilityPartBps = _volatilitySqrtFeeBps(state.volDeviationAccumulator);
            preDecayedShortPpm = _decayLinearPpm(state.shortImpactPpm, state.shortLastTs, SHORT_DECAY_WINDOW_SEC);
        }

        for (uint256 i = 0; i < 3; ++i) {
            uint160 postSqrtPriceX96;
            (
                quote.estimatedInputAmount,
                quote.estimatedOutputAmount,
                quote.estimatedGrossOutputAmount,
                postSqrtPriceX96
            ) = _estimateSwapFlowAndPostPrice(liquidity, preSqrtPriceX96, zeroForOne, workingAmountSpecified);
            if (quote.estimatedInputAmount == 0) return quote;

            if (!emergencyMode) {
                quote.spotBeforeX18 = spotBeforeX18;
                quote.spotAfterX18 = _spotX18FromSqrtPrice(postSqrtPriceX96);
                quote.pifPpm = _priceMovePpmCapped(preSqrtPriceX96, postSqrtPriceX96);
                _populateDynamicFeeQuoteFromState(
                    quote, state, senderBatchState, preVolatilityPartBps, preDecayedShortPpm
                );
            }

            if (launchFeeBps > quote.feeBps) quote.feeBps = launchFeeBps;

            if (amountSpecified < 0) {
                uint256 inputSideFeeBps = feeOnInput ? quote.feeBps : _lpFeeBps(quote.feeBps);
                uint256 inputSideFeeAmount = FullMath.mulDiv(userInputAmount, inputSideFeeBps, BPS_BASE);
                uint256 netPoolInputAmount =
                    userInputAmount > inputSideFeeAmount ? userInputAmount - inputSideFeeAmount : 0;
                if (netPoolInputAmount == quote.estimatedInputAmount) {
                    return quote;
                }

                workingAmountSpecified = -int256(netPoolInputAmount);
                continue;
            }

            if (feeOnInput) return quote;

            uint256 grossedOutputAmount = requestedNetOutputAmount
                + _grossUpFeeFromNetOutput(requestedNetOutputAmount, _protocolFeeBps(quote.feeBps));
            if (grossedOutputAmount == quote.estimatedGrossOutputAmount) {
                quote.estimatedOutputAmount = requestedNetOutputAmount;
                return quote;
            }

            workingAmountSpecified = int256(grossedOutputAmount);
        }

        if (amountSpecified > 0 && !feeOnInput) quote.estimatedOutputAmount = requestedNetOutputAmount;

        return quote;
    }

    function _populateDynamicFeeQuoteFromState(
        DynamicFeeQuote memory quote,
        EWVWAPParams memory state,
        AddressBatchState memory senderBatchState,
        uint256 preVolatilityPartBps,
        uint256 preDecayedShortPpm
    ) internal view {
        bool hasHistory = state.weightedVolume0 > 0 && state.ewVWAPX18 > 0;
        if (hasHistory) {
            uint256 distBefore = _absDiff(quote.spotBeforeX18, state.ewVWAPX18);
            uint256 distAfter = _absDiff(quote.spotAfterX18, state.ewVWAPX18);
            quote.isAdverse = distAfter > distBefore;
        } else {
            quote.isAdverse = true;
        }

        if (hasHistory && !quote.isAdverse) {
            quote.feeBps = FEE_BASE_BPS;
            return;
        }

        {
            uint256 effectivePifPpm = quote.pifPpm;
            if (
                senderBatchState.batchStartTs > 0
                    && block.timestamp - uint256(senderBatchState.batchStartTs) < ADDRESS_BATCH_WINDOW_SEC
            ) {
                effectivePifPpm = uint256(senderBatchState.batchAccumPpm) + quote.pifPpm;
            }
            uint256 satPpm = FullMath.mulDiv(effectivePifPpm, PPM_BASE, effectivePifPpm + PIF_CAP_PPM);
            uint256 dffPpm = FullMath.mulDiv(FEE_DFF_MAX_PPM, satPpm, PPM_BASE);
            uint256 dynamicPpm = FullMath.mulDiv(dffPpm, effectivePifPpm, PPM_BASE);
            quote.adverseImpactPartBps = dynamicPpm / (PPM_BASE / BPS_BASE);
        }

        quote.volatilityPartBps = preVolatilityPartBps;

        uint256 decayedShortPpm = preDecayedShortPpm;
        uint256 projectedShortPpm = decayedShortPpm + quote.pifPpm;
        if (projectedShortPpm > SHORT_CAP_PPM) projectedShortPpm = SHORT_CAP_PPM;
        uint256 chargeableShortPpm = projectedShortPpm > SHORT_FLOOR_PPM ? projectedShortPpm - SHORT_FLOOR_PPM : 0;
        quote.shortImpactPartBps = FullMath.mulDiv(chargeableShortPpm, SHORT_COEFF_BPS, PPM_BASE);

        uint256 feeBps = FEE_BASE_BPS + quote.adverseImpactPartBps + quote.volatilityPartBps + quote.shortImpactPartBps;
        if (feeBps > FEE_MAX_BPS) feeBps = FEE_MAX_BPS;
        quote.feeBps = feeBps;
    }

    function _estimateSwapFlowAndPostPrice(
        uint128 liquidity,
        uint160 preSqrtPriceX96,
        bool zeroForOne,
        int256 amountSpecified
    )
        internal
        pure
        returns (uint256 inputAmount, uint256 outputAmount, uint256 grossOutputAmount, uint160 postSqrtPriceX96)
    {
        if (amountSpecified == 0) return (0, 0, 0, preSqrtPriceX96);

        if (amountSpecified < 0) {
            inputAmount = uint256(-amountSpecified);
            postSqrtPriceX96 =
                SqrtPriceMath.getNextSqrtPriceFromInput(preSqrtPriceX96, liquidity, inputAmount, zeroForOne);
            outputAmount = zeroForOne
                ? SqrtPriceMath.getAmount1Delta(postSqrtPriceX96, preSqrtPriceX96, liquidity, false)
                : SqrtPriceMath.getAmount0Delta(preSqrtPriceX96, postSqrtPriceX96, liquidity, false);
            grossOutputAmount = outputAmount;
            return (inputAmount, outputAmount, grossOutputAmount, postSqrtPriceX96);
        }

        outputAmount = uint256(amountSpecified);
        grossOutputAmount = outputAmount;

        postSqrtPriceX96 =
            SqrtPriceMath.getNextSqrtPriceFromOutput(preSqrtPriceX96, liquidity, grossOutputAmount, zeroForOne);
        inputAmount = zeroForOne
            ? SqrtPriceMath.getAmount0Delta(postSqrtPriceX96, preSqrtPriceX96, liquidity, true)
            : SqrtPriceMath.getAmount1Delta(preSqrtPriceX96, postSqrtPriceX96, liquidity, true);
    }

    function _grossUpFeeFromNetOutput(uint256 netOutputAmount, uint256 feeBps)
        internal
        pure
        returns (uint256 feeAmount)
    {
        if (netOutputAmount == 0 || feeBps == 0) return 0;
        if (feeBps >= BPS_BASE) return type(uint256).max;
        uint256 grossOutputAmount = FullMath.mulDivRoundingUp(netOutputAmount, BPS_BASE, BPS_BASE - feeBps);
        return grossOutputAmount - netOutputAmount;
    }

    /// @dev Updates ewVWAP, reference-price volatility state, and short-term impact state using the realized swap outcome.
    function _updateDynamicStateAfterSwap(PoolId poolId, BalanceDelta delta, uint160 preSqrtPriceX96, address sender)
        internal
    {
        if (preSqrtPriceX96 == 0) return;

        (uint160 postSqrtPriceX96,,,) = poolManager.getSlot0(poolId);
        uint256 pifPpm = _priceMovePpmCapped(preSqrtPriceX96, postSqrtPriceX96);
        MemeverseUniswapHookStorage storage $ = _getMemeverseUniswapHookStorage();
        EWVWAPParams storage state = $.poolEWVWAPParams[poolId];

        AddressBatchState storage bs = $.addressBatchState[sender][poolId];
        if (bs.batchStartTs > 0 && block.timestamp - uint256(bs.batchStartTs) < ADDRESS_BATCH_WINDOW_SEC) {
            bs.batchAccumPpm = uint192(uint256(bs.batchAccumPpm) + pifPpm);
        } else {
            bs.batchAccumPpm = uint192(pifPpm);
            bs.batchStartTs = uint64(block.timestamp);
        }

        uint256 decayedShortPpm = _decayLinearPpm(state.shortImpactPpm, state.shortLastTs, SHORT_DECAY_WINDOW_SEC);
        uint256 updatedShortPpm = decayedShortPpm + pifPpm;
        if (updatedShortPpm > SHORT_CAP_PPM) updatedShortPpm = SHORT_CAP_PPM;
        state.shortImpactPpm = uint24(updatedShortPpm);
        state.shortLastTs = uint40(block.timestamp);

        uint256 spotX18 = _spotX18FromSqrtPrice(postSqrtPriceX96);
        int256 amount0 = delta.amount0();
        uint256 volume0 = uint256(amount0 < 0 ? -amount0 : amount0);
        _updateVolatilityDeviationAccumulatorAfterSwap(state, postSqrtPriceX96);
        if (volume0 == 0 || spotX18 == 0) return;
        uint256 alpha = FEE_ALPHA;
        uint256 alphaR = PPM_BASE - alpha;
        uint256 priceVolume = FullMath.mulDiv(volume0, spotX18, EWVWAP_PRECISION);

        if (state.weightedVolume0 == 0) {
            state.weightedVolume0 = volume0;
            state.weightedPriceVolume0 = priceVolume;
            state.ewVWAPX18 = spotX18;
        } else {
            uint256 newWeightedVolume0 =
                FullMath.mulDiv(alpha, volume0, PPM_BASE) + FullMath.mulDiv(alphaR, state.weightedVolume0, PPM_BASE);
            uint256 newWeightedPriceVolume0 = FullMath.mulDiv(alpha, priceVolume, PPM_BASE)
                + FullMath.mulDiv(alphaR, state.weightedPriceVolume0, PPM_BASE);
            state.weightedVolume0 = newWeightedVolume0;
            state.weightedPriceVolume0 = newWeightedPriceVolume0;
            if (newWeightedVolume0 > 0) {
                state.ewVWAPX18 = FullMath.mulDiv(newWeightedPriceVolume0, EWVWAP_PRECISION, newWeightedVolume0);
            }
        }
    }

    function _decayLinearPpm(uint256 accumulatorPpm, uint256 lastTs, uint256 windowSec)
        internal
        view
        returns (uint256)
    {
        if (accumulatorPpm == 0 || lastTs == 0 || windowSec == 0) return 0;
        if (block.timestamp <= lastTs) return accumulatorPpm;
        uint256 elapsed = block.timestamp - lastTs;
        if (elapsed >= windowSec) return 0;
        return FullMath.mulDiv(accumulatorPpm, windowSec - elapsed, windowSec);
    }

    function _refreshVolatilityAnchorAndCarry(PoolId poolId, uint160 preSqrtPriceX96) internal {
        EWVWAPParams storage state = _getMemeverseUniswapHookStorage().poolEWVWAPParams[poolId];

        if (state.volAnchorSqrtPriceX96 == 0) {
            state.volAnchorSqrtPriceX96 = preSqrtPriceX96;
        }

        uint256 elapsed = block.timestamp > state.volLastMoveTs ? block.timestamp - state.volLastMoveTs : 0;
        if (elapsed < VOL_FILTER_PERIOD_SEC) return;

        state.volAnchorSqrtPriceX96 = preSqrtPriceX96;
        if (state.volLastMoveTs != 0 && elapsed < VOL_DECAY_PERIOD_SEC) {
            state.volCarryAccumulator =
                uint24(FullMath.mulDiv(state.volDeviationAccumulator, VOL_DECAY_FACTOR_BPS, BPS_BASE));
        } else {
            state.volCarryAccumulator = 0;
        }
        state.volDeviationAccumulator = state.volCarryAccumulator;
    }

    function _updateVolatilityDeviationAccumulatorAfterSwap(EWVWAPParams storage state, uint160 postSqrtPriceX96)
        internal
    {
        if (state.volAnchorSqrtPriceX96 == 0) {
            state.volAnchorSqrtPriceX96 = postSqrtPriceX96;
            return;
        }

        uint256 deltaSteps =
            _volatilityDeltaSteps(state.volAnchorSqrtPriceX96, postSqrtPriceX96, VOL_DEVIATION_STEP_BPS);
        uint256 updatedAccumulator = uint256(state.volCarryAccumulator) + deltaSteps * uint256(VOL_INCREMENT_PER_STEP);
        if (updatedAccumulator > VOL_MAX_DEVIATION_ACCUMULATOR) updatedAccumulator = VOL_MAX_DEVIATION_ACCUMULATOR;
        state.volDeviationAccumulator = uint24(updatedAccumulator);

        if (deltaSteps > 0) {
            state.volLastMoveTs = uint40(block.timestamp);
        }
    }

    function _volatilitySqrtFeeBps(uint256 accumulator) internal pure returns (uint256) {
        if (accumulator == 0) return 0;
        // volFeeBps = sqrt(acc / maxAcc) * maxFee, rearranged to avoid precision loss:
        // sqrt(acc * maxFee^2 / maxAcc). Integer division truncates for accumulator < 600
        // (fee would be < 1 bps, so the dead zone is negligible).
        return Math.sqrt(accumulator * uint256(VOL_MAX_FEE_BPS) ** 2 / uint256(VOL_MAX_DEVIATION_ACCUMULATOR));
    }

    function _volatilityDeltaSteps(uint160 referenceSqrtPriceX96, uint160 currentSqrtPriceX96, uint256 stepBps)
        internal
        pure
        returns (uint256)
    {
        if (referenceSqrtPriceX96 == 0 || currentSqrtPriceX96 == 0 || stepBps == 0) return 0;

        (uint256 upper, uint256 lower) = referenceSqrtPriceX96 > currentSqrtPriceX96
            ? (uint256(referenceSqrtPriceX96), uint256(currentSqrtPriceX96))
            : (uint256(currentSqrtPriceX96), uint256(referenceSqrtPriceX96));
        uint256 sqrtRatioX18 = FullMath.mulDiv(upper, EWVWAP_PRECISION, lower);
        if (sqrtRatioX18 <= EWVWAP_PRECISION) return 0;

        return FullMath.mulDiv(sqrtRatioX18 - EWVWAP_PRECISION, BPS_BASE * 2, stepBps * EWVWAP_PRECISION);
    }

    function _spotX18FromSqrtPrice(uint160 sqrtPriceX96) internal pure returns (uint256) {
        (uint256 squareHi, uint256 squareLo) = _squareWide(sqrtPriceX96);
        uint256 integerPart = (squareHi << 64) | (squareLo >> 192);
        uint256 fractionalPart = squareLo & Q192_MASK;
        return integerPart * EWVWAP_PRECISION + FullMath.mulDiv(fractionalPart, EWVWAP_PRECISION, Q192);
    }

    function _absDiff(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }

    function _priceMovePpmCapped(uint160 preSqrtPrice, uint160 postSqrtPrice) internal pure returns (uint256) {
        if (preSqrtPrice == postSqrtPrice) return 0;

        uint256 sqrtRatioX18 = FullMath.mulDiv(uint256(postSqrtPrice), EWVWAP_PRECISION, uint256(preSqrtPrice));

        if (postSqrtPrice > preSqrtPrice) {
            if (sqrtRatioX18 > UP_SHORT_BUCKET) return PIF_CAP_PPM;

            uint256 upSquaredRatioX18 = FullMath.mulDiv(sqrtRatioX18, sqrtRatioX18, EWVWAP_PRECISION);
            uint256 candidate = (upSquaredRatioX18 - EWVWAP_PRECISION) / 1e12;
            if (
                candidate < PIF_CAP_PPM
                    && _wideSquareTimesSmallGte(postSqrtPrice, PPM_BASE, preSqrtPrice, PPM_BASE + candidate + 1)
            ) {
                ++candidate;
            }
            return candidate;
        }

        if (sqrtRatioX18 < DOWN_SHORT_BUCKET) return PIF_CAP_PPM;

        uint256 downSquaredRatioX18 = FullMath.mulDiv(sqrtRatioX18, sqrtRatioX18, EWVWAP_PRECISION);
        uint256 candidatePpm = (EWVWAP_PRECISION - downSquaredRatioX18) / 1e12;
        if (
            candidatePpm != 0
                && !_wideSquareTimesSmallLte(postSqrtPrice, PPM_BASE, preSqrtPrice, PPM_BASE - candidatePpm)
        ) {
            --candidatePpm;
        }
        return candidatePpm;
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

    function _mulWideBySmall(uint256 hi, uint256 lo, uint256 factor)
        internal
        pure
        returns (uint256 outHi, uint256 outLo)
    {
        uint256 loLower = uint128(lo);
        uint256 loUpper = lo >> 128;
        uint256 lowerProduct = loLower * factor;
        uint256 upperProduct = loUpper * factor;

        unchecked {
            outLo = lowerProduct + (upperProduct << 128);
        }
        outHi = (hi * factor) + (upperProduct >> 128);
        if (outLo < lowerProduct) ++outHi;
    }

    function _wideSquareTimesSmallGte(uint160 left, uint256 leftFactor, uint160 right, uint256 rightFactor)
        internal
        pure
        returns (bool)
    {
        (uint256 leftSquareHi, uint256 leftSquareLo) = _squareWide(left);
        (uint256 rightSquareHi, uint256 rightSquareLo) = _squareWide(right);
        (uint256 leftHi, uint256 leftLo) = _mulWideBySmall(leftSquareHi, leftSquareLo, leftFactor);
        (uint256 rightHi, uint256 rightLo) = _mulWideBySmall(rightSquareHi, rightSquareLo, rightFactor);

        return leftHi > rightHi || (leftHi == rightHi && leftLo >= rightLo);
    }

    function _wideSquareTimesSmallLte(uint160 left, uint256 leftFactor, uint160 right, uint256 rightFactor)
        internal
        pure
        returns (bool)
    {
        (uint256 leftSquareHi, uint256 leftSquareLo) = _squareWide(left);
        (uint256 rightSquareHi, uint256 rightSquareLo) = _squareWide(right);
        (uint256 leftHi, uint256 leftLo) = _mulWideBySmall(leftSquareHi, leftSquareLo, leftFactor);
        (uint256 rightHi, uint256 rightLo) = _mulWideBySmall(rightSquareHi, rightSquareLo, rightFactor);

        return leftHi < rightHi || (leftHi == rightHi && leftLo <= rightLo);
    }

    function _currencySymbol(Currency currency) internal view returns (string memory) {
        return IERC20Metadata(Currency.unwrap(currency)).symbol();
    }

    function _revertIfNativeCurrencyUnsupported(Currency currency0, Currency currency1) internal pure {
        if (currency0.isAddressZero() || currency1.isAddressZero()) revert NativeCurrencyUnsupported();
    }
}
