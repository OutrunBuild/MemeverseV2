// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

/// @notice Independent view contract that reads launcher fee state via proxy getters and previews
///         genesis maker fees and distribution LayerZero fees. Implemented by MemeverseFeePreviewReader.
/// @dev Unlike the delegatecall siblings, the reader does NOT bind the launcher ERC-7201 slot and does
///      NOT receive delegatecalls; it staticcalls the proxy's public getters to read state.
interface IMemeverseFeePreviewReader {
    /// @dev Reverted when a constructor argument is the zero address.
    error ZeroInput();

    /// @notice Previews the genesis liquidity maker fees currently available for distribution.
    /// @param verseId Memeverse id.
    /// @return uAssetFee Claimable uAsset-side fee amount.
    /// @return memecoinFee Claimable memecoin-side fee amount.
    function previewGenesisMakerFees(uint256 verseId) external view returns (uint256 uAssetFee, uint256 memecoinFee);

    /// @notice Quotes the LayerZero native fee required to distribute accrued fees cross-chain.
    /// @dev Returns zero when the governance chain is local and no cross-chain dispatch is needed.
    /// @param verseId Memeverse id.
    /// @return lzFee The quoted LayerZero native fee.
    function quoteDistributionLzFee(uint256 verseId) external view returns (uint256 lzFee);
}
