# IMemeverseRegistrarOmnichain
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/5f1e475fc32b5b93b8a81ca9d545cacad2f7567c/src/verse/interfaces/IMemeverseRegistrarOmnichain.sol)

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

