//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

import {SwapParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IMemeverseDynamicFeeEngine} from "./IMemeverseDynamicFeeEngine.sol";
import {IMemeversePreorderSettlementExecutor} from "./IMemeversePreorderSettlementExecutor.sol";

/**
 * @title IMemeverseUniswapHook
 * @notice Interface for the Memeverse Uniswap v4 Hook.
 * @dev Defines shared types, events, and external entrypoints used by the hook implementation.
 */
interface IMemeverseUniswapHook {
    /// @notice Pool information tracked by the hook.
    struct PoolInfo {
        /// @notice Custom ERC20 LP token address for this pool.
        address liquidityToken;
        /// @notice Accumulated LP fees for currency0 (per share, scaled by Q128 in the implementation).
        uint256 fee0PerShare;
        /// @notice Accumulated LP fees for currency1 (per share, scaled by Q128 in the implementation).
        uint256 fee1PerShare;
    }

    /// @notice Per-user fee accounting state for a pool.
    struct UserFeeState {
        /// @notice Snapshot offset of `fee0PerShare` at the last user update, in Q128 per-share units.
        uint256 fee0Offset;
        /// @notice Snapshot offset of `fee1PerShare` at the last user update, in Q128 per-share units.
        uint256 fee1Offset;
        /// @notice Earned but unclaimed currency0 fees.
        uint256 pendingFee0;
        /// @notice Earned but unclaimed currency1 fees.
        uint256 pendingFee1;
    }

    // ==========================
    // External Call Structures
    // ==========================
    struct AddLiquidityCoreParams {
        Currency currency0;
        Currency currency1;
        uint256 amount0Desired;
        uint256 amount1Desired;
        address to;
    }

    struct RemoveLiquidityCoreParams {
        Currency currency0;
        Currency currency1;
        uint128 liquidity;
        address recipient;
    }

    struct ClaimFeesCoreParams {
        PoolKey key;
        address recipient;
    }

    struct PreorderSettlementParams {
        PoolKey key;
        SwapParams params;
        address recipient;
    }

    struct SwapQuote {
        uint256 feeBps;
        uint256 estimatedUserInputAmount;
        uint256 estimatedUserOutputAmount;
        uint256 estimatedProtocolFeeAmount;
        uint256 estimatedLpFeeAmount;
        bool protocolFeeOnInput;
    }

    /**
     * @notice Core quote API for the hook's latest swap state.
     * @dev Official integrations should prefer `MemeverseSwapRouter.quoteSwap(...)`. This low-level quote remains
     * available for custom routers, aggregators, and other advanced on-chain integrations.
     * @param key The pool key being quoted.
     * @param params The swap parameters being quoted.
     * @param trader The address whose per-address batch state determines the adverse fee component.
     * @return quote The projected fee amounts, side, and estimated user/pool flows.
     */
    function quoteSwap(PoolKey calldata key, SwapParams calldata params, address trader)
        external
        view
        returns (SwapQuote memory quote);

    /// @notice Exposes the dynamic fee engine bound to this hook implementation.
    /// @dev The engine address is owner-upgradeable via `upgradeDynamicFeeEngine`. After replacement,
    ///      the new engine starts from zero dynamic-fee state (EWVWAP, volatility, short-impact all reset).
    ///      UUPS upgrades of the hook itself do not affect the engine pointer — it lives in hook storage.
    /// @return Engine used for dynamic fee quotes and realized swap state.
    function dynamicFeeEngine() external view returns (IMemeverseDynamicFeeEngine);

    /// @notice Exposes the LP token implementation cloned for newly initialized pools.
    /// @return Implementation contract used as the source for pool LP clones.
    function lpTokenImplementation() external view returns (address);

    /// @notice Exposes the stateless helper used for preorder settlement calculations.
    /// @return Executor contract currently used by the hook.
    function preorderSettlementExecutor() external view returns (IMemeversePreorderSettlementExecutor);

    /// @notice Exposes the launcher consulted for post-unlock public-swap protection.
    /// @dev Returns the explicit launcher binding used by hook implementations for launch-state checks.
    /// @return Explicit launcher binding used for public-swap protection checks.
    function launcher() external view returns (address);

