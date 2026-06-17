// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";

/// @notice Shared vm.load/vm.store slot primitives for storage-test helpers.
/// @dev Extracted so a single test contract can inherit multiple *StorageHelper contracts
///      (e.g. MemeverseLauncherTestHelper + HookStorageHelper) without triggering
///      "Derived contract must override function _loadSlot/_writeSlot" conflicts.
///      Each helper previously redeclared identical _loadSlot/_writeSlot; those are now
///      inherited once from this base. SLOT-bound helpers (_mappingSlot family) remain
///      per-helper because they reference per-helper SLOT constants.
abstract contract StorageSlotPrimitives is Test {
    /// @dev Read a single storage slot from a proxy via vm.load. Behavior-preserving extraction.
    function _loadSlot(address proxy, bytes32 slot) internal view returns (bytes32) {
        return vm.load(proxy, slot);
    }

    /// @dev Write a single storage slot on a proxy via vm.store. Behavior-preserving extraction.
    function _writeSlot(address proxy, bytes32 slot, bytes32 value) internal {
        vm.store(proxy, slot, value);
    }
}
