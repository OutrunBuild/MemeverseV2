# MemeverseRegistrarAbstract
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/f6152b6dbfadcd8a23a2d518905418243cf2a5e1/src/verse/MemeverseRegistrarAbstract.sol)

**Inherits:**
[IMemeverseRegistrar](/src/verse/interfaces/IMemeverseRegistrar.sol/interface.IMemeverseRegistrar.md), Ownable

**Title:**
MemeverseRegistrar Abstract Contract


## State Variables
### MEMEVERSE_LAUNCHER

```solidity
address public immutable MEMEVERSE_LAUNCHER
```


### MEMEVERSE_COMMON_INFO

```solidity
address public immutable MEMEVERSE_COMMON_INFO
```


## Functions
### constructor

Constructor to initialize the MemeverseRegistrar.


```solidity
constructor(address _owner, address _memeverseLauncher, address _memeverseCommonInfo) Ownable(_owner);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_owner`|`address`|- The owner of the contract.|
|`_memeverseLauncher`|`address`|- Address of memeverseLauncher.|
|`_memeverseCommonInfo`|`address`|- Address of MemeverseCommonInfo.|


### _registerMemeverse

Register a memeverse.


```solidity
function _registerMemeverse(MemeverseParam memory param) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`param`|`MemeverseParam`|- The memeverse parameters.|


