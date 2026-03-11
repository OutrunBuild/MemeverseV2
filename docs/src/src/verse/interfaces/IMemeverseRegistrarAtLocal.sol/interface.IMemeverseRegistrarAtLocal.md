# IMemeverseRegistrarAtLocal
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/5f1e475fc32b5b93b8a81ca9d545cacad2f7567c/src/verse/interfaces/IMemeverseRegistrarAtLocal.sol)


## Functions
### localRegistration


```solidity
function localRegistration(IMemeverseRegistrar.MemeverseParam calldata param) external;
```

### setRegistrationCenter


```solidity
function setRegistrationCenter(address registrationCenter) external;
```

## Events
### SetRegistrationCenter

```solidity
event SetRegistrationCenter(address registrationCenter);
```

## Errors
### ZeroAddress

```solidity
error ZeroAddress();
```

### PermissionDenied

```solidity
error PermissionDenied();
```

