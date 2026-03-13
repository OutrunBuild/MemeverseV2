// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IERC20Minimal} from "@uniswap/v4-core/src/interfaces/external/IERC20Minimal.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {SqrtPriceMath} from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {IPoolManager, SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
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

import {SafeCast} from "../libraries/SafeCast.sol";
import {LiquidityQuote} from "../libraries/LiquidityQuote.sol";
import {MemeverseTransientState} from "../libraries/MemeverseTransientState.sol";
import {CurrencySettler} from "../libraries/CurrencySettler.sol";
import {UniswapLP} from "../libraries/UniswapLP.sol";
import {ReentrancyGuard} from "../common/ReentrancyGuard.sol";
import {IMemeverseUniswapHook} from "./interfaces/IMemeverseUniswapHook.sol";

/**
 * @title MemeverseUniswapHook
 * @notice A Uniswap v4 hook implementing:
 * - Full-range liquidity management (single position from MIN_TICK to MAX_TICK)
 * - A custom ERC20 LP token per pool
 * - Dynamic fees for adverse swaps (based on projected price impact, an EWMA volatility signal,
 *   and a linearly decayed short-term cumulative impact signal)
 * - Anti-sniping protection during the initial blocks after pool initialization
 *
 * @dev High-level flow:
 * - This contract is the Core engine for the Memeverse v4 integration.
 * - End-user and SDK-facing flows are expected to enter via `MemeverseSwapRouter`.
 * - The external Core APIs on this contract remain intentionally open for custom routers and advanced integrators.
 * - The configured `treasury` is expected to be a passive fee receiver. In particular, when protocol fees may be
 *   paid in native currency, the treasury must be able to receive ETH and must not use `receive` / `fallback` to
 *   trigger reentrant swap or liquidity actions.
 * - `beforeInitialize`: validates pool settings and deploys the pool-specific LP token.
 * - `beforeSwap`: enforces anti-snipe rules, computes a dynamic fee, and accrues fees.
 * - `afterSwap`: updates ewVWAP, reference-price volatility state, and short-term impact state, and optionally takes protocol fees.
 * - `addLiquidityCore` / `removeLiquidityCore`: mint/burn LP tokens while adding/removing full-range liquidity.
 * - `claimFeesCore`: allows LPs or routers with signatures to claim accrued fees (tracked via per-share accounting).
 */
