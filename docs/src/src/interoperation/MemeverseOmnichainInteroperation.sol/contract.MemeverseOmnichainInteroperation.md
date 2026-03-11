# MemeverseOmnichainInteroperation
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/5f1e475fc32b5b93b8a81ca9d545cacad2f7567c/src/interoperation/MemeverseOmnichainInteroperation.sol)

**Inherits:**
[IMemeverseOmnichainInteroperation](/src/interoperation/interfaces/IMemeverseOmnichainInteroperation.sol/interface.IMemeverseOmnichainInteroperation.md), [TokenHelper](/src/common/TokenHelper.sol/abstract.TokenHelper.md), Ownable

**Title:**
Memeverse Omnichain Interoperation


## State Variables
### MEMEVERSE_COMMON_INFO

```solidity
address public immutable MEMEVERSE_COMMON_INFO
```


### MEMEVERSE_LAUNCHER

```solidity
address public immutable MEMEVERSE_LAUNCHER
```


### OMNICHAIN_MEMECOIN_STAKER

```solidity
address public immutable OMNICHAIN_MEMECOIN_STAKER
```


### oftReceiveGasLimit

```solidity
uint128 public oftReceiveGasLimit
```


### omnichainStakingGasLimit

```solidity
uint128 public omnichainStakingGasLimit
```


## Functions
### constructor

Constructor


```solidity
constructor(
    address _owner,
    address _memeverseCommonInfo,
    address _memeverseLauncher,
    address _omnichainMemecoinStaker,
    uint128 _oftReceiveGasLimit,
    uint128 _omnichainStakingGasLimit
) Ownable(_owner);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_owner`|`address`|- The owner of the contract|
|`_memeverseCommonInfo`|`address`|- Address of MemeverseCommonInfo|
|`_memeverseLauncher`|`address`|- Address of MemeverseLauncher|
|`_omnichainMemecoinStaker`|`address`|- Address of OmnichainMemecoinStaker|
|`_oftReceiveGasLimit`|`uint128`|- Gas limit for OFT receive|
|`_omnichainStakingGasLimit`|`uint128`|- Gas limit for omnichain memecoin staking|


### quoteMemecoinStaking

Quote the LayerZero fee for the Memecoin Omnichain Staking


```solidity
function quoteMemecoinStaking(address memecoin, address receiver, uint256 amount)
    external
    view
    override
    returns (uint256 lzFee);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`memecoin`|`address`|- Address of memecoin.|
|`receiver`|`address`|- Address of staked memecoin receiver.|
|`amount`|`uint256`|- Amount of memecoin will be staked.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`lzFee`|`uint256`|- The LayerZero fee for the Memecoin Omnichain Staking. The value must be sufficient, it is recommended that the value be slightly higher than the quote value, otherwise, the registration may fail, and the consumed gas will not be refunded.|


### memecoinStaking

Memecoin Omnichain Staking(Cross to GovChain)


```solidity
function memecoinStaking(address memecoin, address receiver, uint256 amount) external payable override;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`memecoin`|`address`|- Address of memecoin.|
|`receiver`|`address`|- Address of staked memecoin receiver.|
|`amount`|`uint256`|- Amount of memecoin will be staked.|


### setGasLimits

Set gas limits for OFT receive and omnichain memecoin staker


```solidity
function setGasLimits(uint128 _oftReceiveGasLimit, uint128 _omnichainStakingGasLimit) external override onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_oftReceiveGasLimit`|`uint128`|- Gas limit for OFT receive|
|`_omnichainStakingGasLimit`|`uint128`|- Gas limit for omnichain memecoin staking|


