# MemeverseSwapRouter
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/f6152b6dbfadcd8a23a2d518905418243cf2a5e1/src/swap/MemeverseSwapRouter.sol)

**Inherits:**
SafeCallback, [IMemeverseSwapRouter](/src/swap/interfaces/IMemeverseSwapRouter.sol/interface.IMemeverseSwapRouter.md)

**Title:**
MemeverseSwapRouter

Recommended single public periphery entrypoint for Memeverse swap and LP flows.

On anti-snipe soft-fail, the router returns successfully without calling `poolManager.swap`, so attempts persist
while the trade does not execute. During the protection window, failed attempts may still charge an input-side
failure fee from the same single input budget used by the swap. Outside the anti-snipe window, the router skips attempt recording and routes directly to
`poolManager.swap`. For exact-output swaps, callers are expected to source `amountInMaximum` from
`MemeverseSwapRouter.quoteSwap()` or a stricter front-end slippage policy.
The underlying hook remains callable as a Core API for custom routers and integrators, but this router is the
intended canonical entrypoint for end-user and on-chain SDK integrations, covering quote, swap, LP, fee claim,
and hook-backed pool bootstrap flows.


## State Variables
### hook

```solidity
IMemeverseUniswapHook public immutable hook
```


## Functions
### constructor


```solidity
constructor(IPoolManager _manager, IMemeverseUniswapHook _hook) SafeCallback(_manager);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_manager`|`IPoolManager`|The Uniswap v4 pool manager.|
|`_hook`|`IMemeverseUniswapHook`|The Memeverse hook that owns anti-snipe attempt tracking for routed swaps.|


### quoteSwap

Returns the current swap quote from the underlying Memeverse hook.

This is a thin passthrough so integrators can treat the router as the single public entrypoint.


```solidity
function quoteSwap(PoolKey calldata key, SwapParams calldata params)
    external
    view
    returns (IMemeverseUniswapHook.SwapQuote memory quote);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`key`|`PoolKey`|The pool key being quoted.|
|`params`|`SwapParams`|The swap parameters being quoted.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`quote`|`IMemeverseUniswapHook.SwapQuote`|The projected fee amounts, side, and estimated user flows.|


### quoteFailedAttempt

Returns the current anti-snipe failure-fee quote from the underlying Memeverse hook.

This is a thin passthrough so integrators can estimate the protection-window failure fee via the router.
`inputBudget` is the single total input budget that will be used for either success or failure.


```solidity
function quoteFailedAttempt(PoolKey calldata key, SwapParams calldata params, uint256 inputBudget)
    external
    view
    returns (IMemeverseUniswapHook.FailedAttemptQuote memory quote);
```

### swap

Executes a swap through the Memeverse hook's anti-snipe gate in a single transaction.

If anti-snipe soft-fails, the function returns `(ZERO_DELTA, false, reason)` and does not call
`poolManager.swap`. During the protection window the router prepares a single input budget for the trade:
on failure part of that budget is consumed as an input-side failure fee, while on success the same budget is
used to execute the swap and only any unused remainder is refunded. Any unused native input is refunded to `nativeRefundRecipient`, which allows
non-payable contract callers to preserve soft-fail attempt recording while routing refunds to a payable address.


```solidity
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
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`key`|`PoolKey`|The pool key to swap against.|
|`params`|`SwapParams`|The swap parameters.|
|`recipient`|`address`|The address receiving any swap output.|
|`nativeRefundRecipient`|`address`|The address receiving any unused native input when `msg.value` is attached.|
|`deadline`|`uint256`|The latest timestamp at which the call is valid.|
|`amountOutMinimum`|`uint256`|The minimum net output the caller is willing to receive. Required for exact-input protection.|
|`amountInMaximum`|`uint256`|The maximum input the caller is willing to pay. Required for exact-output swaps.|
|`hookData`|`bytes`|Opaque hook data forwarded to `poolManager.swap`.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`delta`|`BalanceDelta`|The final swap delta when executed, otherwise zero.|
|`executed`|`bool`|Whether the swap actually reached `poolManager.swap`.|
|`failureReason`|`IMemeverseUniswapHook.AntiSnipeFailureReason`|The anti-snipe failure reason when `executed` is false, otherwise `None`.|


