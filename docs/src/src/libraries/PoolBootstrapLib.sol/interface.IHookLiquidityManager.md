# IHookLiquidityManager
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/f6152b6dbfadcd8a23a2d518905418243cf2a5e1/src/libraries/PoolBootstrapLib.sol)


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

