# TokenHelper
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/5f1e475fc32b5b93b8a81ca9d545cacad2f7567c/src/common/TokenHelper.sol)

**Inherits:**
[ReentrancyGuard](/src/common/ReentrancyGuard.sol/abstract.ReentrancyGuard.md)


## State Variables
### NATIVE

```solidity
address internal constant NATIVE = address(0)
```


### LOWER_BOUND_APPROVAL

```solidity
uint256 internal constant LOWER_BOUND_APPROVAL = type(uint96).max / 2
```


## Functions
### _transferIn


```solidity
function _transferIn(address token, address from, uint256 amount) internal;
```

### _transferFrom


```solidity
function _transferFrom(IERC20 token, address from, address to, uint256 amount) internal;
```

### _transferOut


```solidity
function _transferOut(address token, address to, uint256 amount) internal nonReentrant;
```

### _safeApprove

Approves the stipulated contract to spend the given allowance in the given token

PLS PAY ATTENTION to tokens that requires the approval to be set to 0 before changing it


```solidity
function _safeApprove(address token, address to, uint256 value) internal;
```

### _safeApproveInf


```solidity
function _safeApproveInf(address token, address to) internal;
```

