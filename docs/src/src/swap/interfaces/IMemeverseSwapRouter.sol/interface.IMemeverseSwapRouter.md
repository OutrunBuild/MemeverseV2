# IMemeverseSwapRouter
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/5f1e475fc32b5b93b8a81ca9d545cacad2f7567c/src/swap/interfaces/IMemeverseSwapRouter.sol)

**Title:**
IMemeverseSwapRouter

User-facing interface for the Memeverse swap router.

Exposes the router's quote, swap, liquidity, and fee-claim entrypoints and custom errors.


## Functions
### hook

Returns the configured Memeverse hook used by the router.

Useful for verifying the router is wired to the expected hook deployment.


```solidity
function hook() external view returns (IMemeverseUniswapHook memeverseHook);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`memeverseHook`|`IMemeverseUniswapHook`|The hook contract that owns anti-snipe and LP accounting logic.|


### quoteSwap

Returns the current swap quote from the underlying Memeverse hook.

Thin passthrough for router-first integrations.


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

Returns the anti-snipe failure-fee quote from the underlying Memeverse hook.

`inputBudget` is the total input budget reserved for either success or failure.


```solidity
function quoteFailedAttempt(PoolKey calldata key, SwapParams calldata params, uint256 inputBudget)
    external
    view
    returns (IMemeverseUniswapHook.FailedAttemptQuote memory quote);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`key`|`PoolKey`|The pool key being quoted.|
|`params`|`SwapParams`|The swap parameters being quoted.|
|`inputBudget`|`uint256`|The maximum total input budget reserved for the attempted swap.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`quote`|`IMemeverseUniswapHook.FailedAttemptQuote`|The quoted failure-fee amount, side, and recipient class.|


### swap

Executes a swap through the Memeverse hook's anti-snipe gate in a single transaction.

On anti-snipe soft-fail, the router returns with `executed == false` and a failure reason.

**Note:**
security: Callers should enforce slippage with `amountOutMinimum` or `amountInMaximum`, and must provide
a payable `nativeRefundRecipient` whenever native input is supplied.


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
|`amountOutMinimum`|`uint256`|The minimum net output the caller is willing to receive.|
|`amountInMaximum`|`uint256`|The maximum input the caller is willing to pay.|
|`hookData`|`bytes`|Opaque hook data forwarded to `poolManager.swap`.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`delta`|`BalanceDelta`|The final swap delta when executed, otherwise zero.|
|`executed`|`bool`|Whether the swap actually reached `poolManager.swap`.|
|`failureReason`|`IMemeverseUniswapHook.AntiSnipeFailureReason`|The anti-snipe failure reason when `executed` is false, otherwise `None`.|


### addLiquidity

Adds liquidity through the hook core entrypoint while applying router-level protections.

The router derives actual spend from the current pool price and refunds unused budget.

**Note:**
security: Callers must approve ERC20 inputs to the router before calling and set min amounts that match
their slippage tolerance.


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
) external payable returns (uint128 liquidity);
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

Removes liquidity through the hook core entrypoint while applying router-level protections.

The router burns LP shares, validates minimum outputs, and forwards underlying assets.

**Note:**
security: Callers must approve LP shares to the router and set output minimums to enforce slippage.


```solidity
function removeLiquidity(
    Currency currency0,
    Currency currency1,
    uint128 liquidity,
    uint256 amount0Min,
    uint256 amount1Min,
    address to,
    uint256 deadline
) external returns (BalanceDelta delta);
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

The caller may invoke this directly as owner or provide a signature for relay.

**Note:**
security: Non-owner relays must provide a valid signature in `v`, `r`, and `s`.


```solidity
function claimFees(PoolKey calldata key, address recipient, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
    external
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

Initializes a hook-backed pool and seeds its first full-range liquidity position.

The router sorts the token pair, initializes the pool price, adds liquidity, and refunds unused input.

**Note:**
security: Token addresses must be distinct, and native bootstrap calls require a payable refund
recipient whenever `msg.value` is supplied.


```solidity
function createPoolAndAddLiquidity(
    address tokenA,
    address tokenB,
    uint256 amountADesired,
    uint256 amountBDesired,
    address recipient,
    address nativeRefundRecipient,
    uint256 deadline
) external payable returns (uint128 liquidity, PoolKey memory poolKey);
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


## Errors
### InvalidHook
Reverts when the pool key does not use the configured Memeverse hook.


```solidity
error InvalidHook();
```

### ExpiredPastDeadline
Reverts when `deadline` has passed.


```solidity
error ExpiredPastDeadline();
```

### SwapAmountCannotBeZero
Reverts when the swap amount is zero.


```solidity
error SwapAmountCannotBeZero();
```

### AmountInMaximumRequired
Reverts when an exact-output swap omits `amountInMaximum`.


```solidity
error AmountInMaximumRequired();
```

### InputAmountExceedsMaximum
Reverts when the required input exceeds `amountInMaximum`.


```solidity
error InputAmountExceedsMaximum(uint256 actualInputAmount, uint256 amountInMaximum);
```

### OutputAmountBelowMinimum
Reverts when the received output is below `amountOutMinimum`.


```solidity
error OutputAmountBelowMinimum(uint256 actualOutputAmount, uint256 amountOutMinimum);
```

### InvalidTokenPair
Reverts when bootstrap uses identical token addresses.


```solidity
error InvalidTokenPair();
```

### InvalidNativeRefundRecipient
Reverts when native input is used without a refund recipient.


```solidity
error InvalidNativeRefundRecipient();
```

