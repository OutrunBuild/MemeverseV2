# IMemeverseOFTDispatcher
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/5f1e475fc32b5b93b8a81ca9d545cacad2f7567c/src/verse/interfaces/IMemeverseOFTDispatcher.sol)

**Inherits:**
[MemeverseOFTEnum](/src/common/MemeverseOFTEnum.sol/interface.MemeverseOFTEnum.md), ILayerZeroComposer


## Events
### OFTProcessed

```solidity
event OFTProcessed(
    bytes32 indexed guid,
    address indexed token,
    TokenType indexed tokenType,
    address receiver,
    uint256 amount,
    bool isBurned
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

