# IMemeverseUniswapHook
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/5f1e475fc32b5b93b8a81ca9d545cacad2f7567c/src/swap/interfaces/IMemeverseUniswapHook.sol)

**Title:**
IMemeverseUniswapHook

Interface for the Memeverse Uniswap v4 Hook.

Defines shared types, events, and external entrypoints used by the hook implementation.


## Functions
### requestSwapAttempt

Low-level anti-snipe primitive for routers and advanced integrators.

The returned `allowed` result is intended to be consumed by a router before it decides whether to proceed to
`poolManager.swap`. This is not a recommended end-user entrypoint.


```solidity
function requestSwapAttempt(
    PoolKey calldata key,
    SwapParams calldata params,
    address trader,
    uint256 inputBudget,
    address refundRecipient
) external payable returns (bool allowed, AntiSnipeFailureReason failureReason);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`key`|`PoolKey`|The pool key for the attempted swap.|
|`params`|`SwapParams`|The swap parameters for the attempted swap.|
|`trader`|`address`|The end user on whose behalf the router is attempting the swap.|
|`inputBudget`|`uint256`||
|`refundRecipient`|`address`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`allowed`|`bool`|Whether the attempt passed anti-snipe checks.|
|`failureReason`|`AntiSnipeFailureReason`|The anti-snipe failure reason when `allowed` is false, otherwise `None`.|


### quoteFailedAttempt

Returns the anti-snipe failure-fee quote for a swap attempt during the protection window.

The failure fee is always expressed on the input side. On failure, it routes entirely either to treasury or
LPs depending on whether the input currency equals the configured protocol-fee currency.


```solidity
function quoteFailedAttempt(PoolKey calldata key, SwapParams calldata params, uint256 inputBudget)
    external
    view
    returns (FailedAttemptQuote memory quote);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`key`|`PoolKey`|The pool key for the attempted swap.|
|`params`|`SwapParams`|The swap parameters for the attempted swap.|
|`inputBudget`|`uint256`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`quote`|`FailedAttemptQuote`|The quoted failure-fee amount, side, and recipient class.|


### isAntiSnipeActive

Low-level anti-snipe view helper for routers and SDK orchestration.


```solidity
function isAntiSnipeActive(PoolId poolId) external view returns (bool active);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`poolId`|`PoolId`|The pool id to query.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`active`|`bool`|Whether anti-snipe checks are still active for the pool.|


### quoteSwap

Core quote API for the hook's latest swap state.

Official integrations should prefer `MemeverseSwapRouter.quoteSwap(...)`. This low-level quote remains
available for custom routers, aggregators, and other advanced on-chain integrations.


```solidity
function quoteSwap(PoolKey calldata key, SwapParams calldata params) external view returns (SwapQuote memory quote);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`key`|`PoolKey`|The pool key being quoted.|
|`params`|`SwapParams`|The swap parameters being quoted.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`quote`|`SwapQuote`|The projected fee amounts, side, and estimated user/pool flows.|


### poolInfo

Returns stored pool information for a hook-managed pool.


```solidity
function poolInfo(PoolId poolId)
    external
    view
    returns (address liquidityToken, uint96 antiSnipeEndBlock, uint256 fee0PerShare, uint256 fee1PerShare);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`poolId`|`PoolId`|The pool id to query.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`liquidityToken`|`address`|The LP token contract for the pool.|
|`antiSnipeEndBlock`|`uint96`|The block at which anti-snipe protection ends.|
|`fee0PerShare`|`uint256`|The accumulated fee-per-share for currency0.|
|`fee1PerShare`|`uint256`|The accumulated fee-per-share for currency1.|


### lpToken

Returns the LP token address for a hook-managed pool key.

This is a convenience view over `poolInfo(key.toId()).liquidityToken`.


```solidity
function lpToken(PoolKey calldata key) external view returns (address liquidityToken);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`key`|`PoolKey`|The pool key to query.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`liquidityToken`|`address`|The LP token contract address, or `address(0)` when the pool is not initialized.|


### claimableFees

Returns the current claimable LP fees for an owner without mutating state.

Includes both already-pending fees and fees implied by the latest per-share values and owner LP balance.


```solidity
function claimableFees(PoolKey calldata key, address owner)
    external
    view
    returns (uint256 fee0Amount, uint256 fee1Amount);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`key`|`PoolKey`|The pool key whose fee accounting is queried.|
|`owner`|`address`|The owner address for the fee preview.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`fee0Amount`|`uint256`|The preview claimable amount in currency0.|
|`fee1Amount`|`uint256`|The preview claimable amount in currency1.|


### addLiquidityCore

Low-level liquidity execution API.

Adds full-range liquidity using the caller as payer and mints LP shares to `params.to`.
This function is intended for routers and advanced integrators and does not implement end-user deadline or
min-amount protections. The pool fee is not caller-configurable here: this Hook Core only operates on its
dynamic-fee pool type.


```solidity
function addLiquidityCore(AddLiquidityCoreParams calldata params)
    external
    payable
    returns (uint128 liquidity, BalanceDelta delta);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`params`|`AddLiquidityCoreParams`|The core liquidity-add parameters.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`liquidity`|`uint128`|The LP liquidity minted for this operation.|
