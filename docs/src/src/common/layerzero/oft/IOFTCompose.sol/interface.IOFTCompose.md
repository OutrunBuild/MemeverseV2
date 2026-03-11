# IOFTCompose
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/f6152b6dbfadcd8a23a2d518905418243cf2a5e1/src/common/layerzero/oft/IOFTCompose.sol)

**Title:**
IOFTCompose

Handle the logic related to OFT Compose


## Functions
### getComposeTxExecutedStatus

Get the compose tx executed status by guid.


```solidity
function getComposeTxExecutedStatus(bytes32 guid) external view returns (bool);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`guid`|`bytes32`|- The unique identifier for the received LayerZero message.|


### notifyComposeExecuted

Notify the OFT contract that the composition call has been executed.


```solidity
function notifyComposeExecuted(bytes32 guid) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`guid`|`bytes32`|- The unique identifier for the received LayerZero message.|


### withdrawIfNotExecuted

Withdraw OFT if the composition call has not been executed.


```solidity
function withdrawIfNotExecuted(bytes32 guid, address receiver) external returns (uint256 amount);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`guid`|`bytes32`|- The unique identifier for the received LayerZero message.|
|`receiver`|`address`|- Address to receive OFT.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`amount`|`uint256`|- Withdraw amount|


## Events
### NotifyComposeExecuted

```solidity
event NotifyComposeExecuted(bytes32 indexed guid);
```

### WithdrawIfNotExecuted

```solidity
event WithdrawIfNotExecuted(
    bytes32 indexed guid, address indexed composer, address indexed receiver, uint256 amount
);
```

## Errors
### AlreadyExecuted

```solidity
error AlreadyExecuted();
```

### PermissionDenied

```solidity
error PermissionDenied();
```

## Structs
### ComposeTxStatus

```solidity
struct ComposeTxStatus {
    address composer; // The Layerzero Composer contract of this tx
    address UBO; // Ultimate beneficiary owner
    uint256 amount; // OFT cross-chain amount
    bool isExecuted; // Has Been Executed?
}
```

