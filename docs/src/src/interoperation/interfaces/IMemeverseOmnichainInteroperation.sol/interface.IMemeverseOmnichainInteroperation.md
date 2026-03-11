# IMemeverseOmnichainInteroperation
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/f6152b6dbfadcd8a23a2d518905418243cf2a5e1/src/interoperation/interfaces/IMemeverseOmnichainInteroperation.sol)

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

