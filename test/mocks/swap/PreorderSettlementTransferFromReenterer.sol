// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager, SwapParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

import {
    IMemeversePreorderSettlementExecutor
} from "../../../src/swap/interfaces/IMemeversePreorderSettlementExecutor.sol";

/// @notice Malicious callback-token that reenters `executor.execute` from inside `transferFrom` when the
///         recipient is the executor, modelling a settlement-input attack: while the hook's
///         `executePreorderSettlement` moves `netInput` to the executor via `transferFrom`, a callback
///         token can reenter the executor with a forged `key.hooks == caller`. The reentrant call runs as
///         `msg.sender == this token`, which the executor's immutable-HOOK guard rejects with
///         `Unauthorized` even though the executor holds the just-credited `netInput`. Only `transferFrom`
///         (not `transfer`) is hooked, and only when `to == executor`, so the hook's fee-side
///         `transferFrom` calls to itself/treasury stay undisturbed.
contract PreorderSettlementTransferFromReenterer is MockERC20 {
    IMemeversePreorderSettlementExecutor public executor;
    IPoolManager public manager;
    PoolKey public forgedKey;
    SwapParams public swapParams;
    bool public armed;
    bool public reentryFired;
    bool public reentryBlocked;

    constructor() MockERC20("PreorderTransferFromReenterer", "PTFR", 18) {}

    /// @notice Arms a single reentrant `executor.execute` from the next `transferFrom` whose recipient is
    ///         the executor. Forges `key.hooks == address(this)` so a legacy `msg.sender == key.hooks`
    ///         guard would have passed.
    function arm(
        IMemeversePreorderSettlementExecutor executor_,
        IPoolManager manager_,
        PoolKey memory key_,
        SwapParams memory params_
    ) external {
        executor = executor_;
        manager = manager_;
        forgedKey = key_;
        forgedKey.hooks = IHooks(address(this));
        swapParams = params_;
        armed = true;
    }

    /// @dev Reenters AFTER `super.transferFrom` so the executor already holds the credited `netInput`,
    ///      matching the live attack window. The revert is swallowed so the settlement can continue and
    ///      the test observes `reentryBlocked`. One-shot guard prevents recursion.
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        bool ok = super.transferFrom(from, to, amount);
        if (armed && to == address(executor)) {
            armed = false;
            reentryFired = true;
            try executor.execute(
                IMemeversePreorderSettlementExecutor.ExecuteParams({
                    poolManager: manager,
                    recipient: address(this),
                    treasury: address(this),
                    key: forgedKey,
                    swapParams: swapParams,
                    protocolFeeOnInput: true,
                    protocolFeeOutputBps: 0
                })
            ) {
                reentryBlocked = false;
            } catch {
                reentryBlocked = true;
            }
        }
        return ok;
    }
}
