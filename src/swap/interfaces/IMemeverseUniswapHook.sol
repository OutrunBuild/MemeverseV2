//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {SwapParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

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
        /// @notice Accumulated LP fees for currency0 (per share, scaled by PRECISION in the implementation).
        uint256 fee0PerShare;
        /// @notice Accumulated LP fees for currency1 (per share, scaled by PRECISION in the implementation).
        uint256 fee1PerShare;
    }

    /// @notice Per-user fee accounting state for a pool.
    struct UserFeeState {
        /// @notice Snapshot offset of `fee0PerShare` at the last user update.
        uint256 fee0Offset;
        /// @notice Snapshot offset of `fee1PerShare` at the last user update.
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
        address owner;
        address recipient;
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    struct SwapQuote {
        uint256 feeBps;
        uint256 estimatedUserInputAmount;
        uint256 estimatedUserOutputAmount;
        uint256 estimatedProtocolFeeAmount;
        uint256 estimatedLpFeeAmount;
        bool protocolFeeOnInput;
    }

    struct LaunchFeeConfig {
        uint24 startFeeBps;
        uint24 minFeeBps;
        uint32 decayDurationSeconds;
    }

    /**
     * @notice Core quote API for the hook's latest swap state.
     * @dev Official integrations should prefer `MemeverseSwapRouter.quoteSwap(...)`. This low-level quote remains
     * available for custom routers, aggregators, and other advanced on-chain integrations.
     * @param key The pool key being quoted.
     * @param params The swap parameters being quoted.
     * @return quote The projected fee amounts, side, and estimated user/pool flows.
     */
    function quoteSwap(PoolKey calldata key, SwapParams calldata params) external view returns (SwapQuote memory quote);

    /// @notice Returns the configured launch settlement caller.
    /// @dev This address is allowed to call `poolManager.swap` for the fixed 1% launch settlement path.
    /// @return caller The configured launch settlement caller.
    function launchSettlementCaller() external view returns (address caller);

    /// @notice Returns the launch timestamp for a hook-managed pool.
    /// @dev Used to derive the current launch fee floor for the pool.
    /// @param poolId The pool id to query.
    /// @return timestamp The recorded launch timestamp.
    function poolLaunchTimestamp(PoolId poolId) external view returns (uint40 timestamp);

    /// @notice Returns the default launch fee configuration.
    /// @dev All pools use this config in the first implementation.
    /// @return startFeeBps The launch fee at time zero.
    /// @return minFeeBps The minimum fee after launch decay completes.
    /// @return decayDurationSeconds The launch fee decay duration in seconds.
    function defaultLaunchFeeConfig()
        external
        view
        returns (uint24 startFeeBps, uint24 minFeeBps, uint32 decayDurationSeconds);

    /// @notice Sets the launch settlement caller.
    /// @dev Expected to be restricted by the implementation's access control.
    /// @param caller The address allowed to call `poolManager.swap` for the fixed 1% launch settlement path.
    function setLaunchSettlementCaller(address caller) external;

    /// @notice Sets the default launch fee configuration.
    /// @dev Expected to be restricted by the implementation's access control.
    /// @param config The new default launch fee configuration.
    function setDefaultLaunchFeeConfig(LaunchFeeConfig calldata config) external;

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
     * @notice Returns the LP token address for a hook-managed pool key.
     * @dev This is a convenience view over `poolInfo(key.toId()).liquidityToken`.
     * @param key The pool key to query.
     * @return liquidityToken The LP token contract address, or `address(0)` when the pool is not initialized.
     */
    function lpToken(PoolKey calldata key) external view returns (address liquidityToken);

    /**
     * @notice Returns the current claimable LP fees for an owner without mutating state.
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
        payable
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
     * @dev Claims pending LP fees on behalf of `params.owner`, optionally using a signed authorization.
     * Routers and third parties must provide a valid owner signature. Direct owner calls may set the signature fields
     * to zero and bypass signature verification.
     * @param params The core fee-claim parameters.
     * @return fee0Amount The claimed amount of currency0 fees.
     * @return fee1Amount The claimed amount of currency1 fees.
     */
    function claimFeesCore(ClaimFeesCoreParams calldata params)
        external
        returns (uint256 fee0Amount, uint256 fee1Amount);

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

    /// @notice Emitted when the emergency fixed-fee mode is toggled.
    event EmergencyFlagUpdated(bool oldFlag, bool newFlag);

    /// @notice Emitted when the launch settlement caller is updated.
    event LaunchSettlementCallerUpdated(address oldCaller, address newCaller);

    /// @notice Emitted when the default launch fee configuration is updated.
    event DefaultLaunchFeeConfigUpdated(
        uint24 oldStartFeeBps,
        uint24 oldMinFeeBps,
        uint32 oldDecayDurationSeconds,
        uint24 newStartFeeBps,
        uint24 newMinFeeBps,
        uint32 newDecayDurationSeconds
    );

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

    /// @notice Reverts when initial liquidity does not meet the minimum requirement.
    error LiquidityDoesntMeetMinimum();

    /// @notice Reverts when a restricted hook-only function is called by an external sender.
    error SenderMustBeHook();

    /// @notice Reverts when `deadline` is in the past.
    error ExpiredPastDeadline();

    /// @notice Reverts when actual amounts are worse than user-provided minimums.
    error TooMuchSlippage();

    /// @notice Reverts when the launch settlement caller is zero.
    error ZeroAddress();

    /// @notice Reverts when a launch fee configuration value is zero or invalid.
    error ZeroValue();

    /// @notice Reverts when the attached native value does not exactly match the required native input.
    error InvalidNativeValue(uint256 expected, uint256 actual);

    /// @notice Reverts when a given currency is not supported by configuration.
    error CurrencyNotSupported();

    /// @notice Reverts when the caller is not authorized.
    error Unauthorized();

    /// @notice Reverts when an ERC20 transfer returns false.
    error ERC20TransferFailed();

    /// @notice Reverts when the configured treasury cannot receive native protocol fees.
    error NativeTreasuryMustAcceptETH();

    /// @notice Reverts when a delegated fee-claim signature is invalid.
    error InvalidClaimSignature();
}
