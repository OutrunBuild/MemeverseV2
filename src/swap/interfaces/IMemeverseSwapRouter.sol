// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {SwapParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {IMemeverseUniswapHook} from "./IMemeverseUniswapHook.sol";

/// @title IMemeverseSwapRouter
/// @notice User-facing interface for the Memeverse swap router.
/// @dev Exposes the router's quote, swap, liquidity, and fee-claim entrypoints and custom errors.
interface IMemeverseSwapRouter {
    /// @notice Reverts when the pool key does not use the configured Memeverse hook.
    error InvalidHook();

    /// @notice Reverts when `deadline` has passed.
    error ExpiredPastDeadline();

    /// @notice Reverts when the swap amount is zero.
    error SwapAmountCannotBeZero();

    /// @notice Reverts when an exact-output swap omits `amountInMaximum`.
    error AmountInMaximumRequired();

    /// @notice Reverts when the required input exceeds `amountInMaximum`.
    error InputAmountExceedsMaximum(uint256 actualInputAmount, uint256 amountInMaximum);

    /// @notice Reverts when the received output is below `amountOutMinimum`.
    error OutputAmountBelowMinimum(uint256 actualOutputAmount, uint256 amountOutMinimum);

    /// @notice Reverts when bootstrap uses identical token addresses.
    error InvalidTokenPair();

    /// @notice Reverts when native input is used without a refund recipient.
    error InvalidNativeRefundRecipient();

    /// @notice Returns the configured Memeverse hook used by the router.
    /// @dev Useful for verifying the router is wired to the expected hook deployment.
    /// @return memeverseHook The hook contract that owns anti-snipe and LP accounting logic.
    function hook() external view returns (IMemeverseUniswapHook memeverseHook);

    /// @notice Returns the current swap quote from the underlying Memeverse hook.
    /// @dev Thin passthrough for router-first integrations.
    /// @param key The pool key being quoted.
    /// @param params The swap parameters being quoted.
    /// @return quote The projected fee amounts, side, and estimated user flows.
    function quoteSwap(PoolKey calldata key, SwapParams calldata params)
        external
        view
        returns (IMemeverseUniswapHook.SwapQuote memory quote);

    /// @notice Returns the anti-snipe failure-fee quote from the underlying Memeverse hook.
    /// @dev `inputBudget` is the total input budget reserved for either success or failure.
    /// @param key The pool key being quoted.
    /// @param params The swap parameters being quoted.
    /// @param inputBudget The maximum total input budget reserved for the attempted swap.
    /// @return quote The quoted failure-fee amount, side, and recipient class.
    function quoteFailedAttempt(PoolKey calldata key, SwapParams calldata params, uint256 inputBudget)
        external
        view
        returns (IMemeverseUniswapHook.FailedAttemptQuote memory quote);

    /// @notice Executes a swap through the Memeverse hook's anti-snipe gate in a single transaction.
    /// @dev On anti-snipe soft-fail, the router returns with `executed == false` and a failure reason.
    /// @custom:security Callers should enforce slippage with `amountOutMinimum` or `amountInMaximum`, and must provide
    /// a payable `nativeRefundRecipient` whenever native input is supplied.
    /// @param key The pool key to swap against.
    /// @param params The swap parameters.
    /// @param recipient The address receiving any swap output.
    /// @param nativeRefundRecipient The address receiving any unused native input when `msg.value` is attached.
    /// @param deadline The latest timestamp at which the call is valid.
    /// @param amountOutMinimum The minimum net output the caller is willing to receive.
    /// @param amountInMaximum The maximum input the caller is willing to pay.
    /// @param hookData Opaque hook data forwarded to `poolManager.swap`.
    /// @return delta The final swap delta when executed, otherwise zero.
    /// @return executed Whether the swap actually reached `poolManager.swap`.
    /// @return failureReason The anti-snipe failure reason when `executed` is false, otherwise `None`.
    function swap(
        PoolKey calldata key,
        SwapParams calldata params,
        address recipient,
        address nativeRefundRecipient,
        uint256 deadline,
        uint256 amountOutMinimum,
        uint256 amountInMaximum,
        bytes calldata hookData
    )
        external
        payable
        returns (BalanceDelta delta, bool executed, IMemeverseUniswapHook.AntiSnipeFailureReason failureReason);

