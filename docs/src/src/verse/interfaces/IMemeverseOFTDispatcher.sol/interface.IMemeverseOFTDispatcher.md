# IMemeverseOFTDispatcher
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/f6152b6dbfadcd8a23a2d518905418243cf2a5e1/src/verse/interfaces/IMemeverseOFTDispatcher.sol)

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

