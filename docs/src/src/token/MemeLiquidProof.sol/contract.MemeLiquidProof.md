# MemeLiquidProof
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/5f1e475fc32b5b93b8a81ca9d545cacad2f7567c/src/token/MemeLiquidProof.sol)

**Inherits:**
[IMemeLiquidProof](/src/token/interfaces/IMemeLiquidProof.sol/interface.IMemeLiquidProof.md), [OutrunERC20PermitInit](/src/common/OutrunERC20PermitInit.sol/abstract.OutrunERC20PermitInit.md), [OutrunERC20VotesInit](/src/common/governance/OutrunERC20VotesInit.sol/abstract.OutrunERC20VotesInit.md), [OutrunOFTInit](/src/common/layerzero/oft/OutrunOFTInit.sol/abstract.OutrunOFTInit.md)

**Title:**
Omnichain Memecoin Proof Of Liquidity(POL) Token


## State Variables
### memecoin

```solidity
address public memecoin
```


### memeverseLauncher

```solidity
address public memeverseLauncher
```


### poolId

```solidity
PoolId public poolId
```


## Functions
### onlyMemeverseLauncher


```solidity
modifier onlyMemeverseLauncher() ;
```

### _onlyMemeverseLauncher


```solidity
function _onlyMemeverseLauncher() internal view;
```

### constructor


```solidity
constructor(address _lzEndpoint) OutrunOFTInit(_lzEndpoint);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_lzEndpoint`|`address`|The local LayerZero endpoint address.|


### initialize

Initialize the memecoin liquidProof.


```solidity
function initialize(
    string memory name_,
    string memory symbol_,
    address memecoin_,
    address memeverseLauncher_,
    address delegate_
) external override initializer;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`name_`|`string`|- The name of the memecoin liquidProof.|
|`symbol_`|`string`|- The symbol of the memecoin liquidProof.|
|`memecoin_`|`address`|- The address of the memecoin.|
|`memeverseLauncher_`|`address`|- The address of the memeverse launcher.|
|`delegate_`|`address`|- The address of the OFT delegate.|


### clock


```solidity
function clock() public view override returns (uint48);
```

### CLOCK_MODE


```solidity
function CLOCK_MODE() public pure override returns (string memory);
```

### setPoolId

Set PoolId(Uniswap V4) after deploying liquidity


```solidity
function setPoolId(PoolId _poolId) external override onlyMemeverseLauncher;
```

### mint

Only the memeverse launcher can mint the memeverse proof.

Mint the memeverse proof.


```solidity
function mint(address account, uint256 amount) external override onlyMemeverseLauncher;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`account`|`address`|- The address of the account.|
|`amount`|`uint256`|- The amount of the memeverse proof.|


### burn

User must have approved msg.sender to spend UPT

Burn the memecoin liquid proof.


```solidity
function burn(address account, uint256 amount) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`account`|`address`|- The address of the account.|
|`amount`|`uint256`|- The amount of the memecoin liquid proof.|


### burn

Burn the liquid proof by self.


```solidity
function burn(uint256 amount) external;
```

### nonces


```solidity
function nonces(address owner) public view override(OutrunERC20PermitInit, OutrunNoncesInit) returns (uint256);
```

### _update


```solidity
function _update(address from, address to, uint256 value) internal override(OutrunERC20Init, OutrunERC20VotesInit);
```

