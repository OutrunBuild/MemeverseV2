# OutrunSafeERC20
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/5f1e475fc32b5b93b8a81ca9d545cacad2f7567c/src/libraries/OutrunSafeERC20.sol)

OutrunSafeERC20, adapted from @openzeppelin


## Functions
### safeTransfer

Transfer `value` amount of `token` from the calling contract to `to`. If `token` returns no value,
non-reverting calls are assumed to be successful.


```solidity
function safeTransfer(IERC20 token, address to, uint256 value) internal;
```

### safeTransferFrom

Transfer `value` amount of `token` from `from` to `to`, spending the approval given by `from` to the
calling contract. If `token` returns no value, non-reverting calls are assumed to be successful.


```solidity
function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal;
```

### _callOptionalReturn

Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
on the return value: the return value is optional (but if data is returned, it must not be false).


```solidity
function _callOptionalReturn(IERC20 token, bytes memory data) private;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`IERC20`|The token targeted by the call.|
|`data`|`bytes`|The call data (encoded using abi.encode or one of its variants).|


## Errors
### SafeERC20FailedOperation
An operation with an ERC20 token failed.


```solidity
error SafeERC20FailedOperation(address token);
```

