# PoolBootstrapLib
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/5f1e475fc32b5b93b8a81ca9d545cacad2f7567c/src/libraries/PoolBootstrapLib.sol)

**Title:**
PoolBootstrapLib

Bootstrap helpers for initializing Memeverse-compatible pools and seeding first liquidity.


## State Variables
### TICK_SPACING

```solidity
int24 public constant TICK_SPACING = 200
```


### TICK_LOWER

```solidity
int24 public constant TICK_LOWER = -887200
```


### TICK_UPPER

```solidity
int24 public constant TICK_UPPER = 887200
```


### SQRT_PRICE_LOWER_X96

```solidity
uint160 public constant SQRT_PRICE_LOWER_X96 = 4310618292
```


### SQRT_PRICE_UPPER_X96

```solidity
uint160 public constant SQRT_PRICE_UPPER_X96 = 1456195216270955103206513029158776779468408838535
```


## Functions
### createPoolAndAddLiquidity


```solidity
function createPoolAndAddLiquidity(
    address tokenA,
    address tokenB,
    uint256 amountADesired,
    uint256 amountBDesired,
    address permit2,
    address positionManager,
    address recipient,
    IHooks hook
) internal returns (uint128 liquidity, PoolKey memory poolKey);
```

### mintLiquidityParams


```solidity
function mintLiquidityParams(
    PoolKey memory poolKey,
    int24 _tickLower,
    int24 _tickUpper,
    uint128 liquidity,
    uint128 amount0Max,
    uint128 amount1Max,
    address recipient,
    bytes memory hookData
) internal pure returns (bytes memory, bytes[] memory);
```

### tokenApprovalsForPermit2


```solidity
function tokenApprovalsForPermit2(address tokenA, address tokenB, address permit2, address positionManager)
    internal;
```

### tokenApprovalsToSpender


```solidity
function tokenApprovalsToSpender(address tokenA, address tokenB, address spender) internal;
```

### _poolFee


```solidity
function _poolFee(IHooks hook) private pure returns (uint24 fee);
```

### _toUint128WithDust


```solidity
function _toUint128WithDust(uint256 amount) private pure returns (uint128);
```

## Errors
### InvalidTokenPair

```solidity
error InvalidTokenPair();
```

### ZeroLiquidity

```solidity
error ZeroLiquidity();
```

### AmountExceedsUint128

```solidity
error AmountExceedsUint128();
```

