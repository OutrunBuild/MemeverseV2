# OutrunOAppInit
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/f6152b6dbfadcd8a23a2d518905418243cf2a5e1/src/common/layerzero/oapp/OutrunOAppInit.sol)

**Inherits:**
[OutrunOAppSenderInit](/src/common/layerzero/oapp/OutrunOAppSenderInit.sol/abstract.OutrunOAppSenderInit.md), [OutrunOAppReceiverInit](/src/common/layerzero/oapp/OutrunOAppReceiverInit.sol/abstract.OutrunOAppReceiverInit.md)

**Title:**
OutrunOAppInit (Just for minimal proxy)

Abstract contract serving as the base for OutrunOAppInit implementation, combining OutrunOAppSenderInit and OutrunOAppReceiverInit functionality.


## Functions
### constructor

Constructor to initialize the OApp with the provided endpoint and owner.


```solidity
constructor(address _endpoint) OutrunOAppCoreInit(_endpoint);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_endpoint`|`address`|The address of the LOCAL LayerZero endpoint.|


### __OutrunOApp_init

Initializes the OApp with the provided delegate.

The delegate typically should be set as the owner of the contract.

Ownable is not initialized here on purpose. It should be initialized in the child contract to
accommodate the different version of Ownable.


```solidity
function __OutrunOApp_init(address _delegate) internal onlyInitializing;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_delegate`|`address`|The delegate capable of making OApp configurations inside of the endpoint.|


### __OutrunOApp_init_unchained


```solidity
function __OutrunOApp_init_unchained() internal onlyInitializing;
```

### oAppVersion

Retrieves the OApp version information.


```solidity
function oAppVersion()
    public
    pure
    virtual
    override(OutrunOAppSenderInit, OutrunOAppReceiverInit)
    returns (uint64 senderVersion, uint64 receiverVersion);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`senderVersion`|`uint64`|The version of the OAppSender.sol implementation.|
|`receiverVersion`|`uint64`|The version of the OAppReceiver.sol implementation.|


