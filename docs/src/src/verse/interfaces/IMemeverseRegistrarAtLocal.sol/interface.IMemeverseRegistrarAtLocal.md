# IMemeverseRegistrarAtLocal
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/f6152b6dbfadcd8a23a2d518905418243cf2a5e1/src/verse/interfaces/IMemeverseRegistrarAtLocal.sol)


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

