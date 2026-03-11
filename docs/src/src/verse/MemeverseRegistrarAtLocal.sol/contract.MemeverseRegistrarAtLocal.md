# MemeverseRegistrarAtLocal
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/f6152b6dbfadcd8a23a2d518905418243cf2a5e1/src/verse/MemeverseRegistrarAtLocal.sol)

**Inherits:**
[IMemeverseRegistrarAtLocal](/src/verse/interfaces/IMemeverseRegistrarAtLocal.sol/interface.IMemeverseRegistrarAtLocal.md), [MemeverseRegistrarAbstract](/src/verse/MemeverseRegistrarAbstract.sol/abstract.MemeverseRegistrarAbstract.md)

**Title:**
Local MemeverseRegistrar for deploying memecoin and registering memeverse


## State Variables
### DAY

```solidity
uint256 public constant DAY = 24 * 3600
```


### registrationCenter

```solidity
address public registrationCenter
```


## Functions
### constructor


```solidity
constructor(address _owner, address _registrationCenter, address _memeverseLauncher, address _memeverseCommonInfo)
    MemeverseRegistrarAbstract(_owner, _memeverseLauncher, _memeverseCommonInfo);
```

### quoteRegister

Quote the LayerZero fee for the registration at the registration center.


```solidity
function quoteRegister(
    IMemeverseRegistrationCenter.RegistrationParam calldata param,
    uint128 /*value*/
)
    external
    view
    override
    returns (uint256 lzFee);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`param`|`IMemeverseRegistrationCenter.RegistrationParam`|- The registration parameter.|
|`<none>`|`uint128`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`lzFee`|`uint256`|- The LayerZero fee for the registration at the registration center.|


### localRegistration

Only RegistrationCenter can call

On the same chain, the registration center directly calls this method


```solidity
function localRegistration(MemeverseParam calldata param) external override;
```

### registerAtCenter

Only users can call this method.

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
|`value`|`uint128`|- The gas cost required for omni-chain registration at the registration center, can be estimated through the LayerZero API on the registration center contract. The value must be sufficient, otherwise, the registration will fail, and the consumed gas will not be refunded.|


### setRegistrationCenter


```solidity
function setRegistrationCenter(address _registrationCenter) external override onlyOwner;
```

