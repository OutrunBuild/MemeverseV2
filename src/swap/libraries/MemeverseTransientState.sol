// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

/// @title MemeverseTransientState
/// @notice Thin wrapper around transient storage used by Memeverse swap flows.
/// @dev Keeps raw `tstore` / `tload` isolated from hook business logic.
library MemeverseTransientState {
    function storeSwapContext(uint256 feeBps, uint160 preSqrtPriceX96) internal {
        bytes32 feeSlot = _swapFeeBpsSlot();
        bytes32 priceSlot = _preSwapSqrtPriceSlot();
        assembly {
            tstore(feeSlot, feeBps)
            tstore(priceSlot, preSqrtPriceX96)
        }
    }

    function loadSwapFeeBps() internal view returns (uint256 feeBps) {
        bytes32 feeSlot = _swapFeeBpsSlot();
        assembly {
            feeBps := tload(feeSlot)
        }
    }

    function loadPreSwapSqrtPriceX96() internal view returns (uint160 preSqrtPriceX96) {
        bytes32 priceSlot = _preSwapSqrtPriceSlot();
        assembly {
            preSqrtPriceX96 := tload(priceSlot)
        }
    }

    function storeRequestedInputBudget(uint256 inputBudget) internal {
        bytes32 budgetSlot = _requestedInputBudgetSlot();
        assembly {
            tstore(budgetSlot, inputBudget)
        }
    }

    function loadRequestedInputBudget() internal view returns (uint256 inputBudget) {
        bytes32 budgetSlot = _requestedInputBudgetSlot();
        assembly {
            inputBudget := tload(budgetSlot)
        }
    }

    function _swapFeeBpsSlot() private pure returns (bytes32) {
        return bytes32(uint256(keccak256(abi.encodePacked("memeverse.transient.", "swap-fee-bps"))) - 1);
    }

    function _preSwapSqrtPriceSlot() private pure returns (bytes32) {
        return bytes32(uint256(keccak256(abi.encodePacked("memeverse.transient.", "pre-swap-sqrt-price"))) - 1);
    }

    function _requestedInputBudgetSlot() private pure returns (bytes32) {
        return bytes32(uint256(keccak256(abi.encodePacked("memeverse.transient.", "requested-input-budget"))) - 1);
    }
}
