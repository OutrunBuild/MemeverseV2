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
    /// @notice Enumeration of anti-snipe check failure reasons.
    enum AntiSnipeFailureReason {
        /// @notice Check passed.
        None, // 0
        /// @notice This block already contains a successful swap (only one success allowed per block).
        BlockAlreadyHasSuccessfulSwap, // 1
        /// @notice The swap did not set a sqrtPriceLimitX96.
        NoPriceLimitSet, // 2
        /// @notice The user-provided price limit implies slippage above the hook’s maximum.
        SlippageExceedsMaximum, // 3
        /// @notice Randomized anti-snipe probability check failed.
        ProbabilityCheckFailed // 4
    }

    /// @notice Pool information tracked by the hook.
    struct PoolInfo {
        /// @notice Custom ERC20 LP token address for this pool.
        address liquidityToken;
        /// @notice Block number when anti-snipe protection ends.
        uint96 antiSnipeEndBlock;
        /// @notice Accumulated LP fees for currency0 (per share, scaled by PRECISION in the implementation).
        uint256 fee0PerShare;
        /// @notice Accumulated LP fees for currency1 (per share, scaled by PRECISION in the implementation).
        uint256 fee1PerShare;
    }

    /// @notice Anti-snipe state tracked per block per pool.
    struct AntiSnipeBlockData {
        /// @notice Total number of swap attempts observed in this block.
        uint248 attempts;
        /// @notice Whether this block already has a successful swap.
        bool successful;
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

    struct FailedAttemptQuote {
        uint256 feeBps;
        uint256 feeAmount;
        Currency feeCurrency;
        bool feeToTreasury;
    }

    /**
     * @notice Low-level anti-snipe primitive for routers and advanced integrators.
     * @dev The returned `allowed` result is intended to be consumed by a router before it decides whether to proceed to
     * `poolManager.swap`. This is not a recommended end-user entrypoint.
     * @param key The pool key for the attempted swap.
     * @param params The swap parameters for the attempted swap.
     * @param trader The end user on whose behalf the router is attempting the swap.
     * @return allowed Whether the attempt passed anti-snipe checks.
     * @return failureReason The anti-snipe failure reason when `allowed` is false, otherwise `None`.
     */
    function requestSwapAttempt(
        PoolKey calldata key,
        SwapParams calldata params,
        address trader,
        uint256 inputBudget,
        address refundRecipient
    ) external payable returns (bool allowed, AntiSnipeFailureReason failureReason);

    /**
     * @notice Returns the anti-snipe failure-fee quote for a swap attempt during the protection window.
     * @dev The failure fee is always expressed on the input side. On failure, it routes entirely either to treasury or
     * LPs depending on whether the input currency equals the configured protocol-fee currency.
     * @param key The pool key for the attempted swap.
     * @param params The swap parameters for the attempted swap.
     * @return quote The quoted failure-fee amount, side, and recipient class.
     */
    function quoteFailedAttempt(PoolKey calldata key, SwapParams calldata params, uint256 inputBudget)
        external
        view
        returns (FailedAttemptQuote memory quote);

    /**
     * @notice Low-level anti-snipe view helper for routers and SDK orchestration.
     * @param poolId The pool id to query.
     * @return active Whether anti-snipe checks are still active for the pool.
     */
    function isAntiSnipeActive(PoolId poolId) external view returns (bool active);

    /**
     * @notice Core quote API for the hook's latest swap state.
     * @dev Official integrations should prefer `MemeverseSwapRouter.quoteSwap(...)`. This low-level quote remains
     * available for custom routers, aggregators, and other advanced on-chain integrations.
     * @param key The pool key being quoted.
     * @param params The swap parameters being quoted.
     * @return quote The projected fee amounts, side, and estimated user/pool flows.
     */
    function quoteSwap(PoolKey calldata key, SwapParams calldata params) external view returns (SwapQuote memory quote);

    /**
     * @notice Returns stored pool information for a hook-managed pool.
     * @param poolId The pool id to query.
     * @return liquidityToken The LP token contract for the pool.
     * @return antiSnipeEndBlock The block at which anti-snipe protection ends.
     * @return fee0PerShare The accumulated fee-per-share for currency0.
     * @return fee1PerShare The accumulated fee-per-share for currency1.
     */
    function poolInfo(PoolId poolId)
        external
        view
        returns (address liquidityToken, uint96 antiSnipeEndBlock, uint256 fee0PerShare, uint256 fee1PerShare);

    /**
     * @notice Low-level liquidity execution API.
     * @dev Adds full-range liquidity using the caller as payer and mints LP shares to `params.to`.
     * This function is intended for routers and advanced integrators and does not implement end-user deadline or
     * min-amount protections. The pool fee is not caller-configurable here: this Hook Core only operates on its
     * dynamic-fee pool type.
     * @param params The core liquidity-add parameters.
     * @return liquidity The LP liquidity minted for this operation.
     * @return delta The balance delta settled against the caller.
     */
    function addLiquidityCore(AddLiquidityCoreParams calldata params)
        external
        payable
        returns (uint128 liquidity, BalanceDelta delta);

    /**
     * @notice Low-level liquidity exit API.
     * @dev Removes full-range liquidity owned by the caller and sends the underlying tokens to `params.recipient`.
     * This function is intended for routers and advanced integrators and does not implement end-user deadline or
     * min-amount protections. The pool fee is not caller-configurable here: this Hook Core only operates on its
     * dynamic-fee pool type.
     * @param params The core liquidity-remove parameters.
     * @return delta The balance delta returned by the liquidity removal.
     */
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

    /// @notice Emitted when the anti-snipe duration (in blocks) is updated.
    event AntiSnipeDurationUpdated(uint256 oldDuration, uint256 newDuration);

    /// @notice Emitted when the maximum probability base for anti-snipe checks is updated.
    event MaxAntiSnipeProbabilityBaseUpdated(uint256 oldBase, uint256 newBase);

    /// @notice Emitted when the emergency fixed-fee mode is toggled.
    event EmergencyFlagUpdated(bool oldFlag, bool newFlag);

    /// @notice Emitted when a pool is initialized
    event PoolInitialized(
        PoolId indexed poolId,
        address indexed liquidityToken,
        Currency indexed currency0,
        Currency currency1,
        uint96 antiSnipeEndBlock
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

    /// @notice Emitted when a swap is blocked by anti-snipe protection
    /// @param reason Failure reason enum value (uint8):
    ///   0=None (passed),
    ///   1=BlockAlreadyHasSuccessfulSwap (block already has successful swap),
    ///   2=NoPriceLimitSet (no price limit set),
    ///   3=SlippageExceedsMaximum (slippage exceeds maximum limit),
    ///   4=ProbabilityCheckFailed (probability check failed)
    event SwapBlocked(
        PoolId indexed poolId,
        address indexed trader,
        Currency indexed currencyIn,
        uint256 amountSpecified,
        uint256 blockNumber,
        uint8 reason
    );

    /// @notice Emitted when a swap passes anti-snipe checks
    event SwapAllowed(
        PoolId indexed poolId,
        address indexed trader,
        Currency indexed currencyIn,
        uint256 amountSpecified,
        uint256 blockNumber,
        uint256 attempts
    );

    /// @notice Emitted when a failed anti-snipe attempt is charged a protection-window failure fee.
    event FailedAttemptFeeCollected(
        PoolId indexed poolId,
        address indexed caller,
        Currency indexed feeCurrency,
        bool feeToTreasury,
        uint256 amount,
        uint256 blockNumber
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

    /// @notice Reverts when the attached native value does not exactly match the required native input.
    error InvalidNativeValue(uint256 expected, uint256 actual);

    /// @notice Reverts when a given currency is not supported by configuration.
    error CurrencyNotSupported();

    /// @notice Reverts when the caller is not authorized.
    error Unauthorized();

    /// @notice Reverts when a critical address parameter is unexpectedly zero.
    error ZeroAddress();

    /// @notice Reverts when a numeric configuration is unexpectedly zero.
    error ZeroValue();

    /// @notice Reverts when an ERC20 transfer returns false.
    error ERC20TransferFailed();

    /// @notice Reverts when the configured treasury cannot receive native protocol fees.
    error NativeTreasuryMustAcceptETH();

    /// @notice Reverts when a successful anti-snipe ticket is later used with more input than originally budgeted.
    error InputBudgetExceeded(uint256 actualInputAmount, uint256 inputBudget);

    /// @notice Reverts when a delegated fee-claim signature is invalid.
    error InvalidClaimSignature();

    /// @notice Reverts when the same transaction requests anti-snipe access for the same pool more than once.
    error PoolAlreadyRequestedThisTransaction();

    /// @notice Reverts when an anti-snipe-window swap reaches the hook without a valid same-tx ticket.
    error MissingAntiSnipeTicket();
}
