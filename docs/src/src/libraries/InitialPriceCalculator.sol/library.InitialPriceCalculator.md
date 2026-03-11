# InitialPriceCalculator
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/5f1e475fc32b5b93b8a81ca9d545cacad2f7567c/src/libraries/InitialPriceCalculator.sol)

**Title:**
InitialPriceCalculator for Uniswap V4


## Functions
### calculateInitialSqrtPriceX96

Calculates the initial sqrtPriceX96 for pool creation based on the provided token amounts

The resulting price satisfies P = (amount1 / amount0)^2, ensuring both token amounts are fully utilized
(applicable for wide-range or full-range initial positions)


```solidity
function calculateInitialSqrtPriceX96(uint256 amount0Desired, uint256 amount1Desired)
    internal
    pure
    returns (uint160 sqrtPriceX96);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`amount0Desired`|`uint256`|The desired amount of token0 to provide (adjusted for decimals)|
|`amount1Desired`|`uint256`|The desired amount of token1 to provide (adjusted for decimals)|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`sqrtPriceX96`|`uint160`|The initial sqrt(price) in Q64.96 format (sqrt(price) × 2^96)|


## Errors
### ZeroInput

```solidity
error ZeroInput();
```

### PriceX96Overflow

```solidity
error PriceX96Overflow();
```

