# ReentrancyGuard
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/5f1e475fc32b5b93b8a81ca9d545cacad2f7567c/src/common/ReentrancyGuard.sol)

Outrun's ReentrancyGuard implementation, support transient variable.


## State Variables
### locked

```solidity
bool transient locked
```


## Functions
### nonReentrant


```solidity
modifier nonReentrant() ;
```

## Errors
### ReentrancyGuardReentrantCall

```solidity
error ReentrancyGuardReentrantCall();
```

