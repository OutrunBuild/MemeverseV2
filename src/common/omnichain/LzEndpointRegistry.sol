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

    /// @notice Batch-updates chain-to-endpoint mappings.
    /// @dev Entries with `chainId == 0` or `endpointId == 0` are ignored.
    /// @param pairs List of `(chainId, endpointId)` pairs to store.
    function setLzEndpointIds(LzEndpointIdPair[] calldata pairs) external override onlyOwner {
        uint256 pairsLength = pairs.length;
        for (uint256 i = 0; i < pairsLength;) {
            LzEndpointIdPair calldata pair = pairs[i];
            unchecked {
                ++i;
            }
            if (pair.chainId == 0 || pair.endpointId == 0) continue;

            lzEndpointIdOfChain[pair.chainId] = pair.endpointId;
        }

        emit SetLzEndpointIds(pairs);
    }
}