### addLiquidity

Adds liquidity through the hook core entrypoint while applying periphery protections.

Pulls the caller's desired ERC20 budgets into the router, derives the actual full-range spend at the
current pool price, forwards only the exact required native amount to the hook core, validates min amounts,
and refunds any unused input budget to `nativeRefundRecipient`. This path is separate from the swap
protection-window budget logic.


```solidity
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
) external payable override returns (uint128 liquidity);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`currency0`|`Currency`|Pool currency0.|
|`currency1`|`Currency`|Pool currency1.|
|`amount0Desired`|`uint256`|Desired currency0 budget.|
|`amount1Desired`|`uint256`|Desired currency1 budget.|
|`amount0Min`|`uint256`|Minimum currency0 spend accepted.|
|`amount1Min`|`uint256`|Minimum currency1 spend accepted.|
|`to`|`address`|Recipient of minted LP shares.|
|`nativeRefundRecipient`|`address`|Recipient of any unused native refund.|
|`deadline`|`uint256`|The latest timestamp at which the call is valid.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`liquidity`|`uint128`|The LP liquidity minted to `to`.|


### removeLiquidity

Removes liquidity through the hook core entrypoint while applying periphery protections.

Pulls LP shares into the router, calls the hook core, validates minimum outputs, and forwards the assets.


```solidity
function removeLiquidity(
    Currency currency0,
    Currency currency1,
    uint128 liquidity,
    uint256 amount0Min,
    uint256 amount1Min,
    address to,
    uint256 deadline
) external override returns (BalanceDelta delta);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`currency0`|`Currency`|Pool currency0.|
|`currency1`|`Currency`|Pool currency1.|
|`liquidity`|`uint128`|LP liquidity to burn.|
|`amount0Min`|`uint256`|Minimum currency0 output accepted.|
|`amount1Min`|`uint256`|Minimum currency1 output accepted.|
|`to`|`address`|Recipient of withdrawn assets.|
|`deadline`|`uint256`|The latest timestamp at which the call is valid.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`delta`|`BalanceDelta`|The balance delta returned by the hook core.|


### claimFees

Claims pending LP fees for the caller through the hook core entrypoint.

The caller may either invoke this directly as owner or provide a signature so the router can relay the claim.


```solidity
function claimFees(PoolKey calldata key, address recipient, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
    external
    override
    returns (uint256 fee0Amount, uint256 fee1Amount);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`key`|`PoolKey`|The pool key whose fees are being claimed.|
|`recipient`|`address`|Recipient of the claimed fees.|
|`deadline`|`uint256`|The latest timestamp at which the signature remains valid.|
|`v`|`uint8`|Signature `v`.|
|`r`|`bytes32`|Signature `r`.|
|`s`|`bytes32`|Signature `s`.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`fee0Amount`|`uint256`|The claimed amount of currency0 fees.|
|`fee1Amount`|`uint256`|The claimed amount of currency1 fees.|


### createPoolAndAddLiquidity

Initializes a hook-backed pool and seeds its first full-range liquidity position through the hook core.

Pulls the caller's desired budgets, initializes the pool, derives the actual full-range spend, forwards
only the exact required native amount to the hook core, and refunds any unused input budget to
`nativeRefundRecipient`.


```solidity
function createPoolAndAddLiquidity(
    address tokenA,
    address tokenB,
    uint256 amountADesired,
    uint256 amountBDesired,
    address recipient,
    address nativeRefundRecipient,
    uint256 deadline
) external payable override returns (uint128 liquidity, PoolKey memory poolKey);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`tokenA`|`address`|One side of the pool pair.|
|`tokenB`|`address`|The other side of the pool pair.|
|`amountADesired`|`uint256`|Desired budget for `tokenA`.|
|`amountBDesired`|`uint256`|Desired budget for `tokenB`.|
|`recipient`|`address`|Recipient of minted LP shares.|
|`nativeRefundRecipient`|`address`|Recipient of any unused native refund.|
|`deadline`|`uint256`|The latest timestamp at which the call is valid.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`liquidity`|`uint128`|The minted LP liquidity.|
|`poolKey`|`PoolKey`|The initialized pool key.|


