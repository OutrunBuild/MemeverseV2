// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

/**
 * @title Memeverse Uniswap Hook V2 (upgrade-target shell)
 * @notice Facade upgrade-target shell used by the hook transparent proxy upgrade tests.
 * @dev Does not inherit MemeverseUniswapHook. `version()` confirms the new code is live after ProxyAdmin upgrades.
 *      `version()` confirms the new code is live. Post-upgrade hook storage is read via the proxy's public getters
 *      or storage slots while this facade is active.
 */
contract MemeverseUniswapHookV2 {
    /// @notice PoolManager constructor argument kept for upgrade tests that document operator-side compatibility.
    IPoolManager public immutable poolManager;

    /// @param poolManager_ Must equal the V1 hook's poolManager for the upgrade to pass the match check.
    constructor(IPoolManager poolManager_) {
        poolManager = poolManager_;
    }

    /// @notice Returns the upgrade-target version marker.
    function version() external pure returns (uint256) {
        return 2;
    }
}
