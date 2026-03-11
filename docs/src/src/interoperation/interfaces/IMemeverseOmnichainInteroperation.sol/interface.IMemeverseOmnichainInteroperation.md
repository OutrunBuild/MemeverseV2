# IMemeverseOmnichainInteroperation
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/5f1e475fc32b5b93b8a81ca9d545cacad2f7567c/src/interoperation/interfaces/IMemeverseOmnichainInteroperation.sol)

**Title:**
Memeverse Omnichain Interoperation Interface


## Functions
### quoteMemecoinStaking


```solidity
function quoteMemecoinStaking(address memecoin, address receiver, uint256 amount)
    external
    view
    returns (uint256 lzFee);
```

### memecoinStaking


```solidity
function memecoinStaking(address memecoin, address receiver, uint256 amount) external payable;
```

### setGasLimits


```solidity
function setGasLimits(uint128 oftReceiveGasLimit, uint128 omnichainStakingGasLimit) external;
```

## Events
### SetGasLimits

```solidity
event SetGasLimits(uint128 oftReceiveGasLimit, uint128 omnichainStakingGasLimit);
```

### OmnichainMemecoinStaking

```solidity
event OmnichainMemecoinStaking(
    bytes32 indexed guid, address indexed sender, address receiver, address indexed memecoin, uint256 amount
);
```

## Errors
### ZeroInput

```solidity
error ZeroInput();
```

### EmptyYieldVault

```solidity
error EmptyYieldVault();
```

### InsufficientLzFee

```solidity
error InsufficientLzFee();
```

