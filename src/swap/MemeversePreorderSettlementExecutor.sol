// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {IPoolManager, SwapParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {BalanceDelta, toBalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

import {CurrencySettler} from "./libraries/CurrencySettler.sol";
import {FeeMath} from "./libraries/FeeMath.sol";
import {SafeCast} from "./libraries/SafeCast.sol";
import {IMemeversePreorderSettlementExecutor} from "./interfaces/IMemeversePreorderSettlementExecutor.sol";

/// @notice Preorder settlement PoolManager unlock executor, immutable-bound to a single hook proxy.
contract MemeversePreorderSettlementExecutor is IMemeversePreorderSettlementExecutor, IUnlockCallback {
    using CurrencySettler for Currency;
    using PoolIdLibrary for PoolKey;
    using SafeCast for int128;
    using StateLibrary for IPoolManager;

    bytes internal constant ZERO_BYTES = bytes("");

    error Unauthorized();
    error HookAddressZero();

    /// @notice The hook proxy that is the only permitted caller of `execute`.
    /// @dev Bound at construction; `execute` rejects any other caller so a caller-supplied
    ///      `params.key.hooks` cannot impersonate the hook.
    address public immutable HOOK;

    constructor(address hook) {
        if (hook == address(0)) revert HookAddressZero();
        HOOK = hook;
    }

    struct CallbackData {
        address recipient;
        address treasury;
        PoolKey key;
        SwapParams swapParams;
        bool protocolFeeOnInput;
        uint256 protocolFeeOutputBps;
    }

    function execute(ExecuteParams calldata params) external override returns (ExecuteResult memory result) {
        // Only the immutable-bound hook may drive a settlement swap. Caller-supplied `params.key.hooks`
        // is NOT trusted as an identity claim: a callback-token reentrancy during the hook's
        // transferFrom could otherwise forge key.hooks and drain the executor's held netInput.
        if (msg.sender != HOOK) revert Unauthorized();
        if (address(params.key.hooks) != HOOK) revert Unauthorized();
        return abi.decode(
            params.poolManager
                .unlock(
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

    /// @notice PoolManager unlock callback — executes the preorder settlement swap and settles all deltas.
    /// @dev Called by PoolManager inside `unlock`. Settlement order:
    ///      1. snapshot pre-swap sqrtPriceX96
    ///      2. execute swap
    ///      3. snapshot post-swap sqrtPriceX96
    ///      4. settle input-leg (negative) delta from this contract's held balance
    ///      5. if fee-on-output: deduct protocol fee from gross output and `take` it to treasury
    ///      6. `take` net output to recipient
    ///      7. return adjusted delta (output reduced by fee) + swap delta + price snapshots
    /// @param rawData abi.encode(IPoolManager, CallbackData).
    /// @return Encoded `ExecuteResult`.
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
            protocolFeeOutputAmount = FeeMath.feeOnAmount(grossOutputAmount, data.protocolFeeOutputBps);
            Currency outputCurrency = data.swapParams.zeroForOne ? data.key.currency1 : data.key.currency0;
            poolManager.take(outputCurrency, data.treasury, protocolFeeOutputAmount);
        }

        uint256 takeAmount0 = amount0 > 0 ? uint256(amount0.toUint128()) : 0;
        uint256 takeAmount1 = amount1 > 0 ? uint256(amount1.toUint128()) : 0;
        // No underflow: `protocolFeeOutputAmount = grossOutputAmount * bps / 10_000` where the
        // hook-supplied `bps` is a fixed const <= 10_000, and the output-leg `takeAmount` below
        // equals `grossOutputAmount` (same swapDelta leg). So fee <= gross = takeAmount; the input
        // leg is never subtracted here.
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
