# OutrunOAppSenderInit
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/f6152b6dbfadcd8a23a2d518905418243cf2a5e1/src/common/layerzero/oapp/OutrunOAppSenderInit.sol)

**Inherits:**
[OutrunOAppCoreInit](/src/common/layerzero/oapp/OutrunOAppCoreInit.sol/abstract.OutrunOAppCoreInit.md)

**Title:**
OutrunOAppSenderInit (Just for minimal proxy)

Abstract contract implementing the OAppSender functionality for sending messages to a LayerZero endpoint.


## State Variables
### SENDER_VERSION

```solidity
uint64 internal constant SENDER_VERSION = 1
```


## Functions
### __OutrunOAppSender_init

Ownable is not initialized here on purpose. It should be initialized in the child contract to
accommodate the different version of Ownable.


```solidity
function __OutrunOAppSender_init(address _delegate) internal onlyInitializing;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_delegate`|`address`|The delegate capable of making OApp configurations inside of the endpoint.|


### __OutrunOAppSender_init_unchained


```solidity
function __OutrunOAppSender_init_unchained() internal onlyInitializing;
```

### oAppVersion

Retrieves the OApp version information.

Providing 0 as the default for OAppReceiver version. Indicates that the OAppReceiver is not implemented.
ie. this is a SEND only OApp.

If the OApp uses both OAppSender and OAppReceiver, then this needs to be override returning the correct versions


```solidity
function oAppVersion() public view virtual returns (uint64 senderVersion, uint64 receiverVersion);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`senderVersion`|`uint64`|The version of the OAppSender.sol contract.|
|`receiverVersion`|`uint64`|The version of the OAppReceiver.sol contract.|


### _quote

Internal function to interact with the LayerZero EndpointV2.quote() for fee calculation.


```solidity
function _quote(uint32 _dstEid, bytes memory _message, bytes memory _options, bool _payInLzToken)
    internal
    view
    virtual
    returns (MessagingFee memory fee);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_dstEid`|`uint32`|The destination endpoint ID.|
|`_message`|`bytes`|The message payload.|
|`_options`|`bytes`|Additional options for the message.|
|`_payInLzToken`|`bool`|Flag indicating whether to pay the fee in LZ tokens.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`fee`|`MessagingFee`|The calculated MessagingFee for the message. - nativeFee: The native fee for the message. - lzTokenFee: The LZ token fee for the message.|


### _lzSend

Internal function to interact with the LayerZero EndpointV2.send() for sending a message.


```solidity
function _lzSend(
    uint32 _dstEid,
    bytes memory _message,
    bytes memory _options,
    MessagingFee memory _fee,
    address _refundAddress
) internal virtual returns (MessagingReceipt memory receipt);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_dstEid`|`uint32`|The destination endpoint ID.|
|`_message`|`bytes`|The message payload.|
|`_options`|`bytes`|Additional options for the message.|
|`_fee`|`MessagingFee`|The calculated LayerZero fee for the message. - nativeFee: The native fee. - lzTokenFee: The lzToken fee.|
|`_refundAddress`|`address`|The address to receive any excess fee values sent to the endpoint.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`receipt`|`MessagingReceipt`|The receipt for the sent message. - guid: The unique identifier for the sent message. - nonce: The nonce of the sent message. - fee: The LayerZero fee incurred for the message.|


### _payNative

Internal function to pay the native fee associated with the message.

If the OApp needs to initiate MULTIPLE LayerZero messages in a single transaction,
this will need to be overridden because msg.value would contain multiple lzFees.

Should be overridden in the event the LayerZero endpoint requires a different native currency.

Some EVMs use an ERC20 as a method for paying transactions/gasFees.

The endpoint is EITHER/OR, ie. it will NOT support both types of native payment at a time.


```solidity
function _payNative(uint256 _nativeFee) internal virtual returns (uint256 nativeFee);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_nativeFee`|`uint256`|The native fee to be paid.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`nativeFee`|`uint256`|The amount of native currency paid.|


### _payLzToken

Internal function to pay the LZ token fee associated with the message.

If the caller is trying to pay in the specified lzToken, then the lzTokenFee is passed to the endpoint.

Any excess sent, is passed back to the specified _refundAddress in the _lzSend().


```solidity
function _payLzToken(uint256 _lzTokenFee) internal virtual;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_lzTokenFee`|`uint256`|The LZ token fee to be paid.|


## Errors
### NotEnoughNative

```solidity
error NotEnoughNative(uint256 msgValue);
```

### LzTokenUnavailable

```solidity
error LzTokenUnavailable();
```

