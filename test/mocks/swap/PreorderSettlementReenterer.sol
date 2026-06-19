// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {SwapParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

import {MockPoolManagerForHookLiquidity} from "./HookLiquidityMocks.sol";

/// @notice Malicious ERC20 that reenters a swap from inside `transfer`.
/// @dev Models the adversarial scenario the hook's preorder-settlement bypass is designed against:
///      while the settlement marker is set, a token callback fired during the executor's `settle`
///      tries to start its own pool swap. Only `transfer` reenters because the executor pays its
///      input via `transfer` (see CurrencySettler.settle when payer == address(this)); `transferFrom`
///      is left untouched so the hook's input-side fee collection, which runs before the marker is
///      set, stays undisturbed. The reentrant swap's `sender` is this contract, not the executor, so
///      the hook must route it through the normal (non-bypass) fee path.
contract PreorderSettlementReenterer is MockERC20 {
    MockPoolManagerForHookLiquidity public manager;
    PoolKey public reenterKey;
    SwapParams public reenterParams;
    bool public armed;
    bool public reentryFired;
    bool public reentryBlocked;

    constructor() MockERC20("PreorderReenterer", "PRR", 18) {}

    /// @notice Arms a single reentrant swap fired from the next `transfer`.
    function arm(MockPoolManagerForHookLiquidity manager_, PoolKey memory key_, SwapParams memory params_) external {
        manager = manager_;
        reenterKey = key_;
        reenterParams = params_;
        armed = true;
    }

    /// @dev Fires the armed reentrant swap once, recording whether it was rejected. The reentrant swap's
    ///      revert is swallowed (try/catch) so the surrounding settlement can continue and the test can
    ///      observe the outcome: `reentryBlocked == true` proves the reentry took the normal fee path and
    ///      was rejected, i.e. it did NOT hit the executor bypass. One-shot guard prevents recursion.
    function transfer(address to, uint256 amount) public override returns (bool) {
        if (armed) {
            armed = false;
            reentryFired = true;
            try manager.swap(reenterKey, reenterParams, bytes("")) {
                reentryBlocked = false;
            } catch {
                reentryBlocked = true;
            }
        }
        return super.transfer(to, amount);
    }
}
