// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {IPoolManager, SwapParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {BalanceDelta, toBalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

import {CurrencySettler} from "../../../src/swap/libraries/CurrencySettler.sol";
import {SafeCast} from "../../../src/swap/libraries/SafeCast.sol";
import {IMemeversePreorderSettlementExecutor} from "../../../src/swap/interfaces/IMemeversePreorderSettlementExecutor.sol";

/// @notice Test-only executor that performs a real swap but inflates the reported protocol fee.
/// @dev Used to verify the hook's `PreorderSettlementFeeMismatch` guard catches inconsistent fee reports.
contract FeeMismatchSettlementExecutor is IMemeversePreorderSettlementExecutor, IUnlockCallback {
    using CurrencySettler for Currency;
    using PoolIdLibrary for PoolKey;
    using SafeCast for int128;
    using StateLibrary for IPoolManager;

    bytes internal constant ZERO_BYTES = bytes("");
    uint256 internal constant BPS_BASE = 10_000;

    address public immutable HOOK;

    constructor(address hook) {
        HOOK = hook;
    }

    function execute(ExecuteParams calldata params) external override returns (ExecuteResult memory result) {
        if (msg.sender != HOOK) revert Unauthorized();
        if (address(params.key.hooks) != HOOK) revert Unauthorized();
        return abi.decode(
            params.poolManager.unlock(
                abi.encode(
                    params.poolManager,
                    CallbackData({
                        recipient: params.recipient,
                        treasury: params.treasury,
                        key: params.key,
                        swapParams: params.swapParams,
                        protocolFeeOnInput: params.protocolFeeOnInput,
                        protocolFeeOutputBps: params.protocolFeeOutputBps
                    })
                )
            ),
            (ExecuteResult)
        );
    }

    error Unauthorized();

    struct CallbackData {
        address recipient;
        address treasury;
        PoolKey key;
        SwapParams swapParams;
        bool protocolFeeOnInput;
        uint256 protocolFeeOutputBps;
    }

    /// @dev Runs a real swap, settles deltas, then reports an inflated protocol fee to trigger the hook's mismatch guard.
    function unlockCallback(bytes calldata rawData) external override returns (bytes memory) {
        (IPoolManager poolManager, CallbackData memory data) = abi.decode(rawData, (IPoolManager, CallbackData));
        if (msg.sender != address(poolManager)) revert Unauthorized();

        (uint160 preSwapSqrtPriceX96,,,) = poolManager.getSlot0(data.key.toId());
        BalanceDelta swapDelta = poolManager.swap(data.key, data.swapParams, ZERO_BYTES);
        (uint160 postSwapSqrtPriceX96,,,) = poolManager.getSlot0(data.key.toId());

        int128 amount0 = swapDelta.amount0();
        int128 amount1 = swapDelta.amount1();
        if (amount0 < 0) {
            data.key.currency0.settle(poolManager, address(this), uint256((-amount0).toUint128()), false);
        }
        if (amount1 < 0) {
            data.key.currency1.settle(poolManager, address(this), uint256((-amount1).toUint128()), false);
        }

        uint256 protocolFeeOutputAmount;
        if (!data.protocolFeeOnInput) {
            uint256 grossOutputAmount = _actualOutputAmount(swapDelta, data.swapParams.zeroForOne);
            protocolFeeOutputAmount = FullMath.mulDiv(grossOutputAmount, data.protocolFeeOutputBps, BPS_BASE);
            // Inflate the reported fee by 1 wei to trigger PreorderSettlementFeeMismatch.
            protocolFeeOutputAmount += 1;
            Currency outputCurrency = data.swapParams.zeroForOne ? data.key.currency1 : data.key.currency0;
            poolManager.take(outputCurrency, data.treasury, protocolFeeOutputAmount);
        }

        uint256 takeAmount0 = amount0 > 0 ? uint256(amount0.toUint128()) : 0;
        uint256 takeAmount1 = amount1 > 0 ? uint256(amount1.toUint128()) : 0;
        if (protocolFeeOutputAmount > 0) {
            if (data.swapParams.zeroForOne) {
                takeAmount1 -= protocolFeeOutputAmount;
            } else {
                takeAmount0 -= protocolFeeOutputAmount;
            }
        }

        if (takeAmount0 > 0) poolManager.take(data.key.currency0, data.recipient, takeAmount0);
        if (takeAmount1 > 0) poolManager.take(data.key.currency1, data.recipient, takeAmount1);

        int128 adjustedAmount0 = amount0 > 0 ? int128(int256(takeAmount0)) : amount0;
        int128 adjustedAmount1 = amount1 > 0 ? int128(int256(takeAmount1)) : amount1;
        return abi.encode(
            ExecuteResult({
                adjustedDelta: toBalanceDelta(adjustedAmount0, adjustedAmount1),
                swapDelta: swapDelta,
                preSwapSqrtPriceX96: preSwapSqrtPriceX96,
                postSwapSqrtPriceX96: postSwapSqrtPriceX96,
                protocolFeeOutputAmount: protocolFeeOutputAmount
            })
        );
    }

    function _actualOutputAmount(BalanceDelta delta, bool zeroForOne) internal pure returns (uint256) {
        return zeroForOne ? uint256(delta.amount1().toUint128()) : uint256(delta.amount0().toUint128());
    }
}
