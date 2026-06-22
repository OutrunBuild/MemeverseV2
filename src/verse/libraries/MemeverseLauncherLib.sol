// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

import {IMemeverseSwapRouter} from "../../swap/interfaces/IMemeverseSwapRouter.sol";
import {IMemeverseUniswapHook} from "../../swap/interfaces/IMemeverseUniswapHook.sol";
import {IMemeverseLauncher} from "../interfaces/IMemeverseLauncher.sol";

/// @title MemeverseLauncherLib
/// @notice Internal helpers shared between the MemeverseLauncher facade and its MemeverseBootstrap
///         delegatecall sibling: settlement-wiring validation and genesis-funds arithmetic.
/// @dev Functions are `internal`, so they compile inline into each caller. Under both call paths
///      (facade setters and the sibling's `deployLiquidity`) the caller runs in the proxy's
///      delegatecall context, so `address(this)` resolves to the proxy and the wiring check stays
///      consistent. Keep this library to helpers genuinely used by BOTH contracts — do not let it
///      grow into a catch-all dumping ground.
library MemeverseLauncherLib {
    /// @dev Upper bound on combined genesis funds; guards the addition in `checkedTotalGenesisFunds`
    ///      and the remaining-cap projections in the facade.
    uint256 internal constant MAX_SUPPORTED_TOTAL_GENESIS_FUNDS = type(uint128).max;

    /// @notice Reverts unless the swap-router, uniswap-hook, and launcher are mutually wired:
    ///         the router points at the hook, the hook is bound to this launcher, and the hook's
    ///         pool initializer is the router. Guards preorder settlement at both the config gate
    ///         and the bootstrap runtime gate.
    function validateSettlementWiring(address routerAddress, address hookAddress) internal view {
        require(
            routerAddress != address(0) && hookAddress != address(0),
            IMemeverseLauncher.InvalidPreorderSettlementConfig()
        );
        IMemeverseSwapRouter router = IMemeverseSwapRouter(routerAddress);
        IMemeverseUniswapHook hook = IMemeverseUniswapHook(hookAddress);
        require(
            address(router.hook()) == hookAddress && hook.launcher() == address(this)
                && hook.poolInitializer() == routerAddress,
            IMemeverseLauncher.InvalidPreorderSettlementConfig()
        );
    }

    /// @notice Returns `normalFunds + leveragedDebt`, reverting if the sum exceeds the supported cap.
    function checkedTotalGenesisFunds(uint256 normalFunds, uint256 leveragedDebt)
        internal
        pure
        returns (uint256 totalFunds)
    {
        totalFunds = normalFunds + leveragedDebt;
        if (totalFunds > MAX_SUPPORTED_TOTAL_GENESIS_FUNDS) {
            revert IMemeverseLauncher.TotalGenesisFundsTooHigh(totalFunds, MAX_SUPPORTED_TOTAL_GENESIS_FUNDS);
        }
    }
}
