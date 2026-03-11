# IMemecoinYieldVault
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/f6152b6dbfadcd8a23a2d518905418243cf2a5e1/src/yield/interfaces/IMemecoinYieldVault.sol)

**Inherits:**
IERC20


## Functions
### asset


```solidity
function asset() external view returns (address assetTokenAddress);
```

### totalAssets


```solidity
function totalAssets() external view returns (uint256 totalManagedAssets);
```

### previewDeposit


```solidity
function previewDeposit(uint256 assets) external view returns (uint256 shares);
```

### previewRedeem


```solidity
function previewRedeem(uint256 shares) external view returns (uint256 assets);
```

### initialize


```solidity
function initialize(
    string memory name,
    string memory symbol,
    address yieldDispatcher,
    address asset,
    uint256 verseId
) external;
```

### accumulateYields


```solidity
function accumulateYields(uint256 amount) external;
```

### reAccumulateYields


```solidity
function reAccumulateYields(bytes32 lzGuid) external;
```

### deposit


```solidity
function deposit(uint256 assets, address receiver) external returns (uint256 shares);
```

### requestRedeem


```solidity
function requestRedeem(uint256 shares, address receiver) external returns (uint256 assets);
```

### executeRedeem


```solidity
function executeRedeem() external returns (uint256 redeemedAmount);
```

## Events
### AccumulateYields

```solidity
event AccumulateYields(address indexed yieldSource, uint256 yield, uint256 exchangeRate);
```

### Deposit

```solidity
event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
```

### RedeemRequested

```solidity
event RedeemRequested(
    address indexed sender, address indexed receiver, uint256 assets, uint256 shares, uint256 requestTime
);
```

### RedeemExecuted

```solidity
event RedeemExecuted(address indexed receiver, uint256 amount);
```

## Errors
### ZeroAddress

```solidity
error ZeroAddress();
```

### ZeroRedeemRequest

```solidity
error ZeroRedeemRequest();
```

### MaxRedeemRequestsReached

```solidity
error MaxRedeemRequestsReached();
```

## Structs
### RedeemRequest

```solidity
struct RedeemRequest {
    uint192 amount; // Requested redeem amount
    uint64 requestTime; // Time when the redeem request was made
}
```

