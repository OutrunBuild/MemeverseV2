# IHookLiquidityManager
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/162e33593b63cbed2f42e2c0d082c8afbd5ba111/src/libraries/LiquidityManager.sol)


## Functions
### addLiquidity


```solidity
function addLiquidity(AddLiquidityParams calldata params) external returns (uint128 liquidity);
```

## Structs
### AddLiquidityParams

```solidity
struct AddLiquidityParams {
    Currency currency0;
    Currency currency1;
    uint24 fee;
    uint256 amount0Desired;
    uint256 amount1Desired;
    uint256 amount0Min;
    uint256 amount1Min;
    address to;
    uint256 deadline;
}
```

