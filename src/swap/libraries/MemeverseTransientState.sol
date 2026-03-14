// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {SwapParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

/// @title MemeverseTransientState
/// @notice Thin wrapper around transient storage used by Memeverse swap flows.
/// @dev Keeps raw `tstore` / `tload` isolated from hook business logic while still supporting
/// dynamic same-transaction anti-snipe ticket slots.
library MemeverseTransientState {
    bytes32 internal constant SWAP_FEE_BPS_SLOT = bytes32(uint256(keccak256("memeverse.transient.swap-fee-bps")) - 1);
    bytes32 internal constant PRE_SWAP_SQRT_PRICE_SLOT =
        bytes32(uint256(keccak256("memeverse.transient.pre-swap-sqrt-price")) - 1);
    bytes32 internal constant REQUESTED_INPUT_BUDGET_SLOT =
        bytes32(uint256(keccak256("memeverse.transient.requested-input-budget")) - 1);
    bytes32 internal constant ANTI_SNIPE_TICKET_SEED = keccak256("memeverse.anti-snipe.ticket");
    bytes32 internal constant ANTI_SNIPE_REQUEST_LATCH_SEED = keccak256("memeverse.anti-snipe.request-latch");

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

    function armAntiSnipeTicket(PoolId poolId, address caller, SwapParams calldata params, uint256 inputBudget)
        internal
    {
        bytes32 slot = antiSnipeTicketSlot(poolId, caller, params);
        assembly {
            tstore(slot, inputBudget)
        }
    }

    function consumeAntiSnipeTicket(PoolId poolId, address caller, SwapParams calldata params)
        internal
        returns (uint256 inputBudget)
    {
        bytes32 slot = antiSnipeTicketSlot(poolId, caller, params);
        uint256 rawInputBudget;
        assembly {
            rawInputBudget := tload(slot)
            tstore(slot, 0)
        }
        inputBudget = rawInputBudget;
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

    function markAntiSnipeRequestForPool(PoolId poolId) internal returns (bool firstRequest) {
        bytes32 slot = antiSnipeRequestLatchSlot(poolId);
        uint256 wasMarked;
        assembly {
            wasMarked := tload(slot)
            tstore(slot, 1)
        }
        firstRequest = wasMarked == 0;
    }

    function antiSnipeTicketSlot(PoolId poolId, address caller, SwapParams calldata params)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(
            abi.encode(
                ANTI_SNIPE_TICKET_SEED,
                PoolId.unwrap(poolId),
                caller,
                params.zeroForOne,
                params.amountSpecified,
                params.sqrtPriceLimitX96
            )
        );
    }

    function antiSnipeRequestLatchSlot(PoolId poolId) internal pure returns (bytes32) {
        return keccak256(abi.encode(ANTI_SNIPE_REQUEST_LATCH_SEED, PoolId.unwrap(poolId)));
    }
}
