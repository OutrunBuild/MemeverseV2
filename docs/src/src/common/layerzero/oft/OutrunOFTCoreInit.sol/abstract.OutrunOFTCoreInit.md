# OutrunOFTCoreInit
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/5f1e475fc32b5b93b8a81ca9d545cacad2f7567c/src/common/layerzero/oft/OutrunOFTCoreInit.sol)

**Inherits:**
IOFT, [IOFTCompose](/src/common/layerzero/oft/IOFTCompose.sol/interface.IOFTCompose.md), [OutrunOAppInit](/src/common/layerzero/oapp/OutrunOAppInit.sol/abstract.OutrunOAppInit.md), [OutrunOAppPreCrimeSimulatorInit](/src/common/layerzero/oapp/OutrunOAppPreCrimeSimulatorInit.sol/abstract.OutrunOAppPreCrimeSimulatorInit.md), [OutrunOAppOptionsType3Init](/src/common/layerzero/oapp/OutrunOAppOptionsType3Init.sol/abstract.OutrunOAppOptionsType3Init.md)

**Title:**
OutrunOFTCoreInit (Just for minimal proxy)

Abstract contract for the OftChain (OFT) token.


## State Variables
### decimalConversionRate

```solidity
uint256 public immutable decimalConversionRate
```


### SEND

```solidity
uint16 public constant SEND = 1
```


### SEND_AND_CALL

```solidity
uint16 public constant SEND_AND_CALL = 2
```


### OFT_CORE_STORAGE_LOCATION

```solidity
bytes32 private constant OFT_CORE_STORAGE_LOCATION =
    0x1a2846a4be01d927c13a5ab572124918fa6eabc1d9def75fd5d4e3f0617fe600
```


## Functions
### _getOFTCoreStorage


```solidity
function _getOFTCoreStorage() internal pure returns (OFTCoreStorage storage $);
```

### constructor

Constructor.


```solidity
constructor(uint8 _localDecimals, address _endpoint) OutrunOAppInit(_endpoint);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_localDecimals`|`uint8`|The decimals of the token on the local chain (this chain).|
|`_endpoint`|`address`|The address of the LayerZero endpoint.|


### __OutrunOFTCore_init

Initializer.

The delegate typically should be set as the owner of the contract.

Ownable is not initialized here on purpose. It should be initialized in the child contract to
accommodate the different version of Ownable.


```solidity
function __OutrunOFTCore_init(address _delegate) internal onlyInitializing;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_delegate`|`address`|The delegate capable of making OApp configurations inside of the endpoint.|


### __OFTCore_init_unchained


```solidity
function __OFTCore_init_unchained() internal onlyInitializing;
```

### msgInspector


```solidity
function msgInspector() public view returns (address);
```

### getComposeTxExecutedStatus

Get the compose tx executed status by guid.


```solidity
function getComposeTxExecutedStatus(bytes32 guid) external view override returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`guid`|`bytes32`|The unique identifier for the received LayerZero message.|


### oftVersion

Retrieves interfaceID and the version of the OFT.

interfaceId: This specific interface ID is '0x02e49c2c'.

version: Indicates a cross-chain compatible msg encoding with other OFTs.

If a new feature is added to the OFT cross-chain msg encoding, the version will be incremented.
ie. localOFT version(x,1) CAN send messages to remoteOFT version(x,1)


```solidity
function oftVersion() external pure virtual returns (bytes4 interfaceId, uint64 version);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`interfaceId`|`bytes4`|The interface ID.|
|`version`|`uint64`|The version.|


### sharedDecimals

Retrieves the shared decimals of the OFT.

Sets an implicit cap on the amount of tokens, over uint64.max() will need some sort of outbound cap / totalSupply cap
Lowest common decimal denominator between chains.
Defaults to 6 decimal places to provide up to 18,446,744,073,709.551615 units (max uint64).
For tokens exceeding this totalSupply(), they will need to override the sharedDecimals function with something smaller.
ie. 4 sharedDecimals would be 1,844,674,407,370,955.1615


```solidity
function sharedDecimals() public view virtual returns (uint8);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint8`|The shared decimals of the OFT.|


### setMsgInspector

Sets the message inspector address for the OFT.

This is an optional contract that can be used to inspect both 'message' and 'options'.

