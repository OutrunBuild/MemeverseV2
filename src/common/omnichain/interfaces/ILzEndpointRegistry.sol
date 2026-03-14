//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

/**
 * @dev Interface for the LayerZero endpoint registry.
 */
interface ILzEndpointRegistry {
    struct LzEndpointIdPair {
        uint32 chainId;
        uint32 endpointId;
    }

    /// @notice Returns lz endpoint id of chain.
    /// @dev See the implementation for behavior details.
    /// @param chainId The chainId value.
    /// @return uint32 The uint32 value.
    function lzEndpointIdOfChain(uint32 chainId) external view returns (uint32);

    /// @notice Executes set lz endpoint ids.
    /// @dev See the implementation for behavior details.
    /// @param pairs The pairs value.
    function setLzEndpointIds(LzEndpointIdPair[] calldata pairs) external;

    event SetLzEndpointIds(LzEndpointIdPair[] pairs);
}
