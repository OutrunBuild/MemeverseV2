# IMemeLiquidProof
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/f6152b6dbfadcd8a23a2d518905418243cf2a5e1/src/token/interfaces/IMemeLiquidProof.sol)

**Inherits:**
IERC20

**Title:**
Memecoin Proof Of Liquidity(POL) Token Interface


## Functions
### memeverseLauncher

Get the memeverse launcher.


```solidity
function memeverseLauncher() external view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|memeverseLauncher - The address of the memeverse launcher.|


### initialize

Initialize the memecoin liquidProof.


```solidity
function initialize(
    string memory name_,
    string memory symbol_,
    address memecoin_,
    address memeverseLauncher_,
    address delegate_
) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`name_`|`string`|- The name of the memecoin liquidProof.|
|`symbol_`|`string`|- The symbol of the memecoin liquidProof.|
|`memecoin_`|`address`|- The address of the memecoin.|
|`memeverseLauncher_`|`address`|- The address of the memeverse launcher.|
|`delegate_`|`address`|- The address of the OFT delegate.|


### setPoolId

Set PoolId after deploying liquidity


```solidity
function setPoolId(PoolId poolId) external;
```

### mint

Mint the memeverse proof.


```solidity
function mint(address account, uint256 amount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`account`|`address`|- The address of the account.|
|`amount`|`uint256`|- The amount of the memeverse proof.|


### burn

Burn the memeverse proof.


```solidity
function burn(address account, uint256 amount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`account`|`address`|- The address of the account.|
|`amount`|`uint256`|- The amount of the memeverse proof.|


## Errors
### ZeroInput

```solidity
error ZeroInput();
```

