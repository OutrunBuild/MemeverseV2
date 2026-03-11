# ReentrancyGuard
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/f6152b6dbfadcd8a23a2d518905418243cf2a5e1/src/common/ReentrancyGuard.sol)

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

