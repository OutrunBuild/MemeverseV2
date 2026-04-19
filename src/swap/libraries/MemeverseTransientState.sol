// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

/// @title MemeverseTransientState
/// @notice Thin wrapper around transient storage used by Memeverse swap flows.
/// @dev Keeps raw `tstore` / `tload` isolated from hook business logic.
library MemeverseTransientState {
    bytes32 private constant SWAP_CONTEXT_DEPTH_TAG = keccak256("mv.ts.swap.depth");
    bytes32 private constant SWAP_CONTEXT_FEE_TAG = keccak256("mv.ts.swap.fee");
    bytes32 private constant SWAP_CONTEXT_PRICE_TAG = keccak256("mv.ts.swap.price");

    function pushPriceContext(PoolId poolId, uint160 preSqrtPriceX96) internal returns (uint256 depth) {
        depth = _incrementSwapContextDepth();

        bytes32 priceSlot = _swapContextFieldSlot(SWAP_CONTEXT_PRICE_TAG, poolId, depth);
        assembly {
            tstore(priceSlot, preSqrtPriceX96)
        }
    }

    function pushSwapContext(PoolId poolId, uint256 feeBps, uint160 preSqrtPriceX96) internal returns (uint256 depth) {
        depth = _incrementSwapContextDepth();

        bytes32 feeSlot = _swapContextFieldSlot(SWAP_CONTEXT_FEE_TAG, poolId, depth);
        bytes32 priceSlot = _swapContextFieldSlot(SWAP_CONTEXT_PRICE_TAG, poolId, depth);
        assembly {
            tstore(feeSlot, feeBps)
            tstore(priceSlot, preSqrtPriceX96)
        }
    }

    function consumeCurrentPriceContext(PoolId poolId) internal returns (uint160 preSqrtPriceX96, uint256 depth) {
        depth = _loadSwapContextDepth();
        if (depth == 0) return (0, 0);

        bytes32 feeSlot = _swapContextFieldSlot(SWAP_CONTEXT_FEE_TAG, poolId, depth);
        bytes32 priceSlot = _swapContextFieldSlot(SWAP_CONTEXT_PRICE_TAG, poolId, depth);
        bytes32 depthSlot = _swapContextDepthSlot();
        assembly {
            preSqrtPriceX96 := tload(priceSlot)
            tstore(feeSlot, 0)
            tstore(priceSlot, 0)
            tstore(depthSlot, sub(depth, 1))
        }
    }

    function consumeCurrentSwapContext(PoolId poolId)
        internal
        returns (uint256 feeBps, uint160 preSqrtPriceX96, uint256 depth)
    {
        depth = _loadSwapContextDepth();
        if (depth == 0) return (0, 0, 0);

        bytes32 feeSlot = _swapContextFieldSlot(SWAP_CONTEXT_FEE_TAG, poolId, depth);
        bytes32 priceSlot = _swapContextFieldSlot(SWAP_CONTEXT_PRICE_TAG, poolId, depth);
        bytes32 depthSlot = _swapContextDepthSlot();
        assembly {
            feeBps := tload(feeSlot)
            preSqrtPriceX96 := tload(priceSlot)
            tstore(feeSlot, 0)
            tstore(priceSlot, 0)
            tstore(depthSlot, sub(depth, 1))
        }
    }

    function _loadSwapContextDepth() private view returns (uint256 depth) {
        bytes32 depthSlot = _swapContextDepthSlot();
        assembly {
            depth := tload(depthSlot)
        }
    }

    function _incrementSwapContextDepth() private returns (uint256 depth) {
        bytes32 depthSlot = _swapContextDepthSlot();
        assembly {
            depth := add(tload(depthSlot), 1)
            tstore(depthSlot, depth)
        }
    }

    function _swapContextDepthSlot() private pure returns (bytes32) {
        return bytes32(uint256(SWAP_CONTEXT_DEPTH_TAG) - 1);
    }

    function _swapContextFieldSlot(bytes32 tag, PoolId poolId, uint256 depth) private pure returns (bytes32) {
        return bytes32(uint256(keccak256(abi.encode(tag, PoolId.unwrap(poolId), depth))) - 1);
    }
}
