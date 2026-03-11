# LiquidityAmounts
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/f6152b6dbfadcd8a23a2d518905418243cf2a5e1/src/libraries/LiquidityAmounts.sol)

**Title:**
LiquidityAmounts

Internal liquidity math helpers for full-range and bounded-range Uniswap-style positions.

This is a production-owned copy of the standard liquidity amount formulas so Memeverse code does not depend
on upstream test utilities.


## Functions
### getLiquidityForAmount0

Computes the liquidity supported by a token0 amount across a price range.


```solidity
function getLiquidityForAmount0(uint160 sqrtPriceAX96, uint160 sqrtPriceBX96, uint256 amount0)
    internal
    pure
    returns (uint128 liquidity);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`sqrtPriceAX96`|`uint160`|One boundary sqrt price.|
|`sqrtPriceBX96`|`uint160`|The other boundary sqrt price.|
|`amount0`|`uint256`|The token0 amount.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`liquidity`|`uint128`|The supported liquidity.|


### getLiquidityForAmount1

Computes the liquidity supported by a token1 amount across a price range.


```solidity
function getLiquidityForAmount1(uint160 sqrtPriceAX96, uint160 sqrtPriceBX96, uint256 amount1)
    internal
    pure
    returns (uint128 liquidity);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`sqrtPriceAX96`|`uint160`|One boundary sqrt price.|
|`sqrtPriceBX96`|`uint160`|The other boundary sqrt price.|
|`amount1`|`uint256`|The token1 amount.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`liquidity`|`uint128`|The supported liquidity.|


### getLiquidityForAmounts

Computes the maximum liquidity supported by token budgets at a current pool price.


```solidity
function getLiquidityForAmounts(
    uint160 sqrtPriceX96,
    uint160 sqrtPriceAX96,
    uint160 sqrtPriceBX96,
    uint256 amount0,
    uint256 amount1
) internal pure returns (uint128 liquidity);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`sqrtPriceX96`|`uint160`|The current pool sqrt price.|
|`sqrtPriceAX96`|`uint160`|One boundary sqrt price.|
|`sqrtPriceBX96`|`uint160`|The other boundary sqrt price.|
|`amount0`|`uint256`|The token0 budget.|
|`amount1`|`uint256`|The token1 budget.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`liquidity`|`uint128`|The supported liquidity.|


### getAmount0ForLiquidity

Computes the token0 amount represented by liquidity over a price range.


```solidity
function getAmount0ForLiquidity(uint160 sqrtPriceAX96, uint160 sqrtPriceBX96, uint128 liquidity)
    internal
    pure
    returns (uint256 amount0);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`sqrtPriceAX96`|`uint160`|One boundary sqrt price.|
|`sqrtPriceBX96`|`uint160`|The other boundary sqrt price.|
|`liquidity`|`uint128`|The liquidity amount.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`amount0`|`uint256`|The token0 amount represented by `liquidity`.|


### getAmount1ForLiquidity

Computes the token1 amount represented by liquidity over a price range.


```solidity
function getAmount1ForLiquidity(uint160 sqrtPriceAX96, uint160 sqrtPriceBX96, uint128 liquidity)
    internal
    pure
    returns (uint256 amount1);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`sqrtPriceAX96`|`uint160`|One boundary sqrt price.|
|`sqrtPriceBX96`|`uint160`|The other boundary sqrt price.|
|`liquidity`|`uint128`|The liquidity amount.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`amount1`|`uint256`|The token1 amount represented by `liquidity`.|


### getAmountsForLiquidity

Computes the token0 and token1 amounts represented by liquidity at a current pool price.


```solidity
function getAmountsForLiquidity(
    uint160 sqrtPriceX96,
    uint160 sqrtPriceAX96,
    uint160 sqrtPriceBX96,
    uint128 liquidity
) internal pure returns (uint256 amount0, uint256 amount1);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`sqrtPriceX96`|`uint160`|The current pool sqrt price.|
|`sqrtPriceAX96`|`uint160`|One boundary sqrt price.|
|`sqrtPriceBX96`|`uint160`|The other boundary sqrt price.|
|`liquidity`|`uint128`|The liquidity amount.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`amount0`|`uint256`|The token0 amount represented by `liquidity`.|
|`amount1`|`uint256`|The token1 amount represented by `liquidity`.|


