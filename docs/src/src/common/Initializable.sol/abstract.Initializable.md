# Initializable
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/5f1e475fc32b5b93b8a81ca9d545cacad2f7567c/src/common/Initializable.sol)

This contract is just for minimal proxy


## State Variables
### INITIALIZABLE_STORAGE_LOCATION

```solidity
bytes32 private constant INITIALIZABLE_STORAGE_LOCATION =
    0x364b90b49cc5a06782669778ce5f4dc79d5c3891ab824b5e713b2409af81a500
```


## Functions
### _getInitializableStorage


```solidity
function _getInitializableStorage() private pure returns (InitializableStorage storage $);
```

### constructor


```solidity
constructor() ;
```

### initializer


```solidity
modifier initializer() ;
```

### onlyInitializing


```solidity
modifier onlyInitializing() ;
```

### _checkInitializing


```solidity
function _checkInitializing() internal view;
```

## Errors
### NotInitializing

```solidity
error NotInitializing();
```

### AlreadyInitialized

```solidity
error AlreadyInitialized();
```

## Structs
### InitializableStorage

```solidity
struct InitializableStorage {
    bool initialized;
    bool initializing;
}
```

