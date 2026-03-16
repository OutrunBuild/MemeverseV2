// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

/**
 * @title IOFTCompose
 * @dev Handle the logic related to OFT Compose
 */
interface IOFTCompose {
    struct ComposeTxStatus {
        address composer; // The Layerzero Composer contract of this tx
        address UBO; // Ultimate beneficiary owner
        uint256 amount; // OFT cross-chain amount
        bool isExecuted; // Has Been Executed?
    }

    /// @notice Returns get compose tx executed status.
    /// @dev See the implementation for behavior details.
    /// @param guid The guid value.
    /// @return bool The bool value.
    function getComposeTxExecutedStatus(bytes32 guid) external view returns (bool);

    /// @notice Executes notify compose executed.
    /// @dev See the implementation for behavior details.
    /// @param guid The guid value.
    function notifyComposeExecuted(bytes32 guid) external;

    /// @notice Executes withdraw if not executed.
    /// @dev See the implementation for behavior details.
    /// @param guid The guid value.
    /// @param receiver The receiver value.
    /// @return amount The amount value.
    function withdrawIfNotExecuted(bytes32 guid, address receiver) external returns (uint256 amount);

    event NotifyComposeExecuted(bytes32 indexed guid);

    event WithdrawIfNotExecuted(
        bytes32 indexed guid, address indexed composer, address indexed receiver, uint256 amount
    );

    error AlreadyExecuted();

    error PermissionDenied();
}
