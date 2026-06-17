// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

/// @notice Test helpers for the yield vault suite, kept mock-only (no test-file import).
contract MockComposeAsset is MockERC20 {
    mapping(bytes32 guid => uint256 amount) internal queuedAmounts;

    constructor() MockERC20("Compose Memecoin", "cMEME", 18) {}

    /// @notice Stores the queued compose amount keyed by LayerZero guid.
    /// @dev Test helper for simulating `withdrawIfNotExecuted` availability.
    /// @param guid The LayerZero message guid.
    /// @param amount The amount that should be withdrawn for this guid.
    function setQueuedAmount(bytes32 guid, uint256 amount) external {
        queuedAmounts[guid] = amount;
    }

    /// @notice Mints the queued amount to `receiver` and clears the guid entry.
    /// @dev Test helper mirroring the production `IOFTCompose.withdrawIfNotExecuted` shape.
    /// @param guid The LayerZero message guid.
    /// @param receiver The address receiving the withdrawn tokens.
    /// @return amount The amount withdrawn for the guid.
    function withdrawIfNotExecuted(bytes32 guid, address receiver) external returns (uint256 amount) {
        amount = queuedAmounts[guid];
        queuedAmounts[guid] = 0;
        mint(receiver, amount);
    }

    /// @notice Burns test tokens from the caller.
    /// @dev Used to satisfy the vault path that burns yield when no shares exist.
    /// @param amount The token amount to burn.
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}
