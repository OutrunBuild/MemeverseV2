// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {SwapParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IPermit2} from "lib/v4-periphery/lib/permit2/src/interfaces/IPermit2.sol";
import {ISignatureTransfer} from "lib/v4-periphery/lib/permit2/src/interfaces/ISignatureTransfer.sol";

import {IMemeverseUniswapHook} from "./IMemeverseUniswapHook.sol";

/// @title IMemeverseSwapRouter
/// @notice User-facing interface for the Memeverse swap router.
/// @dev Exposes the router's quote, swap, liquidity, and fee-claim entrypoints with the related parameter structs
/// and custom errors.
interface IMemeverseSwapRouter {
    /// @notice Parameters for adding full-range liquidity through the router.
    struct AddLiquidityParams {
        Currency currency0;
        Currency currency1;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address to;
        address nativeRefundRecipient;
        uint256 deadline;
    }

    /// @notice Parameters for removing full-range liquidity through the router.
    struct RemoveLiquidityParams {
        Currency currency0;
        Currency currency1;
        uint128 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
        address to;
        uint256 deadline;
    }

    /// @notice Parameters for claiming accrued LP fees through the router.
    struct ClaimFeesParams {
        PoolKey key;
        address recipient;
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    /// @notice Parameters for pool bootstrap plus initial liquidity seeding.
    struct CreatePoolAndAddLiquidityParams {
        address tokenA;
        address tokenB;
        uint256 amountADesired;
        uint256 amountBDesired;
        address recipient;
        address nativeRefundRecipient;
        uint256 deadline;
    }

    /// @notice Permit2 parameters for a single ERC20 pull.
    struct Permit2SingleParams {
        ISignatureTransfer.PermitTransferFrom permit;
        ISignatureTransfer.SignatureTransferDetails transferDetails;
        bytes signature;
    }

    /// @notice Permit2 parameters for one or more ERC20 pulls in a batch.
    struct Permit2BatchParams {
        ISignatureTransfer.PermitBatchTransferFrom permit;
        ISignatureTransfer.SignatureTransferDetails[] transferDetails;
        bytes signature;
    }

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

    /// @notice Reverts when Permit2 batch arrays do not match the expected ERC20 funding leg count.
    error InvalidPermit2Length();

    /// @notice Reverts when a Permit2 batch entry does not match the expected token ordering.
    error InvalidPermit2Token(uint256 index, address expectedToken, address actualToken);

    /// @notice Returns the configured Memeverse hook used by the router.
    /// @dev Useful for verifying the router is wired to the expected hook deployment.
    /// @return memeverseHook The hook contract that owns anti-snipe and LP accounting logic.
    function hook() external view returns (IMemeverseUniswapHook memeverseHook);

    /// @notice Returns the Permit2 contract used for signature-based ERC20 funding.
    /// @dev Integrators can use this to confirm the router points at the expected Permit2 deployment.
    /// @return permit2Contract The Permit2 entrypoint the router will call for signature transfers.
    function permit2() external view returns (IPermit2 permit2Contract);

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

    /// @notice Executes a swap after funding the router through Permit2 signature transfer.
    /// @dev Reuses the same routed swap semantics as `swap(...)` after the Permit2 pull succeeds.
    /// @custom:security Callers must sign Permit2 data that matches the intended input budget and token.
    /// @param permitParams The Permit2 single-transfer parameters covering the swap input token.
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
    function swapWithPermit2(
        Permit2SingleParams calldata permitParams,
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
    /// @param params The user-facing liquidity add parameters.
    /// @return liquidity The LP liquidity minted to `params.to`.
    function addLiquidity(AddLiquidityParams calldata params) external payable returns (uint128 liquidity);

    /// @notice Adds liquidity after funding one or two ERC20 inputs through Permit2 signature transfer.
    /// @dev After Permit2 funding succeeds, execution follows the same path as `addLiquidity(...)`.
    /// @custom:security The batch Permit2 payload must align with the ERC20 side(s) of `params`.
    /// @param permitParams The Permit2 batch-transfer parameters covering the ERC20 funding legs.
    /// @param params The user-facing liquidity add parameters.
    /// @return liquidity The LP liquidity minted to `params.to`.
    function addLiquidityWithPermit2(Permit2BatchParams calldata permitParams, AddLiquidityParams calldata params)
        external
        payable
        returns (uint128 liquidity);

    /// @notice Removes liquidity through the hook core entrypoint while applying router-level protections.
    /// @dev The router burns LP shares, validates minimum outputs, and forwards underlying assets.
    /// @custom:security Callers must approve LP shares to the router and set output minimums to enforce slippage.
    /// @param params The user-facing liquidity remove parameters.
    /// @return delta The balance delta returned by the hook core.
    function removeLiquidity(RemoveLiquidityParams calldata params) external returns (BalanceDelta delta);

    /// @notice Removes liquidity after pulling LP shares through Permit2 signature transfer.
    /// @dev After Permit2 funding succeeds, execution follows the same path as `removeLiquidity(...)`.
    /// @custom:security The Permit2 payload must authorize the hook LP token transfer required by `params`.
    /// @param permitParams The Permit2 single-transfer parameters covering the LP token.
    /// @param params The user-facing liquidity remove parameters.
    /// @return delta The balance delta returned by the hook core.
    function removeLiquidityWithPermit2(Permit2SingleParams calldata permitParams, RemoveLiquidityParams calldata params)
        external
        returns (BalanceDelta delta);

    /// @notice Claims pending LP fees for the caller through the hook core entrypoint.
    /// @dev The caller may invoke this directly as owner or provide a signature for relay.
    /// @custom:security Non-owner relays must provide a valid signature in `params.v`, `params.r`, and `params.s`.
    /// @param params The user-facing fee-claim parameters.
    /// @return fee0Amount The claimed amount of currency0 fees.
    /// @return fee1Amount The claimed amount of currency1 fees.
    function claimFees(ClaimFeesParams calldata params) external returns (uint256 fee0Amount, uint256 fee1Amount);

    /// @notice Initializes a hook-backed pool and seeds its first full-range liquidity position.
    /// @dev The router sorts the token pair, initializes the pool price, adds liquidity, and refunds unused input.
    /// @custom:security Token addresses must be distinct, and native bootstrap calls require a payable refund
    /// recipient whenever `msg.value` is supplied.
    /// @param params The bootstrap parameters.
    /// @return liquidity The minted LP liquidity.
    /// @return poolKey The initialized pool key.
    function createPoolAndAddLiquidity(CreatePoolAndAddLiquidityParams calldata params)
        external
        payable
        returns (uint128 liquidity, PoolKey memory poolKey);

    /// @notice Initializes a hook-backed pool and seeds first liquidity after Permit2 funding.
    /// @dev After Permit2 funding succeeds, execution follows the same path as `createPoolAndAddLiquidity(...)`.
    /// @custom:security The batch Permit2 payload must align with the ERC20 side(s) of the bootstrap token pair.
    /// @param permitParams The Permit2 batch-transfer parameters covering the ERC20 bootstrap funding legs.
    /// @param params The bootstrap parameters.
    /// @return liquidity The minted LP liquidity.
    /// @return poolKey The initialized pool key.
    function createPoolAndAddLiquidityWithPermit2(
        Permit2BatchParams calldata permitParams,
        CreatePoolAndAddLiquidityParams calldata params
    ) external payable returns (uint128 liquidity, PoolKey memory poolKey);
}
