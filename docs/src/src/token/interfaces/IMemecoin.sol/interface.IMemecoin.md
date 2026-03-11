# IMemecoin
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/f6152b6dbfadcd8a23a2d518905418243cf2a5e1/src/token/interfaces/IMemecoin.sol)

**Inherits:**
IERC20

**Title:**
Memecoin interface


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

Initialize the memecoin.


```solidity
function initialize(string memory name_, string memory symbol_, address _memeverseLauncher, address _delegate)
    external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`name_`|`string`|- The name of the memecoin.|
|`symbol_`|`string`|- The symbol of the memecoin.|
|`_memeverseLauncher`|`address`|- The address of the memeverse launcher.|
|`_delegate`|`address`|- The address of the delegate.|


### mint

Mint the memecoin.


```solidity
function mint(address account, uint256 amount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`account`|`address`|- The address of the account.|
|`amount`|`uint256`|- The amount of the memecoin.|


### burn

Burn the memecoin.


```solidity
function burn(uint256 amount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`amount`|`uint256`|- The amount of the memecoin.|


## Errors
### ZeroInput

```solidity
error ZeroInput();
```

