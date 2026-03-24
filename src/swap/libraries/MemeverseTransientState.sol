// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

/// @title MemeverseTransientState
/// @notice Thin wrapper around transient storage used by Memeverse swap flows.
/// @dev Keeps raw `tstore` / `tload` isolated from hook business logic.
library MemeverseTransientState {
    bytes32 internal constant SWAP_FEE_BPS_SLOT = bytes32(uint256(keccak256("memeverse.transient.swap-fee-bps")) - 1);
    bytes32 internal constant PRE_SWAP_SQRT_PRICE_SLOT =
        bytes32(uint256(keccak256("memeverse.transient.pre-swap-sqrt-price")) - 1);
    bytes32 internal constant REQUESTED_INPUT_BUDGET_SLOT =
        bytes32(uint256(keccak256("memeverse.transient.requested-input-budget")) - 1);

    function storeSwapContext(uint256 feeBps, uint160 preSqrtPriceX96) internal {
        bytes32 feeSlot = SWAP_FEE_BPS_SLOT;
        bytes32 priceSlot = PRE_SWAP_SQRT_PRICE_SLOT;
        assembly {
            tstore(feeSlot, feeBps)
            tstore(priceSlot, preSqrtPriceX96)
        }
    }

    function loadSwapFeeBps() internal view returns (uint256 feeBps) {
        bytes32 feeSlot = SWAP_FEE_BPS_SLOT;
        assembly {
            feeBps := tload(feeSlot)
        }
    }

    function loadPreSwapSqrtPriceX96() internal view returns (uint160 preSqrtPriceX96) {
        bytes32 priceSlot = PRE_SWAP_SQRT_PRICE_SLOT;
        assembly {
            preSqrtPriceX96 := tload(priceSlot)
        }
    }

    function storeRequestedInputBudget(uint256 inputBudget) internal {
        bytes32 budgetSlot = REQUESTED_INPUT_BUDGET_SLOT;
        assembly {
            tstore(budgetSlot, inputBudget)
        }
    }

    function loadRequestedInputBudget() internal view returns (uint256 inputBudget) {
        bytes32 budgetSlot = REQUESTED_INPUT_BUDGET_SLOT;
        assembly {
            inputBudget := tload(budgetSlot)
        }
    }
}
