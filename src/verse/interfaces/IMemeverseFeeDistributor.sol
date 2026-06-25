// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

/// @notice Delegatecall-only entries invoked by the MemeverseLauncher facade to run fee collection
///         and distribution in the proxy storage context. Implemented by MemeverseFeeDistributor.
/// @dev `collectAndDistributeFees` is payable because the cross-chain distribution path consumes
///      `msg.value` as the LayerZero native fee; under delegatecall the distributor's dispatcher
///      must therefore accept a non-zero `msg.value` forwarded by the payable facade entry.
interface IMemeverseFeeDistributor {
    /// @notice Collects redeemed fees, burns POL, splits the executor reward, and distributes the
    ///         remaining fees to governance / yield vault recipients.
    /// @dev Invoked via delegatecall by the facade's `redeemAndDistributeFees`; `msg.value` is the
    ///      caller-supplied LayerZero native fee and is preserved across the delegatecall.
    /// @param verseId Memeverse id.
    /// @param rewardReceiver Receiver of the executor reward.
    /// @param polSplitter The launcher's configured POLSplitter address.
    /// @return govFee The distributed governor fee amount.
    /// @return memecoinFee The distributed memecoin fee amount.
    /// @return polFee The distributed POL fee amount.
    /// @return executorReward The distributed executor reward amount.
    /// @return hadFees False iff no redeemed fees were collected (the early-return path); the facade uses
    ///                 this to decide whether to emit `RedeemAndDistributeFees`, exactly mirroring the
    ///                 original inline `_hasNoRedeemedFees` gate so event semantics are preserved.
    function collectAndDistributeFees(uint256 verseId, address rewardReceiver, address polSplitter)
        external
        payable
        returns (uint256 govFee, uint256 memecoinFee, uint256 polFee, uint256 executorReward, bool hadFees);

    /// @notice Captures and accrues auxiliary-pool fees when a verse transitions Locked -> Unlocked.
    /// @dev Invoked via delegatecall by the facade's `changeStage` Locked->Unlocked branch. Burns the
    ///      captured POL fee and accumulates the governance share into `pendingAuxiliaryGovFeeStates`.
    /// @param verseId Memeverse id.
    /// @param polSplitter The launcher's configured POLSplitter address.
    /// @param hook The launcher's configured MemeverseUniswapHook address.
    function captureLockedAuxiliaryFees(uint256 verseId, address polSplitter, address hook) external;
}
