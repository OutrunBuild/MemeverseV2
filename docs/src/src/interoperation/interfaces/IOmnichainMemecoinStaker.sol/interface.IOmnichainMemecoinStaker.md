# IOmnichainMemecoinStaker
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/f6152b6dbfadcd8a23a2d518905418243cf2a5e1/src/interoperation/interfaces/IOmnichainMemecoinStaker.sol)

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

