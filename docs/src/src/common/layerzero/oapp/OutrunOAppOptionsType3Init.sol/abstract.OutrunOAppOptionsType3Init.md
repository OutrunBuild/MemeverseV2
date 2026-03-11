# OutrunOAppOptionsType3Init
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/f6152b6dbfadcd8a23a2d518905418243cf2a5e1/src/common/layerzero/oapp/OutrunOAppOptionsType3Init.sol)

**Inherits:**
IOAppOptionsType3, [OutrunOwnableInit](/src/common/OutrunOwnableInit.sol/abstract.OutrunOwnableInit.md)

**Title:**
OutrunOAppOptionsType3Init (Just for minimal proxy)

Abstract contract implementing the IOAppOptionsType3 interface with type 3 options.


## State Variables
### OPTION_TYPE_3

```solidity
uint16 internal constant OPTION_TYPE_3 = 3
```


### OAPP_OPTIONS_TYPE_3_STORAGE_LOCATION

```solidity
bytes32 private constant OAPP_OPTIONS_TYPE_3_STORAGE_LOCATION =
    0xb8742acedc513ab939c44ee9081fd12ef5e204cfe39a55d50dba0e689496ff00
```


## Functions
### _getOAppOptionsType3Storage


```solidity
function _getOAppOptionsType3Storage() internal pure returns (OAppOptionsType3Storage storage $);
```

### __OutrunOAppOptionsType3_init

Ownable is not initialized here on purpose. It should be initialized in the child contract to
accommodate the different version of Ownable.


```solidity
function __OutrunOAppOptionsType3_init() internal onlyInitializing;
```

### __OutrunOAppOptionsType3_init_unchained


```solidity
function __OutrunOAppOptionsType3_init_unchained() internal onlyInitializing;
```

### enforcedOptions


```solidity
function enforcedOptions(uint32 _eid, uint16 _msgType) public view returns (bytes memory);
```

### setEnforcedOptions

Sets the enforced options for specific endpoint and message type combinations.

Only the owner/admin of the OApp can call this function.

Provides a way for the OApp to enforce things like paying for PreCrime, AND/OR minimum dst lzReceive gas amounts etc.

These enforced options can vary as the potential options/execution on the remote may differ as per the msgType.
eg. Amount of lzReceive() gas necessary to deliver a lzCompose() message adds overhead you dont want to pay
if you are only making a standard LayerZero message ie. lzReceive() WITHOUT sendCompose().


```solidity
function setEnforcedOptions(EnforcedOptionParam[] calldata _enforcedOptions) public virtual onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_enforcedOptions`|`EnforcedOptionParam[]`|An array of EnforcedOptionParam structures specifying enforced options.|


### combineOptions

Combines options for a given endpoint and message type.

If there is an enforced lzReceive option:
- {gasLimit: 200k, msg.value: 1 ether} AND a caller supplies a lzReceive option: {gasLimit: 100k, msg.value: 0.5 ether}
- The resulting options will be {gasLimit: 300k, msg.value: 1.5 ether} when the message is executed on the remote lzReceive() function.

This presence of duplicated options is handled off-chain in the verifier/executor.


```solidity
function combineOptions(uint32 _eid, uint16 _msgType, bytes calldata _extraOptions)
    public
    view
    virtual
    returns (bytes memory);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_eid`|`uint32`|The endpoint ID.|
|`_msgType`|`uint16`|The OAPP message type.|
|`_extraOptions`|`bytes`|Additional options passed by the caller.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes`|options The combination of caller specified options AND enforced options.|


### _assertOptionsType3

Internal function to assert that options are of type 3.


```solidity
function _assertOptionsType3(bytes calldata _options) internal pure virtual;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_options`|`bytes`|The options to be checked.|


## Structs
### OAppOptionsType3Storage

```solidity
struct OAppOptionsType3Storage {
    // @dev The "msgType" should be defined in the child contract.
    mapping(uint32 => mapping(uint16 => bytes)) enforcedOptions;
}
```

