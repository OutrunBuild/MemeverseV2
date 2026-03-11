# OutrunOFTInit
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/f6152b6dbfadcd8a23a2d518905418243cf2a5e1/src/common/layerzero/oft/OutrunOFTInit.sol)

**Inherits:**
[OutrunOFTCoreInit](/src/common/layerzero/oft/OutrunOFTCoreInit.sol/abstract.OutrunOFTCoreInit.md), [OutrunERC20Init](/src/common/OutrunERC20Init.sol/abstract.OutrunERC20Init.md)

**Title:**
Outrun OFT Init Contract (Just for minimal proxy)

OFT is an ERC-20 token that extends the functionality of the OFTCore contract.


## Functions
### constructor

Constructor for the OFT contract.


```solidity
constructor(address _lzEndpoint) OutrunOFTCoreInit(decimals(), _lzEndpoint);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_lzEndpoint`|`address`|The local LayerZero endpoint address.|


### __OutrunOFT_init

Initializes the OFT with the provided name, symbol, and delegate.

The delegate typically should be set as the owner of the contract.

Ownable is not initialized here on purpose. It should be initialized in the child contract to
accommodate the different version of Ownable.


```solidity
function __OutrunOFT_init(string memory _name, string memory _symbol, address _delegate) internal onlyInitializing;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_name`|`string`|The name of the OFT.|
|`_symbol`|`string`|The symbol of the OFT.|
|`_delegate`|`address`|The delegate capable of making OApp configurations inside of the endpoint.|


### __OFT_init_unchained


```solidity
function __OFT_init_unchained() internal onlyInitializing;
```

### token

Retrieves the address of the underlying ERC20 implementation.

In the case of OFT, address(this) and erc20 are the same contract.


```solidity
function token() public view returns (address);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`address`|The address of the OFT token.|


### approvalRequired

Indicates whether the OFT contract requires approval of the 'token()' to send.

In the case of OFT where the contract IS the token, approval is NOT required.


```solidity
function approvalRequired() external pure virtual returns (bool);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`bool`|requiresApproval Needs approval of the underlying token implementation.|


### withdrawIfNotExecuted

Withdraw OFT if the composition call has not been executed.


```solidity
function withdrawIfNotExecuted(bytes32 guid, address receiver) external override returns (uint256 amount);
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


### _debit

Burns tokens from the sender's specified balance.


```solidity
function _debit(address _from, uint256 _amountLD, uint256 _minAmountLD, uint32 _dstEid)
    internal
    virtual
    override
    returns (uint256 amountSentLD, uint256 amountReceivedLD);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_from`|`address`|The address to debit the tokens from.|
|`_amountLD`|`uint256`|The amount of tokens to send in local decimals.|
|`_minAmountLD`|`uint256`|The minimum amount to send in local decimals.|
|`_dstEid`|`uint32`|The destination chain ID.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`amountSentLD`|`uint256`|The amount sent in local decimals.|
|`amountReceivedLD`|`uint256`|The amount received in local decimals on the remote.|


### _credit

Credits tokens to the specified address.

_srcEid The source chain ID.


```solidity
function _credit(
    address _to,
    uint256 _amountLD,
    uint32 /*_srcEid*/
)
    internal
    virtual
    override
    returns (uint256 amountReceivedLD);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_to`|`address`|The address to credit the tokens to.|
|`_amountLD`|`uint256`|The amount of tokens to credit in local decimals.|
|`<none>`|`uint32`||

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`amountReceivedLD`|`uint256`|The amount of tokens ACTUALLY received in local decimals.|


