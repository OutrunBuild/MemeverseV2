// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

/// @notice Delegatecall-only entry invoked by the MemeverseLauncher facade to run POL minting
///         (Locked-stage user add-liquidity + POL mint) in the proxy storage context. Implemented by
///         MemeversePOLMinter.
/// @dev The facade performs the outer validation (verseId / pause / input non-zero / stage >= Locked),
///      reads verse.uAsset / verse.memecoin / verse.pol, then delegatecalls this entry. `msg.value` is
///      irrelevant because the entry is nonpayable.
interface IMemeversePOLMinter {
    /// @notice Collects uAsset/memecoin from the caller, adds liquidity via the verse router, mints POL to the
    ///         caller, and refunds any unused input.
    /// @dev Invoked via delegatecall by the facade's `mintPOLToken`. Under delegatecall `msg.sender` is still
    ///      the original caller (transfer-in payer, POL mint recipient, refund target) and `address(this)` is
    ///      the launcher proxy (token custody, approval owner, router liquidity recipient).
    /// @param uAsset The verse uAsset address (forwarded by the facade).
    /// @param memecoin The verse memecoin address (forwarded by the facade).
    /// @param pol The verse POL address (forwarded by the facade).
    /// @param amountInUAssetDesired Maximum uAsset budget.
    /// @param amountInMemecoinDesired Maximum memecoin budget.
    /// @param amountInUAssetMin Minimum uAsset spend accepted by the router in auto-liquidity mode.
    /// @param amountInMemecoinMin Minimum memecoin spend accepted by the router in auto-liquidity mode.
    /// @param amountOutDesired Desired POL amount; zero means mint the amount implied by the budgets.
    /// @param deadline Transaction deadline forwarded to the router.
    /// @return amountInUAsset The consumed uAsset amount.
    /// @return amountInMemecoin The consumed memecoin amount.
    /// @return amountOut The minted POL amount.
    function mintPOLToken(
        address uAsset,
        address memecoin,
        address pol,
        uint256 amountInUAssetDesired,
        uint256 amountInMemecoinDesired,
        uint256 amountInUAssetMin,
        uint256 amountInMemecoinMin,
        uint256 amountOutDesired,
        uint256 deadline
    ) external returns (uint256 amountInUAsset, uint256 amountInMemecoin, uint256 amountOut);
}