Set it to address(0) to disable it, or set it to a contract address to enable it.


```solidity
function setMsgInspector(address _msgInspector) public virtual onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_msgInspector`|`address`|The address of the message inspector.|


### quoteOFT

Provides a quote for OFT-related operations.


```solidity
function quoteOFT(SendParam calldata _sendParam)
    external
    view
    virtual
    returns (OFTLimit memory oftLimit, OFTFeeDetail[] memory oftFeeDetails, OFTReceipt memory oftReceipt);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_sendParam`|`SendParam`|The parameters for the send operation.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`oftLimit`|`OFTLimit`|The OFT limit information.|
|`oftFeeDetails`|`OFTFeeDetail[]`|The details of OFT fees.|
|`oftReceipt`|`OFTReceipt`|The OFT receipt information.|


### quoteSend

Provides a quote for the send() operation.

MessagingFee: LayerZero msg fee
- nativeFee: The native fee.
- lzTokenFee: The lzToken fee.


```solidity
function quoteSend(SendParam calldata _sendParam, bool _payInLzToken)
    external
    view
    virtual
    returns (MessagingFee memory msgFee);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_sendParam`|`SendParam`|The parameters for the send() operation.|
|`_payInLzToken`|`bool`|Flag indicating whether the caller is paying in the LZ token.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`msgFee`|`MessagingFee`|The calculated LayerZero messaging fee from the send() operation.|


### send

Executes the send operation.

MessagingReceipt: LayerZero msg receipt
- guid: The unique identifier for the sent message.
- nonce: The nonce of the sent message.
- fee: The LayerZero fee incurred for the message.


```solidity
function send(SendParam calldata _sendParam, MessagingFee calldata _fee, address _refundAddress)
    external
    payable
    virtual
    returns (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_sendParam`|`SendParam`|The parameters for the send operation.|
|`_fee`|`MessagingFee`|The calculated fee for the send() operation. - nativeFee: The native fee. - lzTokenFee: The lzToken fee.|
|`_refundAddress`|`address`|The address to receive any excess funds.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`msgReceipt`|`MessagingReceipt`|The receipt for the send operation.|
|`oftReceipt`|`OFTReceipt`|The OFT receipt information.|


### _buildMsgAndOptions

Internal function to build the message and options.


```solidity
function _buildMsgAndOptions(SendParam calldata _sendParam, uint256 _amountLD)
    internal
    view
    virtual
    returns (bytes memory message, bytes memory options);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_sendParam`|`SendParam`|The parameters for the send() operation.|
|`_amountLD`|`uint256`|The amount in local decimals.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`message`|`bytes`|The encoded message.|
|`options`|`bytes`|The encoded options.|


### _lzReceive

Internal function to handle the receive on the LayerZero endpoint.

_executor The address of the executor.

_extraData Additional data.


```solidity
function _lzReceive(
    Origin calldata _origin,
    bytes32 _guid,
    bytes calldata _message,
    address,
    /*_executor*/ // @dev unused in the default implementation.
    bytes calldata /*_extraData*/ // @dev unused in the default implementation.
)
    internal
    virtual
    override;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_origin`|`Origin`|The origin information. - srcEid: The source chain endpoint ID. - sender: The sender address from the src chain. - nonce: The nonce of the LayerZero message.|
|`_guid`|`bytes32`|The unique identifier for the received LayerZero message.|
|`_message`|`bytes`|The encoded message.|
|`<none>`|`address`||
|`<none>`|`bytes`||


### notifyComposeExecuted

Notify the OFT contract that the composition call has been executed.


