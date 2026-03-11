# IMemeverseRegistrarOmnichain
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/f6152b6dbfadcd8a23a2d518905418243cf2a5e1/src/verse/interfaces/IMemeverseRegistrarOmnichain.sol)

Interface for the Memeverse Registrar on Omnichain.


## Functions
### setRegistrationGasLimit


```solidity
function setRegistrationGasLimit(RegistrationGasLimit calldata registrationGasLimit) external;
```

## Events
### SetRegistrationGasLimit

```solidity
event SetRegistrationGasLimit(RegistrationGasLimit registrationGasLimit);
```

## Errors
### InsufficientLzFee

```solidity
error InsufficientLzFee();
```

## Structs
### RegistrationGasLimit

```solidity
struct RegistrationGasLimit {
    uint80 baseRegistrationGasLimit;
    uint80 localRegistrationGasLimit;
    uint80 omnichainRegistrationGasLimit;
}
```

