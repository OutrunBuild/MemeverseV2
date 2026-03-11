# IMemeverseUniswapHook
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/162e33593b63cbed2f42e2c0d082c8afbd5ba111/src/verse/interfaces/IMemeverseUniswapHook.sol)

**Title:**
IMemeverseUniswapHook

Interface for the Memeverse Uniswap v4 Hook.

Defines shared types, events, and external entrypoints used by the hook implementation.


## Functions
### updateUserSnapshot

Updates a user’s fee accounting snapshot to the current pool values.

Implementations typically accrue newly earned fees into a pending balance and refresh offsets.


```solidity
function updateUserSnapshot(PoolId id, address user) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`id`|`PoolId`|The pool id.|
|`user`|`address`|The user address.|


## Events
### TreasuryUpdated
Emitted when the treasury address is updated.


```solidity
event TreasuryUpdated(address oldTreasury, address newTreasury);
```

### ProtocolFeeCurrencyUpdated
Emitted when the protocol-fee currency allowlist is updated.


```solidity
event ProtocolFeeCurrencyUpdated(Currency indexed currency, bool indexed enabled);
```

### AntiSnipeDurationUpdated
Emitted when the anti-snipe duration (in blocks) is updated.


```solidity
event AntiSnipeDurationUpdated(uint256 oldDuration, uint256 newDuration);
```

### MaxAntiSnipeProbabilityBaseUpdated
Emitted when the maximum probability base for anti-snipe checks is updated.


```solidity
event MaxAntiSnipeProbabilityBaseUpdated(uint256 oldBase, uint256 newBase);
```

### PoolInitialized
Emitted when a pool is initialized


```solidity
event PoolInitialized(
    PoolId indexed poolId,
    address indexed liquidityToken,
    Currency indexed currency0,
    Currency currency1,
    uint96 antiSnipeEndBlock
);
```

### ProtocolFeeCollected
Emitted when protocol fees are collected


```solidity
event ProtocolFeeCollected(
    PoolId indexed poolId, Currency indexed currency, address indexed treasury, uint256 amount, uint256 blockNumber
);
```

### LPFeeCollected
Emitted when LP fees are collected


```solidity
event LPFeeCollected(
    PoolId indexed poolId, Currency indexed currency, uint256 amount, uint256 feePerShare, uint256 blockNumber
);
```

### LiquidityAdded
Emitted when liquidity is added to a pool


```solidity
event LiquidityAdded(
    PoolId indexed poolId,
    address indexed provider,
    address indexed to,
    uint128 liquidity,
    uint256 amount0,
    uint256 amount1
);
```

### LiquidityRemoved
Emitted when liquidity is removed from a pool


```solidity
event LiquidityRemoved(
    PoolId indexed poolId, address indexed provider, uint128 liquidity, uint256 amount0, uint256 amount1
);
```

### FeesClaimed
Emitted when a user claims their LP fees


```solidity
event FeesClaimed(
    PoolId indexed poolId,
    address indexed user,
    Currency indexed currency0,
    Currency currency1,
    uint256 fee0Amount,
    uint256 fee1Amount
);
```

### DynamicFeeUpdated
Emitted when the dynamic fee is updated.


```solidity
event DynamicFeeUpdated(uint256 indexed oldFeeBps, uint256 indexed newFeeBps);
```

### SwapBlocked
Emitted when a swap is blocked by anti-snipe protection


```solidity
event SwapBlocked(
    PoolId indexed poolId,
    address indexed trader,
    Currency indexed currencyIn,
    uint256 amountSpecified,
    uint256 blockNumber,
    uint8 reason
);
```

**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`poolId`|`PoolId`||
|`trader`|`address`||
|`currencyIn`|`Currency`||
|`amountSpecified`|`uint256`||
|`blockNumber`|`uint256`||
|`reason`|`uint8`|Failure reason enum value (uint8): 0=None (passed), 1=BlockAlreadyHasSuccessfulSwap (block already has successful swap), 2=NoPriceLimitSet (no price limit set), 3=SlippageExceedsMaximum (slippage exceeds maximum limit), 4=ProbabilityCheckFailed (probability check failed)|

### SwapAllowed
Emitted when a swap passes anti-snipe checks


```solidity
event SwapAllowed(
    PoolId indexed poolId,
    address indexed trader,
    Currency indexed currencyIn,
    uint256 amountSpecified,
    uint256 blockNumber,
    uint256 attempts
);
```

## Errors
### PoolNotInitialized
Reverts when a pool has not been initialized by the hook.


```solidity
error PoolNotInitialized();
```

### TickSpacingNotDefault
Reverts when the pool tickSpacing is not the expected default.


```solidity
error TickSpacingNotDefault();
```

### FeeMustBeDynamic
Reverts when the pool fee configuration is not set to dynamic fee.


```solidity
error FeeMustBeDynamic();
```

### LiquidityDoesntMeetMinimum
Reverts when initial liquidity does not meet the minimum requirement.


```solidity
error LiquidityDoesntMeetMinimum();
```

### SenderMustBeHook
Reverts when a restricted hook-only function is called by an external sender.


```solidity
error SenderMustBeHook();
```

### ExpiredPastDeadline
Reverts when `deadline` is in the past.


```solidity
error ExpiredPastDeadline();
```

### TooMuchSlippage
Reverts when actual amounts are worse than user-provided minimums.


```solidity
error TooMuchSlippage();
```

### CurrencyNotSupported
Reverts when a given currency is not supported by configuration.


```solidity
error CurrencyNotSupported();
```

### Unauthorized
Reverts when the caller is not authorized.


```solidity
error Unauthorized();
```

## Structs
### PoolInfo
Pool information tracked by the hook.


```solidity
struct PoolInfo {
    /// @notice Custom ERC20 LP token address for this pool.
    address liquidityToken;
    /// @notice Block number when anti-snipe protection ends.
    uint96 antiSnipeEndBlock;
    /// @notice Accumulated LP fees for currency0 (per share, scaled by PRECISION in the implementation).
    uint256 fee0PerShare;
    /// @notice Accumulated LP fees for currency1 (per share, scaled by PRECISION in the implementation).
    uint256 fee1PerShare;
}
```

### AntiSnipeBlockData
Anti-snipe state tracked per block per pool.


```solidity
struct AntiSnipeBlockData {
    /// @notice Total number of swap attempts observed in this block.
    uint248 attempts;
    /// @notice Whether this block already has a successful swap.
    bool successful;
}
```

### UserFeeState
Per-user fee accounting state for a pool.


```solidity
struct UserFeeState {
    /// @notice Snapshot offset of `fee0PerShare` at the last user update.
    uint256 fee0Offset;
    /// @notice Snapshot offset of `fee1PerShare` at the last user update.
    uint256 fee1Offset;
    /// @notice Earned but unclaimed currency0 fees.
    uint256 pendingFee0;
    /// @notice Earned but unclaimed currency1 fees.
    uint256 pendingFee1;
}
```

### AddLiquidityParams
Parameters for adding liquidity.


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

### RemoveLiquidityParams
Parameters for removing liquidity.


```solidity
struct RemoveLiquidityParams {
    Currency currency0;
    Currency currency1;
    uint24 fee;
    uint128 liquidity;
    uint128 deadline;
}
```

## Enums
### AntiSnipeFailureReason
Enumeration of anti-snipe check failure reasons.


```solidity
enum AntiSnipeFailureReason {
    /// @notice Check passed.
    None, // 0
    /// @notice This block already contains a successful swap (only one success allowed per block).
    BlockAlreadyHasSuccessfulSwap, // 1
    /// @notice The swap did not set a sqrtPriceLimitX96.
    NoPriceLimitSet, // 2
    /// @notice The user-provided price limit implies slippage above the hook’s maximum.
    SlippageExceedsMaximum, // 3
    /// @notice Randomized anti-snipe probability check failed.
    ProbabilityCheckFailed // 4
}
```

