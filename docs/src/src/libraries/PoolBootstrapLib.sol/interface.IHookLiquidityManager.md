# IHookLiquidityManager
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/5f1e475fc32b5b93b8a81ca9d545cacad2f7567c/src/libraries/PoolBootstrapLib.sol)


## Functions
### addLiquidityCore


```solidity
function addLiquidityCore(AddLiquidityCoreParams calldata params)
    external
    payable
    returns (uint128 liquidity, BalanceDelta delta);
```

## Structs
### AddLiquidityCoreParams

```solidity
struct AddLiquidityCoreParams {
    Currency currency0;
    Currency currency1;
    uint256 amount0Desired;
    uint256 amount1Desired;
    address to;
}
```