### _unlockCallback

Executes the actual swap during the manager unlock window and settles the caller delta.


```solidity
function _unlockCallback(bytes calldata rawData) internal override returns (bytes memory);
```

### receive


```solidity
receive() external payable;
```

### _pullCurrency


```solidity
function _pullCurrency(Currency currency, address from, uint256 amount) internal;
```

### _prepareCurrencyBudget


```solidity
function _prepareCurrencyBudget(Currency currency, address from, uint256 amount) internal;
```

### _addLiquidityViaHook


```solidity
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
) internal returns (uint128 liquidity);
```

### _ensureHookApproval


```solidity
function _ensureHookApproval(Currency currency, uint256 amount) internal;
```

### _refundUnusedInput


```solidity
function _refundUnusedInput(Currency currency, address recipient, uint256 desiredAmount, uint256 usedAmount)
    internal;
```

### _refundUnusedNative

Refunds only the per-call native surplus and never sweeps unrelated router balance.


```solidity
function _refundUnusedNative(address recipient, uint256 suppliedAmount, uint256 spentAmount) internal;
```

### _validatedNativeRefundRecipient


```solidity
function _validatedNativeRefundRecipient(address recipient, uint256 suppliedAmount)
    internal
    pure
    returns (address);
```

### _nativeAmountForPair


```solidity
function _nativeAmountForPair(Currency currency0, Currency currency1, uint256 amount0, uint256 amount1)
    internal
    pure
    returns (uint256);
```

### _nativeSwapBudget


```solidity
function _nativeSwapBudget(PoolKey calldata key, SwapParams calldata params, uint256 amountInMaximum)
    internal
    pure
    returns (uint256);
```

### _swapInputBudget


```solidity
function _swapInputBudget(SwapParams calldata params, uint256 amountInMaximum) internal pure returns (uint256);
```

### _inputCurrency


```solidity
function _inputCurrency(PoolKey calldata key, bool zeroForOne) internal pure returns (Currency);
```

### _hookPoolKey


```solidity
function _hookPoolKey(Currency currency0, Currency currency1) internal view returns (PoolKey memory);
```

### _spentLiquidityAmounts


```solidity
function _spentLiquidityAmounts(BalanceDelta delta)
    internal
    pure
    returns (uint256 amount0Used, uint256 amount1Used);
```

### _receivedLiquidityAmounts


```solidity
function _receivedLiquidityAmounts(BalanceDelta delta)
    internal
    pure
    returns (uint256 amount0Received, uint256 amount1Received);
```

### _actualInputAmount


```solidity
function _actualInputAmount(BalanceDelta delta, bool zeroForOne) internal pure returns (uint256);
```

### _actualOutputAmount


```solidity
function _actualOutputAmount(BalanceDelta delta, bool zeroForOne) internal pure returns (uint256);
```

### _nativeSwapInputSpent


```solidity
function _nativeSwapInputSpent(PoolKey calldata key, BalanceDelta delta) internal pure returns (uint256);
```

### _transferCurrency


```solidity
function _transferCurrency(Currency currency, address to, uint256 amount) internal;
```

## Structs
### CallbackData

```solidity
struct CallbackData {
    address payer;
    address recipient;
    PoolKey key;
    SwapParams params;
    bytes hookData;
}
```

