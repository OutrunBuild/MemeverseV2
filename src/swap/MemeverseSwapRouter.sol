// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {IPoolManager, SwapParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {SafeCallback} from "@uniswap/v4-periphery/src/base/SafeCallback.sol";
import {IERC20Minimal} from "@uniswap/v4-core/src/interfaces/external/IERC20Minimal.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {OutrunSafeERC20} from "../yield/libraries/OutrunSafeERC20.sol";
import {IMemeverseUniswapHook} from "./interfaces/IMemeverseUniswapHook.sol";
import {IMemeverseSwapRouter} from "./interfaces/IMemeverseSwapRouter.sol";
import {LiquidityQuote} from "./libraries/LiquidityQuote.sol";
import {LiquidityAmounts} from "./libraries/LiquidityAmounts.sol";
import {CurrencySettler} from "./libraries/CurrencySettler.sol";
import {SafeCast} from "./libraries/SafeCast.sol";

/// @title MemeverseSwapRouter
/// @notice Recommended single public periphery entrypoint for Memeverse swap and LP flows.
/// @dev Swaps always execute or revert. For exact-output swaps, callers are expected to source `amountInMaximum`
/// from `MemeverseSwapRouter.quoteSwap()` or a stricter front-end slippage policy. The underlying hook remains
/// callable as a Core API for custom routers and integrators, but this router is the intended canonical entrypoint
/// for end-user and on-chain SDK integrations, covering quote, swap, LP, fee claim, and hook-backed pool bootstrap
/// flows.
contract MemeverseSwapRouter is SafeCallback, IMemeverseSwapRouter {
    using OutrunSafeERC20 for IERC20;
    using CurrencySettler for Currency;
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using SafeCast for int128;

    struct CallbackData {
        address payer;
        address recipient;
        PoolKey key;
        SwapParams params;
        bytes hookData;
    }

    IMemeverseUniswapHook public immutable override hook;
    IPermit2 public immutable override permit2;
    /* solhint-disable gas-small-strings */
    bytes32 internal constant SWAP_WITNESS_TYPEHASH = keccak256(
        "MemeverseSwapWitness(bytes32 poolId,bool zeroForOne,int256 amountSpecified,uint160 sqrtPriceLimitX96,address recipient,uint256 deadline,uint256 amountOutMinimum,uint256 amountInMaximum,bytes32 hookDataHash)"
    );
    bytes32 internal constant ADD_LIQUIDITY_WITNESS_TYPEHASH = keccak256(
        "MemeverseAddLiquidityWitness(address currency0,address currency1,uint256 amount0Desired,uint256 amount1Desired,uint256 amount0Min,uint256 amount1Min,address to,uint256 deadline)"
    );
    bytes32 internal constant REMOVE_LIQUIDITY_WITNESS_TYPEHASH = keccak256(
        "MemeverseRemoveLiquidityWitness(address currency0,address currency1,uint128 liquidity,uint256 amount0Min,uint256 amount1Min,address to,uint256 deadline)"
    );
    bytes32 internal constant CREATE_POOL_WITNESS_TYPEHASH = keccak256(
        "MemeverseCreatePoolWitness(address tokenA,address tokenB,uint256 amountADesired,uint256 amountBDesired,uint160 startPrice,address recipient,uint256 deadline)"
    );
    string internal constant SWAP_WITNESS_TYPE_STRING =
        "MemeverseSwapWitness witness)MemeverseSwapWitness(bytes32 poolId,bool zeroForOne,int256 amountSpecified,uint160 sqrtPriceLimitX96,address recipient,uint256 deadline,uint256 amountOutMinimum,uint256 amountInMaximum,bytes32 hookDataHash)TokenPermissions(address token,uint256 amount)";
    string internal constant ADD_LIQUIDITY_WITNESS_TYPE_STRING =
        "MemeverseAddLiquidityWitness witness)MemeverseAddLiquidityWitness(address currency0,address currency1,uint256 amount0Desired,uint256 amount1Desired,uint256 amount0Min,uint256 amount1Min,address to,uint256 deadline)TokenPermissions(address token,uint256 amount)";
    string internal constant REMOVE_LIQUIDITY_WITNESS_TYPE_STRING =
        "MemeverseRemoveLiquidityWitness witness)MemeverseRemoveLiquidityWitness(address currency0,address currency1,uint128 liquidity,uint256 amount0Min,uint256 amount1Min,address to,uint256 deadline)TokenPermissions(address token,uint256 amount)";
    string internal constant CREATE_POOL_WITNESS_TYPE_STRING =
        "MemeverseCreatePoolWitness witness)MemeverseCreatePoolWitness(address tokenA,address tokenB,uint256 amountADesired,uint256 amountBDesired,uint160 startPrice,address recipient,uint256 deadline)TokenPermissions(address token,uint256 amount)";

    /* solhint-enable gas-small-strings */

    /// @param _manager The Uniswap v4 pool manager.
    /// @param _hook The Memeverse hook that owns launch-fee and LP accounting for routed swaps.
    /// @param _permit2 The Permit2 entrypoint used for signature-based ERC20 pulls.
    constructor(IPoolManager _manager, IMemeverseUniswapHook _hook, IPermit2 _permit2) SafeCallback(_manager) {
        hook = _hook;
        permit2 = _permit2;
    }

    modifier beforeDeadline(uint256 deadline) {
        if (deadline < block.timestamp) revert ExpiredPastDeadline();
        _;
    }

    modifier differentTokens(address tokenA, address tokenB) {
        if (tokenA == tokenB) revert InvalidTokenPair();
        _;
    }

    modifier erc20Pair(Currency currency0, Currency currency1) {
        _revertIfNativeCurrencyUnsupported(currency0, currency1);
        _;
    }

    /// @notice Request the hook's current swap quote so integrations can preview fees, side, and expected flows.
    /// @dev This router-first facade keeps quote logic centralized while reusing the hook's internal math.
    /// @param key Pool key being quoted.
    /// @param params Swap parameters that define direction, amount, and slippage posture.
    /// @return quote A projected swap quote describing fees, estimated user input/output, and protocol split.
    function quoteSwap(PoolKey calldata key, SwapParams calldata params)
        external
        view
        override
        returns (IMemeverseUniswapHook.SwapQuote memory quote)
    {
        return hook.quoteSwap(key, params);
    }

    /// @notice Derive the hook-managed pool key that corresponds to a given token pair.
    /// @dev Sorts the tokens canonically and applies the router's hook configuration before delegating to the hook.
    /// @param tokenA One side of the pair.
    /// @param tokenB The other side of the pair.
    /// @return key Canonical hook pool key for the pair.
    function getHookPoolKey(address tokenA, address tokenB)
        public
        view
        override
        differentTokens(tokenA, tokenB)
        returns (PoolKey memory key)
    {
        (Currency currency0, Currency currency1,) = _sortedCurrencies(tokenA, tokenB);
        key = _hookPoolKey(currency0, currency1);
    }

    /// @notice Preview how much LP fee an owner can claim for a token pair.
    /// @dev Resolves the hook pool key from token addresses before delegating to `hook.claimableFees`.
    /// @param tokenA One side of the pair.
    /// @param tokenB The other side of the pair.
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

    /// @notice Return the LP token contract for the hook-managed pair formed by the given tokens.
    /// @dev Resolves the hook pool key from token addresses before delegating to `hook.lpToken`.
    /// @param tokenA One side of the pair.
    /// @param tokenB The other side of the pair.
    /// @return liquidityToken The LP token contract for the pair.
    function lpToken(address tokenA, address tokenB) external view override returns (address liquidityToken) {
        PoolKey memory key = getHookPoolKey(tokenA, tokenB);
        return hook.lpToken(key);
    }

    /// @notice Quote how much of each pool token the router would spend to mint a desired liquidity amount.
    /// @dev Resolves the hook pool key, reads the current pool price, and applies the same full-range liquidity math
    /// used by the Router and Hook Core add-liquidity paths.
    /// @param tokenA One side of the pair.
    /// @param tokenB The other side of the pair.
    /// @param liquidityDesired Target LP liquidity to quote.
    /// @return amountARequired Required amount of `tokenA`.
    /// @return amountBRequired Required amount of `tokenB`.
    function quoteAmountsForLiquidity(address tokenA, address tokenB, uint128 liquidityDesired)
        external
        view
        override
        differentTokens(tokenA, tokenB)
        returns (uint256 amountARequired, uint256 amountBRequired)
    {
        (Currency currency0, Currency currency1, bool tokenAIsCurrency0) = _sortedCurrencies(tokenA, tokenB);
        PoolKey memory key = _hookPoolKey(currency0, currency1);
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(key.toId());
        (uint256 amount0Required, uint256 amount1Required) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96, LiquidityQuote.MIN_SQRT_PRICE_X96, LiquidityQuote.MAX_SQRT_PRICE_X96, liquidityDesired
        );
        return tokenAIsCurrency0 ? (amount0Required, amount1Required) : (amount1Required, amount0Required);
    }

    /// @notice Execute a swap through the Memeverse hook with router-managed slippage and caller-directed refunds.
    /// @dev Swaps always settle or revert; the caller must cover slippage via `amountOutMinimum` or `amountInMaximum`, and any leftover budget is refunded to the caller.
    /// @param key Pool key to swap against.
    /// @param params Swap parameters that define direction, amount, and price impact.
    /// @param recipient Address that should receive the swap output.
    /// @param deadline Timestamp by which the call must execute.
    /// @param amountOutMinimum Minimum net output the caller is willing to accept.
    /// @param amountInMaximum Maximum input the caller allows for exact-output swaps.
    /// @param hookData Opaque hook data forwarded to `poolManager.swap`.
    /// @return delta Balance delta describing the net token movement settled by the swap.
    function swap(
        PoolKey calldata key,
        SwapParams calldata params,
        address recipient,
        uint256 deadline,
        uint256 amountOutMinimum,
        uint256 amountInMaximum,
        bytes calldata hookData
    ) external override returns (BalanceDelta delta) {
        (Currency inputCurrency, uint256 inputBudget) = _swapInputContext(key, params, amountInMaximum);
        _pullCurrency(inputCurrency, msg.sender, inputBudget);

        return _swap(
            key,
            params,
            recipient,
            deadline,
            amountOutMinimum,
            amountInMaximum,
            hookData,
            msg.sender,
            inputCurrency,
            inputBudget
        );
    }

    /// @notice Execute a swap after funding the router via Permit2 signature transfer.
    /// @dev Behaves identically to `swap(...)` once the Permit2 pull completes.
    /// @custom:security Callers must sign Permit2 data that matches the intended input budget and token.
    /// @param permitParams Permit2 single-transfer parameters and signature for the routed input.
    /// @param key The pool key to swap against.
    /// @param params The swap parameters.
    /// @param recipient The address receiving any swap output.
    /// @param deadline The latest timestamp at which the call is valid.
    /// @param amountOutMinimum The minimum net output the caller is willing to receive.
    /// @param amountInMaximum The maximum input the caller is willing to pay.
    /// @param hookData Opaque hook data forwarded to `poolManager.swap`.
    /// @return delta The final swap delta.
    function swapWithPermit2(
        IMemeverseSwapRouter.Permit2SingleParams calldata permitParams,
        PoolKey calldata key,
        SwapParams calldata params,
        address recipient,
        uint256 deadline,
        uint256 amountOutMinimum,
        uint256 amountInMaximum,
        bytes calldata hookData
    ) external override returns (BalanceDelta delta) {
        (Currency inputCurrency, uint256 inputBudget) = _swapInputContext(key, params, amountInMaximum);
        _prepareSwapPermit2Input(
            permitParams,
            key,
            params,
            recipient,
            deadline,
            amountOutMinimum,
            amountInMaximum,
            hookData,
            inputCurrency,
            inputBudget
        );

        return _swap(
            key,
            params,
            recipient,
            deadline,
            amountOutMinimum,
            amountInMaximum,
            hookData,
            msg.sender,
            inputCurrency,
            inputBudget
        );
    }

    /// @notice Add liquidity via the hook core while the router finalizes exact spend, enforces minimums, and refunds leftovers.
    /// @dev Pulls the caller's desired budgets, validates min amounts, and refunds any unused input budget back to the caller.
    /// @param currency0 Pool currency0.
    /// @param currency1 Pool currency1.
    /// @param amount0Desired Desired currency0 budget.
    /// @param amount1Desired Desired currency1 budget.
    /// @param amount0Min Minimum currency0 spend accepted after routing.
    /// @param amount1Min Minimum currency1 spend accepted after routing.
    /// @param to Recipient of minted LP shares.
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
        uint256 deadline
    ) external override returns (uint128 liquidity) {
        PoolKey memory key = _resolveAddLiquidityExecutionContext(currency0, currency1, deadline);
        _pullAndApproveAddLiquidityBudgets(key.currency0, key.currency1, amount0Desired, amount1Desired, msg.sender);

        return _addLiquidityViaHook(key, amount0Desired, amount1Desired, amount0Min, amount1Min, to, msg.sender);
    }

    /// @notice Add liquidity after covering the ERC20 sides through a Permit2 signature transfer.
    /// @dev After Permit2 funding succeeds, execution follows the same path as `addLiquidity(...)`.
    /// @custom:security The batch Permit2 payload must align with the ERC20 side(s) of this call.
    /// @param permitParams Permit2 batch-transfer parameters and signature that fund the ERC20 legs.
    /// @param currency0 Pool currency0.
    /// @param currency1 Pool currency1.
    /// @param amount0Desired Desired currency0 budget.
    /// @param amount1Desired Desired currency1 budget.
    /// @param amount0Min Minimum currency0 spend accepted.
    /// @param amount1Min Minimum currency1 spend accepted.
    /// @param to Recipient of minted LP shares.
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
        uint256 deadline
    ) external override returns (uint128 liquidity) {
        PoolKey memory key = _resolveAddLiquidityExecutionContext(currency0, currency1, deadline);
        _pullCurrenciesWithPermit2(
            permitParams,
            msg.sender,
            Currency.unwrap(currency0),
            Currency.unwrap(currency1),
            amount0Desired,
            amount1Desired,
            _addLiquidityPermit2Witness(
                currency0, currency1, amount0Desired, amount1Desired, amount0Min, amount1Min, to, deadline
            ),
            ADD_LIQUIDITY_WITNESS_TYPE_STRING
        );
        _approvePreparedAddLiquidityBudgets(key.currency0, key.currency1, amount0Desired, amount1Desired);

        return _addLiquidityViaHook(key, amount0Desired, amount1Desired, amount0Min, amount1Min, to, msg.sender);
    }

    /// @notice Remove liquidity through the hook while the router enforces min outputs and forwards the settled assets.
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

    /// @notice Remove liquidity after funding the LP side via Permit2 signature transfer.
    /// @dev After Permit2 funding succeeds, execution follows the same path as `removeLiquidity(...)`.
    /// @custom:security The Permit2 payload must authorize the hook LP token transfer required by this call.
    /// @param permitParams Permit2 single-transfer parameters and signature covering the LP token.
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
        (address liquidityToken,,) = hook.poolInfo(key.toId());
        _pullCurrencyWithPermit2(
            permitParams,
            msg.sender,
            liquidityToken,
            uint256(liquidity),
            _removeLiquidityPermit2Witness(currency0, currency1, liquidity, amount0Min, amount1Min, to, deadline),
            REMOVE_LIQUIDITY_WITNESS_TYPE_STRING
        );

        return _removeLiquidity(currency0, currency1, liquidity, amount0Min, amount1Min, to, deadline, msg.sender, true);
    }

    /// @notice Claim pending LP fees for the caller, either directly or via a signed relay, through the hook core entrypoint.
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

    /// @notice Initialize a hook-backed pool and seed its first full-range liquidity position through the hook core.
    /// @dev Pulls the caller's desired budgets, initializes the pool, and adds liquidity through the hook core.
    /// @param tokenA One side of the pool pair.
    /// @param tokenB The other side of the pool pair.
    /// @param amountADesired Desired budget for `tokenA`.
    /// @param amountBDesired Desired budget for `tokenB`.
    /// @param startPrice The initial `sqrtPriceX96` passed to the pool manager.
    /// @param recipient Recipient of minted LP shares.
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
        uint256 deadline
    ) external override returns (uint128 liquidity, PoolKey memory poolKey) {
        uint256 amount0Desired;
        uint256 amount1Desired;
        PoolKey memory preparedKey;
        (amount0Desired, amount1Desired, preparedKey) =
            _prepareCreatePoolAndAddLiquidityExecution(tokenA, tokenB, amountADesired, amountBDesired, deadline);
        _pullAndApproveAddLiquidityBudgets(
            preparedKey.currency0, preparedKey.currency1, amount0Desired, amount1Desired, msg.sender
        );
        poolManager.initialize(preparedKey, startPrice);
        liquidity = _addLiquidityViaHook(preparedKey, amount0Desired, amount1Desired, 0, 0, recipient, msg.sender);
        poolKey = preparedKey;
    }

    /// @notice Initialize a hook-backed pool after funding one or two ERC20 inputs through Permit2.
    /// @dev After Permit2 funding succeeds, execution follows the same path as `createPoolAndAddLiquidity(...)`.
    /// @custom:security The batch Permit2 payload must align with the ERC20 sides of the bootstrap pair.
    /// @param permitParams Permit2 batch-transfer parameters that fund the ERC20 bootstrap legs.
    /// @param tokenA One side of the pool pair.
    /// @param tokenB The other side of the pool pair.
    /// @param amountADesired Desired budget for `tokenA`.
    /// @param amountBDesired Desired budget for `tokenB`.
    /// @param startPrice The initial `sqrtPriceX96` passed to the pool manager.
    /// @param recipient Recipient of minted LP shares.
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
        uint256 deadline
    ) external override returns (uint128 liquidity, PoolKey memory poolKey) {
        uint256 amount0Desired;
        uint256 amount1Desired;
        PoolKey memory preparedKey;
        (amount0Desired, amount1Desired, preparedKey) =
            _prepareCreatePoolAndAddLiquidityExecution(tokenA, tokenB, amountADesired, amountBDesired, deadline);
        _pullCurrenciesWithPermit2(
            permitParams,
            msg.sender,
            tokenA,
            tokenB,
            amountADesired,
            amountBDesired,
            _createPoolAndAddLiquidityPermit2Witness(
                tokenA, tokenB, amountADesired, amountBDesired, startPrice, recipient, deadline
            ),
            CREATE_POOL_WITNESS_TYPE_STRING
        );
        _approvePreparedAddLiquidityBudgets(
            preparedKey.currency0, preparedKey.currency1, amount0Desired, amount1Desired
        );
        poolManager.initialize(preparedKey, startPrice);
        liquidity = _addLiquidityViaHook(preparedKey, amount0Desired, amount1Desired, 0, 0, recipient, msg.sender);
        poolKey = preparedKey;
    }

    /// @dev Executes the actual swap during the manager unlock window and settles the caller delta.
    function _unlockCallback(bytes calldata rawData) internal override returns (bytes memory) {
        CallbackData memory data = abi.decode(rawData, (CallbackData));

        BalanceDelta delta = poolManager.swap(data.key, data.params, data.hookData);
        int128 amount0 = delta.amount0();
        int128 amount1 = delta.amount1();

        if (amount0 < 0) {
            data.key.currency0.settle(poolManager, data.payer, uint256((-amount0).toUint128()), false);
        }
        if (amount1 < 0) {
            data.key.currency1.settle(poolManager, data.payer, uint256((-amount1).toUint128()), false);
        }
        if (amount0 > 0) {
            data.key.currency0.take(poolManager, data.recipient, uint256(amount0.toUint128()), false);
        }
        if (amount1 > 0) {
            data.key.currency1.take(poolManager, data.recipient, uint256(amount1.toUint128()), false);
        }

        return abi.encode(delta);
    }

    function _swap(
        PoolKey calldata key,
        SwapParams calldata params,
        address recipient,
        uint256 deadline,
        uint256 amountOutMinimum,
        uint256 amountInMaximum,
        bytes calldata hookData,
        address payer,
        Currency inputCurrency,
        uint256 inputBudget
    ) internal beforeDeadline(deadline) returns (BalanceDelta delta) {
        if (address(key.hooks) != address(hook)) revert InvalidHook();
        if (params.amountSpecified == 0) revert SwapAmountCannotBeZero();
        if (params.amountSpecified > 0 && amountInMaximum == 0) revert AmountInMaximumRequired();

        delta = abi.decode(
            poolManager.unlock(
                abi.encode(
                    CallbackData({
                        payer: address(this), recipient: recipient, key: key, params: params, hookData: hookData
                    })
                )
            ),
            (BalanceDelta)
        );

        uint256 actualInputAmount = _actualInputAmount(delta, params.zeroForOne);
        if (amountInMaximum > 0 && actualInputAmount > amountInMaximum) {
            revert InputAmountExceedsMaximum(actualInputAmount, amountInMaximum);
        }
        uint256 minimumOutput = amountOutMinimum;
        if (params.amountSpecified > 0) {
            uint256 requestedOutput = uint256(params.amountSpecified);
            if (minimumOutput < requestedOutput) minimumOutput = requestedOutput;
        }
        if (minimumOutput > 0) {
            uint256 actualOutputAmount = _actualOutputAmount(delta, params.zeroForOne);
            if (actualOutputAmount < minimumOutput) {
                revert OutputAmountBelowMinimum(actualOutputAmount, minimumOutput);
            }
        }

        _refundUnusedInput(inputCurrency, payer, inputBudget, actualInputAmount);
        return delta;
    }

    function _pullCurrency(Currency currency, address from, uint256 amount) internal {
        if (amount == 0) return;
        if (!IERC20Minimal(Currency.unwrap(currency)).transferFrom(from, address(this), amount)) {
            revert IMemeverseUniswapHook.ERC20TransferFailed();
        }
    }

    function _prepareSwapPermit2Input(
        IMemeverseSwapRouter.Permit2SingleParams calldata permitParams,
        PoolKey calldata key,
        SwapParams calldata params,
        address recipient,
        uint256 deadline,
        uint256 amountOutMinimum,
        uint256 amountInMaximum,
        bytes calldata hookData,
        Currency inputCurrency,
        uint256 inputBudget
    ) internal {
        if (inputBudget == 0) return;

        _pullCurrencyWithPermit2(
            permitParams,
            msg.sender,
            Currency.unwrap(inputCurrency),
            inputBudget,
            _swapPermit2Witness(key, params, recipient, deadline, amountOutMinimum, amountInMaximum, hookData),
            SWAP_WITNESS_TYPE_STRING
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
        if (permitParams.permit.permitted.length != 2 || permitParams.transferDetails.length != 2) {
            revert InvalidPermit2Length();
        }

        _validatePermit2BatchEntry(permitParams, 0, token0, amount0);
        _validatePermit2BatchEntry(permitParams, 1, token1, amount1);

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

    function _resolveAddLiquidityExecutionContext(Currency currency0, Currency currency1, uint256 deadline)
        internal
        view
        beforeDeadline(deadline)
        returns (PoolKey memory key)
    {
        key = _hookPoolKey(currency0, currency1);
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
    ) internal beforeDeadline(deadline) returns (BalanceDelta delta) {
        PoolKey memory key = _hookPoolKey(currency0, currency1);
        if (!liquidityPrepared) {
            (address liquidityToken,,) = hook.poolInfo(key.toId());
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

    function _prepareCreatePoolAndAddLiquidityExecution(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 deadline
    )
        internal
        view
        beforeDeadline(deadline)
        differentTokens(tokenA, tokenB)
        returns (uint256 amount0Desired, uint256 amount1Desired, PoolKey memory poolKey)
    {
        (Currency currency0, Currency currency1, bool tokenAIsCurrency0) = _sortedCurrencies(tokenA, tokenB);
        amount0Desired = tokenAIsCurrency0 ? amountADesired : amountBDesired;
        amount1Desired = tokenAIsCurrency0 ? amountBDesired : amountADesired;
        poolKey = _hookPoolKey(currency0, currency1);
    }

    function _addLiquidityViaHook(
        PoolKey memory key,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        address to,
        address payer
    ) internal returns (uint128 liquidity) {
        BalanceDelta delta;
        (liquidity, delta) = hook.addLiquidityCore(
            IMemeverseUniswapHook.AddLiquidityCoreParams({
                currency0: key.currency0,
                currency1: key.currency1,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                to: to
            })
        );

        _handleAddLiquiditySettlement(
            key.currency0, key.currency1, delta, amount0Desired, amount1Desired, amount0Min, amount1Min, payer
        );
    }

    function _pullAndApproveAddLiquidityBudgets(
        Currency currency0,
        Currency currency1,
        uint256 amount0Desired,
        uint256 amount1Desired,
        address payer
    ) internal {
        _prepareCurrencyBudget(currency0, payer, amount0Desired);
        _prepareCurrencyBudget(currency1, payer, amount1Desired);
    }

    function _approvePreparedAddLiquidityBudgets(
        Currency currency0,
        Currency currency1,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) internal {
        _ensureHookApproval(currency0, amount0Desired);
        _ensureHookApproval(currency1, amount1Desired);
    }

    function _handleAddLiquiditySettlement(
        Currency currency0,
        Currency currency1,
        BalanceDelta delta,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        address payer
    ) internal {
        (uint256 amount0Used, uint256 amount1Used) = _spentLiquidityAmounts(delta);
        if (amount0Used < amount0Min || amount1Used < amount1Min) {
            revert IMemeverseUniswapHook.TooMuchSlippage();
        }

        _refundUnusedInput(currency0, payer, amount0Desired, amount0Used);
        _refundUnusedInput(currency1, payer, amount1Desired, amount1Used);
    }

    function _ensureHookApproval(Currency currency, uint256 amount) internal {
        if (amount == 0) return;
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
        if (desiredAmount <= usedAmount) return;
        unchecked {
            _transferCurrency(currency, recipient, desiredAmount - usedAmount);
        }
    }

    function _swapInputContext(PoolKey calldata key, SwapParams calldata params, uint256 amountInMaximum)
        internal
        pure
        returns (Currency inputCurrency, uint256 inputBudget)
    {
        inputCurrency = _inputCurrency(key, params.zeroForOne);
        inputBudget = _swapInputBudget(params, amountInMaximum);
    }

    function _swapInputBudget(SwapParams calldata params, uint256 amountInMaximum) internal pure returns (uint256) {
        if (params.amountSpecified < 0) return uint256(-params.amountSpecified);
        return amountInMaximum;
    }

    function _inputCurrency(PoolKey calldata key, bool zeroForOne) internal pure returns (Currency) {
        return zeroForOne ? key.currency0 : key.currency1;
    }

    function _sortedCurrencies(address tokenA, address tokenB)
        internal
        pure
        returns (Currency currency0, Currency currency1, bool tokenAIsCurrency0)
    {
        tokenAIsCurrency0 = tokenA < tokenB;
        currency0 = Currency.wrap(tokenAIsCurrency0 ? tokenA : tokenB);
        currency1 = Currency.wrap(tokenAIsCurrency0 ? tokenB : tokenA);
    }

    function _hookPoolKey(Currency currency0, Currency currency1)
        internal
        view
        erc20Pair(currency0, currency1)
        returns (PoolKey memory)
    {
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
        amount0Used = uint256((-delta.amount0()).toUint128());
        amount1Used = uint256((-delta.amount1()).toUint128());
    }

    function _receivedLiquidityAmounts(BalanceDelta delta)
        internal
        pure
        returns (uint256 amount0Received, uint256 amount1Received)
    {
        amount0Received = uint256(delta.amount0().toUint128());
        amount1Received = uint256(delta.amount1().toUint128());
    }

    function _actualInputAmount(BalanceDelta delta, bool zeroForOne) internal pure returns (uint256) {
        return zeroForOne ? uint256((-delta.amount0()).toUint128()) : uint256((-delta.amount1()).toUint128());
    }

    function _actualOutputAmount(BalanceDelta delta, bool zeroForOne) internal pure returns (uint256) {
        return zeroForOne ? uint256(delta.amount1().toUint128()) : uint256(delta.amount0().toUint128());
    }

    function _swapPermit2Witness(
        PoolKey calldata key,
        SwapParams calldata params,
        address recipient,
        uint256 deadline,
        uint256 amountOutMinimum,
        uint256 amountInMaximum,
        bytes calldata hookData
    ) internal pure returns (bytes32 witness) {
        witness = keccak256(
            abi.encode(
                SWAP_WITNESS_TYPEHASH,
                key.toId(),
                params.zeroForOne,
                params.amountSpecified,
                params.sqrtPriceLimitX96,
                recipient,
                deadline,
                amountOutMinimum,
                amountInMaximum,
                keccak256(hookData)
            )
        );
    }

    function _addLiquidityPermit2Witness(
        Currency currency0,
        Currency currency1,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        address to,
        uint256 deadline
    ) internal pure returns (bytes32 witness) {
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
                deadline
            )
        );
    }

    function _removeLiquidityPermit2Witness(
        Currency currency0,
        Currency currency1,
        uint128 liquidity,
        uint256 amount0Min,
        uint256 amount1Min,
        address to,
        uint256 deadline
    ) internal pure returns (bytes32 witness) {
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
    }

    function _createPoolAndAddLiquidityPermit2Witness(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint160 startPrice,
        address recipient,
        uint256 deadline
    ) internal pure returns (bytes32 witness) {
        witness = keccak256(
            abi.encode(
                CREATE_POOL_WITNESS_TYPEHASH,
                tokenA,
                tokenB,
                amountADesired,
                amountBDesired,
                startPrice,
                recipient,
                deadline
            )
        );
    }

    function _transferCurrency(Currency currency, address to, uint256 amount) internal {
        if (amount == 0) return;
        if (!IERC20Minimal(Currency.unwrap(currency)).transfer(to, amount)) {
            revert IMemeverseUniswapHook.ERC20TransferFailed();
        }
    }

    function _revertIfNativeCurrencyUnsupported(Currency currency0, Currency currency1) internal pure {
        if (currency0.isAddressZero() || currency1.isAddressZero()) {
            revert IMemeverseUniswapHook.NativeCurrencyUnsupported();
        }
    }
}