```solidity
function notifyComposeExecuted(bytes32 guid) external override;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`guid`|`bytes32`|The unique identifier for the received LayerZero message.|


### _lzReceiveSimulate

Internal function to handle the OAppPreCrimeSimulator simulated receive.

Enables the preCrime simulator to mock sending lzReceive() messages,
routes the msg down from the OAppPreCrimeSimulator, and back up to the OAppReceiver.


```solidity
function _lzReceiveSimulate(
    Origin calldata _origin,
    bytes32 _guid,
    bytes calldata _message,
    address _executor,
    bytes calldata _extraData
) internal virtual override;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_origin`|`Origin`|The origin information. - srcEid: The source chain endpoint ID. - sender: The sender address from the src chain. - nonce: The nonce of the LayerZero message.|
|`_guid`|`bytes32`|The unique identifier for the received LayerZero message.|
|`_message`|`bytes`|The LayerZero message.|
|`_executor`|`address`|The address of the off-chain executor.|
|`_extraData`|`bytes`|Arbitrary data passed by the msg executor.|


### isPeer

Check if the peer is considered 'trusted' by the OApp.

Enables OAppPreCrimeSimulator to check whether a potential Inbound Packet is from a trusted source.


```solidity
function isPeer(uint32 _eid, bytes32 _peer) public view virtual override returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_eid`|`uint32`|The endpoint ID to check.|
|`_peer`|`bytes32`|The peer to check.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|Whether the peer passed is considered 'trusted' by the OApp.|


### _removeDust

Internal function to remove dust from the given local decimal amount.

Prevents the loss of dust when moving amounts between chains with different decimals.

eg. uint(123) with a conversion rate of 100 becomes uint(100).


```solidity
function _removeDust(uint256 _amountLD) internal view virtual returns (uint256 amountLD);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_amountLD`|`uint256`|The amount in local decimals.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`amountLD`|`uint256`|The amount after removing dust.|


### _toLD

Internal function to convert an amount from shared decimals into local decimals.


```solidity
function _toLD(uint64 _amountSD) internal view virtual returns (uint256 amountLD);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_amountSD`|`uint64`|The amount in shared decimals.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`amountLD`|`uint256`|The amount in local decimals.|


### _toSD

Internal function to convert an amount from local decimals into shared decimals.


```solidity
function _toSD(uint256 _amountLD) internal view virtual returns (uint64 amountSD);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_amountLD`|`uint256`|The amount in local decimals.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`amountSD`|`uint64`|The amount in shared decimals.|


### _debitView

Internal function to mock the amount mutation from a OFT debit() operation.

_dstEid The destination endpoint ID.

This is where things like fees would be calculated and deducted from the amount to be received on the remote.


```solidity
function _debitView(
    uint256 _amountLD,
    uint256 _minAmountLD,
    uint32 /*_dstEid*/
)
    internal
    view
    virtual
    returns (uint256 amountSentLD, uint256 amountReceivedLD);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_amountLD`|`uint256`|The amount to send in local decimals.|
|`_minAmountLD`|`uint256`|The minimum amount to send in local decimals.|
|`<none>`|`uint32`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`amountSentLD`|`uint256`|The amount sent, in local decimals.|
|`amountReceivedLD`|`uint256`|The amount to be received on the remote chain, in local decimals.|


### _debit

Internal function to perform a debit operation.

Defined here but are intended to be overriden depending on the OFT implementation.

Depending on OFT implementation the _amountLD could differ from the amountReceivedLD.


```solidity
function _debit(address _from, uint256 _amountLD, uint256 _minAmountLD, uint32 _dstEid)
    internal
    virtual
    returns (uint256 amountSentLD, uint256 amountReceivedLD);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_from`|`address`|The address to debit.|
|`_amountLD`|`uint256`|The amount to send in local decimals.|
|`_minAmountLD`|`uint256`|The minimum amount to send in local decimals.|
|`_dstEid`|`uint32`|The destination endpoint ID.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`amountSentLD`|`uint256`|The amount sent in local decimals.|
|`amountReceivedLD`|`uint256`|The amount received in local decimals on the remote.|


### _credit

Internal function to perform a credit operation.

Defined here but are intended to be overriden depending on the OFT implementation.

Depending on OFT implementation the _amountLD could differ from the amountReceivedLD.


```solidity
function _credit(address _to, uint256 _amountLD, uint32 _srcEid) internal virtual returns (uint256 amountReceivedLD);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_to`|`address`|The address to credit.|
|`_amountLD`|`uint256`|The amount to credit in local decimals.|
|`_srcEid`|`uint32`|The source endpoint ID.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`amountReceivedLD`|`uint256`|The amount ACTUALLY received in local decimals.|


## Events
### MsgInspectorSet

```solidity
event MsgInspectorSet(address inspector);
```

## Structs
### OFTCoreStorage

```solidity
struct OFTCoreStorage {
    // Address of an optional contract to inspect both 'message' and 'options'
    address msgInspector;
    mapping(bytes32 guid => ComposeTxStatus) composeTxs;
}
```

