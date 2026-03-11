# OutrunOAppCoreInit
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/5f1e475fc32b5b93b8a81ca9d545cacad2f7567c/src/common/layerzero/oapp/OutrunOAppCoreInit.sol)

**Inherits:**
IOAppCore, [OutrunOwnableInit](/src/common/OutrunOwnableInit.sol/abstract.OutrunOwnableInit.md)

**Title:**
OutrunOAppCoreInit (Just for minimal proxy)

Abstract contract implementing the IOAppCore interface with basic OApp configurations.


## State Variables
### endpoint

```solidity
ILayerZeroEndpointV2 public immutable endpoint
```


### OAPP_CORE_STORAGE_LOCATION

```solidity
bytes32 private constant OAPP_CORE_STORAGE_LOCATION =
    0x7c5e164903b57308a9588eaf98afe7394cf4b3ef4aeeacd4cf0d6c6393897400
```


## Functions
### _getOAppCoreStorage


```solidity
function _getOAppCoreStorage() internal pure returns (OAppCoreStorage storage $);
```

### constructor

Constructor to initialize the OAppCore with the provided endpoint and delegate.


```solidity
constructor(address _endpoint) ;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_endpoint`|`address`|The address of the LOCAL Layer Zero endpoint.|


### __OutrunOAppCore_init

Initializes the OAppCore with the provided delegate.

The delegate typically should be set as the owner of the contract.

Ownable is not initialized here on purpose. It should be initialized in the child contract to
accommodate the different version of Ownable.


```solidity
function __OutrunOAppCore_init(address _delegate) internal onlyInitializing;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_delegate`|`address`|The delegate capable of making OApp configurations inside of the endpoint.|


### __OutrunOAppCore_init_unchained


```solidity
function __OutrunOAppCore_init_unchained(address _delegate) internal onlyInitializing;
```

### peers

Returns the peer address (OApp instance) associated with a specific endpoint.


```solidity
function peers(uint32 _eid) public view override returns (bytes32);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_eid`|`uint32`|The endpoint ID.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes32`|peer The address of the peer associated with the specified endpoint.|


### setPeer

Sets the peer address (OApp instance) for a corresponding endpoint.

Only the owner/admin of the OApp can call this function.

Indicates that the peer is trusted to send LayerZero messages to this OApp.

Set this to bytes32(0) to remove the peer address.

Peer is a bytes32 to accommodate non-evm chains.


```solidity
function setPeer(uint32 _eid, bytes32 _peer) public virtual onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_eid`|`uint32`|The endpoint ID.|
|`_peer`|`bytes32`|The address of the peer to be associated with the corresponding endpoint.|


### _getPeerOrRevert

Internal function to get the peer address associated with a specific endpoint; reverts if NOT set.
ie. the peer is set to bytes32(0).


```solidity
function _getPeerOrRevert(uint32 _eid) internal view virtual returns (bytes32);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_eid`|`uint32`|The endpoint ID.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bytes32`|peer The address of the peer associated with the specified endpoint.|


### setDelegate

Sets the delegate address for the OApp.

Only the owner/admin of the OApp can call this function.

Provides the ability for a delegate to set configs, on behalf of the OApp, directly on the Endpoint contract.


```solidity
function setDelegate(address _delegate) public onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_delegate`|`address`|The address of the delegate to be set.|


## Structs
### OAppCoreStorage

```solidity
struct OAppCoreStorage {
    // Mapping to store peers associated with corresponding endpoints
    mapping(uint32 eid => bytes32 peer) peers;
}
```

