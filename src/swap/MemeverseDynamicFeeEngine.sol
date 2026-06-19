// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {SqrtPriceMath} from "@uniswap/v4-core/src/libraries/SqrtPriceMath.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {wadExp} from "solmate/utils/SignedWadMath.sol";

import {IMemeverseDynamicFeeEngine} from "./interfaces/IMemeverseDynamicFeeEngine.sol";
import {FeeMath} from "./libraries/FeeMath.sol";

/// @title MemeverseDynamicFeeEngine
/// @notice Owns Memeverse dynamic fee state, quote math, and realized swap state updates.
/// @dev State-mutating APIs use `msg.sender` as the hook namespace and consume hook-supplied
///      pool and launch-fee inputs instead of reading hook or PoolManager state.
///      `quoteSwapWithContext` is a read-only quote path using the hook-supplied context for the
///      explicit hook namespace.
///      Upgradeable UUPS proxy; mutable state lives in the ERC7201 namespace.
///      Pure price/fee math primitives (spot conversion, price-move ppm, volatility fee) live in
///      the `FeeMath` library; they are `internal pure` and inline into this contract.
// solhint-disable-next-line gas-small-strings
contract MemeverseDynamicFeeEngine layout at erc7201("outrun.storage.MemeverseDynamicFeeEngine")
    is
    IMemeverseDynamicFeeEngine,
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    uint256 public constant BPS_BASE = FeeMath.BPS_BASE;
    uint256 public constant PPM_BASE = FeeMath.PPM_BASE;
    uint24 internal constant FEE_ALPHA = 500_000;
    uint24 internal constant FEE_DFF_MAX_PPM = 800_000;
    int256 internal constant LAUNCH_FEE_EXP_SHAPE_WAD = 4e18;
    uint24 internal constant FEE_BASE_BPS = 100;
    uint24 internal constant FEE_MAX_BPS = 10_000;
    uint24 internal constant VOL_DEVIATION_STEP_BPS = 1;
    uint24 internal constant VOL_FILTER_PERIOD_SEC = 10;
    uint24 internal constant VOL_DECAY_PERIOD_SEC = 60;
    uint24 internal constant VOL_DECAY_FACTOR_BPS = 5_000;
    uint24 internal constant SHORT_DECAY_WINDOW_SEC = 15;
    uint24 internal constant SHORT_COEFF_BPS = 2_500;
    uint24 internal constant SHORT_FLOOR_PPM = 20_000;
    uint24 internal constant SHORT_CAP_PPM = 100_000;
    uint24 internal constant VOL_INCREMENT_PER_STEP = 1_000;
    uint256 internal constant ADDRESS_BATCH_WINDOW_SEC = 3;

    IPoolManager public immutable override poolManager;

    /// @notice Storage layout for the MemeverseDynamicFeeEngine ERC7201 namespace.
    ///         When adding fields in upgrades, append only at the end.
    ///         Never reorder or insert fields between existing ones.
    /// @custom:storage-location erc7201:outrun.storage.MemeverseDynamicFeeEngine
    struct MemeverseDynamicFeeEngineStorage {
        mapping(address hook => mapping(PoolId poolId => DynamicFeeState)) dynamicFeeStates;
        mapping(address hook => mapping(address trader => mapping(PoolId poolId => AddressBatchState)))
            addressBatchStates;
        address authorizedHook;
    }

    MemeverseDynamicFeeEngineStorage private memeverseDynamicFeeEngineStorage;

    /// @custom:oz-upgrades-unsafe-allow constructor
    /// @param _poolManager PoolManager shared with the hook.
    constructor(IPoolManager _poolManager) {
        if (address(_poolManager) == address(0)) revert ZeroAddress();
        poolManager = _poolManager;
        _disableInitializers();
    }

    /// @notice Initializes the UUPS proxy owner and the single authorized hook caller.
    /// @param initialOwner Owner authorized to upgrade the engine.
    /// @param authorizedHook_ Hook address authorized to call mutating engine APIs. Must be non-zero.
    function initialize(address initialOwner, address authorizedHook_) external initializer {
        if (initialOwner == address(0) || authorizedHook_ == address(0)) revert ZeroAddress();
        __Ownable_init(initialOwner);
        memeverseDynamicFeeEngineStorage.authorizedHook = authorizedHook_;
    }

    /// @notice Engine ownership is managed through the Hook contract.
    ///         To change the engine, deploy a new one and call Hook.upgradeDynamicFeeEngine().
    function transferOwnership(address) public pure override {
        revert EngineOwnershipManagedByHook();
    }

    /// @notice Engine ownership cannot be renounced.
    ///         To decommission the engine, replace it via Hook.upgradeDynamicFeeEngine().
    function renounceOwnership() public pure override {
        revert EngineOwnershipManagedByHook();
    }

    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner {
        address currentPoolManager = address(poolManager);
        address newPoolManager = address(MemeverseDynamicFeeEngine(newImplementation).poolManager());
        // Operational guardrail, not a security boundary: the external poolManager() call trusts the new
        // implementation to self-report honestly. A malicious owner can bypass this by deploying an
        // implementation with a custom poolManager() getter that returns the expected address. This check
        // protects against accidental mismatches (wrong PoolManager constructor arg) during honest upgrades.
        if (newPoolManager != currentPoolManager) {
            revert UpgradePoolManagerMismatch(currentPoolManager, newPoolManager);
        }
    }

    /// @inheritdoc IMemeverseDynamicFeeEngine
    function authorizedHook() external view override returns (address) {
        return memeverseDynamicFeeEngineStorage.authorizedHook;
    }

    /// @inheritdoc IMemeverseDynamicFeeEngine
    function refreshBeforeSwap(RefreshBeforeSwapParams calldata params) external override onlyAuthorizedCaller {
        DynamicFeeState storage stored = memeverseDynamicFeeEngineStorage.dynamicFeeStates[msg.sender][params.poolId];
        _refreshVolatilityAnchorAndCarry(stored, params.preSqrtPriceX96);
    }

    /// @inheritdoc IMemeverseDynamicFeeEngine
    function prepareSwapFee(PrepareSwapFeeParams calldata params)
        external
        override
        onlyAuthorizedCaller
        returns (PreparedSwapFee memory quote)
    {
        DynamicFeeState storage stored = memeverseDynamicFeeEngineStorage.dynamicFeeStates[msg.sender][params.poolId];
        _refreshVolatilityAnchorAndCarry(stored, params.preSqrtPriceX96);
        return _estimateDynamicFeeQuote(
            stored,
            memeverseDynamicFeeEngineStorage.addressBatchStates[msg.sender][params.trader][params.poolId],
            params.liquidity,
            params.preSqrtPriceX96,
            params.swapParams.zeroForOne,
            params.swapParams.amountSpecified,
            params.protocolFeeOnInput,
            _quoteLaunchFeeBps(params.launchFeeConfig, params.launchTimestamp)
        );
    }

    /// @inheritdoc IMemeverseDynamicFeeEngine
    /// @dev Design invariant: this function MUST depend only on `params` fields
    ///      (delta, price snapshots, trader). It MUST NOT read PoolManager unsettled
    ///      balances or perform settle/take — the caller controls call timing relative
    ///      to settlement, and balance-dependent logic would create ordering coupling.
    function updateAfterSwap(UpdateAfterSwapParams calldata params) external override onlyAuthorizedCaller {
        if (params.preSqrtPriceX96 == 0) return;

        uint256 pifPpm = FeeMath.priceMovePpmCapped(params.preSqrtPriceX96, params.postSqrtPriceX96);
        DynamicFeeState storage state = memeverseDynamicFeeEngineStorage.dynamicFeeStates[msg.sender][params.poolId];
        AddressBatchState storage batch =
            memeverseDynamicFeeEngineStorage.addressBatchStates[msg.sender][params.trader][params.poolId];

        if (batch.batchStartTs > 0 && block.timestamp - uint256(batch.batchStartTs) < ADDRESS_BATCH_WINDOW_SEC) {
            batch.batchAccumPpm = uint192(uint256(batch.batchAccumPpm) + pifPpm);
        } else {
            batch.batchAccumPpm = uint192(pifPpm);
            batch.batchStartTs = uint64(block.timestamp);
        }

        uint256 updatedShortPpm =
            _decayLinearPpm(state.shortImpactPpm, state.shortLastTs, SHORT_DECAY_WINDOW_SEC) + pifPpm;
        if (updatedShortPpm > SHORT_CAP_PPM) updatedShortPpm = SHORT_CAP_PPM;
        state.shortImpactPpm = uint24(updatedShortPpm);
        state.shortLastTs = uint40(block.timestamp);

        uint256 spotX18 = FeeMath.spotX18FromSqrtPrice(params.postSqrtPriceX96);
        int256 amount0 = params.delta.amount0();
        uint256 volume0 = uint256(amount0 < 0 ? -amount0 : amount0);
        _updateVolatilityDeviationAccumulatorAfterSwap(state, params.postSqrtPriceX96);
        if (volume0 == 0 || spotX18 == 0) return;

        uint256 priceVolume = FullMath.mulDiv(volume0, spotX18, FeeMath.EWVWAP_PRECISION);
        if (state.weightedVolume0 == 0) {
            state.weightedVolume0 = volume0;
            state.weightedPriceVolume0 = priceVolume;
            state.ewVWAPX18 = spotX18;
            return;
        }

        uint256 alphaR = PPM_BASE - FEE_ALPHA;
        uint256 newWeightedVolume0 =
            FullMath.mulDiv(FEE_ALPHA, volume0, PPM_BASE) + FullMath.mulDiv(alphaR, state.weightedVolume0, PPM_BASE);
        uint256 newWeightedPriceVolume0 = FullMath.mulDiv(FEE_ALPHA, priceVolume, PPM_BASE)
            + FullMath.mulDiv(alphaR, state.weightedPriceVolume0, PPM_BASE);
        state.weightedVolume0 = newWeightedVolume0;
        state.weightedPriceVolume0 = newWeightedPriceVolume0;
        if (newWeightedVolume0 > 0) {
            state.ewVWAPX18 = FullMath.mulDiv(newWeightedPriceVolume0, FeeMath.EWVWAP_PRECISION, newWeightedVolume0);
        }
    }

    /// @inheritdoc IMemeverseDynamicFeeEngine
    function quoteSwapWithContext(address hook, QuoteSwapContext calldata context)
        external
        view
        override
        onlyAuthorizedCaller
        returns (PreparedSwapFee memory quote)
    {
        DynamicFeeState memory state = memeverseDynamicFeeEngineStorage.dynamicFeeStates[hook][context.poolId];
        // Inline volatility refresh on the memory copy — mirrors _refreshVolatilityAnchorAndCarry
        // without touching storage, since quoteSwapWithContext is a view function.
        if (state.volAnchorSqrtPriceX96 == 0) state.volAnchorSqrtPriceX96 = context.preSqrtPriceX96;
        uint256 elapsed = block.timestamp > state.volLastMoveTs ? block.timestamp - state.volLastMoveTs : 0;
        if (elapsed >= VOL_FILTER_PERIOD_SEC) {
            state.volAnchorSqrtPriceX96 = context.preSqrtPriceX96;
            state.volCarryAccumulator = state.volLastMoveTs != 0 && elapsed < VOL_DECAY_PERIOD_SEC
                ? uint24(FullMath.mulDiv(state.volDeviationAccumulator, VOL_DECAY_FACTOR_BPS, BPS_BASE))
                : 0;
            state.volDeviationAccumulator = state.volCarryAccumulator;
        }

        return _estimateDynamicFeeQuote(
            state,
            memeverseDynamicFeeEngineStorage.addressBatchStates[hook][context.trader][context.poolId],
            context.liquidity,
            context.preSqrtPriceX96,
            context.swapParams.zeroForOne,
            context.swapParams.amountSpecified,
            context.protocolFeeOnInput,
            _quoteLaunchFeeBps(context.launchFeeConfig, context.launchTimestamp)
        );
    }

    /// @inheritdoc IMemeverseDynamicFeeEngine
    function getDynamicFeeState(address hook, PoolId poolId)
        external
        view
        override
        returns (DynamicFeeState memory state)
    {
        return memeverseDynamicFeeEngineStorage.dynamicFeeStates[hook][poolId];
    }

    /// @inheritdoc IMemeverseDynamicFeeEngine
    function getAddressBatchState(address hook, address trader, PoolId poolId)
        external
        view
        override
        returns (AddressBatchState memory state)
    {
        return memeverseDynamicFeeEngineStorage.addressBatchStates[hook][trader][poolId];
    }

    modifier onlyAuthorizedCaller() {
        if (msg.sender != memeverseDynamicFeeEngineStorage.authorizedHook) {
            revert UnauthorizedCaller(msg.sender);
        }
        _;
    }

    function _quoteLaunchFeeBps(LaunchFeeConfig memory config, uint40 launchTimestamp)
        internal
        view
        returns (uint256 feeBps)
    {
        if (launchTimestamp == 0) return config.minFeeBps;
        uint256 elapsed = block.timestamp > launchTimestamp ? block.timestamp - launchTimestamp : 0;
        if (elapsed >= config.decayDurationSeconds) return config.minFeeBps;
        // This normalized exponential decay is part of the launch-fee invariant.
        uint256 decayWad = _normalizedLaunchDecayWad(elapsed, config.decayDurationSeconds);
        return config.minFeeBps + FullMath.mulDiv(config.startFeeBps - config.minFeeBps, decayWad, 1e18);
    }

    function _normalizedLaunchDecayWad(uint256 elapsed, uint256 duration) internal pure returns (uint256 decayWad) {
        int256 expAtElapsedWad = wadExp(-int256(FullMath.mulDiv(elapsed, uint256(LAUNCH_FEE_EXP_SHAPE_WAD), duration)));
        int256 expAtEndWad = wadExp(-LAUNCH_FEE_EXP_SHAPE_WAD);
        decayWad = uint256((expAtElapsedWad - expAtEndWad) * 1e18 / (1e18 - expAtEndWad));
    }

    function _estimateDynamicFeeQuote(
        DynamicFeeState memory state,
        AddressBatchState memory senderBatchState,
        uint128 liquidity,
        uint160 preSqrtPriceX96,
        bool zeroForOne,
        int256 amountSpecified,
        bool feeOnInput,
        uint256 launchFeeBps
    ) internal view returns (PreparedSwapFee memory quote) {
        quote.feeBps = launchFeeBps > FEE_BASE_BPS ? launchFeeBps : FEE_BASE_BPS;
        if (amountSpecified == 0 || liquidity == 0) return quote;

        int256 workingAmountSpecified = amountSpecified;
        uint256 userInputAmount = amountSpecified < 0 ? uint256(-amountSpecified) : 0;
        uint256 requestedNetOutputAmount = amountSpecified > 0 ? uint256(amountSpecified) : 0;
        uint256 spotBeforeX18 = FeeMath.spotX18FromSqrtPrice(preSqrtPriceX96);
        // preVolatilityPartBps and preDecayedShortPpm are loop-invariant (state.volDeviationAccumulator /
        // state.shortImpactPpm are unchanged inside the loop); precompute once to avoid per-iteration recomputation.
        uint256 preVolatilityPartBps = FeeMath.volatilitySqrtFeeBps(state.volDeviationAccumulator);
        uint256 preDecayedShortPpm = _decayLinearPpm(state.shortImpactPpm, state.shortLastTs, SHORT_DECAY_WINDOW_SEC);

        // Fixed-point iteration: fee and swap amount are mutually dependent — fee reduces the
        // net amount reaching the pool (input path) or requires grossing up the requested output
        // (output path). Each iteration re-estimates the swap with the fee-adjusted amount until
        // the pool's actual I/O matches what the fee was computed from. Typically converges in
        // 1–2 rounds; 3 is a safety cap. If still divergent after 3 rounds, the last estimate
        // is returned (the fallback after the loop handles the output-specified case).
        for (uint256 i = 0; i < 3; ++i) {
            bool converged;
            (quote, workingAmountSpecified, converged) = _estimateDynamicFeeQuoteIter(
                quote,
                state,
                senderBatchState,
                liquidity,
                preSqrtPriceX96,
                spotBeforeX18,
                preVolatilityPartBps,
                preDecayedShortPpm,
                zeroForOne,
                amountSpecified,
                workingAmountSpecified,
                userInputAmount,
                requestedNetOutputAmount,
                feeOnInput,
                launchFeeBps
            );
            if (quote.estimatedInputAmount == 0) return quote;
            if (converged) return quote;
        }

        if (amountSpecified > 0 && !feeOnInput) quote.estimatedOutputAmount = requestedNetOutputAmount;
    }

    /// @dev Single iteration of the iterative dynamic fee quote convergence loop.
    ///      Returns the updated quote, the next `workingAmountSpecified`, and whether the loop has
    ///      converged (caller should return). A non-converged iteration may still produce a zero
    ///      next `workingAmountSpecified` (e.g. fee consumes the entire input), so convergence is
    ///      signaled explicitly via the bool rather than reusing the amount value.
    function _estimateDynamicFeeQuoteIter(
        PreparedSwapFee memory quote,
        DynamicFeeState memory state,
        AddressBatchState memory senderBatchState,
        uint128 liquidity,
        uint160 preSqrtPriceX96,
        uint256 spotBeforeX18,
        uint256 preVolatilityPartBps,
        uint256 preDecayedShortPpm,
        bool zeroForOne,
        int256 amountSpecified,
        int256 workingAmountSpecified,
        uint256 userInputAmount,
        uint256 requestedNetOutputAmount,
        bool feeOnInput,
        uint256 launchFeeBps
    ) internal view returns (PreparedSwapFee memory, int256 nextWorkingAmount, bool converged) {
        uint160 postSqrtPriceX96;
        (quote.estimatedInputAmount, quote.estimatedOutputAmount, quote.estimatedGrossOutputAmount, postSqrtPriceX96) =
            _estimateSwapFlowAndPostPrice(liquidity, preSqrtPriceX96, zeroForOne, workingAmountSpecified);
        if (quote.estimatedInputAmount == 0) return (quote, 0, true);

        quote.spotBeforeX18 = spotBeforeX18;
        quote.spotAfterX18 = FeeMath.spotX18FromSqrtPrice(postSqrtPriceX96);
        quote.pifPpm = FeeMath.priceMovePpmCapped(preSqrtPriceX96, postSqrtPriceX96);
        _populateDynamicFeeQuoteFromState(quote, state, senderBatchState, preVolatilityPartBps, preDecayedShortPpm);

        if (launchFeeBps > quote.feeBps) quote.feeBps = launchFeeBps;

        if (amountSpecified < 0) {
            uint256 inputSideFeeBps = feeOnInput ? quote.feeBps : FeeMath.lpFeeBps(quote.feeBps);
            uint256 inputSideFeeAmount = FullMath.mulDiv(userInputAmount, inputSideFeeBps, BPS_BASE);
            uint256 netPoolInputAmount = userInputAmount > inputSideFeeAmount ? userInputAmount - inputSideFeeAmount : 0;
            // Fee fully consuming the input (netPoolInputAmount == 0) is NOT convergence; the loop
            // must continue so the next iteration estimates with zero input and reports failure.
            if (netPoolInputAmount == quote.estimatedInputAmount) return (quote, 0, true);
            return (quote, -int256(netPoolInputAmount), false);
        }

        if (feeOnInput) return (quote, 0, true);
        uint256 grossedOutputAmount = requestedNetOutputAmount
            + _grossUpFeeFromNetOutput(requestedNetOutputAmount, FeeMath.protocolFeeBps(quote.feeBps));
        if (grossedOutputAmount == quote.estimatedGrossOutputAmount) {
            quote.estimatedOutputAmount = requestedNetOutputAmount;
            return (quote, 0, true);
        }
        return (quote, int256(grossedOutputAmount), false);
    }

    /// @dev `preVolatilityPartBps` and `preDecayedShortPpm` are loop-invariant: they depend only on
    ///      `state.volDeviationAccumulator` and `state.shortImpactPpm`, which are unchanged inside the
    ///      convergence loop. Callers precompute them once to avoid redundant recomputation per iteration.
    function _populateDynamicFeeQuoteFromState(
        PreparedSwapFee memory quote,
        DynamicFeeState memory state,
        AddressBatchState memory senderBatchState,
        uint256 preVolatilityPartBps,
        uint256 preDecayedShortPpm
    ) internal view {
        bool hasHistory = state.weightedVolume0 > 0 && state.ewVWAPX18 > 0;
        quote.isAdverse = hasHistory
            ? _absDiff(quote.spotAfterX18, state.ewVWAPX18) > _absDiff(quote.spotBeforeX18, state.ewVWAPX18)
            : true;
        if (hasHistory && !quote.isAdverse) {
            quote.feeBps = FEE_BASE_BPS;
            return;
        }

        uint256 effectivePifPpm = quote.pifPpm;
        if (
            senderBatchState.batchStartTs > 0
                && block.timestamp - uint256(senderBatchState.batchStartTs) < ADDRESS_BATCH_WINDOW_SEC
        ) {
            effectivePifPpm = uint256(senderBatchState.batchAccumPpm) + quote.pifPpm;
        }
        uint256 satPpm = FullMath.mulDiv(effectivePifPpm, PPM_BASE, effectivePifPpm + FeeMath.PIF_CAP_PPM);
        uint256 dffPpm = FullMath.mulDiv(FEE_DFF_MAX_PPM, satPpm, PPM_BASE);
        uint256 dynamicPpm = FullMath.mulDiv(dffPpm, effectivePifPpm, PPM_BASE);
        quote.adverseImpactPartBps = dynamicPpm / (PPM_BASE / BPS_BASE);
        quote.volatilityPartBps = preVolatilityPartBps;

        uint256 projectedShortPpm = preDecayedShortPpm + quote.pifPpm;
        if (projectedShortPpm > SHORT_CAP_PPM) projectedShortPpm = SHORT_CAP_PPM;
        uint256 chargeableShortPpm = projectedShortPpm > SHORT_FLOOR_PPM ? projectedShortPpm - SHORT_FLOOR_PPM : 0;
        quote.shortImpactPartBps = FullMath.mulDiv(chargeableShortPpm, SHORT_COEFF_BPS, PPM_BASE);

        uint256 feeBps = FEE_BASE_BPS + quote.adverseImpactPartBps + quote.volatilityPartBps + quote.shortImpactPartBps;
        quote.feeBps = feeBps > FEE_MAX_BPS ? FEE_MAX_BPS : feeBps;
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

    function _refreshVolatilityAnchorAndCarry(DynamicFeeState storage state, uint160 preSqrtPriceX96) internal {
        if (state.volAnchorSqrtPriceX96 == 0) state.volAnchorSqrtPriceX96 = preSqrtPriceX96;
        uint40 lastMoveTs = state.volLastMoveTs;
        uint256 elapsed = block.timestamp > lastMoveTs ? block.timestamp - lastMoveTs : 0;
        if (elapsed < VOL_FILTER_PERIOD_SEC) return;

        state.volAnchorSqrtPriceX96 = preSqrtPriceX96;
        uint24 refreshedCarry = lastMoveTs != 0 && elapsed < VOL_DECAY_PERIOD_SEC
            ? uint24(FullMath.mulDiv(state.volDeviationAccumulator, VOL_DECAY_FACTOR_BPS, BPS_BASE))
            : 0;
        // Keep carry and deviation in lockstep at refresh boundaries so post-swap movement starts from the decayed base.
        state.volCarryAccumulator = refreshedCarry;
        state.volDeviationAccumulator = refreshedCarry;
    }

    function _updateVolatilityDeviationAccumulatorAfterSwap(DynamicFeeState storage state, uint160 postSqrtPriceX96)
        internal
    {
        if (state.volAnchorSqrtPriceX96 == 0) {
            state.volAnchorSqrtPriceX96 = postSqrtPriceX96;
            return;
        }
        uint256 deltaSteps =
            _volatilityDeltaSteps(state.volAnchorSqrtPriceX96, postSqrtPriceX96, VOL_DEVIATION_STEP_BPS);
        uint256 updatedAccumulator = uint256(state.volCarryAccumulator) + deltaSteps * uint256(VOL_INCREMENT_PER_STEP);
        if (updatedAccumulator > FeeMath.VOL_MAX_DEVIATION_ACCUMULATOR) {
            updatedAccumulator = FeeMath.VOL_MAX_DEVIATION_ACCUMULATOR;
        }
        state.volDeviationAccumulator = uint24(updatedAccumulator);
        if (deltaSteps > 0) state.volLastMoveTs = uint40(block.timestamp);
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
        uint256 sqrtRatioX18 = FullMath.mulDiv(upper, FeeMath.EWVWAP_PRECISION, lower);
        if (sqrtRatioX18 <= FeeMath.EWVWAP_PRECISION) return 0;
        return
            FullMath.mulDiv(sqrtRatioX18 - FeeMath.EWVWAP_PRECISION, BPS_BASE * 2, stepBps * FeeMath.EWVWAP_PRECISION);
    }

    function _absDiff(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }
}
