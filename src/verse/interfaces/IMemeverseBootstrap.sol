// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

/// @notice Delegatecall-only entry invoked by the MemeverseLauncher facade to run bootstrap
///         liquidity deployment in the proxy storage context. Implemented by MemeverseBootstrap.
interface IMemeverseBootstrap {
    function deployLiquidity(
        uint256 verseId,
        address uAsset,
        address memecoin,
        address pol,
        uint256 totalLeveragedDebt,
        address _polend,
        address _polSplitter
    ) external;
}
