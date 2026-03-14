// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {ILzEndpointRegistry} from "./interfaces/ILzEndpointRegistry.sol";

/**
 * @title LayerZero Endpoint Registry
 */
contract LzEndpointRegistry is ILzEndpointRegistry, Ownable {
    mapping(uint32 chainId => uint32) public lzEndpointIdOfChain;

    constructor(address _owner) Ownable(_owner) {}

    /// @notice Executes set lz endpoint ids.
    /// @dev See the implementation for behavior details.
    /// @param pairs The pairs value.
    function setLzEndpointIds(LzEndpointIdPair[] calldata pairs) external override onlyOwner {
        for (uint256 i = 0; i < pairs.length;) {
            LzEndpointIdPair calldata pair = pairs[i];
            unchecked {
                i++;
            }
            if (pair.chainId == 0 || pair.endpointId == 0) continue;

            lzEndpointIdOfChain[pair.chainId] = pair.endpointId;
        }

        emit SetLzEndpointIds(pairs);
    }
}
