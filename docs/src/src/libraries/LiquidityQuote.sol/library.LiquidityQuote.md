# LiquidityQuote
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/5f1e475fc32b5b93b8a81ca9d545cacad2f7567c/src/libraries/LiquidityQuote.sol)

**Title:**
LiquidityQuote

Shared quote helper for full-range liquidity adds in Memeverse hook-based pools.

Used by the hook Core, router, and bootstrap helpers to derive the same liquidity result and actual token
usage from a caller's desired token budgets at the current pool price.


## State Variables
### MIN_SQRT_PRICE_X96

```solidity
uint160 internal constant MIN_SQRT_PRICE_X96 = 4_310_618_292
```


### MAX_SQRT_PRICE_X96

```solidity
uint160 internal constant MAX_SQRT_PRICE_X96 = 1_456_195_216_270_955_103_206_513_029_158_776_779_468_408_838_535
```


## Functions
### quote

Quotes the full-range liquidity add result from desired token budgets.

Returns both the liquidity implied by the desired budgets and the actual token amounts consumed by that
liquidity at `sqrtPriceX96`.


```solidity
function quote(uint160 sqrtPriceX96, uint256 amount0Desired, uint256 amount1Desired)
    internal
    pure
    returns (uint128 liquidity, uint256 amount0Used, uint256 amount1Used);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`sqrtPriceX96`|`uint160`|The current pool sqrt price.|
|`amount0Desired`|`uint256`|The caller's budget for currency0.|
|`amount1Desired`|`uint256`|The caller's budget for currency1.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`liquidity`|`uint128`|The maximum full-range liquidity supported by the budgets.|
|`amount0Used`|`uint256`|The quoted amount of currency0 consumed by that liquidity.|
|`amount1Used`|`uint256`|The quoted amount of currency1 consumed by that liquidity.|


