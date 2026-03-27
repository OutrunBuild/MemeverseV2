// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

/**
 * @title IOFTCompose
 * @dev Interface for tracking and resolving OFT compose execution status.
 */
interface IOFTCompose {
    struct ComposeTxStatus {
        address composer; // The Layerzero Composer contract of this tx
        address UBO; // Ultimate beneficiary owner
        uint256 amount; // OFT cross-chain amount
        bool isExecuted; // Has Been Executed?
    }

    /// @notice Checks whether a compose transaction has already been finalized.
    /// @dev Used to guard duplicate settlement paths.
    /// @param guid LayerZero message GUID.
    /// @return executed True when compose execution is finalized.
    function getComposeTxExecutedStatus(bytes32 guid) external view returns (bool);

    /// @notice Marks a compose transaction as executed.
    /// @dev Intended for the authorized compose executor once downstream settlement completes.
    /// @param guid LayerZero message GUID.
    function notifyComposeExecuted(bytes32 guid) external;

    /// @notice Recovers bridged tokens from a compose flow that never executed.
    /// @dev Reverts if already executed or caller is unauthorized.
    /// @param guid LayerZero message GUID.
    /// @param receiver Address receiving the withdrawn tokens.
    /// @return amount Amount transferred to `receiver`.
    function withdrawIfNotExecuted(bytes32 guid, address receiver) external returns (uint256 amount);

    event NotifyComposeExecuted(bytes32 indexed guid);

    event WithdrawIfNotExecuted(
        bytes32 indexed guid, address indexed composer, address indexed receiver, uint256 amount
    );

    error AlreadyExecuted();

    error PermissionDenied();
}
