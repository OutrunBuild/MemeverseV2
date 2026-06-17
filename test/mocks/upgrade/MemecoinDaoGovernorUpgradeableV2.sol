// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title Memecoin DAO Governor V2 (upgrade-target shell)
 * @notice Bare upgrade-target shell used by the UUPS upgrade test. Does NOT inherit the governor.
 * @dev Post-upgrade state is verified via `vm.load` against the V1 storage slots; this contract only
 *      exposes `upgradeVersion()` to confirm the new code is live. During the V1->shell upgrade, the
 *      proxy runs V1's `_authorizeUpgrade` (onlyGovernance); this contract's `_authorizeUpgrade` exists
 *      only to satisfy the abstract UUPS requirement and is never exercised through this shell.
 */
contract MemecoinDaoGovernorUpgradeableV2 is UUPSUpgradeable {
    /// @notice Returns the upgrade-target version marker.
    function upgradeVersion() external pure returns (uint256) {
        return 2;
    }

    /// @dev No-op: upgrade authorization is enforced by the V1 implementation while it is still live.
    function _authorizeUpgrade(address) internal pure override {}
}
