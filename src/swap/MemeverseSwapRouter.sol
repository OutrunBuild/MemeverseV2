// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {IPoolManager, SwapParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {SafeCallback} from "@uniswap/v4-periphery/src/base/SafeCallback.sol";
import {IERC20Minimal} from "@uniswap/v4-core/src/interfaces/external/IERC20Minimal.sol";
import {IPermit2} from "lib/v4-periphery/lib/permit2/src/interfaces/IPermit2.sol";
import {ISignatureTransfer} from "lib/v4-periphery/lib/permit2/src/interfaces/ISignatureTransfer.sol";

import {IMemeverseUniswapHook} from "./interfaces/IMemeverseUniswapHook.sol";
import {IMemeverseSwapRouter} from "./interfaces/IMemeverseSwapRouter.sol";
import {UniswapLP} from "../libraries/UniswapLP.sol";
import {LiquidityQuote} from "../libraries/LiquidityQuote.sol";
import {InitialPriceCalculator} from "../libraries/InitialPriceCalculator.sol";
import {CurrencySettler} from "../libraries/CurrencySettler.sol";

/// @title MemeverseSwapRouter
/// @notice Recommended single public periphery entrypoint for Memeverse swap and LP flows.
/// @dev On anti-snipe soft-fail, the router returns successfully without calling `poolManager.swap`, so attempts persist
/// while the trade does not execute. During the protection window, failed attempts may still charge an input-side
/// failure fee from the same single input budget used by the swap. Outside the anti-snipe window, the router skips attempt recording and routes directly to
/// `poolManager.swap`. For exact-output swaps, callers are expected to source `amountInMaximum` from
/// `MemeverseSwapRouter.quoteSwap()` or a stricter front-end slippage policy.
/// The underlying hook remains callable as a Core API for custom routers and integrators, but this router is the
/// intended canonical entrypoint for end-user and on-chain SDK integrations, covering quote, swap, LP, fee claim,
/// and hook-backed pool bootstrap flows.
contract MemeverseSwapRouter is SafeCallback {
    using CurrencySettler for Currency;
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    struct CallbackData {
        address payer;
        address recipient;
        PoolKey key;
        SwapParams params;
        bytes hookData;
    }

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

    struct RemoveLiquidityParams {
        Currency currency0;
        Currency currency1;
        uint128 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
        address to;
        uint256 deadline;
    }

    struct ClaimFeesParams {
        PoolKey key;
        address recipient;
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    struct CreatePoolAndAddLiquidityParams {
        address tokenA;
        address tokenB;
        uint256 amountADesired;
        uint256 amountBDesired;
        address recipient;
        address nativeRefundRecipient;
        uint256 deadline;
    }

    /// @notice Reverts when the provided pool key does not point to the configured Memeverse hook.
    error InvalidHook();

    /// @notice Reverts when `deadline` is in the past.
    error ExpiredPastDeadline();

    /// @notice Reverts when the requested swap amount is zero.
    error SwapAmountCannotBeZero();

    /// @notice Reverts when an exact-output swap does not provide an input upper bound.
    error AmountInMaximumRequired();

    /// @notice Reverts when the final required input exceeds the user-specified upper bound.
    error InputAmountExceedsMaximum(uint256 actualInputAmount, uint256 amountInMaximum);

    /// @notice Reverts when the final received output is below the user-specified lower bound.
    error OutputAmountBelowMinimum(uint256 actualOutputAmount, uint256 amountOutMinimum);

    /// @notice Reverts when bootstrap is attempted with identical token addresses.
    error InvalidTokenPair();

    /// @notice Reverts when a payable native refund recipient is required but not provided.
    error InvalidNativeRefundRecipient();

    IMemeverseUniswapHook public immutable hook;
    IPermit2 public immutable permit2;

    /// @param _manager The Uniswap v4 pool manager.
    /// @param _hook The Memeverse hook that owns anti-snipe attempt tracking for routed swaps.
    /// @param _permit2 The Permit2 entrypoint used for signature-based ERC20 pulls.
    constructor(IPoolManager _manager, IMemeverseUniswapHook _hook, IPermit2 _permit2) SafeCallback(_manager) {
        hook = _hook;
        permit2 = _permit2;
    }

    /// @notice Returns the current swap quote from the underlying Memeverse hook.
    /// @dev This is a thin passthrough so integrators can treat the router as the single public entrypoint.
    /// @param key The pool key being quoted.
    /// @param params The swap parameters being quoted.
    /// @return quote The projected fee amounts, side, and estimated user flows.
    function quoteSwap(PoolKey calldata key, SwapParams calldata params)
        external
        view
        returns (IMemeverseUniswapHook.SwapQuote memory quote)
    {
        return hook.quoteSwap(key, params);
    }

    /// @notice Returns the current anti-snipe failure-fee quote from the underlying Memeverse hook.
    /// @dev This is a thin passthrough so integrators can estimate the protection-window failure fee via the router.
    /// `inputBudget` is the single total input budget that will be used for either success or failure.
    function quoteFailedAttempt(PoolKey calldata key, SwapParams calldata params, uint256 inputBudget)
        external
        view
        returns (IMemeverseUniswapHook.FailedAttemptQuote memory quote)
    {
        return hook.quoteFailedAttempt(key, params, inputBudget);
    }

    /// @notice Executes a swap through the Memeverse hook's anti-snipe gate in a single transaction.
    /// @dev If anti-snipe soft-fails, the function returns `(ZERO_DELTA, false, reason)` and does not call
    /// `poolManager.swap`. During the protection window the router prepares a single input budget for the trade:
    /// on failure part of that budget is consumed as an input-side failure fee, while on success the same budget is
    /// used to execute the swap and only any unused remainder is refunded. Any unused native input is refunded to `nativeRefundRecipient`, which allows
    /// non-payable contract callers to preserve soft-fail attempt recording while routing refunds to a payable address.
    /// @param key The pool key to swap against.
    /// @param params The swap parameters.
    /// @param recipient The address receiving any swap output.
    /// @param nativeRefundRecipient The address receiving any unused native input when `msg.value` is attached.
    /// @param deadline The latest timestamp at which the call is valid.
    /// @param amountOutMinimum The minimum net output the caller is willing to receive. Required for exact-input protection.
    /// @param amountInMaximum The maximum input the caller is willing to pay. Required for exact-output swaps.
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
        returns (BalanceDelta delta, bool executed, IMemeverseUniswapHook.AntiSnipeFailureReason failureReason)
    {
        return _swap(
            key,
            params,
            recipient,
            nativeRefundRecipient,
            deadline,
            amountOutMinimum,
            amountInMaximum,
            hookData,
            msg.sender,
            msg.sender,
            false
        );
    }

    function swapWithPermit2(
        IMemeverseSwapRouter.Permit2SingleParams calldata permitParams,
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
        returns (BalanceDelta delta, bool executed, IMemeverseUniswapHook.AntiSnipeFailureReason failureReason)
    {
        Currency inputCurrency = _inputCurrency(key, params.zeroForOne);
        uint256 inputBudget = _swapInputBudget(params, amountInMaximum);
        if (!inputCurrency.isAddressZero() && inputBudget > 0) {
            (bytes32 witness, string memory witnessTypeString) = _swapPermit2Witness(
                key,
                params,
                recipient,
                nativeRefundRecipient,
                deadline,
                amountOutMinimum,
                amountInMaximum,
                hookData
            );
            _pullCurrencyWithPermit2(
                permitParams, msg.sender, Currency.unwrap(inputCurrency), inputBudget, witness, witnessTypeString
            );
        }

        return _swap(
            key,
            params,
            recipient,
            nativeRefundRecipient,
            deadline,
            amountOutMinimum,
            amountInMaximum,
            hookData,
            msg.sender,
            address(this),
            true
        );
    }

    /// @notice Adds liquidity through the hook core entrypoint while applying periphery protections.
    /// @dev Pulls the caller's desired ERC20 budgets into the router, derives the actual full-range spend at the
    /// current pool price, forwards only the exact required native amount to the hook core, validates min amounts,
    /// and refunds any unused input budget to `params.nativeRefundRecipient`. This path is separate from the swap
    /// protection-window budget logic.
    /// @param params The user-facing liquidity add parameters.
    /// @return liquidity The LP liquidity minted to `params.to`.
    function addLiquidity(AddLiquidityParams calldata params) external payable returns (uint128 liquidity) {
        if (params.deadline < block.timestamp) revert ExpiredPastDeadline();

        uint256 nativeDesired = params.currency0.isAddressZero()
            ? params.amount0Desired
            : params.currency1.isAddressZero() ? params.amount1Desired : 0;
        if (msg.value != nativeDesired) revert IMemeverseUniswapHook.InvalidNativeValue(nativeDesired, msg.value);
        address refundRecipient = _validatedNativeRefundRecipient(params.nativeRefundRecipient, msg.value);

        PoolKey memory key = _hookPoolKey(params.currency0, params.currency1);
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(key.toId());
        return _addLiquidityViaHook(
            key,
            params.amount0Desired,
            params.amount1Desired,
            params.amount0Min,
            params.amount1Min,
            params.to,
            refundRecipient,
            nativeDesired,
            sqrtPriceX96
        );
    }

    /// @notice Removes liquidity through the hook core entrypoint while applying periphery protections.
    /// @dev Pulls LP shares into the router, calls the hook core, validates minimum outputs, and forwards the assets.
    /// @param params The user-facing liquidity remove parameters.
    /// @return delta The balance delta returned by the hook core.
    function removeLiquidity(RemoveLiquidityParams calldata params) external returns (BalanceDelta delta) {
        if (params.deadline < block.timestamp) revert ExpiredPastDeadline();

        PoolKey memory key = _hookPoolKey(params.currency0, params.currency1);
        (address liquidityToken,,,) = hook.poolInfo(key.toId());
        UniswapLP(liquidityToken).transferFrom(msg.sender, address(this), params.liquidity);

        delta = hook.removeLiquidityCore(
            IMemeverseUniswapHook.RemoveLiquidityCoreParams({
                currency0: params.currency0,
                currency1: params.currency1,
                liquidity: params.liquidity,
                recipient: address(this)
            })
        );

        (uint256 amount0Out, uint256 amount1Out) = _receivedLiquidityAmounts(delta);
        if (amount0Out < params.amount0Min || amount1Out < params.amount1Min) {
            revert IMemeverseUniswapHook.TooMuchSlippage();
        }

        _transferCurrency(params.currency0, params.to, amount0Out);
        _transferCurrency(params.currency1, params.to, amount1Out);
    }

    /// @notice Claims pending LP fees for the caller through the hook core entrypoint.
    /// @dev The caller may either invoke this directly as owner or provide a signature so the router can relay the claim.
    /// @param params The user-facing fee-claim parameters.
    /// @return fee0Amount The claimed amount of currency0 fees.
    /// @return fee1Amount The claimed amount of currency1 fees.
    function claimFees(ClaimFeesParams calldata params) external returns (uint256 fee0Amount, uint256 fee1Amount) {
        return hook.claimFeesCore(
            IMemeverseUniswapHook.ClaimFeesCoreParams({
                key: params.key,
                owner: msg.sender,
                recipient: params.recipient,
                deadline: params.deadline,
                v: params.v,
                r: params.r,
                s: params.s
            })
        );
    }

    /// @notice Initializes a hook-backed pool and seeds its first full-range liquidity position through the hook core.
    /// @dev Pulls the caller's desired budgets, initializes the pool, derives the actual full-range spend, forwards
    /// only the exact required native amount to the hook core, and refunds any unused input budget to
    /// `params.nativeRefundRecipient`.
    /// @param params The bootstrap parameters.
    /// @return liquidity The minted LP liquidity.
    /// @return poolKey The initialized pool key.
    function createPoolAndAddLiquidity(CreatePoolAndAddLiquidityParams calldata params)
        external
        payable
        returns (uint128 liquidity, PoolKey memory poolKey)
    {
        if (params.deadline < block.timestamp) revert ExpiredPastDeadline();
        if (params.tokenA == params.tokenB) revert InvalidTokenPair();

        (Currency currency0, Currency currency1) = params.tokenA < params.tokenB
            ? (Currency.wrap(params.tokenA), Currency.wrap(params.tokenB))
            : (Currency.wrap(params.tokenB), Currency.wrap(params.tokenA));
        uint256 amount0Desired = params.tokenA < params.tokenB ? params.amountADesired : params.amountBDesired;
        uint256 amount1Desired = params.tokenA < params.tokenB ? params.amountBDesired : params.amountADesired;

        uint256 nativeDesired = params.tokenA == address(0)
            ? params.amountADesired
            : params.tokenB == address(0) ? params.amountBDesired : 0;
        if (msg.value != nativeDesired) revert IMemeverseUniswapHook.InvalidNativeValue(nativeDesired, msg.value);
        address refundRecipient = _validatedNativeRefundRecipient(params.nativeRefundRecipient, msg.value);

        _prepareCurrencyBudget(currency0, msg.sender, amount0Desired);
        _prepareCurrencyBudget(currency1, msg.sender, amount1Desired);

        uint160 startingPrice = InitialPriceCalculator.calculateInitialSqrtPriceX96(amount0Desired, amount1Desired);
        poolKey = _hookPoolKey(currency0, currency1);

        poolManager.initialize(poolKey, startingPrice);
        liquidity = _addLiquidityViaHook(
            poolKey,
            amount0Desired,
            amount1Desired,
            0,
            0,
            params.recipient,
            refundRecipient,
            nativeDesired,
            startingPrice
        );
    }

    /// @dev Executes the actual swap during the manager unlock window and settles the caller delta.
    function _unlockCallback(bytes calldata rawData) internal override returns (bytes memory) {
        CallbackData memory data = abi.decode(rawData, (CallbackData));

        BalanceDelta delta = poolManager.swap(data.key, data.params, data.hookData);

        if (delta.amount0() < 0) {
            data.key.currency0.settle(poolManager, data.payer, uint256(int256(-delta.amount0())), false);
        }
        if (delta.amount1() < 0) {
            data.key.currency1.settle(poolManager, data.payer, uint256(int256(-delta.amount1())), false);
        }
        if (delta.amount0() > 0) {
            data.key.currency0.take(poolManager, data.recipient, uint256(int256(delta.amount0())), false);
        }
        if (delta.amount1() > 0) {
            data.key.currency1.take(poolManager, data.recipient, uint256(int256(delta.amount1())), false);
        }

        return abi.encode(delta);
    }

    receive() external payable {}

    function _swap(
        PoolKey calldata key,
        SwapParams calldata params,
        address recipient,
        address nativeRefundRecipient,
        uint256 deadline,
        uint256 amountOutMinimum,
        uint256 amountInMaximum,
        bytes calldata hookData,
        address trader,
        address payer,
        bool inputBudgetPrepared
    )
        internal
        returns (BalanceDelta delta, bool executed, IMemeverseUniswapHook.AntiSnipeFailureReason failureReason)
    {
        if (deadline < block.timestamp) revert ExpiredPastDeadline();
        if (address(key.hooks) != address(hook)) revert InvalidHook();
        if (params.amountSpecified == 0) revert SwapAmountCannotBeZero();
        if (params.amountSpecified > 0 && amountInMaximum == 0) revert AmountInMaximumRequired();

        bool antiSnipeActive = hook.isAntiSnipeActive(key.toId());
        Currency inputCurrency = _inputCurrency(key, params.zeroForOne);
        uint256 inputBudget = _swapInputBudget(params, amountInMaximum);
        uint256 nativeSwapBudget = _nativeSwapBudget(key, params, amountInMaximum);
        IMemeverseUniswapHook.FailedAttemptQuote memory failedAttemptQuote;

        if (antiSnipeActive) {
            failedAttemptQuote = hook.quoteFailedAttempt(key, params, inputBudget);
            if (!inputCurrency.isAddressZero() && inputBudget > 0) {
                if (!inputBudgetPrepared) {
                    _pullCurrency(inputCurrency, trader, inputBudget);
                }
                _ensureHookApproval(inputCurrency, inputBudget);
            }
        }

        if (msg.value != nativeSwapBudget) {
            revert IMemeverseUniswapHook.InvalidNativeValue(nativeSwapBudget, msg.value);
        }
        address refundRecipient = _validatedNativeRefundRecipient(nativeRefundRecipient, msg.value);

        if (antiSnipeActive) {
            (executed, failureReason) =
                hook.requestSwapAttempt{value: nativeSwapBudget}(key, params, trader, inputBudget, address(this));
            if (!executed) {
                if (!inputCurrency.isAddressZero() && (antiSnipeActive || payer == address(this))) {
                    _refundUnusedInput(inputCurrency, trader, inputBudget, failedAttemptQuote.feeAmount);
                }
                _refundUnusedNative(refundRecipient, nativeSwapBudget, failedAttemptQuote.feeAmount);
                return (BalanceDeltaLibrary.ZERO_DELTA, false, failureReason);
            }
        } else {
            executed = true;
            failureReason = IMemeverseUniswapHook.AntiSnipeFailureReason.None;
        }

        delta = abi.decode(
            poolManager.unlock(
                abi.encode(
                    CallbackData({
                        payer: antiSnipeActive ? address(this) : payer,
                        recipient: recipient,
                        key: key,
                        params: params,
                        hookData: hookData
                    })
                )
            ),
            (BalanceDelta)
        );

        uint256 actualInputAmount = _actualInputAmount(delta, params.zeroForOne);
        if (amountInMaximum > 0 && actualInputAmount > amountInMaximum) {
            revert InputAmountExceedsMaximum(actualInputAmount, amountInMaximum);
        }
        if (amountOutMinimum > 0) {
            uint256 actualOutputAmount = _actualOutputAmount(delta, params.zeroForOne);
            if (actualOutputAmount < amountOutMinimum) {
                revert OutputAmountBelowMinimum(actualOutputAmount, amountOutMinimum);
            }
        }

        if (!inputCurrency.isAddressZero() && (antiSnipeActive || payer == address(this))) {
            _refundUnusedInput(inputCurrency, trader, inputBudget, actualInputAmount);
        }
        _refundUnusedNative(refundRecipient, msg.value, _nativeSwapInputSpent(key, delta));

        return (delta, true, IMemeverseUniswapHook.AntiSnipeFailureReason.None);
    }

    function _pullCurrency(Currency currency, address from, uint256 amount) internal {
        if (amount == 0 || currency.isAddressZero()) return;
        if (!IERC20Minimal(Currency.unwrap(currency)).transferFrom(from, address(this), amount)) {
            revert IMemeverseUniswapHook.ERC20TransferFailed();
        }
    }

    function _pullCurrencyWithPermit2(
        IMemeverseSwapRouter.Permit2SingleParams calldata permitParams,
        address owner,
        address token,
        uint256 amount,
        bytes32 witness,
        string memory witnessTypeString
    ) internal {
        if (permitParams.permit.permitted.token != token) revert IMemeverseUniswapHook.ERC20TransferFailed();
        if (permitParams.transferDetails.to != address(this)) revert IMemeverseUniswapHook.ERC20TransferFailed();
        if (permitParams.transferDetails.requestedAmount != amount) revert IMemeverseUniswapHook.ERC20TransferFailed();

        permit2.permitWitnessTransferFrom(
            permitParams.permit,
            permitParams.transferDetails,
            owner,
            witness,
            witnessTypeString,
            permitParams.signature
        );
    }

    function _prepareCurrencyBudget(Currency currency, address from, uint256 amount) internal {
        _pullCurrency(currency, from, amount);
        _ensureHookApproval(currency, amount);
    }

    function _addLiquidityViaHook(
        PoolKey memory key,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        address to,
        address refundRecipient,
        uint256 nativeDesired,
        uint160 sqrtPriceX96
    ) internal returns (uint128 liquidity) {
        _prepareCurrencyBudget(key.currency0, msg.sender, amount0Desired);
        _prepareCurrencyBudget(key.currency1, msg.sender, amount1Desired);

        (, uint256 quotedAmount0Used, uint256 quotedAmount1Used) =
            LiquidityQuote.quote(sqrtPriceX96, amount0Desired, amount1Desired);
        uint256 nativeToForward =
            _nativeAmountForPair(key.currency0, key.currency1, quotedAmount0Used, quotedAmount1Used);

        BalanceDelta delta;
        (liquidity, delta) = hook.addLiquidityCore{value: nativeToForward}(
            IMemeverseUniswapHook.AddLiquidityCoreParams({
                currency0: key.currency0,
                currency1: key.currency1,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                to: to
            })
        );

        (uint256 amount0Used, uint256 amount1Used) = _spentLiquidityAmounts(delta);
        if (amount0Used < amount0Min || amount1Used < amount1Min) {
            revert IMemeverseUniswapHook.TooMuchSlippage();
        }

        _refundUnusedInput(key.currency0, msg.sender, amount0Desired, amount0Used);
        _refundUnusedInput(key.currency1, msg.sender, amount1Desired, amount1Used);
        _refundUnusedNative(refundRecipient, nativeDesired, nativeToForward);
    }

    function _ensureHookApproval(Currency currency, uint256 amount) internal {
        if (amount == 0 || currency.isAddressZero()) return;
        address token = Currency.unwrap(currency);
        if (IERC20Minimal(token).allowance(address(this), address(hook)) < amount) {
            if (!IERC20Minimal(token).approve(address(hook), type(uint256).max)) {
                revert IMemeverseUniswapHook.ERC20TransferFailed();
            }
        }
    }

    function _refundUnusedInput(Currency currency, address recipient, uint256 desiredAmount, uint256 usedAmount)
        internal
    {
        if (currency.isAddressZero()) return;
        if (desiredAmount <= usedAmount) return;
        _transferCurrency(currency, recipient, desiredAmount - usedAmount);
    }

    /// @dev Refunds only the per-call native surplus and never sweeps unrelated router balance.
    function _refundUnusedNative(address recipient, uint256 suppliedAmount, uint256 spentAmount) internal {
        if (suppliedAmount <= spentAmount) return;
        uint256 refund = suppliedAmount - spentAmount;
        (bool success,) = payable(recipient).call{value: refund}("");
        if (!success) revert IMemeverseUniswapHook.ERC20TransferFailed();
    }

    function _validatedNativeRefundRecipient(address recipient, uint256 suppliedAmount)
        internal
        pure
        returns (address)
    {
        if (suppliedAmount > 0 && recipient == address(0)) revert InvalidNativeRefundRecipient();
        return recipient;
    }

    function _nativeAmountForPair(Currency currency0, Currency currency1, uint256 amount0, uint256 amount1)
        internal
        pure
        returns (uint256)
    {
        if (currency0.isAddressZero()) return amount0;
        if (currency1.isAddressZero()) return amount1;
        return 0;
    }

    function _nativeSwapBudget(PoolKey calldata key, SwapParams calldata params, uint256 amountInMaximum)
        internal
        pure
        returns (uint256)
    {
        Currency currencyIn = _inputCurrency(key, params.zeroForOne);
        if (!currencyIn.isAddressZero()) return 0;
        return _swapInputBudget(params, amountInMaximum);
    }

    function _swapInputBudget(SwapParams calldata params, uint256 amountInMaximum) internal pure returns (uint256) {
        if (params.amountSpecified < 0) return uint256(-params.amountSpecified);
        return amountInMaximum;
    }

    function _inputCurrency(PoolKey calldata key, bool zeroForOne) internal pure returns (Currency) {
        return zeroForOne ? key.currency0 : key.currency1;
    }

    function _hookPoolKey(Currency currency0, Currency currency1) internal view returns (PoolKey memory) {
        return PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 200,
            hooks: IHooks(address(hook))
        });
    }

    function _spentLiquidityAmounts(BalanceDelta delta)
        internal
        pure
        returns (uint256 amount0Used, uint256 amount1Used)
    {
        amount0Used = uint256(uint128(-delta.amount0()));
        amount1Used = uint256(uint128(-delta.amount1()));
    }

    function _receivedLiquidityAmounts(BalanceDelta delta)
        internal
        pure
        returns (uint256 amount0Received, uint256 amount1Received)
    {
        amount0Received = uint256(uint128(delta.amount0()));
        amount1Received = uint256(uint128(delta.amount1()));
    }

    function _actualInputAmount(BalanceDelta delta, bool zeroForOne) internal pure returns (uint256) {
        return zeroForOne ? uint256(int256(-delta.amount0())) : uint256(int256(-delta.amount1()));
    }

    function _actualOutputAmount(BalanceDelta delta, bool zeroForOne) internal pure returns (uint256) {
        return zeroForOne ? uint256(int256(delta.amount1())) : uint256(int256(delta.amount0()));
    }

    function _nativeSwapInputSpent(PoolKey calldata key, BalanceDelta delta) internal pure returns (uint256) {
        if (key.currency0.isAddressZero() && delta.amount0() < 0) {
            return uint256(int256(-delta.amount0()));
        }
        if (key.currency1.isAddressZero() && delta.amount1() < 0) {
            return uint256(int256(-delta.amount1()));
        }
        return 0;
    }

    function _swapPermit2Witness(
        PoolKey calldata key,
        SwapParams calldata params,
        address recipient,
        address nativeRefundRecipient,
        uint256 deadline,
        uint256 amountOutMinimum,
        uint256 amountInMaximum,
        bytes calldata hookData
    ) internal pure returns (bytes32 witness, string memory witnessTypeString) {
        witness = keccak256(
            abi.encode(
                key.toId(),
                params.zeroForOne,
                params.amountSpecified,
                params.sqrtPriceLimitX96,
                recipient,
                nativeRefundRecipient,
                deadline,
                amountOutMinimum,
                amountInMaximum,
                keccak256(hookData)
            )
        );
        witnessTypeString =
            "MemeverseSwapWitness(bytes32 poolId,bool zeroForOne,int256 amountSpecified,uint160 sqrtPriceLimitX96,address recipient,address nativeRefundRecipient,uint256 deadline,uint256 amountOutMinimum,uint256 amountInMaximum,bytes32 hookDataHash)TokenPermissions(address token,uint256 amount)";
    }

    function _transferCurrency(Currency currency, address to, uint256 amount) internal {
        if (amount == 0) return;
        if (currency.isAddressZero()) {
            (bool success,) = payable(to).call{value: amount}("");
            if (!success) revert IMemeverseUniswapHook.ERC20TransferFailed();
        } else {
            if (!IERC20Minimal(Currency.unwrap(currency)).transfer(to, amount)) {
                revert IMemeverseUniswapHook.ERC20TransferFailed();
            }
        }
    }
}
