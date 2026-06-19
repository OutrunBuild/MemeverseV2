// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

import {IPoolManager, SwapParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

/// @notice Stateless executor for preorder settlement PoolManager unlock flows.
interface IMemeversePreorderSettlementExecutor {
    struct ExecuteParams {
        IPoolManager poolManager;
        address recipient;
        address treasury;
        PoolKey key;
        SwapParams swapParams;
        bool protocolFeeOnInput;
        uint256 protocolFeeOutputBps;
    }

    struct ExecuteResult {
        BalanceDelta adjustedDelta;
        BalanceDelta swapDelta;
        uint160 preSwapSqrtPriceX96;
        uint160 postSwapSqrtPriceX96;
        uint256 protocolFeeOutputAmount;
    }

    /// @notice Executes the preorder settlement swap inside a PoolManager unlock.
    function execute(ExecuteParams calldata params) external returns (ExecuteResult memory result);

    /// @notice The immutable hook proxy address that is the only permitted caller of `execute`.
    function HOOK() external view returns (address);
}
