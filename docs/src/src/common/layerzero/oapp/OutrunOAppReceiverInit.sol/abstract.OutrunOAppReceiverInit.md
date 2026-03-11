# OutrunOAppReceiverInit
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/f6152b6dbfadcd8a23a2d518905418243cf2a5e1/src/common/layerzero/oapp/OutrunOAppReceiverInit.sol)

**Inherits:**
IOAppReceiver, [OutrunOAppCoreInit](/src/common/layerzero/oapp/OutrunOAppCoreInit.sol/abstract.OutrunOAppCoreInit.md)

**Title:**
OutrunOAppReceiverInit (Just for minimal proxy)

Abstract contract implementing the ILayerZeroReceiver interface and extending OAppCore for OApp receivers.


## State Variables
### RECEIVER_VERSION

```solidity
uint64 internal constant RECEIVER_VERSION = 2
```


## Functions
### __OutrunOAppReceiver_init

Ownable is not initialized here on purpose. It should be initialized in the child contract to
accommodate the different version of Ownable.


```solidity
function __OutrunOAppReceiver_init(address _delegate) internal onlyInitializing;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_delegate`|`address`|The delegate capable of making OApp configurations inside of the endpoint.|


### __OutrunOAppReceiver_init_unchained


```solidity
function __OutrunOAppReceiver_init_unchained() internal onlyInitializing;
```

### oAppVersion

Retrieves the OApp version information.

Providing 0 as the default for OAppSender version. Indicates that the OAppSender is not implemented.
ie. this is a RECEIVE only OApp.

If the OApp uses both OAppSender and OAppReceiver, then this needs to be override returning the correct versions.


```solidity
function oAppVersion() public view virtual returns (uint64 senderVersion, uint64 receiverVersion);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`senderVersion`|`uint64`|The version of the OAppSender.sol contract.|
|`receiverVersion`|`uint64`|The version of the OAppReceiver.sol contract.|


### isComposeMsgSender

Indicates whether an address is an approved composeMsg sender to the Endpoint.

_origin The origin information containing the source endpoint and sender address.
- srcEid: The source chain endpoint ID.
- sender: The sender address on the src chain.
- nonce: The nonce of the message.

_message The lzReceive payload.

Applications can optionally choose to implement separate composeMsg senders that are NOT the bridging layer.

The default sender IS the OAppReceiver implementer.


```solidity
function isComposeMsgSender(
    Origin calldata,
    /*_origin*/
    bytes calldata,
    /*_message*/
    address _sender
)
    public
    view
    virtual
    returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`Origin`||
|`<none>`|`bytes`||
|`_sender`|`address`|The sender address.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|isSender Is a valid sender.|


### allowInitializePath

Checks if the path initialization is allowed based on the provided origin.

This indicates to the endpoint that the OApp has enabled msgs for this particular path to be received.

This defaults to assuming if a peer has been set, its initialized.
Can be overridden by the OApp if there is other logic to determine this.


```solidity
function allowInitializePath(Origin calldata origin) public view virtual returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`origin`|`Origin`|The origin information containing the source endpoint and sender address.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|Whether the path has been initialized.|


### nextNonce

Retrieves the next nonce for a given source endpoint and sender address.

_srcEid The source endpoint ID.

_sender The sender address.

The path nonce starts from 1. If 0 is returned it means that there is NO nonce ordered enforcement.

Is required by the off-chain executor to determine the OApp expects msg execution is ordered.

This is also enforced by the OApp.

By default this is NOT enabled. ie. nextNonce is hardcoded to return 0.


```solidity
function nextNonce(
    uint32,
    /*_srcEid*/
    bytes32 /*_sender*/
)
    public
    view
    virtual
    returns (uint64 nonce);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`nonce`|`uint64`|The next nonce.|


### lzReceive

Entry point for receiving messages or packets from the endpoint.

Entry point for receiving msg/packet from the LayerZero endpoint.


```solidity
function lzReceive(
    Origin calldata _origin,
    bytes32 _guid,
    bytes calldata _message,
    address _executor,
    bytes calldata _extraData
) public payable virtual;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_origin`|`Origin`|The origin information containing the source endpoint and sender address. - srcEid: The source chain endpoint ID. - sender: The sender address on the src chain. - nonce: The nonce of the message.|
|`_guid`|`bytes32`|The unique identifier for the received LayerZero message.|
|`_message`|`bytes`|The payload of the received message.|
|`_executor`|`address`|The address of the executor for the received message.|
|`_extraData`|`bytes`|Additional arbitrary data provided by the corresponding executor.|


### _lzReceive

Internal function to implement lzReceive logic without needing to copy the basic parameter validation.


```solidity
function _lzReceive(
    Origin calldata _origin,
    bytes32 _guid,
    bytes calldata _message,
    address _executor,
    bytes calldata _extraData
) internal virtual;
```

## Errors
### OnlyEndpoint

```solidity
error OnlyEndpoint(address addr);
```

