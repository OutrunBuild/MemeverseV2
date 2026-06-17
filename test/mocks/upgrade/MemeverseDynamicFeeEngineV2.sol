// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

/**
 * @title Memeverse Dynamic Fee Engine V2 (upgrade-target shell)
 * @notice Facade upgrade-target shell used by the UUPS upgrade test. Does NOT inherit the engine.
 * @dev The V1 engine's `_authorizeUpgrade` casts the new implementation to `MemeverseDynamicFeeEngine` and
 *      calls `poolManager()` to compare against the V1 immutable `poolManager`. A bare shell lacking a
 *      matching `poolManager()` view would revert on that cast. This facade exposes `poolManager` (immutable,
 *      set from the constructor) so the match check passes; it is a pure address-reinterpret + interface
 *      call, so the shell does not need to actually inherit the engine.
 *      `version()` confirms the new code is live. Post-upgrade fee state is read via `vm.load` against the
 *      V1 storage slots, not V1 getters (which the shell lacks). During the V1->shell upgrade the proxy runs
 *      V1's `_authorizeUpgrade` (onlyOwner + poolManager match); this contract's `_authorizeUpgrade` exists
 *      only to satisfy the abstract UUPS requirement and is never exercised through this shell.
 */
contract MemeverseDynamicFeeEngineV2 is UUPSUpgradeable {
    /// @notice PoolManager the V1 engine was constructed with. Compared by V1 `_authorizeUpgrade` during upgrade.
    IPoolManager public immutable poolManager;

    /// @param poolManager_ Must equal the V1 engine's poolManager for the upgrade to pass the match check.
    constructor(IPoolManager poolManager_) {
        poolManager = poolManager_;
    }

    /// @notice Returns the upgrade-target version marker.
    function version() external pure returns (uint256) {
        return 2;
    }

    /// @dev No-op: upgrade authorization is enforced by the V1 implementation while it is still live.
    function _authorizeUpgrade(address) internal pure override {}
}
