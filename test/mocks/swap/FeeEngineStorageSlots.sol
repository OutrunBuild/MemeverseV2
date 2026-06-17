// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

/// @title FeeEngineStorageSlots
/// @notice Centralized ERC7201 storage-slot math for MemeverseDynamicFeeEngine tests/mocks.
/// @dev LOCATION mirrors src/swap/MemeverseDynamicFeeEngine.sol
///      MEMEVERSE_DYNAMIC_FEE_ENGINE_STORAGE_LOCATION (private there, so centralized here as the
///      single test-side source of truth). If the src namespace changes, update LOCATION here only.
library FeeEngineStorageSlots {
    /// @dev ERC7201 namespace base for MemeverseDynamicFeeEngineStorage.
    bytes32 internal constant LOCATION = 0xb7b6769a89985fd739eb1342563b5dbd4d11da8b84d601f10d877057788e0e00;

    /// @dev authorizedHook is the 3rd field (index 2) of MemeverseDynamicFeeEngineStorage.
    uint256 internal constant AUTHORIZED_HOOK_OFFSET = 2;

    // DynamicFeeState field offsets within a dynamicFeeStates[hook][poolId] mapping value.
    uint256 internal constant DFS_WEIGHTED_PRICE_VOLUME0 = 1;
    uint256 internal constant DFS_EWVWAP_X18 = 2;
    /// @dev Packed slot: volAnchorSqrtPriceX96:160 | volLastMoveTs:40 | volDeviationAccumulator:24 | volCarryAccumulator:24 (248 bits).
    uint256 internal constant DFS_PACKED_VOL = 3;
    /// @dev Packed slot: shortImpactPpm:24 | shortLastTs:40.
    uint256 internal constant DFS_PACKED_SHORT = 4;

    /// @dev Slot of `address authorizedHook` (namespace-base + AUTHORIZED_HOOK_OFFSET).
    function authorizedHookSlot() internal pure returns (bytes32) {
        return bytes32(uint256(LOCATION) + AUTHORIZED_HOOK_OFFSET);
    }

    /// @dev Slot of DynamicFeeState for (hook, poolId). Mirrors Solidity nested-mapping slot derivation:
    ///      `dynamicFeeStates` is the first struct field (namespace-base + 0).
    ///      outer = keccak(abi.encode(hook, base)); inner = keccak(abi.encode(poolId, outer)).
    ///      PoolId is a bytes32 wrapper and encodes identically to bytes32; address encodes right-aligned in 32 bytes.
    function dynamicFeeStateSlot(address hook_, PoolId poolId_) internal pure returns (bytes32) {
        bytes32 outer = keccak256(abi.encode(hook_, LOCATION));
        return keccak256(abi.encode(poolId_, outer));
    }

    /// @dev Slot of AddressBatchState for (hook, trader, poolId). `addressBatchStates` is the second struct field
    ///      (namespace-base + 1). Nested-key order is hook -> trader -> poolId.
    function addressBatchStateSlot(address hook_, address trader_, PoolId poolId_) internal pure returns (bytes32) {
        bytes32 outer = keccak256(abi.encode(hook_, bytes32(uint256(LOCATION) + 1)));
        bytes32 mid = keccak256(abi.encode(trader_, outer));
        return keccak256(abi.encode(poolId_, mid));
    }
}
