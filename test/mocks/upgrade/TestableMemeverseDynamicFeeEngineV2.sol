// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {FeeEngineStorageSlots} from "../swap/FeeEngineStorageSlots.sol";

/**
 * @title Testable Memeverse Dynamic Fee Engine V2 (upgrade-target facade)
 * @notice Facade upgrade-target shell for the HookLiquidity engine-upgrade tests. Does NOT inherit
 *         the production MemeverseDynamicFeeEngine — direct test inheritance of upgradable prod
 *         contracts is forbidden by the repo test rules.
 * @dev After the upgrade, the proxy storage still carries the V1-era `OwnableUpgradeable` owner (the hook)
 *      at the shared ERC7201 `openzeppelin.storage.Ownable` slot, because V1 initialized it via
 *      `__Ownable_init`. Inheriting `OwnableUpgradeable` here makes the facade's `owner()` read that same
 *      slot, so the hook's post-upgrade `_requireEngineBoundToHook` (which calls `owner()` on the engine)
 *      observes the hook as owner. The facade never re-initializes Ownable; it relies on the persisted slot.
 *      `_authorizeUpgrade` mirrors V1's `onlyOwner` guard.
 *      `authorizedHook()` exposes the ERC7201 `authorizedHook` slot at namespace-base + 2 so the
 *      post-upgrade `_requireEngineBoundToHook` re-binding check reads the persisted value. `poolManager`
 *      is an immutable constructor echo compared by V1 `_authorizeUpgrade`. `version()` confirms the new
 *      code is live. `migrateAuthorizedHook()` is the delegatecall migration target used by the
 *      break-migration test: it writes a bad value into the same `authorizedHook` slot so the
 *      reauthorization check sees a corrupted hook binding. This shell exposes no swap callback logic, so
 *      post-upgrade swap execution is not exercised here — those upgrade tests assert storage survival via
 *      `vm.load` instead.
 */
contract TestableMemeverseDynamicFeeEngineV2 is UUPSUpgradeable, OwnableUpgradeable {
    /// @notice PoolManager the V1 engine was constructed with. Compared by V1 `_authorizeUpgrade`.
    IPoolManager public immutable poolManager;

    /// @param poolManager_ Must equal the V1 engine's poolManager for the upgrade to pass the match check.
    constructor(IPoolManager poolManager_) {
        poolManager = poolManager_;
    }

    /// @notice Returns the upgrade-target version marker.
    function version() external pure returns (uint256) {
        return 2;
    }

    /// @notice Returns the persisted ERC7201 `authorizedHook`. Read by the hook's post-upgrade
    ///         `_requireEngineBoundToHook` re-binding check.
    /// @dev Mirrors V1's slot layout (namespace-base + 2). Does not mutate state.
    function authorizedHook() external view returns (address) {
        bytes32 slot = FeeEngineStorageSlots.authorizedHookSlot();
        address value;
        assembly {
            value := sload(slot)
        }
        return value;
    }

    /// @notice Migration callback: overwrites the ERC7201 `authorizedHook` slot. Called via delegatecall
    ///         as upgrade migration data from the break-migration test; the sstore writes to the proxy's
    ///         storage context, so a subsequent `vm.load(proxy, slot)` observes the corrupted value.
    function migrateAuthorizedHook(address badAuthorizedHook) external {
        bytes32 slot = FeeEngineStorageSlots.authorizedHookSlot();
        assembly {
            sstore(slot, badAuthorizedHook)
        }
    }

    /// @dev Matches V1's guard: UUPS authorization is owner-restricted. Not exercised on the V1->facade
    ///      upgrade itself (V1's `_authorizeUpgrade` runs while V1 is still live); it exists for parity and
    ///      to satisfy the abstract UUPS requirement.
    function _authorizeUpgrade(address) internal view override onlyOwner {}
}