contract MemeverseUniswapHook is IMemeverseUniswapHook, IUnlockCallback, BaseHook, ReentrancyGuard, Ownable {
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
    uint16 internal constant MINIMUM_LIQUIDITY = 1000;
    uint256 internal constant PRECISION = 1e18;
    uint256 internal constant Q96 = 1 << 96;
    uint256 internal constant Q96_SQUARED = Q96 * Q96;

    uint256 public constant PROTOCOL_FEE_RATIO_BPS = 3000;
    uint256 public constant ANTI_SNIPE_MAX_SLIPPAGE_BPS = 200;
    uint256 public constant BPS_BASE = 10000;
    uint256 public constant PPM_BASE = 1_000_000;
    uint24 internal constant FEE_ALPHA = 500_000; // ewVWAP EWMA weight, ppm domain.
    uint24 internal constant FEE_DFF_MAX_PPM = 800_000; // Upper bound of dynamic fee factor, ppm domain.
    uint24 internal constant FEE_BASE_BPS = 100; // Minimum fee in bps.
    uint24 internal constant FEE_MAX_BPS = 10_000; // Maximum fee in bps.
    uint24 internal constant PIF_CAP_PPM = 60_000; // PIF cap for fee growth, ppm domain.
    uint24 internal constant VOL_DEVIATION_STEP_BPS = 1; // Reference-price deviation step in bps.
    uint24 internal constant VOL_FILTER_PERIOD_SEC = 10; // Time below this keeps current volatility anchor/carry.
    uint24 internal constant VOL_DECAY_PERIOD_SEC = 60; // Time above this fully clears carried volatility state.
    uint24 internal constant VOL_DECAY_FACTOR_BPS = 5_000; // Partial carry-over factor inside decay window.
    uint24 internal constant VOL_QUADRATIC_FEE_CONTROL = 4_500_000; // Quadratic volatility fee control.
    uint24 internal constant VOL_MAX_DEVIATION_ACCUMULATOR = 350_000; // Cap for volatility deviation state.
    uint24 internal constant SHORT_DECAY_WINDOW_SEC = 15; // Linear decay window for short-term impact state.
    uint24 internal constant SHORT_COEFF_BPS = 2_000; // Short-term impact surcharge coefficient.
    uint24 internal constant SHORT_FLOOR_PPM = 20_000; // Free short-impact allowance before charging starts.
    uint24 internal constant SHORT_CAP_PPM = 150_000; // Cap for short-term impact accumulator.
    bytes32 internal constant CLAIM_FEES_TYPEHASH =
        keccak256("ClaimFees(address owner,address recipient,bytes32 poolId,uint256 nonce,uint256 deadline)");

    address public treasury;
    uint256 public antiSnipeDurationBlocks;
    uint256 public maxAntiSnipeProbabilityBase;
    mapping(address => bool) public supportedProtocolFeeCurrencies;
    mapping(PoolId => PoolInfo) public poolInfo;
    mapping(PoolId => mapping(uint256 => AntiSnipeBlockData)) public antiSnipeBlockData;
    mapping(PoolId => mapping(address => UserFeeState)) public userFeeState;
    uint256 internal immutable INITIAL_CHAIN_ID;
    bytes32 internal immutable INITIAL_DOMAIN_SEPARATOR;
    mapping(address => uint256) public claimNonces;

    /// @notice Per-pool exponentially weighted state used by dynamic fee computation.
    struct EWVWAPParams {
        uint256 weightedVolume0; // EW token0 volume.
        uint256 weightedPriceVolume0; // EW(price * token0 volume) at 1e18 spot precision.
        uint256 ewVWAPX18; // EWVWAP spot in X18 precision.
        uint160 volAnchorSqrtPriceX96; // Anchor sqrt price used to measure reference-price deviation.
        uint40 volLastMoveTs; // Last timestamp when the volatility deviation accumulator observed a non-zero move.
        uint24 volDeviationAccumulator; // Accumulated reference-price deviation state.
        uint24 volCarryAccumulator; // Carried-over accumulator after filter/decay handling.
        uint24 shortImpactPpm; // Short-term cumulative impact accumulator (decay applied on read/update).
        uint40 shortLastTs; // Last timestamp for short-term impact decay.
    }

    struct DynamicFeeQuote {
        uint256 feeBps;
        uint256 pifPpm;
        uint256 dynamicPartBps;
        uint256 volPartBps;
        uint256 shortPartBps;
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

    struct SwapFeeContext {
        Currency currencyIn;
        Currency currencyOut;
        bool protocolFeeOnInput;
        bool inputIsCurrency0;
    }

    bool public emergencyFlag;
    mapping(PoolId => EWVWAPParams) public poolEWVWAPParams;

    /// @param _manager Uniswap v4 pool manager.
    /// @param _owner Contract owner.
    /// @param _treasury Treasury receiving protocol fees (if enabled).
    /// @param _antiSnipeDurationBlocks Number of blocks after init where anti-snipe rules apply.
    /// @param _maxAntiSnipeProbabilityBase Upper bound for probability base used by anti-snipe randomness.
    constructor(
        IPoolManager _manager,
        address _owner,
        address _treasury,
        uint256 _antiSnipeDurationBlocks,
        uint256 _maxAntiSnipeProbabilityBase
    ) BaseHook(_manager) Ownable(_owner) {
        if (_maxAntiSnipeProbabilityBase == 0) revert ZeroValue();
        if (_treasury == address(0)) revert ZeroAddress();
        treasury = _treasury;
        antiSnipeDurationBlocks = _antiSnipeDurationBlocks;
        maxAntiSnipeProbabilityBase = _maxAntiSnipeProbabilityBase;
        INITIAL_CHAIN_ID = block.chainid;
        INITIAL_DOMAIN_SEPARATOR = _computeDomainSeparator();
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

    /// @notice Records an anti-snipe attempt and also returns the computed failure-fee quote.
    /// @dev Intended for routers that need the quote for post-attempt refunds without a second quote call.
    /// @param key The pool key for the attempted swap.
    /// @param params The attempted swap parameters.
    /// @param trader The end user on whose behalf the router is acting.
    /// @param inputBudget The single total input budget attached to this attempt.
    /// @param refundRecipient The address receiving any refunded native failure-fee budget when the attempt succeeds.
    /// @return allowed Whether the attempt passed anti-snipe checks.
    /// @return failureReason The anti-snipe failure reason when `allowed` is false, otherwise `None`.
    /// @return failedAttemptQuote The failure-fee quote computed for this attempt.
    function requestSwapAttemptWithQuote(
        PoolKey calldata key,
        SwapParams calldata params,
        address trader,
        uint256 inputBudget,
        address refundRecipient
    )
        external
        payable
        override
        returns (bool allowed, AntiSnipeFailureReason failureReason, FailedAttemptQuote memory failedAttemptQuote)
    {
        return _requestSwapAttempt(key, params, trader, inputBudget, refundRecipient);
    }

    function _requestSwapAttempt(
        PoolKey calldata key,
        SwapParams calldata params,
        address trader,
        uint256 inputBudget,
        address refundRecipient
    )
        internal
        returns (bool allowed, AntiSnipeFailureReason failureReason, FailedAttemptQuote memory failedAttemptQuote)
    {
        PoolId poolId = key.toId();
        if (poolInfo[poolId].liquidityToken == address(0)) revert PoolNotInitialized();

        if (!_isAntiSnipeActive(poolId)) {
            if (msg.value > 0) _transferCurrency(CurrencyLibrary.ADDRESS_ZERO, refundRecipient, msg.value);
            return (true, AntiSnipeFailureReason.None, failedAttemptQuote);
        }

        if (!MemeverseTransientState.markAntiSnipeRequestForPool(poolId)) {
            revert PoolAlreadyRequestedThisTransaction();
        }

        failedAttemptQuote = _quoteFailedAttempt(poolId, key, params, inputBudget);
        _validateAttemptFeeFunding(failedAttemptQuote, inputBudget, refundRecipient);
        (allowed, failureReason) = _checkAntiSnipe(poolId, params);

        Currency currencyIn = params.zeroForOne ? key.currency0 : key.currency1;
        uint256 absSpecified = uint256(params.amountSpecified < 0 ? -params.amountSpecified : params.amountSpecified);
        if (allowed) {
            if (msg.value > 0) _transferCurrency(CurrencyLibrary.ADDRESS_ZERO, refundRecipient, msg.value);
            MemeverseTransientState.armAntiSnipeTicket(poolId, msg.sender, params, inputBudget);

            emit SwapAllowed(
                poolId,
                trader,
                currencyIn,
                absSpecified,
                block.number,
                antiSnipeBlockData[poolId][block.number].attempts
            );
        } else {
            _collectFailedAttemptFee(poolId, key, failedAttemptQuote);
            if (failedAttemptQuote.feeCurrency.isAddressZero() && inputBudget > failedAttemptQuote.feeAmount) {
                _transferCurrency(
                    CurrencyLibrary.ADDRESS_ZERO, refundRecipient, inputBudget - failedAttemptQuote.feeAmount
                );
            }
            emit SwapBlocked(poolId, trader, currencyIn, absSpecified, block.number, uint8(failureReason));
        }
    }

    /// @notice Returns whether a pool is still inside its anti-snipe protection window.
    /// @dev Routers can use this to skip `requestSwapAttempt` entirely outside the launch window.
    /// @param poolId The pool id to query.
    /// @return active Whether anti-snipe checks are active for the pool at the current block.
    function isAntiSnipeActive(PoolId poolId) external view override returns (bool active) {
        return _isAntiSnipeActive(poolId);
    }

    /// @notice Returns the current anti-snipe failure-fee quote for an attempted swap.
    /// @dev The failure fee is always charged on the input side during the protection window. Outside the protection
    /// window this returns a zero fee amount. For exact-output swaps, `inputBudget` acts as an upper bound while the
    /// fee itself is still based on the currently estimated actual input.
    /// @param key The pool key for the attempted swap.
    /// @param params The attempted swap parameters.
    /// @param inputBudget The single total input budget attached to this attempt.
    /// @return quote The quoted failure-fee amount, side, and recipient class.
    function quoteFailedAttempt(PoolKey calldata key, SwapParams calldata params, uint256 inputBudget)
        external
        view
        override
        returns (FailedAttemptQuote memory quote)
    {
        return _quoteFailedAttempt(key.toId(), key, params, inputBudget);
    }

    /// @notice Returns the current swap fee preview under the hook's latest state.
    /// @dev The preview separates LP-fee and protocol-fee amounts because they may settle in different currencies:
    /// LP fees always accrue in the input currency, while protocol fees settle in the supported fee currency selected
    /// for this swap path (input side preferred, otherwise output side). For exact-output swaps, `estimatedUserInputAmount` is the intended router-side
    /// guardrail candidate for `amountInMaximum`.
    /// @param key The pool key being quoted.
    /// @param params The swap parameters being quoted.
    /// @return quote The projected fee side, user flows, and fee split.
    function quoteSwap(PoolKey calldata key, SwapParams calldata params)
        external
        view
        override
        returns (SwapQuote memory quote)
    {
        PoolId poolId = key.toId();
        SwapFeeContext memory ctx = _resolveSwapFeeContext(key, params.zeroForOne);

        (uint160 preSqrtPriceX96,,,) = poolManager.getSlot0(poolId);
        DynamicFeeQuote memory feeQuote = _quoteDynamicFee(poolId, params, preSqrtPriceX96, ctx.protocolFeeOnInput);
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

    /// @notice Returns the LP token address for a hook-managed pool key.
    /// @dev Convenience helper for integrators that already operate with `PoolKey`.
    /// @param key The pool key to query.
    /// @return liquidityToken The deployed LP token, or `address(0)` when the pool is not initialized.
    function lpToken(PoolKey calldata key) external view override returns (address liquidityToken) {
        return poolInfo[key.toId()].liquidityToken;
    }

    /// @notice Returns the current claimable LP fees for an owner without mutating accounting state.
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
        returns (uint256 fee0Amount, uint256 fee1Amount)
    {
        PoolId poolId = key.toId();
        PoolInfo storage pool = poolInfo[poolId];
        if (pool.liquidityToken == address(0)) return (0, 0);

        UserFeeState storage state = userFeeState[poolId][owner];
        fee0Amount = state.pendingFee0;
        fee1Amount = state.pendingFee1;

        uint256 balance = UniswapLP(pool.liquidityToken).balanceOf(owner);
        if (balance == 0) return (fee0Amount, fee1Amount);

        if (pool.fee0PerShare > state.fee0Offset) {
            fee0Amount += FullMath.mulDiv(balance, pool.fee0PerShare - state.fee0Offset, PRECISION);
        }
        if (pool.fee1PerShare > state.fee1Offset) {
            fee1Amount += FullMath.mulDiv(balance, pool.fee1PerShare - state.fee1Offset, PRECISION);
        }
    }

    function _beforeInitialize(address, PoolKey calldata key, uint160) internal override returns (bytes4) {
        if (key.tickSpacing != TICK_SPACING) revert TickSpacingNotDefault();
        if (!LPFeeLibrary.isDynamicFee(key.fee)) revert FeeMustBeDynamic();

        PoolId poolId = key.toId();
        string memory tokenSymbol = string(
            abi.encodePacked("Outrun", "-", _currencySymbol(key.currency0), "-", _currencySymbol(key.currency1), "-LP")
        );
        address liquidityToken = address(new UniswapLP(tokenSymbol, tokenSymbol, 18, poolId, address(this)));

        poolInfo[poolId].liquidityToken = liquidityToken;
        poolInfo[poolId].antiSnipeEndBlock = uint96(block.number + antiSnipeDurationBlocks);

        emit PoolInitialized(poolId, liquidityToken, key.currency0, key.currency1, poolInfo[poolId].antiSnipeEndBlock);

        return IHooks.beforeInitialize.selector;
    }

    /// @dev Enforces anti-snipe ticket checks, computes the dynamic fee, collects any exact-input input-side fees,
    /// and stores swap context for `afterSwap`.
    function _beforeSwap(address sender, PoolKey calldata key, SwapParams calldata params, bytes calldata)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        PoolId poolId = key.toId();
        bool antiSnipeActive = poolInfo[poolId].antiSnipeEndBlock > block.number;
        if (antiSnipeActive) {
            _consumeAntiSnipeTicket(poolId, sender, params);
        }

        uint256 absSpecified = uint256(params.amountSpecified < 0 ? -params.amountSpecified : params.amountSpecified);
        SwapFeeContext memory ctx = _resolveSwapFeeContext(key, params.zeroForOne);

        (uint160 preSqrtPriceX96,,,) = poolManager.getSlot0(poolId);
        _refreshVolatilityAnchorAndCarry(poolId, preSqrtPriceX96);
        DynamicFeeQuote memory quote = _quoteDynamicFee(poolId, params, preSqrtPriceX96, ctx.protocolFeeOnInput);
        uint256 dynamicFeeBps = quote.feeBps;

        MemeverseTransientState.storeSwapContext(dynamicFeeBps, preSqrtPriceX96);

        uint256 lpFeeBps = _lpFeeBps(dynamicFeeBps);
        uint256 protocolFeeBps = _protocolFeeBps(dynamicFeeBps);

        uint256 lpFeeInputAmount = 0;
        uint256 protocolFeeInputAmount = 0;
        if (params.amountSpecified < 0) {
            lpFeeInputAmount = FullMath.mulDiv(absSpecified, lpFeeBps, BPS_BASE);
            if (ctx.protocolFeeOnInput) {
                protocolFeeInputAmount = FullMath.mulDiv(absSpecified, protocolFeeBps, BPS_BASE);
            }
        }

        if (lpFeeInputAmount > 0) {
            _collectLpFee(poolId, ctx.currencyIn, ctx.inputIsCurrency0, lpFeeInputAmount);
        }
        if (protocolFeeInputAmount > 0) {
            _collectProtocolFee(poolId, ctx.currencyIn, protocolFeeInputAmount);
        }

        if (params.amountSpecified > 0 && !ctx.protocolFeeOnInput) {
            uint256 protocolFeeOutputAmount = quote.estimatedGrossOutputAmount - absSpecified;
            return (IHooks.beforeSwap.selector, toBeforeSwapDelta(protocolFeeOutputAmount.toInt128(), int128(0)), 0);
        }

        if (params.amountSpecified > 0 || !ctx.protocolFeeOnInput) {
            return (IHooks.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }

        int128 specifiedDeltaInput = (lpFeeInputAmount + protocolFeeInputAmount).toInt128();
        return (IHooks.beforeSwap.selector, toBeforeSwapDelta(specifiedDeltaInput, int128(0)), 0);
    }

    function _checkAntiSnipe(PoolId poolId, SwapParams calldata params)
        internal
        returns (bool pass, AntiSnipeFailureReason failureReason)
    {
        PoolInfo storage pool = poolInfo[poolId];

        if (pool.antiSnipeEndBlock <= block.number) return (true, AntiSnipeFailureReason.None);

        uint256 currentBlockNum = block.number;
        AntiSnipeBlockData storage currentBlockData = antiSnipeBlockData[poolId][currentBlockNum];

        uint256 currentAttempts;
        unchecked {
            currentAttempts = ++currentBlockData.attempts;
        }

        if (currentBlockData.successful) return (false, AntiSnipeFailureReason.BlockAlreadyHasSuccessfulSwap);

        if (params.sqrtPriceLimitX96 == 0) return (false, AntiSnipeFailureReason.NoPriceLimitSet);

        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(poolId);
        uint160 hookPriceLimit = _getHookPriceLimit(sqrtPriceX96, params.zeroForOne);
        if (params.zeroForOne ? params.sqrtPriceLimitX96 < hookPriceLimit : params.sqrtPriceLimitX96 > hookPriceLimit) {
            return (false, AntiSnipeFailureReason.SlippageExceedsMaximum);
        }

        uint256 prevBlockAttemptsCount = antiSnipeBlockData[poolId][currentBlockNum - 1].attempts;
        uint256 probabilityBase = prevBlockAttemptsCount == 0
            ? 1
            : prevBlockAttemptsCount > maxAntiSnipeProbabilityBase
                ? maxAntiSnipeProbabilityBase
                : prevBlockAttemptsCount;

        uint256 randomNum = uint256(
            keccak256(
                abi.encodePacked(
                    tx.origin,
                    block.coinbase,
                    block.basefee,
                    block.prevrandao,
                    blockhash(currentBlockNum - 1),
                    gasleft(),
                    currentAttempts
                )
            )
        ) % probabilityBase;

        if (randomNum == 0) {
            return (true, AntiSnipeFailureReason.None);
        } else {
            return (false, AntiSnipeFailureReason.ProbabilityCheckFailed);
        }
    }

    function _getHookPriceLimit(uint160 sqrtPriceX96, bool zeroForOne) internal pure returns (uint160) {
        if (zeroForOne) {
            return uint160(FullMath.mulDiv(sqrtPriceX96, BPS_BASE - ANTI_SNIPE_MAX_SLIPPAGE_BPS, BPS_BASE));
        } else {
            return uint160(FullMath.mulDiv(sqrtPriceX96, BPS_BASE + ANTI_SNIPE_MAX_SLIPPAGE_BPS, BPS_BASE));
        }
    }

    function _afterSwap(address, PoolKey calldata key, SwapParams calldata params, BalanceDelta delta, bytes calldata)
        internal
        override
        returns (bytes4, int128)
    {
        _updateDynamicStateAfterSwap(key.toId(), delta);

        SwapFeeContext memory ctx = _resolveSwapFeeContext(key, params.zeroForOne);
        uint256 feeBps = MemeverseTransientState.loadSwapFeeBps();
        uint256 lpFeeBps = _lpFeeBps(feeBps);
        uint256 protocolFeeBps = _protocolFeeBps(feeBps);

        if (params.amountSpecified > 0) {
            uint256 actualInputAbs = _actualInputAmount(delta, params.zeroForOne);
            if (actualInputAbs == 0) return (IHooks.afterSwap.selector, 0);
            uint256 requestedInputBudget = MemeverseTransientState.loadRequestedInputBudget();
            if (requestedInputBudget > 0 && actualInputAbs > requestedInputBudget) {
                revert InputBudgetExceeded(actualInputAbs, requestedInputBudget);
            }

            uint256 exactOutputLpFeeInputAmount = FullMath.mulDiv(actualInputAbs, lpFeeBps, BPS_BASE);
            if (exactOutputLpFeeInputAmount > 0) {
                _collectLpFee(key.toId(), ctx.currencyIn, ctx.inputIsCurrency0, exactOutputLpFeeInputAmount);
            }

            uint256 unspecifiedDelta;
            if (ctx.protocolFeeOnInput) {
                uint256 exactOutputProtocolFeeInputAmount = FullMath.mulDiv(actualInputAbs, protocolFeeBps, BPS_BASE);
                if (exactOutputProtocolFeeInputAmount > 0) {
                    _collectProtocolFee(key.toId(), ctx.currencyIn, exactOutputProtocolFeeInputAmount);
                }
                unspecifiedDelta = exactOutputLpFeeInputAmount + exactOutputProtocolFeeInputAmount;
            } else {
                uint256 actualGrossOutputAbs = _actualOutputAmount(delta, params.zeroForOne);
                uint256 exactOutputProtocolFeeOutputAmount = actualGrossOutputAbs - uint256(params.amountSpecified);
                if (exactOutputProtocolFeeOutputAmount > 0) {
                    _collectProtocolFee(key.toId(), ctx.currencyOut, exactOutputProtocolFeeOutputAmount);
                }
                unspecifiedDelta = exactOutputLpFeeInputAmount;
            }

            return (IHooks.afterSwap.selector, int128(int256(unspecifiedDelta)));
        }

        if (!ctx.protocolFeeOnInput) {
            uint256 actualOutputAbs = _actualOutputAmount(delta, params.zeroForOne);
            if (actualOutputAbs == 0) return (IHooks.afterSwap.selector, 0);

            uint256 exactInputProtocolFeeOutputAmount = FullMath.mulDiv(actualOutputAbs, protocolFeeBps, BPS_BASE);
            if (exactInputProtocolFeeOutputAmount > 0) {
                _collectProtocolFee(key.toId(), ctx.currencyOut, exactInputProtocolFeeOutputAmount);
            }
            return (IHooks.afterSwap.selector, int128(int256(exactInputProtocolFeeOutputAmount)));
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

    /// @notice Adds full-range liquidity using the caller as payer and mints LP shares to `params.to`.
    /// @dev This is the low-level liquidity entrypoint intended for routers and other on-chain integrators.
    /// It omits deadline and min-amount checks, requires exact native funding when one side is native, and returns the
    /// settled delta to the caller. Callers are expected to pre-compute the required native amount from the same
    /// full-range quote inputs before invoking this Core entrypoint.
    /// @param params The core liquidity-add parameters.
    /// @return liquidity The LP liquidity minted by the operation.
    /// @return delta The balance delta settled against the caller.
    function addLiquidityCore(AddLiquidityCoreParams calldata params)
        external
        payable
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
        PoolKey memory key = _poolKey(params.currency0, params.currency1);
        PoolId poolId = key.toId();
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(poolId);
        if (poolInfo[poolId].liquidityToken == address(0) || sqrtPriceX96 == 0) revert PoolNotInitialized();

        updateUserSnapshot(poolId, params.to);

        uint128 poolLiquidity = poolManager.getLiquidity(poolId);
        uint256 amount0Used;
        uint256 amount1Used;
        (liquidity, amount0Used, amount1Used) =
            LiquidityQuote.quote(sqrtPriceX96, params.amount0Desired, params.amount1Desired);

        uint256 requiredNative = 0;
        if (key.currency0.isAddressZero()) {
            requiredNative = amount0Used;
        } else if (key.currency1.isAddressZero()) {
            requiredNative = amount1Used;
        }
        if (msg.value != requiredNative) revert InvalidNativeValue(requiredNative, msg.value);

        if (poolLiquidity == 0 && liquidity <= MINIMUM_LIQUIDITY) revert LiquidityDoesntMeetMinimum();

        addedDelta = _modifyLiquidity(
            payer,
            key,
            ModifyLiquidityParams({
                tickLower: MIN_TICK, tickUpper: MAX_TICK, liquidityDelta: liquidity.toInt256(), salt: 0
            })
        );

        PoolInfo storage pool = poolInfo[poolId];
        if (poolLiquidity == 0) {
            unchecked {
                liquidity -= MINIMUM_LIQUIDITY;
            }
            UniswapLP(pool.liquidityToken).mint(address(0), MINIMUM_LIQUIDITY);
        }

        UniswapLP(pool.liquidityToken).mint(params.to, liquidity);

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
        PoolKey memory key = _poolKey(params.currency0, params.currency1);
        PoolId poolId = key.toId();
        if (poolManager.getLiquidity(poolId) == 0) revert PoolNotInitialized();

        updateUserSnapshot(poolId, msg.sender);

        UniswapLP lp = UniswapLP(poolInfo[poolId].liquidityToken);
        delta = _modifyLiquidity(
            msg.sender,
            key,
            ModifyLiquidityParams({
                tickLower: MIN_TICK, tickUpper: MAX_TICK, liquidityDelta: -(params.liquidity.toInt256()), salt: 0
            })
        );
        lp.burn(msg.sender, params.liquidity);

        emit LiquidityRemoved(
            poolId,
            msg.sender,
            params.liquidity,
            uint256(delta.amount0().toUint128()),
            uint256(delta.amount1().toUint128())
        );

        if (params.recipient != msg.sender) {
            _forwardLiquidityOutputs(params.recipient, key, delta);
        }
    }

    /// @notice Claims pending LP fees on behalf of an owner using either direct ownership or a signed authorization.
    /// @dev The owner may call directly, or a third party may relay with a valid owner signature.
    /// @param params The core fee-claim parameters.
    /// @return fee0Amount The claimed amount of currency0 fees.
    /// @return fee1Amount The claimed amount of currency1 fees.
    function claimFeesCore(ClaimFeesCoreParams calldata params)
        external
        override
        nonReentrant
        returns (uint256 fee0Amount, uint256 fee1Amount)
    {
        _authorizeClaim(params);
        return _claimFees(params.key, params.owner, params.recipient);
    }

    function _modifyLiquidity(address sender, PoolKey memory key, ModifyLiquidityParams memory params)
        internal
        returns (BalanceDelta delta)
    {
        delta = abi.decode(
            poolManager.unlock(abi.encode(ModifyLiquidityCallbackData({sender: sender, key: key, params: params}))),
            (BalanceDelta)
        );
    }

    /// @notice Callback invoked by the PoolManager during `unlock` flow.
    /// @dev Only callable by the PoolManager.
    /// @param rawData Encoded liquidity callback payload produced by `_modifyLiquidity`.
    /// @return result Encoded `BalanceDelta` returned back to the pool manager.
    function unlockCallback(bytes calldata rawData) external override onlyPoolManager returns (bytes memory) {
        ModifyLiquidityCallbackData memory data = abi.decode(rawData, (ModifyLiquidityCallbackData));

        BalanceDelta delta;
        (delta,) = poolManager.modifyLiquidity(data.key, data.params, ZERO_BYTES);

        if (data.params.liquidityDelta < 0) {
            _takeDeltas(data.sender, data.key, delta);
        } else {
            _settleDeltas(data.sender, data.key, delta);
        }

        return abi.encode(delta);
    }

    /// @dev Transfers `amount` of `currency` to `to`. Supports native currency (address(0)) and ERC20.
    function _transferCurrency(Currency currency, address to, uint256 amount) internal {
        if (amount == 0) return;

        if (currency.isAddressZero()) {
            (bool success,) = to.call{value: amount}("");
            if (!success) revert ERC20TransferFailed();
        } else {
            if (!IERC20Minimal(Currency.unwrap(currency)).transfer(to, amount)) revert ERC20TransferFailed();
        }
    }

    function _settleDeltas(address sender, PoolKey memory key, BalanceDelta delta) internal {
        key.currency0.settle(poolManager, sender, uint256((-delta.amount0()).toUint128()), false);
        key.currency1.settle(poolManager, sender, uint256((-delta.amount1()).toUint128()), false);
    }

    function _takeDeltas(address recipient, PoolKey memory key, BalanceDelta delta) internal {
        poolManager.take(key.currency0, recipient, uint256(delta.amount0().toUint128()));
        poolManager.take(key.currency1, recipient, uint256(delta.amount1().toUint128()));
    }

    function _forwardLiquidityOutputs(address recipient, PoolKey memory key, BalanceDelta delta) internal {
        if (delta.amount0() > 0) {
            _transferCurrency(key.currency0, recipient, uint256(delta.amount0().toUint128()));
        }
        if (delta.amount1() > 0) {
            _transferCurrency(key.currency1, recipient, uint256(delta.amount1().toUint128()));
        }
    }

    function _claimFees(PoolKey memory key, address owner, address recipient)
        internal
        returns (uint256 fee0Amount, uint256 fee1Amount)
    {
        PoolId poolId = key.toId();
        if (poolInfo[poolId].liquidityToken == address(0)) revert PoolNotInitialized();

        updateUserSnapshot(poolId, owner);

        UserFeeState storage state = userFeeState[poolId][owner];
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

    function _authorizeClaim(ClaimFeesCoreParams calldata params) internal {
        if (msg.sender == params.owner) return;
        if (params.deadline < block.timestamp) revert ExpiredPastDeadline();

        uint256 nonce = claimNonces[params.owner]++;
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        CLAIM_FEES_TYPEHASH,
                        params.owner,
                        params.recipient,
                        PoolId.unwrap(params.key.toId()),
                        nonce,
                        params.deadline
                    )
                )
            )
        );

        address recovered = ecrecover(digest, params.v, params.r, params.s);
        if (recovered == address(0) || recovered != params.owner) revert InvalidClaimSignature();
    }

    /// @notice Returns the EIP-712 domain separator used for fee-claim signatures.
    /// @dev Recomputes the separator when the chain id changes to preserve replay protection across forks.
    /// @return separator The active domain separator for this deployment and chain id.
    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return block.chainid == INITIAL_CHAIN_ID ? INITIAL_DOMAIN_SEPARATOR : _computeDomainSeparator();
    }

    function _computeDomainSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("MemeverseUniswapHook"),
                keccak256("1"),
                block.chainid,
                address(this)
            )
        );
    }

    function _poolKey(Currency currency0, Currency currency1) internal view returns (PoolKey memory key) {
        key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(this))
        });
    }

    function _resolveSwapFeeContext(PoolKey calldata key, bool zeroForOne)
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
        _takeToTreasury(feeCurrency, protocolFeeAmount);
        emit ProtocolFeeCollected(poolId, feeCurrency, treasury, protocolFeeAmount, block.number);
    }

    function _collectLpFee(PoolId poolId, Currency feeCurrency, bool feeCurrencyIsCurrency0, uint256 lpFeeAmount)
        internal
    {
        if (lpFeeAmount == 0) return;
        uint256 totalSupply = UniswapLP(poolInfo[poolId].liquidityToken).totalSupply();
        if (totalSupply == 0) return;

        poolManager.take(feeCurrency, address(this), lpFeeAmount);
        _creditLpFee(poolId, feeCurrency, feeCurrencyIsCurrency0, lpFeeAmount, totalSupply);
    }

    function _quoteFailedAttempt(PoolId poolId, PoolKey calldata key, SwapParams calldata params, uint256 inputBudget)
        internal
        view
        returns (FailedAttemptQuote memory quote)
    {
        if (poolInfo[poolId].antiSnipeEndBlock <= block.number) return quote;

        SwapFeeContext memory ctx = _resolveSwapFeeContext(key, params.zeroForOne);
        quote.feeCurrency = ctx.currencyIn;
        quote.feeToTreasury = ctx.protocolFeeOnInput;

        (uint160 preSqrtPriceX96,,,) = poolManager.getSlot0(poolId);
        DynamicFeeQuote memory feeQuote = _quoteDynamicFee(poolId, params, preSqrtPriceX96, true);
        quote.feeBps = feeQuote.feeBps;
        uint256 failureFeeBase =
            params.amountSpecified < 0 ? uint256(-params.amountSpecified) : feeQuote.estimatedInputAmount;
        if (failureFeeBase > inputBudget) failureFeeBase = inputBudget;
        quote.feeAmount = FullMath.mulDiv(failureFeeBase, quote.feeBps, BPS_BASE);
    }

    function _validateAttemptFeeFunding(FailedAttemptQuote memory quote, uint256 inputBudget, address refundRecipient)
        internal
        view
    {
        if (quote.feeCurrency.isAddressZero()) {
            if (msg.value != inputBudget) revert InvalidNativeValue(inputBudget, msg.value);
            if (inputBudget > 0 && refundRecipient == address(0)) revert ZeroAddress();
        } else if (msg.value != 0) {
            revert InvalidNativeValue(0, msg.value);
        }
    }

    function _collectFailedAttemptFee(PoolId poolId, PoolKey calldata key, FailedAttemptQuote memory quote) internal {
        uint256 feeAmount = quote.feeAmount;
        if (feeAmount == 0) return;

        if (quote.feeToTreasury) {
            _transferFromCallerToTreasury(quote.feeCurrency, feeAmount);
        } else {
            uint256 totalSupply = UniswapLP(poolInfo[poolId].liquidityToken).totalSupply();
            if (totalSupply == 0) revert PoolNotInitialized();

            if (!quote.feeCurrency.isAddressZero()) {
                if (!IERC20Minimal(Currency.unwrap(quote.feeCurrency))
                        .transferFrom(msg.sender, address(this), feeAmount)) {
                    revert ERC20TransferFailed();
                }
            }
            _creditLpFee(
                poolId,
                quote.feeCurrency,
                Currency.unwrap(quote.feeCurrency) == Currency.unwrap(key.currency0),
                feeAmount,
                totalSupply
            );
        }

        emit FailedAttemptFeeCollected(
            poolId, msg.sender, quote.feeCurrency, quote.feeToTreasury, feeAmount, block.number
        );
    }

    function _isAntiSnipeActive(PoolId poolId) internal view returns (bool) {
        return poolInfo[poolId].antiSnipeEndBlock > block.number;
    }

    function _takeToTreasury(Currency feeCurrency, uint256 amount) internal {
        if (treasury == address(0)) revert Unauthorized();
        if (feeCurrency.isAddressZero()) {
            try poolManager.take(feeCurrency, treasury, amount) {}
            catch {
                revert NativeTreasuryMustAcceptETH();
            }
        } else {
            poolManager.take(feeCurrency, treasury, amount);
        }
    }

    function _transferFromCallerToTreasury(Currency feeCurrency, uint256 amount) internal {
        if (treasury == address(0)) revert Unauthorized();
        if (feeCurrency.isAddressZero()) {
            (bool success,) = payable(treasury).call{value: amount}("");
            if (!success) revert NativeTreasuryMustAcceptETH();
        } else {
            if (!IERC20Minimal(Currency.unwrap(feeCurrency)).transferFrom(msg.sender, treasury, amount)) {
                revert ERC20TransferFailed();
            }
        }
    }

    function _setProtocolFeeCurrencySupport(Currency currency, bool supported) internal {
        supportedProtocolFeeCurrencies[Currency.unwrap(currency)] = supported;
        emit ProtocolFeeCurrencySupportUpdated(currency, supported);
    }

    function _isProtocolFeeCurrencySupported(Currency currency) internal view returns (bool) {
        return supportedProtocolFeeCurrencies[Currency.unwrap(currency)];
    }

    function _creditLpFee(
        PoolId poolId,
        Currency feeCurrency,
        bool feeCurrencyIsCurrency0,
        uint256 lpFeeAmount,
        uint256 totalSupply
    ) internal {
        PoolInfo storage pool = poolInfo[poolId];
        uint256 feePerShare = FullMath.mulDiv(lpFeeAmount, PRECISION, totalSupply);
        if (feeCurrencyIsCurrency0) {
            pool.fee0PerShare += feePerShare;
            emit LPFeeCollected(poolId, feeCurrency, lpFeeAmount, pool.fee0PerShare, block.number);
        } else {
            pool.fee1PerShare += feePerShare;
            emit LPFeeCollected(poolId, feeCurrency, lpFeeAmount, pool.fee1PerShare, block.number);
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
        return feeBps - _protocolFeeBps(feeBps);
    }

    function _consumeAntiSnipeTicket(PoolId poolId, address caller, SwapParams calldata params) internal {
        uint256 requestedInputBudget = MemeverseTransientState.consumeAntiSnipeTicket(poolId, caller, params);
        if (requestedInputBudget == 0) revert MissingAntiSnipeTicket();
        MemeverseTransientState.storeRequestedInputBudget(requestedInputBudget);

        AntiSnipeBlockData storage currentBlockData = antiSnipeBlockData[poolId][block.number];
        if (currentBlockData.successful) revert MissingAntiSnipeTicket();
        currentBlockData.successful = true;
    }

    /// @notice Updates the user fee accounting snapshot for a pool.
    /// @dev Requires the pool LP token to exist. Accrues newly earned fees into `pendingFee0/1`
    /// and updates per-share offsets for `user`.
    /// @param id The hook-managed pool id.
    /// @param user The user whose fee snapshot is synchronized.
    function updateUserSnapshot(PoolId id, address user) public override {
        PoolInfo storage pool = poolInfo[id];
        UserFeeState storage state = userFeeState[id][user];

        uint256 balance = UniswapLP(pool.liquidityToken).balanceOf(user);
        if (balance == 0) {
            state.fee0Offset = pool.fee0PerShare;
            state.fee1Offset = pool.fee1PerShare;
            return;
        }

        unchecked {
            uint256 fee0Claimable = FullMath.mulDiv(balance, pool.fee0PerShare - state.fee0Offset, PRECISION);
            uint256 fee1Claimable = FullMath.mulDiv(balance, pool.fee1PerShare - state.fee1Offset, PRECISION);

            if (fee0Claimable > 0) state.pendingFee0 += fee0Claimable;
            if (fee1Claimable > 0) state.pendingFee1 += fee1Claimable;
        }

        state.fee0Offset = pool.fee0PerShare;
        state.fee1Offset = pool.fee1PerShare;
    }

    /// @notice Updates the treasury address.
    /// @dev Only callable by the owner. Zero address is rejected because protocol fees require a concrete recipient.
    /// The configured treasury is expected to be a passive receiver and must not use fee receipts to trigger
    /// reentrant swap or liquidity actions.
    /// @param _treasury The new treasury address.
    function setTreasury(address _treasury) external onlyOwner {
        if (_treasury == address(0)) revert ZeroAddress();
        address old = treasury;
        treasury = _treasury;
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
    /// Native currency support is represented by `address(0)`.
    /// @param currency The currency whose support flag is being updated.
    /// @param supported Whether protocol fees may settle in `currency`.
    function setProtocolFeeCurrencySupport(Currency currency, bool supported) external onlyOwner {
        _setProtocolFeeCurrencySupport(currency, supported);
    }

    /// @notice Sets the default anti-snipe duration, in blocks, used for newly initialized pools.
    /// @dev Existing pools keep their stored end blocks; only future initializations use the new default.
    /// @param _durationBlocks The new anti-snipe duration in blocks.
    function setAntiSnipeDuration(uint256 _durationBlocks) external onlyOwner {
        uint256 old = antiSnipeDurationBlocks;
        antiSnipeDurationBlocks = _durationBlocks;
        emit AntiSnipeDurationUpdated(old, _durationBlocks);
    }

    /// @notice Sets the max probability base used by anti-snipe randomness.
    /// @dev Zero is rejected because the probability denominator must stay non-zero.
    /// @param _maxBase The new upper bound for anti-snipe probability scaling.
    function setMaxAntiSnipeProbabilityBase(uint256 _maxBase) external onlyOwner {
        if (_maxBase == 0) revert ZeroValue();
        uint256 old = maxAntiSnipeProbabilityBase;
        maxAntiSnipeProbabilityBase = _maxBase;
        emit MaxAntiSnipeProbabilityBaseUpdated(old, _maxBase);
    }

    /// @notice Emergency switch: if enabled, dynamic fee charging falls back to base fee only.
    /// @dev Intended as an owner-controlled safety valve for fee logic incidents.
    /// @param flag Whether emergency fixed-fee mode should be enabled.
    function setEmergencyFlag(bool flag) external onlyOwner {
        bool old = emergencyFlag;
        emergencyFlag = flag;
        emit EmergencyFlagUpdated(old, flag);
    }

    // -----------------------------------------------------------------------------
    // Dynamic fee computation
    // -----------------------------------------------------------------------------

    /// @dev Dynamic fee quote. Returns base fee in emergency mode, for zero-sized/zero-liquidity
    /// cases, or when an ewVWAP history marks the swap as non-adverse. Does not move funds.
    function _quoteDynamicFee(PoolId poolId, SwapParams calldata params, uint160 preSqrtPriceX96, bool feeOnInput)
        internal
        view
        returns (DynamicFeeQuote memory quote)
    {
        quote.feeBps = FEE_BASE_BPS;
        if (emergencyFlag) return quote;

        if (params.amountSpecified == 0) return quote;

        uint128 liquidity = poolManager.getLiquidity(poolId);
        if (liquidity == 0) return quote;

        EWVWAPParams memory state = poolEWVWAPParams[poolId];
        quote = _estimateDynamicFeeQuote(
            state, liquidity, preSqrtPriceX96, params.zeroForOne, params.amountSpecified, feeOnInput
        );
    }

    function _estimateDynamicFeeQuote(
        EWVWAPParams memory state,
        uint128 liquidity,
        uint160 preSqrtPriceX96,
        bool zeroForOne,
        int256 amountSpecified,
        bool feeOnInput
    ) internal view returns (DynamicFeeQuote memory quote) {
        quote.feeBps = FEE_BASE_BPS;
        if (amountSpecified == 0 || liquidity == 0) return quote;

        int256 workingAmountSpecified = amountSpecified;
        uint256 userInputAmount = amountSpecified < 0 ? uint256(-amountSpecified) : 0;
        uint256 requestedNetOutputAmount = amountSpecified > 0 ? uint256(amountSpecified) : 0;

        for (uint256 i = 0; i < 3; i++) {
            uint160 postSqrtPriceX96;
            (
                quote.estimatedInputAmount,
                quote.estimatedOutputAmount,
                quote.estimatedGrossOutputAmount,
                postSqrtPriceX96
            ) = _estimateSwapFlowAndPostPrice(liquidity, preSqrtPriceX96, zeroForOne, workingAmountSpecified);
            if (quote.estimatedInputAmount == 0) return quote;

            quote.spotBeforeX18 = _spotX18FromSqrtPrice(preSqrtPriceX96);
            quote.spotAfterX18 = _spotX18FromSqrtPrice(postSqrtPriceX96);
            quote.pifPpm = _priceMovePpm(preSqrtPriceX96, postSqrtPriceX96);

            _populateDynamicFeeQuoteFromState(quote, state);

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

            if (feeOnInput) {
                return quote;
            }

            uint256 grossedOutputAmount = requestedNetOutputAmount
                + _grossUpFeeFromNetOutput(requestedNetOutputAmount, _protocolFeeBps(quote.feeBps));
            if (grossedOutputAmount == quote.estimatedGrossOutputAmount) {
                quote.estimatedOutputAmount = requestedNetOutputAmount;
                return quote;
            }

            workingAmountSpecified = int256(grossedOutputAmount);
        }

        if (amountSpecified > 0 && !feeOnInput) {
            quote.estimatedOutputAmount = requestedNetOutputAmount;
        }

        return quote;
    }

    function _populateDynamicFeeQuoteFromState(DynamicFeeQuote memory quote, EWVWAPParams memory state) internal view {
        bool hasHistory = state.weightedVolume0 > 0 && state.ewVWAPX18 > 0;
        if (hasHistory) {
            uint256 distBefore = _absDiff(quote.spotBeforeX18, state.ewVWAPX18);
            uint256 distAfter = _absDiff(quote.spotAfterX18, state.ewVWAPX18);
            quote.isAdverse = distAfter > distBefore;
            if (!quote.isAdverse) return;
        } else {
            quote.isAdverse = true;
        }

        uint256 cappedPif = quote.pifPpm > PIF_CAP_PPM ? PIF_CAP_PPM : quote.pifPpm;
        uint256 satPpm = FullMath.mulDiv(cappedPif, PPM_BASE, cappedPif + PIF_CAP_PPM);
        uint256 dffPpm = FullMath.mulDiv(FEE_DFF_MAX_PPM, satPpm, PPM_BASE);
        uint256 dynamicPpm = FullMath.mulDiv(dffPpm, cappedPif, PPM_BASE);
        quote.dynamicPartBps = dynamicPpm / (PPM_BASE / BPS_BASE);

        quote.volPartBps = _volatilityQuadraticFeeBps(
            state.volDeviationAccumulator, VOL_DEVIATION_STEP_BPS, VOL_QUADRATIC_FEE_CONTROL
        );

        uint256 decayedShortPpm = _decayLinearPpm(state.shortImpactPpm, state.shortLastTs, SHORT_DECAY_WINDOW_SEC);
        uint256 projectedShortPpm = decayedShortPpm + quote.pifPpm;
        if (projectedShortPpm > SHORT_CAP_PPM) projectedShortPpm = SHORT_CAP_PPM;
        uint256 chargeableShortPpm = projectedShortPpm > SHORT_FLOOR_PPM ? projectedShortPpm - SHORT_FLOOR_PPM : 0;
        quote.shortPartBps = FullMath.mulDiv(chargeableShortPpm, SHORT_COEFF_BPS, PPM_BASE);

        uint256 feeBps = FEE_BASE_BPS + quote.dynamicPartBps + quote.volPartBps + quote.shortPartBps;
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
    function _updateDynamicStateAfterSwap(PoolId poolId, BalanceDelta delta) internal {
        uint160 preSqrtPriceX96 = MemeverseTransientState.loadPreSwapSqrtPriceX96();
        if (preSqrtPriceX96 == 0) return;

        (uint160 postSqrtPriceX96,,,) = poolManager.getSlot0(poolId);
        uint256 pifPpm = _priceMovePpm(preSqrtPriceX96, postSqrtPriceX96);
        EWVWAPParams storage state = poolEWVWAPParams[poolId];

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
        uint256 priceVolume = FullMath.mulDiv(volume0, spotX18, PRECISION);

        if (state.weightedVolume0 == 0) {
            state.weightedVolume0 = volume0;
            state.weightedPriceVolume0 = priceVolume;
            state.ewVWAPX18 = spotX18;
        } else {
            state.weightedVolume0 =
                FullMath.mulDiv(alpha, volume0, PPM_BASE) + FullMath.mulDiv(alphaR, state.weightedVolume0, PPM_BASE);
            state.weightedPriceVolume0 = FullMath.mulDiv(alpha, priceVolume, PPM_BASE)
                + FullMath.mulDiv(alphaR, state.weightedPriceVolume0, PPM_BASE);
            if (state.weightedVolume0 > 0) {
                state.ewVWAPX18 = FullMath.mulDiv(state.weightedPriceVolume0, PRECISION, state.weightedVolume0);
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
        EWVWAPParams storage state = poolEWVWAPParams[poolId];

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
        uint256 updatedAccumulator = uint256(state.volCarryAccumulator) + deltaSteps * BPS_BASE;
        if (updatedAccumulator > VOL_MAX_DEVIATION_ACCUMULATOR) updatedAccumulator = VOL_MAX_DEVIATION_ACCUMULATOR;
        state.volDeviationAccumulator = uint24(updatedAccumulator);

        if (deltaSteps > 0) {
            state.volLastMoveTs = uint40(block.timestamp);
        }
    }

    function _volatilityQuadraticFeeBps(uint256 accumulator, uint256 stepBps, uint256 feeControl)
        internal
        pure
        returns (uint256)
    {
        if (accumulator == 0 || stepBps == 0 || feeControl == 0) return 0;

        uint256 scaledAccumulator = accumulator * stepBps;
        scaledAccumulator *= scaledAccumulator;
        uint256 variableFeeNumerator = (scaledAccumulator * feeControl + 100_000_000_000 - 1) / 100_000_000_000;
        return variableFeeNumerator / 100_000;
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
        uint256 sqrtRatioX18 = FullMath.mulDiv(upper, PRECISION, lower);
        if (sqrtRatioX18 <= PRECISION) return 0;

        return FullMath.mulDiv(sqrtRatioX18 - PRECISION, BPS_BASE * 2, stepBps * PRECISION);
    }

    function _spotX18FromSqrtPrice(uint160 sqrtPriceX96) internal pure returns (uint256) {
        return FullMath.mulDiv(uint256(sqrtPriceX96) * uint256(sqrtPriceX96), PRECISION, Q96_SQUARED);
    }

    function _absDiff(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }

    function _priceMovePpm(uint160 preSqrtPrice, uint160 postSqrtPrice) internal pure returns (uint256) {
        uint256 preP = uint256(preSqrtPrice) * uint256(preSqrtPrice);
        uint256 postP = uint256(postSqrtPrice) * uint256(postSqrtPrice);
        uint256 num = postP > preP ? postP - preP : preP - postP;
        return FullMath.mulDiv(num, PPM_BASE, preP);
    }

    function _currencySymbol(Currency currency) internal view returns (string memory) {
        if (currency.isAddressZero()) return "NATIVE";
        return IERC20Metadata(Currency.unwrap(currency)).symbol();
    }

    receive() external payable {}
}
