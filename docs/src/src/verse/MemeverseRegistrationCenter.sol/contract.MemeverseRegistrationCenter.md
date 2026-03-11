# MemeverseRegistrationCenter
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/5f1e475fc32b5b93b8a81ca9d545cacad2f7567c/src/verse/MemeverseRegistrationCenter.sol)

**Inherits:**
[IMemeverseRegistrationCenter](/src/verse/interfaces/IMemeverseRegistrationCenter.sol/interface.IMemeverseRegistrationCenter.md), OApp, [TokenHelper](/src/common/TokenHelper.sol/abstract.TokenHelper.md)

**Title:**
Memeverse Omnichain Registration Center


## State Variables
### DAY

```solidity
uint256 public constant DAY = 180
```


### MEMEVERSE_REGISTRAR

```solidity
address public immutable MEMEVERSE_REGISTRAR
```


### MEMEVERSE_COMMON_INFO

```solidity
address public immutable MEMEVERSE_COMMON_INFO
```


### minDurationDays

```solidity
uint128 public minDurationDays
```


### maxDurationDays

```solidity
uint128 public maxDurationDays
```


### minLockupDays

```solidity
uint128 public minLockupDays
```


### maxLockupDays

```solidity
uint128 public maxLockupDays
```


### registerGasLimit

```solidity
uint256 public registerGasLimit
```


### symbolRegistry

```solidity
mapping(string symbol => SymbolRegistration) public symbolRegistry
```


### symbolHistory

```solidity
mapping(string symbol => mapping(uint256 uniqueId => SymbolRegistration)) public symbolHistory
```


### supportedUPTs

```solidity
mapping(address UPT => bool) supportedUPTs
```


## Functions
### constructor

Constructor


```solidity
constructor(address _owner, address _lzEndpoint, address _memeverseRegistrar, address _memeverseCommonInfo)
    OApp(_lzEndpoint, _owner)
    Ownable(_owner);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_owner`|`address`|- The owner of the contract|
|`_lzEndpoint`|`address`|- The lz endpoint|
|`_memeverseRegistrar`|`address`|- The memeverse registrar|
|`_memeverseCommonInfo`|`address`||


### previewRegistration

Preview if the symbol can be registered


```solidity
function previewRegistration(string calldata symbol) external view override returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`symbol`|`string`|- The symbol to preview|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|true if the symbol can be registered, false otherwise|


### quoteSend

Calculate the fee quotation for cross-chain transactions


```solidity
function quoteSend(uint32[] memory omnichainIds, bytes memory message)
    public
    view
    override
    returns (uint256, uint256[] memory, uint32[] memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`omnichainIds`|`uint32[]`|- The omnichain ids|
|`message`|`bytes`|- The message to send|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|totalFee - The total cross-chain fee|
|`<none>`|`uint256[]`|fees - The cross-chain fee for each omnichain id|
|`<none>`|`uint32[]`|eids - The lz endpoint id for each omnichain id|


### registration

Registration memeverse


```solidity
function registration(RegistrationParam memory param) public payable override;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`param`|`RegistrationParam`|- The registration parameter|


### removeGasDust

Remove gas dust from the contract


```solidity
function removeGasDust(address receiver) external override onlyOwner;
```

### lzSend

lzSend external call. Only called by self.


```solidity
function lzSend(
    uint32 dstEid,
    bytes memory message,
    bytes memory options,
    MessagingFee memory fee,
    address refundAddress
) public payable override;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`dstEid`|`uint32`|- The destination eid|
|`message`|`bytes`|- The message|
|`options`|`bytes`|- The options|
|`fee`|`MessagingFee`|- The cross-chain fee|
|`refundAddress`|`address`|- The refund address|


### _omnichainSend

Omnichain send


```solidity
function _omnichainSend(uint32[] memory omnichainIds, IMemeverseRegistrar.MemeverseParam memory param) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`omnichainIds`|`uint32[]`|- The omnichain ids|
|`param`|`IMemeverseRegistrar.MemeverseParam`|- The registration parameter|


### _registrationParamValidation

Registration parameter validation


```solidity
function _registrationParamValidation(RegistrationParam memory param) internal view;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`param`|`RegistrationParam`|- The registration parameter|


### _deduplicate


```solidity
function _deduplicate(uint32[] memory input) internal pure returns (uint32[] memory);
```

### _lzReceive

Internal function to implement lzReceive logic


```solidity
function _lzReceive(
    Origin calldata _origin,
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

### setSupportedUPT

Set supported UPT genesis fund


```solidity
function setSupportedUPT(address UPT, bool isSupported) external override onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`UPT`|`address`|- Address of UPT|
|`isSupported`|`bool`|- Is Supported?|


### setDurationDaysRange

Set genesis stage duration days range


```solidity
function setDurationDaysRange(uint128 _minDurationDays, uint128 _maxDurationDays) external override onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_minDurationDays`|`uint128`|- Min genesis stage duration days|
|`_maxDurationDays`|`uint128`|- Max genesis stage duration days|


### setLockupDaysRange

Set liquidity lockup days range


```solidity
function setLockupDaysRange(uint128 _minLockupDays, uint128 _maxLockupDays) external override onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_minLockupDays`|`uint128`|- Min liquidity lockup days|
|`_maxLockupDays`|`uint128`|- Max liquidity lockup days|


### setRegisterGasLimit

Set the register gas limit


```solidity
function setRegisterGasLimit(uint256 _registerGasLimit) external override onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_registerGasLimit`|`uint256`|- The register gas limit|


