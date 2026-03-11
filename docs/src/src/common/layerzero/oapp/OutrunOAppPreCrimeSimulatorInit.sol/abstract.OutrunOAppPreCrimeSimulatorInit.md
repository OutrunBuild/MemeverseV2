# OutrunOAppPreCrimeSimulatorInit
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/5f1e475fc32b5b93b8a81ca9d545cacad2f7567c/src/common/layerzero/oapp/OutrunOAppPreCrimeSimulatorInit.sol)

**Inherits:**
IOAppPreCrimeSimulator, [OutrunOwnableInit](/src/common/OutrunOwnableInit.sol/abstract.OutrunOwnableInit.md)

**Title:**
OutrunOAppPreCrimeSimulatorInit (Just for minimal proxy)

Abstract contract serving as the base for preCrime simulation functionality in an OApp.


## State Variables
### OAPP_PRE_CRIME_SIMULATOR_STORAGE_LOCATION

```solidity
bytes32 private constant OAPP_PRE_CRIME_SIMULATOR_STORAGE_LOCATION =
    0x64ee1c09e489d82d98a23ae0880bbc36a3637a4a59e3c120b24b8998a504ab00
```


## Functions
### _getOAppPreCrimeSimulatorStorage


```solidity
function _getOAppPreCrimeSimulatorStorage() internal pure returns (OAppPreCrimeSimulatorStorage storage $);
```

### __OutrunOAppPreCrimeSimulator_init

Ownable is not initialized here on purpose. It should be initialized in the child contract to
accommodate the different version of Ownable.


```solidity
function __OutrunOAppPreCrimeSimulator_init() internal onlyInitializing;
```

### __OutrunOAppPreCrimeSimulator_init_unchained


```solidity
function __OutrunOAppPreCrimeSimulator_init_unchained() internal onlyInitializing;
```

### preCrime


```solidity
function preCrime() external view override returns (address);
```

### oApp

Retrieves the address of the OApp contract.

The simulator contract is the base contract for the OApp by default.

If the simulator is a separate contract, override this function.


```solidity
function oApp() external view virtual returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The address of the OApp contract.|


### setPreCrime

Sets the preCrime contract address.


```solidity
function setPreCrime(address _preCrime) public virtual onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_preCrime`|`address`|The address of the preCrime contract.|


### lzReceiveAndRevert

Interface for pre-crime simulations. Always reverts at the end with the simulation results.

WARNING: MUST revert at the end with the simulation results.

Gives the preCrime implementation the ability to mock sending packets to the lzReceive function,
WITHOUT actually executing them.


```solidity
function lzReceiveAndRevert(InboundPacket[] calldata _packets) public payable virtual;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_packets`|`InboundPacket[]`|An array of InboundPacket objects representing received packets to be delivered.|


### lzReceiveSimulate

Is effectively an internal function because msg.sender must be address(this).
Allows resetting the call stack for 'internal' calls.


```solidity
function lzReceiveSimulate(
    Origin calldata _origin,
    bytes32 _guid,
    bytes calldata _message,
    address _executor,
    bytes calldata _extraData
) external payable virtual;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_origin`|`Origin`|The origin information containing the source endpoint and sender address. - srcEid: The source chain endpoint ID. - sender: The sender address on the src chain. - nonce: The nonce of the message.|
|`_guid`|`bytes32`|The unique identifier of the packet.|
|`_message`|`bytes`|The message payload of the packet.|
|`_executor`|`address`|The executor address for the packet.|
|`_extraData`|`bytes`|Additional data for the packet.|


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
) internal virtual;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_origin`|`Origin`|The origin information. - srcEid: The source chain endpoint ID. - sender: The sender address from the src chain. - nonce: The nonce of the LayerZero message.|
|`_guid`|`bytes32`|The GUID of the LayerZero message.|
|`_message`|`bytes`|The LayerZero message.|
|`_executor`|`address`|The address of the off-chain executor.|
|`_extraData`|`bytes`|Arbitrary data passed by the msg executor.|


### isPeer

checks if the specified peer is considered 'trusted' by the OApp.


```solidity
function isPeer(uint32 _eid, bytes32 _peer) public view virtual returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_eid`|`uint32`|The endpoint Id to check.|
|`_peer`|`bytes32`|The peer to check.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|Whether the peer passed is considered 'trusted' by the OApp.|


## Structs
### OAppPreCrimeSimulatorStorage

```solidity
struct OAppPreCrimeSimulatorStorage {
    // The address of the preCrime implementation.
    address preCrime;
}
```