    /// @notice Exposes the public-swap resume time for a hook-managed pool.
    /// @dev `0` means no active post-unlock public-swap protection is recorded for the pool.
    /// @param poolId Pool being queried.
    /// @return Stored public-swap resume timestamp for the pool.
    function publicSwapResumeTime(PoolId poolId) external view returns (uint40);

    /// @notice Exposes when a hook-managed pool was initialized.
    /// @dev The launch timestamp anchors the launch-fee decay schedule.
    ///      UPGRADE INVARIANT: Hook.quoteSwap() reads this getter to assemble QuoteSwapContext for the engine.
    ///      Hook UUPS upgrades MUST preserve this function signature; a selector break silently disables off-chain quoting.
    /// @param poolId Pool being queried.
    /// @return Recorded launch timestamp.
    function poolLaunchTimestamp(PoolId poolId) external view returns (uint40);

    /// @notice Returns the current dynamic fee state for a pool, sourced from the bound engine.
    /// @dev The underlying state lives in the dynamic fee engine and is namespaced by hook address.
    /// @param poolId Pool being queried.
    /// @return weightedVolume0 Exponentially weighted token0 volume.
    /// @return weightedPriceVolume0 Exponentially weighted (price * token0 volume) at 1e18 spot precision.
    /// @return ewVWAPX18 Exponentially weighted VWAP spot in X18 precision.
    /// @return volAnchorSqrtPriceX96 Anchor sqrt price used to measure reference-price deviation.
    /// @return volLastMoveTs Last timestamp when the volatility deviation accumulator observed a non-zero move.
    /// @return volDeviationAccumulator Accumulated reference-price deviation state.
    /// @return volCarryAccumulator Carried-over accumulator after filter/decay handling.
    /// @return shortImpactPpm Short-term cumulative impact accumulator (decay applied on read/update).
    /// @return shortLastTs Last timestamp for short-term impact decay.
    function poolDynamicFeeState(PoolId poolId)
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
        );

    /// @notice Exposes the default launch-fee decay schedule.
    /// @dev New pools use this configuration unless a future implementation introduces pool-specific overrides.
    ///      UPGRADE INVARIANT: Hook.quoteSwap() reads this getter to assemble QuoteSwapContext for the engine.
    ///      Hook UUPS upgrades MUST preserve this function signature; a selector break silently disables off-chain quoting.
    /// @return startFeeBps Launch fee applied immediately after pool initialization.
    /// @return minFeeBps Floor fee reached after decay completes.
    /// @return decayDurationSeconds Time required for the launch fee to decay to its floor.
    function defaultLaunchFeeConfig()
        external
        view
        returns (uint24 startFeeBps, uint24 minFeeBps, uint32 decayDurationSeconds);

    /// @notice Exposes the router authorized to initialize hook-managed pools.
    /// @return Router address allowed to authorize and trigger pool initialization.
    function poolInitializer() external view returns (address);

    /// @notice Updates the launcher consulted for public-swap protection.
    /// @dev Implementations are expected to restrict this to an admin or owner role.
    /// @param launcher_ New launcher binding.
    function setLauncher(address launcher_) external;

    /// @notice Updates the router authorized to initialize hook-managed pools.
    /// @dev Implementations are expected to restrict this to an admin or owner role.
    /// @param initializer New authorized initializer router.
    function setPoolInitializer(address initializer) external;

    /// @notice Authorizes exactly one pool initialization at a specific start price.
    /// @dev Callable only by `poolInitializer`; consumed by `beforeInitialize`.
    /// @param key Pool key being initialized.
    /// @param startPriceX96 Expected initial pool price.
    function authorizePoolInitialization(PoolKey calldata key, uint160 startPriceX96) external;

    /// @notice Updates the public-swap resume time for a hook-managed pool identified by token pair.
    /// @dev Intended for the configured launcher to snapshot post-unlock protection windows without depending on
    /// router-derived pool-key helpers.
    /// @param tokenA One token in the pair.
    /// @param tokenB The other token in the pair.
    /// @param resumeTime New public-swap resume timestamp for the pool.
    function setPublicSwapResumeTime(address tokenA, address tokenB, uint40 resumeTime) external;

    /// @notice Updates the default launch-fee decay configuration.
    /// @dev Implementations are expected to restrict this to an admin or owner role.
    /// @param config New default launch-fee schedule.
    function setDefaultLaunchFeeConfig(IMemeverseDynamicFeeEngine.LaunchFeeConfig calldata config) external;

    /**
     * @notice Returns stored pool information for a hook-managed pool.
     * @dev Exposes the LP token address and fee-per-share accumulators.
     * @param poolId The pool id to query.
     * @return liquidityToken The LP token contract for the pool.
     * @return fee0PerShare The accumulated fee-per-share for currency0.
     * @return fee1PerShare The accumulated fee-per-share for currency1.
     */
    function poolInfo(PoolId poolId)
        external
        view
        returns (address liquidityToken, uint256 fee0PerShare, uint256 fee1PerShare);

    /**
     * @notice Return the LP token address for a hook-managed pool key, or `address(0)` when the pool is not initialized.
     * @dev This is a convenience view over `poolInfo(key.toId()).liquidityToken`.
     * @param key The pool key to query.
     * @return liquidityToken The LP token contract address, or `address(0)` when the pool is not initialized.
     */
    function lpToken(PoolKey calldata key) external view returns (address liquidityToken);

    /**
     * @notice Preview the current claimable LP fees for an owner without mutating state.
     * @dev Includes both already-pending fees and fees implied by the latest per-share values and owner LP balance.
     * @param key The pool key whose fee accounting is queried.
     * @param owner The owner address for the fee preview.
     * @return fee0Amount The preview claimable amount in currency0.
     * @return fee1Amount The preview claimable amount in currency1.
     */
    function claimableFees(PoolKey calldata key, address owner)
        external
        view
        returns (uint256 fee0Amount, uint256 fee1Amount);

    /// @notice Low-level liquidity execution API.
    /// @dev Adds full-range liquidity using the caller as payer and mints LP shares to `params.to`.
    /// Intended for routers and advanced integrators and does not implement end-user deadline or
    /// min-amount protections. The pool fee is not caller-configurable here: this Hook Core only operates on its
    /// dynamic-fee pool type.
    /// @param params The core liquidity-add parameters.
    /// @return liquidity The LP liquidity minted for this operation.
    /// @return delta The balance delta settled against the caller.
    function addLiquidityCore(AddLiquidityCoreParams calldata params)
        external
        returns (uint128 liquidity, BalanceDelta delta);

    /// @notice Low-level liquidity exit API.
    /// @dev Removes full-range liquidity owned by the caller and sends the underlying tokens to `params.recipient`.
    /// Intended for routers and advanced integrators and does not implement end-user deadline or
    /// min-amount protections. The pool fee is not caller-configurable here: this Hook Core only operates on its
    /// dynamic-fee pool type.
    /// @param params The core liquidity-remove parameters.
    /// @return delta The balance delta returned by the liquidity removal.
    function removeLiquidityCore(RemoveLiquidityCoreParams calldata params) external returns (BalanceDelta delta);

    /**
     * @notice Low-level fee-claim API.
     * @dev Claims pending LP fees for `msg.sender` and forwards them to `params.recipient`.
     * @param params The core fee-claim parameters.
     * @return fee0Amount The claimed amount of currency0 fees.
     * @return fee1Amount The claimed amount of currency1 fees.
     */
    function claimFeesCore(ClaimFeesCoreParams calldata params)
        external
        returns (uint256 fee0Amount, uint256 fee1Amount);

    /**
     * @notice Execute the preorder settlement swap through the hook's dedicated settlement path.
     * @dev Callable only by the configured launcher.
     * @param params Preorder settlement payload.
     * @return delta Balance delta describing the net token movement after applying fixed 1% settlement economics.
     */
    function executePreorderSettlement(PreorderSettlementParams calldata params) external returns (BalanceDelta delta);

    /**
     * @notice Internal accounting helper for LP fee snapshots.
     * @dev Integrators normally should not call this directly unless they intentionally want to synchronize fee
     * accounting outside the standard LP token transfer / claim flow.
     * @param id The pool id.
     * @param user The user address.
     */
    function updateUserSnapshot(PoolId id, address user) external;

    // ==========================
    // Events
    // ==========================

    /// @notice Emitted when the treasury address is updated.
    event TreasuryUpdated(address oldTreasury, address newTreasury);

    /// @notice Emitted when a currency's protocol-fee support flag is updated.
    event ProtocolFeeCurrencySupportUpdated(Currency indexed currency, bool supported);

    /// @notice Emitted when the launcher binding is updated.
    event LauncherUpdated(address oldLauncher, address newLauncher);

    /// @notice Emitted when the pool initializer router is updated.
    event PoolInitializerUpdated(address oldInitializer, address newInitializer);

    /// @notice Emitted when a one-time pool initialization authorization is written.
    event PoolInitializationAuthorized(PoolId indexed poolId, uint160 startPriceX96);

    /// @notice Emitted when the default launch fee configuration is updated.
    event DefaultLaunchFeeConfigUpdated(
        uint24 oldStartFeeBps,
        uint24 oldMinFeeBps,
        uint32 oldDecayDurationSeconds,
        uint24 newStartFeeBps,
        uint24 newMinFeeBps,
        uint32 newDecayDurationSeconds
    );

    /// @notice Emitted when the public swap resume time is updated for a pool.
    event PublicSwapResumeTimeUpdated(PoolId indexed poolId, uint40 oldResumeTime, uint40 newResumeTime);

    /// @notice Emitted when a pool is initialized
    event PoolInitialized(
        PoolId indexed poolId, address indexed liquidityToken, Currency indexed currency0, Currency currency1
    );

    /// @notice Emitted when protocol fees are collected
    event ProtocolFeeCollected(
        PoolId indexed poolId, Currency indexed currency, address indexed treasury, uint256 amount, uint256 blockNumber
    );

    /// @notice Emitted when LP fees are collected
    event LPFeeCollected(
        PoolId indexed poolId, Currency indexed currency, uint256 amount, uint256 feePerShare, uint256 blockNumber
    );

    /// @notice Emitted when liquidity is added to a pool
    event LiquidityAdded(
        PoolId indexed poolId,
        address indexed provider,
        address indexed to,
        uint128 liquidity,
        uint256 amount0,
        uint256 amount1
    );

    /// @notice Emitted when liquidity is removed from a pool
    event LiquidityRemoved(
        PoolId indexed poolId, address indexed provider, uint128 liquidity, uint256 amount0, uint256 amount1
    );

    /// @notice Emitted when a user claims their LP fees
    event FeesClaimed(
        PoolId indexed poolId,
        address indexed user,
        Currency indexed currency0,
        Currency currency1,
        uint256 fee0Amount,
        uint256 fee1Amount
    );

    /// @notice Reverts when a pool has not been initialized by the hook.
    error PoolNotInitialized();

    /// @notice Reverts when the pool tickSpacing is not the expected default.
    error TickSpacingNotDefault();

    /// @notice Reverts when the pool fee configuration is not set to dynamic fee.
    error FeeMustBeDynamic();

    /// @notice Reverts when a supplied PoolKey points at a different hook address.
    error HookAddressMismatch();

    /// @notice Reverts when pool liquidity exists but no tracked LP shares can earn fees.
    error NoActiveLiquidityShares();

    /// @notice Reverts when a restricted hook-only function is called by an external sender.
    error SenderMustBeHook();

    /// @notice Reverts when `deadline` is in the past.
    error ExpiredPastDeadline();

    /// @notice Reverts when actual amounts are worse than user-provided minimums.
    error TooMuchSlippage();

    /// @notice Reverts when an exact-input swap underdelivers the expected pool-side input.
    error ExactInputPartialFill();

    /// @notice Reverts when an exact-output swap underdelivers the expected pool-side output.
    error ExactOutputPartialFill();

    /// @notice Reverts when a zero address is supplied where a non-zero address is required.
    error ZeroAddress();

    /// @notice Reverts when a hook-managed pool or protocol config uses native currency.
    error NativeCurrencyUnsupported();

    /// @notice Reverts when a launch fee configuration value is zero or invalid.
    error ZeroValue();

    /// @notice Reverts when a given currency is not supported by configuration.
    error CurrencyNotSupported();

    /// @notice Reverts when the caller is not authorized.
    error Unauthorized();

    /// @notice Reverts when the pool initializer router is not authorized.
    error UnauthorizedPoolInitializer();

    /// @notice Reverts when a pool initialization has not been pre-authorized.
    error UnauthorizedPoolInitialization();

    /// @notice Reverts when a pool initialization authorization is already active.
    error PoolInitializationAlreadyAuthorized();

    /// @notice Reverts when pool initialization uses a different price than authorized.
    error InvalidInitialPrice();

    /// @notice Reverts when a public swap is attempted during the post-unlock protection window.
    error PublicSwapDisabled();

    /// @notice Reverts when an ERC20 transfer returns false.
    error ERC20TransferFailed();

    /// @notice Reverts when a pool-manager upgrade target does not match the current manager.
    error UpgradePoolManagerMismatch(address currentPoolManager, address newPoolManager);

    /// @notice Reverts when the hook and engine are constructed with different PoolManager addresses.
    error DynamicFeeEnginePoolManagerMismatch(address hookPoolManager, address enginePoolManager);

    /// @notice Reverts when the new dynamic fee engine has not authorized this hook as a caller.
    error EngineNotAuthorizedCaller(address engine);

    /// @notice Reverts when the dynamic fee engine owner is not the hook proxy itself.
    error DynamicFeeEngineOwnerMismatch(address engine, address expectedOwner, address actualOwner);

    /// @notice Reverts when the LP token implementation address has no deployed code.
    error LPTokenImplementationCodeNotReady(address implementation);

    /// @notice Reverts when the preorder settlement executor address has no deployed code.
    error PreorderSettlementExecutorCodeNotReady(address executor);

    /// @notice Reverts when the executor is immutable-bound to a hook other than this hook proxy.
    error PreorderSettlementExecutorHookMismatch(address executor, address expectedHook, address actualHook);

    /// @notice Reverts when the executor-reported output-side protocol fee does not match the hook-derived amount.
    error PreorderSettlementFeeMismatch();

    /// @notice Migrates the hook to a new dynamic fee engine proxy.
    /// @dev `newEngine` must be an initialized engine proxy owned by this hook proxy and authorized for this hook.
    ///      Do not pass an implementation address here; use `upgradeDynamicFeeEngineImplementation` to upgrade the
    ///      currently bound engine proxy implementation.
    /// @param newEngine Initialized engine proxy owned by this hook proxy and authorized for this hook.
    function upgradeDynamicFeeEngine(IMemeverseDynamicFeeEngine newEngine) external;

    /// @notice Upgrades the implementation used by the currently bound dynamic fee engine proxy.
    /// @param newImplementation New engine implementation address.
    /// @param data Optional initialization or migration calldata forwarded to the engine upgrade.
    function upgradeDynamicFeeEngineImplementation(address newImplementation, bytes calldata data) external;

    /// @notice Replaces the stateless preorder settlement executor.
    /// @param executor New executor implementation with deployed code.
    function setPreorderSettlementExecutor(IMemeversePreorderSettlementExecutor executor) external;

    /// @notice Updates the clone template used to deploy LP tokens for new pools.
    /// @dev Implementations are expected to restrict this to an admin or owner role.
    ///      Existing LP clones are unaffected — they are independent contracts.
    /// @param implementation_ The new LP token clone implementation.
    function setLpTokenImplementation(address implementation_) external;

    /// @notice Emitted when the dynamic fee engine pointer is updated.
    event DynamicFeeEngineUpdated(address oldEngine, address newEngine);

    /// @notice Emitted when the LP token implementation pointer is initialized or updated.
    event LPTokenImplementationUpdated(address oldImplementation, address newImplementation);

    /// @notice Emitted when the preorder settlement executor pointer is initialized or updated.
    event PreorderSettlementExecutorUpdated(address oldExecutor, address newExecutor);
}
