# IOmnichainMemecoinStaker
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/5f1e475fc32b5b93b8a81ca9d545cacad2f7567c/src/interoperation/interfaces/IOmnichainMemecoinStaker.sol)

**Inherits:**
ILayerZeroComposer


## Events
### OmnichainMemecoinStakingProcessed

```solidity
event OmnichainMemecoinStakingProcessed(
    bytes32 indexed guid, address indexed memecoin, address indexed yieldVault, address receiver, uint256 amount
);
```

## Errors
### AlreadyExecuted

```solidity
error AlreadyExecuted();
```

### PermissionDenied

```solidity
error PermissionDenied();
```