|`delta`|`BalanceDelta`|The balance delta settled against the caller.|


### removeLiquidityCore

Low-level liquidity exit API.

Removes full-range liquidity owned by the caller and sends the underlying tokens to `params.recipient`.
This function is intended for routers and advanced integrators and does not implement end-user deadline or
min-amount protections. The pool fee is not caller-configurable here: this Hook Core only operates on its
dynamic-fee pool type.


```solidity
function removeLiquidityCore(RemoveLiquidityCoreParams calldata params) external returns (BalanceDelta delta);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`params`|`RemoveLiquidityCoreParams`|The core liquidity-remove parameters.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`delta`|`BalanceDelta`|The balance delta returned by the liquidity removal.|


### claimFeesCore

Low-level fee-claim API.

Claims pending LP fees on behalf of `params.owner`, optionally using a signed authorization.
Routers and third parties must provide a valid owner signature. Direct owner calls may set the signature fields
to zero and bypass signature verification.


```solidity
function claimFeesCore(ClaimFeesCoreParams calldata params)
    external
    returns (uint256 fee0Amount, uint256 fee1Amount);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`params`|`ClaimFeesCoreParams`|The core fee-claim parameters.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`fee0Amount`|`uint256`|The claimed amount of currency0 fees.|
|`fee1Amount`|`uint256`|The claimed amount of currency1 fees.|


### updateUserSnapshot

Internal accounting helper for LP fee snapshots.

Integrators normally should not call this directly unless they intentionally want to synchronize fee
accounting outside the standard LP token transfer / claim flow.


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

### ProtocolFeeCurrencySupportUpdated
Emitted when a currency's protocol-fee support flag is updated.


```solidity
event ProtocolFeeCurrencySupportUpdated(Currency indexed currency, bool supported);
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

### EmergencyFlagUpdated
Emitted when the emergency fixed-fee mode is toggled.


```solidity
event EmergencyFlagUpdated(bool oldFlag, bool newFlag);
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

### FailedAttemptFeeCollected
Emitted when a failed anti-snipe attempt is charged a protection-window failure fee.


```solidity
event FailedAttemptFeeCollected(
    PoolId indexed poolId,
    address indexed caller,
    Currency indexed feeCurrency,
    bool feeToTreasury,
    uint256 amount,
    uint256 blockNumber
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

### InvalidNativeValue
Reverts when the attached native value does not exactly match the required native input.


```solidity
error InvalidNativeValue(uint256 expected, uint256 actual);
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

### ZeroAddress
Reverts when a critical address parameter is unexpectedly zero.


```solidity
error ZeroAddress();
```

### ZeroValue
Reverts when a numeric configuration is unexpectedly zero.


```solidity
error ZeroValue();
```

### ERC20TransferFailed
Reverts when an ERC20 transfer returns false.


```solidity
error ERC20TransferFailed();
```

### NativeTreasuryMustAcceptETH
Reverts when the configured treasury cannot receive native protocol fees.


```solidity
error NativeTreasuryMustAcceptETH();
```

### InputBudgetExceeded
Reverts when a successful anti-snipe ticket is later used with more input than originally budgeted.


```solidity
error InputBudgetExceeded(uint256 actualInputAmount, uint256 inputBudget);
```

### InvalidClaimSignature
Reverts when a delegated fee-claim signature is invalid.


```solidity
error InvalidClaimSignature();
```

### PoolAlreadyRequestedThisTransaction
Reverts when the same transaction requests anti-snipe access for the same pool more than once.


```solidity
error PoolAlreadyRequestedThisTransaction();
```

### MissingAntiSnipeTicket
Reverts when an anti-snipe-window swap reaches the hook without a valid same-tx ticket.


```solidity
error MissingAntiSnipeTicket();
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

### RemoveLiquidityCoreParams

```solidity
struct RemoveLiquidityCoreParams {
    Currency currency0;
    Currency currency1;
    uint128 liquidity;
    address recipient;
}
```

### ClaimFeesCoreParams

```solidity
struct ClaimFeesCoreParams {
    PoolKey key;
    address owner;
    address recipient;
    uint256 deadline;
    uint8 v;
    bytes32 r;
    bytes32 s;
}
```

### SwapQuote

```solidity
struct SwapQuote {
    uint256 feeBps;
    uint256 estimatedUserInputAmount;
    uint256 estimatedUserOutputAmount;
    uint256 estimatedProtocolFeeAmount;
    uint256 estimatedLpFeeAmount;
    bool protocolFeeOnInput;
}
```

### FailedAttemptQuote

```solidity
struct FailedAttemptQuote {
    uint256 feeBps;
    uint256 feeAmount;
    Currency feeCurrency;
    bool feeToTreasury;
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

