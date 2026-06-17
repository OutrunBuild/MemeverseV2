// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

import {IPoolManager, SwapParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

/// @title IMemeverseDynamicFeeEngine
/// @notice Interface for Memeverse dynamic swap fee quoting and state tracking.
/// @dev Mutating APIs namespace hook-owned state by `msg.sender`; callers pass `trader` explicitly for address batching.
interface IMemeverseDynamicFeeEngine {
    /// @notice Initializes the UUPS proxy owner and authorizes the single hook caller.
    /// @param initialOwner Owner authorized to upgrade the engine.
    /// @param authorizedHook Hook address authorized to call mutating engine APIs. Must be non-zero.
    function initialize(address initialOwner, address authorizedHook) external;

    /// @notice Hook-owned launch-fee schedule copied into mutating engine calls.
    struct LaunchFeeConfig {
        uint24 startFeeBps;
        uint24 minFeeBps;
        uint32 decayDurationSeconds;
    }

    /// @notice Per-hook, per-pool dynamic fee state.
    struct DynamicFeeState {
        uint256 weightedVolume0;
        uint256 weightedPriceVolume0;
        uint256 ewVWAPX18;
        uint160 volAnchorSqrtPriceX96;
        uint40 volLastMoveTs;
        uint24 volDeviationAccumulator;
        uint24 volCarryAccumulator;
        uint24 shortImpactPpm;
        uint40 shortLastTs;
    }

    /// @notice Per-hook, per-trader, per-pool short batch state.
    struct AddressBatchState {
        uint192 batchAccumPpm;
        uint64 batchStartTs;
    }

    /// @notice Inputs used to refresh pre-swap volatility anchor state without realized swap writes.
    struct RefreshBeforeSwapParams {
        PoolId poolId;
        uint160 preSqrtPriceX96;
    }

    /// @notice Inputs used by the hook to prepare one swap fee without reading hook or PoolManager state.
    struct PrepareSwapFeeParams {
        PoolId poolId;
        SwapParams swapParams;
        address trader;
        uint160 preSqrtPriceX96;
        uint128 liquidity;
        bool protocolFeeOnInput;
        LaunchFeeConfig launchFeeConfig;
        uint40 launchTimestamp;
    }

    /// @notice Hook-assembled read-only quote context.
    /// @dev `poolId` selects the engine's per-hook pool state namespace; PoolManager and hook storage are read by the hook.
    struct QuoteSwapContext {
        PoolId poolId;
        SwapParams swapParams;
        address trader;
        uint160 preSqrtPriceX96;
        uint128 liquidity;
        bool protocolFeeOnInput;
        LaunchFeeConfig launchFeeConfig;
        uint40 launchTimestamp;
    }

    /// @notice Prepared fee quote returned to the hook before a swap.
    struct PreparedSwapFee {
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

    /// @notice Inputs used to update realized dynamic fee state after an actual swap.
    struct UpdateAfterSwapParams {
        PoolId poolId;
        BalanceDelta delta;
        address trader;
        uint160 preSqrtPriceX96;
        uint160 postSqrtPriceX96;
    }

    /// @notice PoolManager used only by read-only quote calls.
    /// @return Bound Uniswap v4 PoolManager.
    function poolManager() external view returns (IPoolManager);

    /// @notice Refreshes pre-swap volatility anchor/carry state in the caller hook namespace.
    /// @param params Hook-supplied pre-swap state.
    function refreshBeforeSwap(RefreshBeforeSwapParams calldata params) external;

    /// @notice Prepares the dynamic fee for one swap in the caller hook namespace.
    /// @param params Hook-supplied swap and pool state.
    /// @return quote Prepared dynamic fee quote.
    function prepareSwapFee(PrepareSwapFeeParams calldata params) external returns (PreparedSwapFee memory quote);

    /// @notice Updates realized dynamic fee state after one completed swap.
    /// @param params Hook-supplied realized swap state.
    function updateAfterSwap(UpdateAfterSwapParams calldata params) external;

    /// @notice Returns the single hook address authorized to call mutating engine APIs.
    /// @return The authorized hook address.
    function authorizedHook() external view returns (address);

    /// @notice Returns a read-only dynamic fee quote for a hook-supplied pool context.
    /// @dev Only the configured authorized hook may call this API, preserving the engine's hook namespace integrity.
    /// @param hook Hook namespace whose dynamic fee state should be read.
    /// @param context Hook-assembled pool, swap, and launch state.
    /// @return quote Prepared dynamic fee quote.
    function quoteSwapWithContext(address hook, QuoteSwapContext calldata context)
        external
        view
        returns (PreparedSwapFee memory quote);

    /// @notice Reads per-hook dynamic fee state.
    /// @param hook Hook namespace.
    /// @param poolId Pool id.
    /// @return state Current dynamic fee state.
    function getDynamicFeeState(address hook, PoolId poolId) external view returns (DynamicFeeState memory state);

    /// @notice Reads per-hook, per-trader address batch state.
    /// @param hook Hook namespace.
    /// @param trader Trader namespace.
    /// @param poolId Pool id.
    /// @return state Current address batch state.
    function getAddressBatchState(address hook, address trader, PoolId poolId)
        external
        view
        returns (AddressBatchState memory state);

    /// @notice Reverts when attempting to transfer or renounce engine ownership directly.
    ///         Engine ownership is managed through the Hook's upgradeDynamicFeeEngine flow.
    error EngineOwnershipManagedByHook();

    /// @notice Reverts when a required address parameter is the zero address.
    error ZeroAddress();

    /// @notice Reverts when a pool-manager upgrade target does not match the current manager.
    error UpgradePoolManagerMismatch(address currentPoolManager, address newPoolManager);

    /// @notice Reverts when a caller is not allowed to update dynamic fee state.
    error UnauthorizedCaller(address caller);
}
