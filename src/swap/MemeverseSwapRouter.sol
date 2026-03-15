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
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IMemeverseUniswapHook} from "./interfaces/IMemeverseUniswapHook.sol";
import {IMemeverseSwapRouter} from "./interfaces/IMemeverseSwapRouter.sol";
import {LiquidityQuote} from "./libraries/LiquidityQuote.sol";
import {LiquidityAmounts} from "./libraries/LiquidityAmounts.sol";
import {CurrencySettler} from "./libraries/CurrencySettler.sol";

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
contract MemeverseSwapRouter is SafeCallback, IMemeverseSwapRouter {
    using SafeERC20 for IERC20;
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

    IMemeverseUniswapHook public immutable override hook;
    IPermit2 public immutable override permit2;
    bytes32 internal constant SWAP_WITNESS_TYPEHASH = keccak256(
        "MemeverseSwapWitness(bytes32 poolId,bool zeroForOne,int256 amountSpecified,uint160 sqrtPriceLimitX96,address recipient,address nativeRefundRecipient,uint256 deadline,uint256 amountOutMinimum,uint256 amountInMaximum,bytes32 hookDataHash)"
    );
    bytes32 internal constant ADD_LIQUIDITY_WITNESS_TYPEHASH = keccak256(
        "MemeverseAddLiquidityWitness(address currency0,address currency1,uint256 amount0Desired,uint256 amount1Desired,uint256 amount0Min,uint256 amount1Min,address to,address nativeRefundRecipient,uint256 deadline)"
    );
    bytes32 internal constant REMOVE_LIQUIDITY_WITNESS_TYPEHASH = keccak256(
        "MemeverseRemoveLiquidityWitness(address currency0,address currency1,uint128 liquidity,uint256 amount0Min,uint256 amount1Min,address to,uint256 deadline)"
    );
    bytes32 internal constant CREATE_POOL_WITNESS_TYPEHASH = keccak256(
        "MemeverseCreatePoolWitness(address tokenA,address tokenB,uint256 amountADesired,uint256 amountBDesired,uint160 startPrice,address recipient,address nativeRefundRecipient,uint256 deadline)"
    );
    string internal constant SWAP_WITNESS_TYPE_STRING =
        "MemeverseSwapWitness witness)MemeverseSwapWitness(bytes32 poolId,bool zeroForOne,int256 amountSpecified,uint160 sqrtPriceLimitX96,address recipient,address nativeRefundRecipient,uint256 deadline,uint256 amountOutMinimum,uint256 amountInMaximum,bytes32 hookDataHash)TokenPermissions(address token,uint256 amount)";
    string internal constant ADD_LIQUIDITY_WITNESS_TYPE_STRING =
        "MemeverseAddLiquidityWitness witness)MemeverseAddLiquidityWitness(address currency0,address currency1,uint256 amount0Desired,uint256 amount1Desired,uint256 amount0Min,uint256 amount1Min,address to,address nativeRefundRecipient,uint256 deadline)TokenPermissions(address token,uint256 amount)";
    string internal constant REMOVE_LIQUIDITY_WITNESS_TYPE_STRING =
        "MemeverseRemoveLiquidityWitness witness)MemeverseRemoveLiquidityWitness(address currency0,address currency1,uint128 liquidity,uint256 amount0Min,uint256 amount1Min,address to,uint256 deadline)TokenPermissions(address token,uint256 amount)";
    string internal constant CREATE_POOL_WITNESS_TYPE_STRING =
        "MemeverseCreatePoolWitness witness)MemeverseCreatePoolWitness(address tokenA,address tokenB,uint256 amountADesired,uint256 amountBDesired,uint160 startPrice,address recipient,address nativeRefundRecipient,uint256 deadline)TokenPermissions(address token,uint256 amount)";

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
        override
        returns (IMemeverseUniswapHook.SwapQuote memory quote)
    {
        return hook.quoteSwap(key, params);
    }

    /// @notice Returns the current anti-snipe failure-fee quote from the underlying Memeverse hook.
    /// @dev This is a thin passthrough so integrators can estimate the protection-window failure fee via the router.
    /// `inputBudget` is the single total input budget that will be used for either success or failure.
    /// @param key The pool key being quoted.
    /// @param params The swap parameters being quoted.
    /// @param inputBudget The maximum total input budget reserved for the attempted swap.
    /// @return quote The quoted failure-fee amount, side, and recipient class.
    function quoteFailedAttempt(PoolKey calldata key, SwapParams calldata params, uint256 inputBudget)
        external
        view
        override
        returns (IMemeverseUniswapHook.FailedAttemptQuote memory quote)
    {
        return hook.quoteFailedAttempt(key, params, inputBudget);
    }

    /// @notice Returns the hook-managed pool key for the given token pair.
    /// @dev Uses the Memeverse dynamic-fee pool settings and the router's configured hook.
    /// @param tokenA First token address (may be native as address(0)).
    /// @param tokenB Second token address (may be native as address(0)).
    /// @return key The hook pool key derived from token ordering and hook configuration.
    function getHookPoolKey(address tokenA, address tokenB) public view override returns (PoolKey memory key) {
        if (tokenA == tokenB) revert InvalidTokenPair();
        (Currency currency0, Currency currency1) = tokenA < tokenB
            ? (Currency.wrap(tokenA), Currency.wrap(tokenB))
            : (Currency.wrap(tokenB), Currency.wrap(tokenA));
        key = _hookPoolKey(currency0, currency1);
    }

    /// @notice Returns the claimable LP fees for an owner in the hook-managed pool for a token pair.
    /// @dev Resolves the hook pool key from token addresses before delegating to `hook.claimableFees`.
    /// @param tokenA First token address (may be native as address(0)).
    /// @param tokenB Second token address (may be native as address(0)).
    /// @param owner The owner address whose LP fees are previewed.
    /// @return fee0 The preview claimable amount in currency0.
    /// @return fee1 The preview claimable amount in currency1.
    function previewClaimableFees(address tokenA, address tokenB, address owner)
        external
        view
        override
        returns (uint256 fee0, uint256 fee1)
    {
        PoolKey memory key = getHookPoolKey(tokenA, tokenB);
        return hook.claimableFees(key, owner);
    }

    /// @notice Returns the LP token address for the hook-managed pool of a token pair.
    /// @dev Resolves the hook pool key from token addresses before delegating to `hook.lpToken`.
    /// @param tokenA First token address (may be native as address(0)).
    /// @param tokenB Second token address (may be native as address(0)).
    /// @return liquidityToken The LP token contract for the pair.
    function lpToken(address tokenA, address tokenB) external view override returns (address liquidityToken) {
        PoolKey memory key = getHookPoolKey(tokenA, tokenB);
        return hook.lpToken(key);
    }

    /// @notice Returns the required token amounts for a target LP liquidity in the pair pool.
    /// @dev Resolves the hook pool key, reads the current pool price, and applies the same full-range liquidity math
    /// used by the Router and Hook Core add-liquidity paths.
    /// @param tokenA First token address (may be native as address(0)).
    /// @param tokenB Second token address (may be native as address(0)).
    /// @param liquidityDesired Target LP liquidity to quote.
    /// @return amountARequired Required amount of `tokenA`.
    /// @return amountBRequired Required amount of `tokenB`.
    function quoteAmountsForLiquidity(address tokenA, address tokenB, uint128 liquidityDesired)
        external
        view
        override
        returns (uint256 amountARequired, uint256 amountBRequired)
    {
        PoolKey memory key = getHookPoolKey(tokenA, tokenB);
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(key.toId());
        (uint256 amount0Required, uint256 amount1Required) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96, LiquidityQuote.MIN_SQRT_PRICE_X96, LiquidityQuote.MAX_SQRT_PRICE_X96, liquidityDesired
        );
        return tokenA < tokenB ? (amount0Required, amount1Required) : (amount1Required, amount0Required);
    }

    /// @notice Executes a swap through the Memeverse hook's anti-snipe gate in a single transaction.
    /// @dev If anti-snipe soft-fails, this entrypoint returns `(ZERO_DELTA, false, reason)` and does not call
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
        override
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
        override
        returns (BalanceDelta delta, bool executed, IMemeverseUniswapHook.AntiSnipeFailureReason failureReason)
    {
        _prepareSwapPermit2Input(
                permitParams,
                key,
                params,
                recipient,
                nativeRefundRecipient,
                deadline,
                amountOutMinimum,
                amountInMaximum,
                hookData
            );

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
    /// and refunds any unused input budget to `nativeRefundRecipient`. This path is separate from the swap
    /// protection-window budget logic.
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
    ) external payable override returns (uint128 liquidity) {
        return _addLiquidity(
            currency0,
            currency1,
            amount0Desired,
            amount1Desired,
            amount0Min,
            amount1Min,
            to,
            nativeRefundRecipient,
            deadline,
            msg.sender,
            msg.sender,
            false
        );
    }

    /// @notice Adds liquidity after funding one or two ERC20 inputs through Permit2 signature transfer.
    /// @dev After Permit2 funding succeeds, execution follows the same path as `addLiquidity(...)`.
    /// @custom:security The batch Permit2 payload must align with the ERC20 side(s) of this call.
    /// @param permitParams The Permit2 batch-transfer parameters covering the ERC20 funding legs.
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
    function addLiquidityWithPermit2(
        IMemeverseSwapRouter.Permit2BatchParams calldata permitParams,
        Currency currency0,
        Currency currency1,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        address to,
        address nativeRefundRecipient,
        uint256 deadline
    ) external payable override returns (uint128 liquidity) {
        (bytes32 witness, string memory witnessTypeString) = _addLiquidityPermit2Witness(
            currency0,
            currency1,
            amount0Desired,
            amount1Desired,
            amount0Min,
            amount1Min,
            to,
            nativeRefundRecipient,
            deadline
        );
        _pullCurrenciesWithPermit2(
            permitParams,
            msg.sender,
            Currency.unwrap(currency0),
            Currency.unwrap(currency1),
            amount0Desired,
            amount1Desired,
            witness,
            witnessTypeString
        );

        return _addLiquidity(
            currency0,
            currency1,
            amount0Desired,
            amount1Desired,
            amount0Min,
            amount1Min,
            to,
            nativeRefundRecipient,
            deadline,
            address(this),
            msg.sender,
            true
        );
    }

    /// @notice Removes liquidity through the hook core entrypoint while applying periphery protections.
    /// @dev Pulls LP shares into the router, calls the hook core, validates minimum outputs, and forwards the assets.
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
    ) external override returns (BalanceDelta delta) {
        return _removeLiquidity(
            currency0, currency1, liquidity, amount0Min, amount1Min, to, deadline, msg.sender, false
        );
    }

    /// @notice Removes liquidity after pulling LP shares through Permit2 signature transfer.
    /// @dev After Permit2 funding succeeds, execution follows the same path as `removeLiquidity(...)`.
    /// @custom:security The Permit2 payload must authorize the hook LP token transfer required by this call.
    /// @param permitParams The Permit2 single-transfer parameters covering the LP token.
    /// @param currency0 Pool currency0.
    /// @param currency1 Pool currency1.
    /// @param liquidity LP liquidity to burn.
    /// @param amount0Min Minimum currency0 output accepted.
    /// @param amount1Min Minimum currency1 output accepted.
    /// @param to Recipient of withdrawn assets.
    /// @param deadline The latest timestamp at which the call is valid.
    /// @return delta The balance delta returned by the hook core.
    function removeLiquidityWithPermit2(
        IMemeverseSwapRouter.Permit2SingleParams calldata permitParams,
        Currency currency0,
        Currency currency1,
        uint128 liquidity,
        uint256 amount0Min,
        uint256 amount1Min,
        address to,
        uint256 deadline
    ) external override returns (BalanceDelta delta) {
        PoolKey memory key = _hookPoolKey(currency0, currency1);
        (address liquidityToken,,,) = hook.poolInfo(key.toId());
        (bytes32 witness, string memory witnessTypeString) =
            _removeLiquidityPermit2Witness(currency0, currency1, liquidity, amount0Min, amount1Min, to, deadline);
        _pullCurrencyWithPermit2(
            permitParams, msg.sender, liquidityToken, uint256(liquidity), witness, witnessTypeString
        );

        return _removeLiquidity(currency0, currency1, liquidity, amount0Min, amount1Min, to, deadline, msg.sender, true);
    }

    /// @notice Claims pending LP fees for the caller through the hook core entrypoint.
    /// @dev The caller may either invoke this directly as owner or provide a signature so the router can relay the claim.
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
        override
        returns (uint256 fee0Amount, uint256 fee1Amount)
    {
        return hook.claimFeesCore(
            IMemeverseUniswapHook.ClaimFeesCoreParams({
                key: key, owner: msg.sender, recipient: recipient, deadline: deadline, v: v, r: r, s: s
            })
        );
    }

    /// @notice Initializes a hook-backed pool and seeds its first full-range liquidity position through the hook core.
    /// @dev Pulls the caller's desired budgets, initializes the pool, derives the actual full-range spend, forwards
    /// only the exact required native amount to the hook core, and refunds any unused input budget to
    /// `nativeRefundRecipient`.
    /// @param tokenA One side of the pool pair.
    /// @param tokenB The other side of the pool pair.
    /// @param amountADesired Desired budget for `tokenA`.
    /// @param amountBDesired Desired budget for `tokenB`.
    /// @param startPrice The initial `sqrtPriceX96` passed to the pool manager.
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
        uint160 startPrice,
        address recipient,
        address nativeRefundRecipient,
        uint256 deadline
    ) external payable override returns (uint128 liquidity, PoolKey memory poolKey) {
        return _createPoolAndAddLiquidity(
            tokenA,
            tokenB,
            amountADesired,
            amountBDesired,
            startPrice,
            recipient,
            nativeRefundRecipient,
            deadline,
            msg.sender,
            msg.sender,
            false
        );
    }

    /// @notice Initializes a hook-backed pool after funding one or two ERC20 inputs through Permit2.
    /// @dev After Permit2 funding succeeds, execution follows the same path as `createPoolAndAddLiquidity(...)`.
    /// @custom:security The batch Permit2 payload must align with the ERC20 sides of the bootstrap pair.
    /// @param permitParams The Permit2 batch-transfer parameters covering the ERC20 bootstrap legs.
    /// @param tokenA One side of the pool pair.
    /// @param tokenB The other side of the pool pair.
    /// @param amountADesired Desired budget for `tokenA`.
    /// @param amountBDesired Desired budget for `tokenB`.
    /// @param startPrice The initial `sqrtPriceX96` passed to the pool manager.
    /// @param recipient Recipient of minted LP shares.
    /// @param nativeRefundRecipient Recipient of any unused native refund.
    /// @param deadline The latest timestamp at which the call is valid.
    /// @return liquidity The minted LP liquidity.
    /// @return poolKey The initialized pool key.
    function createPoolAndAddLiquidityWithPermit2(
        IMemeverseSwapRouter.Permit2BatchParams calldata permitParams,
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint160 startPrice,
        address recipient,
        address nativeRefundRecipient,
        uint256 deadline
    ) external payable override returns (uint128 liquidity, PoolKey memory poolKey) {
        (bytes32 witness, string memory witnessTypeString) = _createPoolAndAddLiquidityPermit2Witness(
            tokenA, tokenB, amountADesired, amountBDesired, startPrice, recipient, nativeRefundRecipient, deadline
        );
        _pullCurrenciesWithPermit2(
            permitParams, msg.sender, tokenA, tokenB, amountADesired, amountBDesired, witness, witnessTypeString
        );

        return _createPoolAndAddLiquidity(
            tokenA,
            tokenB,
            amountADesired,
            amountBDesired,
            startPrice,
            recipient,
            nativeRefundRecipient,
            deadline,
            address(this),
            msg.sender,
            true
        );
    }

    /// @dev Executes the actual swap during the manager unlock window and settles the caller delta.
    function _unlockCallback(bytes calldata rawData) internal override returns (bytes memory) {
        CallbackData memory data = abi.decode(rawData, (CallbackData));

        BalanceDelta delta = poolManager.swap(data.key, data.params, data.hookData);
        int128 amount0 = delta.amount0();
        int128 amount1 = delta.amount1();

        if (amount0 < 0) {
            data.key.currency0.settle(poolManager, data.payer, uint256(uint128(-amount0)), false);
        }
        if (amount1 < 0) {
            data.key.currency1.settle(poolManager, data.payer, uint256(uint128(-amount1)), false);
        }
        if (amount0 > 0) {
            data.key.currency0.take(poolManager, data.recipient, uint256(uint128(amount0)), false);
        }
        if (amount1 > 0) {
            data.key.currency1.take(poolManager, data.recipient, uint256(uint128(amount1)), false);
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
    ) internal returns (BalanceDelta delta, bool executed, IMemeverseUniswapHook.AntiSnipeFailureReason failureReason) {
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
            if (!inputCurrency.isAddressZero() && inputBudget > 0) {
                if (!inputBudgetPrepared) {
                    _pullCurrency(inputCurrency, trader, inputBudget);
                }
                _ensureHookApproval(inputCurrency, inputBudget);
            }
        }

        address refundRecipient = _validateNativeFunding(nativeSwapBudget, nativeRefundRecipient);

        if (antiSnipeActive) {
            (executed, failureReason, failedAttemptQuote) = hook.requestSwapAttemptWithQuote{value: nativeSwapBudget}(
                key, params, trader, inputBudget, address(this)
            );
            if (!executed) {
                if (!inputCurrency.isAddressZero()) {
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
        uint256 nativeInputSpent = inputCurrency.isAddressZero() ? actualInputAmount : 0;
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
        _refundUnusedNative(refundRecipient, msg.value, nativeInputSpent);

        return (delta, true, IMemeverseUniswapHook.AntiSnipeFailureReason.None);
    }

    function _pullCurrency(Currency currency, address from, uint256 amount) internal {
        if (amount == 0 || currency.isAddressZero()) return;
        if (!IERC20Minimal(Currency.unwrap(currency)).transferFrom(from, address(this), amount)) {
            revert IMemeverseUniswapHook.ERC20TransferFailed();
        }
    }

    function _prepareSwapPermit2Input(
        IMemeverseSwapRouter.Permit2SingleParams calldata permitParams,
        PoolKey calldata key,
        SwapParams calldata params,
        address recipient,
        address nativeRefundRecipient,
        uint256 deadline,
        uint256 amountOutMinimum,
        uint256 amountInMaximum,
        bytes calldata hookData
    ) internal {
        Currency inputCurrency = _inputCurrency(key, params.zeroForOne);
        uint256 inputBudget = _swapInputBudget(params, amountInMaximum);
        if (inputCurrency.isAddressZero() || inputBudget == 0) return;

        (bytes32 witness, string memory witnessTypeString) = _swapPermit2Witness(
            key, params, recipient, nativeRefundRecipient, deadline, amountOutMinimum, amountInMaximum, hookData
        );
        _pullCurrencyWithPermit2(
            permitParams, msg.sender, Currency.unwrap(inputCurrency), inputBudget, witness, witnessTypeString
        );
    }

    function _pullCurrencyWithPermit2(
        IMemeverseSwapRouter.Permit2SingleParams calldata permitParams,
        address owner,
        address token,
        uint256 amount,
        bytes32 witness,
        string memory witnessTypeString
    ) internal {
        if (permitParams.permit.permitted.token != token) {
            revert IMemeverseUniswapHook.ERC20TransferFailed();
        }
        if (permitParams.transferDetails.to != address(this)) revert IMemeverseUniswapHook.ERC20TransferFailed();
        if (permitParams.transferDetails.requestedAmount != amount) revert IMemeverseUniswapHook.ERC20TransferFailed();

        permit2.permitWitnessTransferFrom(
            permitParams.permit, permitParams.transferDetails, owner, witness, witnessTypeString, permitParams.signature
        );
    }

    function _pullCurrenciesWithPermit2(
        IMemeverseSwapRouter.Permit2BatchParams calldata permitParams,
        address owner,
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1,
        bytes32 witness,
        string memory witnessTypeString
    ) internal {
        bool token0IsNative = token0 == address(0);
        bool token1IsNative = token1 == address(0);
        uint256 expectedLength = (token0IsNative || token1IsNative) ? 1 : 2;
        if (
            permitParams.permit.permitted.length != expectedLength
                || permitParams.transferDetails.length != expectedLength
        ) {
            revert InvalidPermit2Length();
        }

        uint256 index;
        if (!token0IsNative) {
            _validatePermit2BatchEntry(permitParams, index, token0, amount0);
            unchecked {
                ++index;
            }
        }
        if (!token1IsNative) {
            _validatePermit2BatchEntry(permitParams, index, token1, amount1);
        }

        permit2.permitWitnessTransferFrom(
            permitParams.permit, permitParams.transferDetails, owner, witness, witnessTypeString, permitParams.signature
        );
    }

    function _validatePermit2BatchEntry(
        IMemeverseSwapRouter.Permit2BatchParams calldata permitParams,
        uint256 index,
        address expectedToken,
        uint256 expectedAmount
    ) internal view {
        address actualToken = permitParams.permit.permitted[index].token;
        if (actualToken != expectedToken) revert InvalidPermit2Token(index, expectedToken, actualToken);
        if (permitParams.transferDetails[index].to != address(this)) {
            revert IMemeverseUniswapHook.ERC20TransferFailed();
        }
        if (permitParams.transferDetails[index].requestedAmount != expectedAmount) {
            revert IMemeverseUniswapHook.ERC20TransferFailed();
        }
    }

    function _prepareCurrencyBudget(Currency currency, address from, uint256 amount) internal {
        _pullCurrency(currency, from, amount);
        _ensureHookApproval(currency, amount);
    }

    function _addLiquidity(
        Currency currency0,
        Currency currency1,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        address to,
        address nativeRefundRecipient,
        uint256 deadline,
        address payer,
        address inputRefundRecipient,
        bool budgetsPrepared
    ) internal returns (uint128 liquidity) {
        if (deadline < block.timestamp) revert ExpiredPastDeadline();

        uint256 nativeDesired =
            currency0.isAddressZero() ? amount0Desired : currency1.isAddressZero() ? amount1Desired : 0;
        address refundRecipient = _validateNativeFunding(nativeDesired, nativeRefundRecipient);

        PoolKey memory key = _hookPoolKey(currency0, currency1);
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(key.toId());
        return _addLiquidityViaHook(
            key,
            amount0Desired,
            amount1Desired,
            amount0Min,
            amount1Min,
            to,
            refundRecipient,
            nativeDesired,
            sqrtPriceX96,
            payer,
            inputRefundRecipient,
            budgetsPrepared
        );
    }

    function _removeLiquidity(
        Currency currency0,
        Currency currency1,
        uint128 liquidity,
        uint256 amount0Min,
        uint256 amount1Min,
        address to,
        uint256 deadline,
        address payer,
        bool liquidityPrepared
    ) internal returns (BalanceDelta delta) {
        if (deadline < block.timestamp) revert ExpiredPastDeadline();

        PoolKey memory key = _hookPoolKey(currency0, currency1);
        if (!liquidityPrepared) {
            (address liquidityToken,,,) = hook.poolInfo(key.toId());
            IERC20(liquidityToken).safeTransferFrom(payer, address(this), liquidity);
        }

        delta = hook.removeLiquidityCore(
            IMemeverseUniswapHook.RemoveLiquidityCoreParams({
                currency0: currency0, currency1: currency1, liquidity: liquidity, recipient: address(this)
            })
        );

        (uint256 amount0Out, uint256 amount1Out) = _receivedLiquidityAmounts(delta);
        if (amount0Out < amount0Min || amount1Out < amount1Min) {
            revert IMemeverseUniswapHook.TooMuchSlippage();
        }

        _transferCurrency(currency0, to, amount0Out);
        _transferCurrency(currency1, to, amount1Out);
    }

    function _createPoolAndAddLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint160 startPrice,
        address recipient,
        address nativeRefundRecipient,
        uint256 deadline,
        address payer,
        address inputRefundRecipient,
        bool budgetsPrepared
    ) internal returns (uint128 liquidity, PoolKey memory poolKey) {
        if (deadline < block.timestamp) revert ExpiredPastDeadline();
        if (tokenA == tokenB) revert InvalidTokenPair();

        (Currency currency0, Currency currency1) = tokenA < tokenB
            ? (Currency.wrap(tokenA), Currency.wrap(tokenB))
            : (Currency.wrap(tokenB), Currency.wrap(tokenA));
        uint256 amount0Desired = tokenA < tokenB ? amountADesired : amountBDesired;
        uint256 amount1Desired = tokenA < tokenB ? amountBDesired : amountADesired;

        uint256 nativeDesired = tokenA == address(0) ? amountADesired : tokenB == address(0) ? amountBDesired : 0;
        address refundRecipient = _validateNativeFunding(nativeDesired, nativeRefundRecipient);
        poolKey = _hookPoolKey(currency0, currency1);

        poolManager.initialize(poolKey, startPrice);
        liquidity = _addLiquidityViaHook(
            poolKey,
            amount0Desired,
            amount1Desired,
            0,
            0,
            recipient,
            refundRecipient,
            nativeDesired,
            startPrice,
            payer,
            inputRefundRecipient,
            budgetsPrepared
        );
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
        uint160 sqrtPriceX96,
        address payer,
        address inputRefundRecipient,
        bool budgetsPrepared
    ) internal returns (uint128 liquidity) {
        if (budgetsPrepared) {
            _ensureHookApproval(key.currency0, amount0Desired);
            _ensureHookApproval(key.currency1, amount1Desired);
        } else {
            _prepareCurrencyBudget(key.currency0, payer, amount0Desired);
            _prepareCurrencyBudget(key.currency1, payer, amount1Desired);
        }

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

        _refundUnusedInput(key.currency0, inputRefundRecipient, amount0Desired, amount0Used);
        _refundUnusedInput(key.currency1, inputRefundRecipient, amount1Desired, amount1Used);
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

    function _validateNativeFunding(uint256 nativeDesired, address nativeRefundRecipient)
        internal
        view
        returns (address refundRecipient)
    {
        if (msg.value != nativeDesired) revert IMemeverseUniswapHook.InvalidNativeValue(nativeDesired, msg.value);
        refundRecipient = _validatedNativeRefundRecipient(nativeRefundRecipient, msg.value);
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
                SWAP_WITNESS_TYPEHASH,
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
        witnessTypeString = SWAP_WITNESS_TYPE_STRING;
    }

    function _addLiquidityPermit2Witness(
        Currency currency0,
        Currency currency1,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        address to,
        address nativeRefundRecipient,
        uint256 deadline
    ) internal pure returns (bytes32 witness, string memory witnessTypeString) {
        witness = keccak256(
            abi.encode(
                ADD_LIQUIDITY_WITNESS_TYPEHASH,
                Currency.unwrap(currency0),
                Currency.unwrap(currency1),
                amount0Desired,
                amount1Desired,
                amount0Min,
                amount1Min,
                to,
                nativeRefundRecipient,
                deadline
            )
        );
        witnessTypeString = ADD_LIQUIDITY_WITNESS_TYPE_STRING;
    }

    function _removeLiquidityPermit2Witness(
        Currency currency0,
        Currency currency1,
        uint128 liquidity,
        uint256 amount0Min,
        uint256 amount1Min,
        address to,
        uint256 deadline
    ) internal pure returns (bytes32 witness, string memory witnessTypeString) {
        witness = keccak256(
            abi.encode(
                REMOVE_LIQUIDITY_WITNESS_TYPEHASH,
                Currency.unwrap(currency0),
                Currency.unwrap(currency1),
                liquidity,
                amount0Min,
                amount1Min,
                to,
                deadline
            )
        );
        witnessTypeString = REMOVE_LIQUIDITY_WITNESS_TYPE_STRING;
    }

    function _createPoolAndAddLiquidityPermit2Witness(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint160 startPrice,
        address recipient,
        address nativeRefundRecipient,
        uint256 deadline
    ) internal pure returns (bytes32 witness, string memory witnessTypeString) {
        witness = keccak256(
            abi.encode(
                CREATE_POOL_WITNESS_TYPEHASH,
                tokenA,
                tokenB,
                amountADesired,
                amountBDesired,
                startPrice,
                recipient,
                nativeRefundRecipient,
                deadline
            )
        );
        witnessTypeString = CREATE_POOL_WITNESS_TYPE_STRING;
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