    /// @notice Adds liquidity through the hook core entrypoint while applying router-level protections.
    /// @dev The router derives actual spend from the current pool price and refunds unused budget.
    /// @custom:security Callers must approve ERC20 inputs to the router before calling and set min amounts that match
    /// their slippage tolerance.
    /// @param currency0 Pool currency0.
    /// @param currency1 Pool currency1.
    /// @param amount0Desired Desired currency0 budget.
    /// @param amount1Desired Desired currency1 budget.
    /// @param amount0Min Minimum currency0 spend accepted.
    /// @param amount1Min Minimum currency1 spend accepted.
    /// @param to Recipient of minted LP shares.
    /// @param nativeRefundRecipient Recipient of any unused native refund.
    /// @param deadline The latest timestamp at which the call is valid.
    /// @return liquidity The LP liquidity minted to `to`.
    function addLiquidity(
        Currency currency0,
        Currency currency1,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        address to,
        address nativeRefundRecipient,
        uint256 deadline
    ) external payable returns (uint128 liquidity);

    /// @notice Removes liquidity through the hook core entrypoint while applying router-level protections.
    /// @dev The router burns LP shares, validates minimum outputs, and forwards underlying assets.
    /// @custom:security Callers must approve LP shares to the router and set output minimums to enforce slippage.
    /// @param currency0 Pool currency0.
    /// @param currency1 Pool currency1.
    /// @param liquidity LP liquidity to burn.
    /// @param amount0Min Minimum currency0 output accepted.
    /// @param amount1Min Minimum currency1 output accepted.
    /// @param to Recipient of withdrawn assets.
    /// @param deadline The latest timestamp at which the call is valid.
    /// @return delta The balance delta returned by the hook core.
    function removeLiquidity(
        Currency currency0,
        Currency currency1,
        uint128 liquidity,
        uint256 amount0Min,
        uint256 amount1Min,
        address to,
        uint256 deadline
    ) external returns (BalanceDelta delta);

    /// @notice Claims pending LP fees for the caller through the hook core entrypoint.
    /// @dev The caller may invoke this directly as owner or provide a signature for relay.
    /// @custom:security Non-owner relays must provide a valid signature in `v`, `r`, and `s`.
    /// @param key The pool key whose fees are being claimed.
    /// @param recipient Recipient of the claimed fees.
    /// @param deadline The latest timestamp at which the signature remains valid.
    /// @param v Signature `v`.
    /// @param r Signature `r`.
    /// @param s Signature `s`.
    /// @return fee0Amount The claimed amount of currency0 fees.
    /// @return fee1Amount The claimed amount of currency1 fees.
    function claimFees(PoolKey calldata key, address recipient, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
        returns (uint256 fee0Amount, uint256 fee1Amount);

    /// @notice Initializes a hook-backed pool and seeds its first full-range liquidity position.
    /// @dev The router sorts the token pair, initializes the pool price, adds liquidity, and refunds unused input.
    /// @custom:security Token addresses must be distinct, and native bootstrap calls require a payable refund
    /// recipient whenever `msg.value` is supplied.
    /// @param tokenA One side of the pool pair.
    /// @param tokenB The other side of the pool pair.
    /// @param amountADesired Desired budget for `tokenA`.
    /// @param amountBDesired Desired budget for `tokenB`.
    /// @param recipient Recipient of minted LP shares.
    /// @param nativeRefundRecipient Recipient of any unused native refund.
    /// @param deadline The latest timestamp at which the call is valid.
    /// @return liquidity The minted LP liquidity.
    /// @return poolKey The initialized pool key.
    function createPoolAndAddLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        address recipient,
        address nativeRefundRecipient,
        uint256 deadline
    )
        external
        payable
        returns (uint128 liquidity, PoolKey memory poolKey);
}
