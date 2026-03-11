# Memecoin
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/f6152b6dbfadcd8a23a2d518905418243cf2a5e1/src/token/Memecoin.sol)

**Inherits:**
[IMemecoin](/src/token/interfaces/IMemecoin.sol/interface.IMemecoin.md), [OutrunOFTInit](/src/common/layerzero/oft/OutrunOFTInit.sol/abstract.OutrunOFTInit.md)

**Title:**
Omnichain Memecoin


## State Variables
### memeverseLauncher

```solidity
address public memeverseLauncher
```


## Functions
### constructor


```solidity
constructor(address _lzEndpoint) OutrunOFTInit(_lzEndpoint);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_lzEndpoint`|`address`|The local LayerZero endpoint address.|


### initialize

Initialize the memecoin.


```solidity
function initialize(string memory name_, string memory symbol_, address _memeverseLauncher, address _delegate)
    external
    override
    initializer;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`name_`|`string`|- The name of the memecoin.|
|`symbol_`|`string`|- The symbol of the memecoin.|
|`_memeverseLauncher`|`address`|- The address of the memeverse launcher.|
|`_delegate`|`address`|- The address of the OFT delegate.|


### mint

Mint the memecoin.


```solidity
function mint(address account, uint256 amount) external override;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`account`|`address`|- The address of the account.|
|`amount`|`uint256`|- The amount of the memecoin.|


### burn

Burn the memecoin.


```solidity
function burn(uint256 amount) external override;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`amount`|`uint256`|- The amount of the memecoin.|


