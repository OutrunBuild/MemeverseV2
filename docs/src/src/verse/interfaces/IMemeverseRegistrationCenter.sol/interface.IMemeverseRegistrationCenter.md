# IMemeverseRegistrationCenter
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/f6152b6dbfadcd8a23a2d518905418243cf2a5e1/src/verse/interfaces/IMemeverseRegistrationCenter.sol)

**Title:**
Memeverse Registration Center Interface


## Functions
### previewRegistration


```solidity
function previewRegistration(string calldata symbol) external view returns (bool);
```

### quoteSend


```solidity
function quoteSend(uint32[] memory omnichainIds, bytes memory message)
    external
    view
    returns (uint256, uint256[] memory, uint32[] memory);
```

### registration


```solidity
function registration(RegistrationParam calldata param) external payable;
```

### removeGasDust


```solidity
function removeGasDust(address receiver) external;
```

### lzSend


```solidity
function lzSend(
    uint32 dstEid,
    bytes memory message,
    bytes memory options,
    MessagingFee memory fee,
    address refundAddress
) external payable;
```

### setSupportedUPT


```solidity
function setSupportedUPT(address UPT, bool isSupported) external;
```

### setDurationDaysRange


```solidity
function setDurationDaysRange(uint128 minDurationDays, uint128 maxDurationDays) external;
```

### setLockupDaysRange


```solidity
function setLockupDaysRange(uint128 minLockupDays, uint128 maxLockupDays) external;
```

### setRegisterGasLimit


```solidity
function setRegisterGasLimit(uint256 registerGasLimit) external;
```

## Events
### Registration

```solidity
event Registration(uint256 indexed uniqueId, RegistrationParam param);
```

### RemoveGasDust

```solidity
event RemoveGasDust(address indexed receiver, uint256 dust);
```

### SetSupportedUPT

```solidity
event SetSupportedUPT(address UPT, bool isSupported);
```

### SetDurationDaysRange

```solidity
event SetDurationDaysRange(uint128 minDurationDays, uint128 maxDurationDays);
```

### SetLockupDaysRange

```solidity
event SetLockupDaysRange(uint128 minLockupDays, uint128 maxLockupDays);
```

### SetRegisterGasLimit

```solidity
event SetRegisterGasLimit(uint256 registerGasLimit);
```

## Errors
### ZeroInput

```solidity
error ZeroInput();
```

### InvalidUPT

```solidity
error InvalidUPT();
```

### InvalidInput

```solidity
error InvalidInput();
```

### InvalidLength

```solidity
error InvalidLength();
```

### PermissionDenied

```solidity
error PermissionDenied();
```

### EmptyOmnichainIds

```solidity
error EmptyOmnichainIds();
```

### InvalidLockupDays

```solidity
error InvalidLockupDays();
```

### InsufficientLzFee

```solidity
error InsufficientLzFee();
```

### InvalidDurationDays

```solidity
error InvalidDurationDays();
```

### SymbolNotUnlock

```solidity
error SymbolNotUnlock(uint64 unlockTime);
```

### InvalidOmnichainId

```solidity
error InvalidOmnichainId(uint32 omnichainId);
```

## Structs
### RegistrationParam

```solidity
struct RegistrationParam {
    string name; // Token name
    string symbol; // Token symbol
    string uri; // Token icon uri
    string desc; // Description
    string[] communities; // Community, index -> 0:Website, 1:X, 2:Discord, 3:Telegram, >4:Others
    uint256 durationDays; // DurationDays of genesis stage
    uint256 lockupDays; // LockupDays of liquidity
    uint32[] omnichainIds; // ChainIds of the token's omnichain(EVM)
    address UPT; // UPT of Memeverse
    bool flashGenesis; // Allowing the transition to the liquidity lock stage once the minimum funding requirement is met, without waiting for the genesis stage to end.
}
```

### SymbolRegistration

```solidity
struct SymbolRegistration {
    uint256 uniqueId; // unique verseId
    uint64 endTime; // Memeverse genesis endTime
    uint192 nonce; // Number of replication
}
```

### LzEndpointIdPair

```solidity
struct LzEndpointIdPair {
    uint32 chainId;
    uint32 endpointId;
}
```

### RegisterGasLimitPair

```solidity
struct RegisterGasLimitPair {
    uint32 chainId;
    uint128 gasLimit;
}
```

