# MemeverseRegistrarOmnichain
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/5f1e475fc32b5b93b8a81ca9d545cacad2f7567c/src/verse/MemeverseRegistrarOmnichain.sol)

**Inherits:**
[IMemeverseRegistrarOmnichain](/src/verse/interfaces/IMemeverseRegistrarOmnichain.sol/interface.IMemeverseRegistrarOmnichain.md), [MemeverseRegistrarAbstract](/src/verse/MemeverseRegistrarAbstract.sol/abstract.MemeverseRegistrarAbstract.md), OApp

**Title:**
Omnichain MemeverseRegistrar for deploying memecoin and registering memeverse


## State Variables
### REGISTRATION_CENTER_EID

```solidity
uint32 public immutable REGISTRATION_CENTER_EID
```


### REGISTRATION_CENTER_CHAINID

```solidity
uint32 public immutable REGISTRATION_CENTER_CHAINID
```


### registrationGasLimit

```solidity
RegistrationGasLimit public registrationGasLimit
```


## Functions
### constructor

Constructor


```solidity
constructor(
    address _owner,
    address _localEndpoint,
    address _memeverseLauncher,
    address _memeverseCommonInfo,
    uint32 _registrationCenterEid,
    uint32 _registrationCenterChainid,
    uint80 _baseRegistrationGasLimit,
    uint80 _localRegistrationGasLimit,
    uint80 _omnichainRegistrationGasLimit
) MemeverseRegistrarAbstract(_owner, _memeverseLauncher, _memeverseCommonInfo) OApp(_localEndpoint, _owner);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_owner`|`address`|- The owner of the contract|
|`_localEndpoint`|`address`|- The local endpoint|
|`_memeverseLauncher`|`address`||
|`_memeverseCommonInfo`|`address`||
|`_registrationCenterEid`|`uint32`|- The registration center eid|
|`_registrationCenterChainid`|`uint32`|- The registration center chainid|
|`_baseRegistrationGasLimit`|`uint80`|- The base registration gas limit|
|`_localRegistrationGasLimit`|`uint80`|- The local registration gas limit|
|`_omnichainRegistrationGasLimit`|`uint80`|- The omnichain registration gas limit|


### quoteRegister

Quote the LayerZero fee for the registration at the registration center.


```solidity
function quoteRegister(IMemeverseRegistrationCenter.RegistrationParam calldata param, uint128 value)
    external
    view
    override
    returns (uint256 lzFee);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`param`|`IMemeverseRegistrationCenter.RegistrationParam`|- The registration parameter.|
|`value`|`uint128`|- The gas cost required for omni-chain registration at the registration center, can be estimated through the LayerZero API on the registration center contract.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`lzFee`|`uint256`|- The LayerZero fee for the registration at the registration center.|


### registerAtCenter

Register through cross-chain at the RegistrationCenter


```solidity
function registerAtCenter(IMemeverseRegistrationCenter.RegistrationParam calldata param, uint128 value)
    external
    payable
    override;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`param`|`IMemeverseRegistrationCenter.RegistrationParam`||
|`value`|`uint128`|- The gas cost required for omni-chain registration at the registration center, can be estimated through the LayerZero API on the registration center contract. The value must be sufficient, it is recommended that the value be slightly higher than the quote value, otherwise, the registration may fail, and the consumed gas will not be refunded.|


### setRegistrationGasLimit

Set the registration gas limit


```solidity
function setRegistrationGasLimit(RegistrationGasLimit calldata _registrationGasLimit) external override onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_registrationGasLimit`|`RegistrationGasLimit`|- The registration gas limit|


### _lzReceive

Internal function to implement lzReceive logic


```solidity
function _lzReceive(
    Origin calldata,
    /*_origin*/
    bytes32,
    /*_guid*/
    bytes calldata _message,
    address,
    /*_executor*/
    bytes calldata /*_extraData*/
)
    internal
    virtual
    override;
```

