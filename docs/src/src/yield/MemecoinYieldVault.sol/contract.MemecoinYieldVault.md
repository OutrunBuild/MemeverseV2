# MemecoinYieldVault
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/f6152b6dbfadcd8a23a2d518905418243cf2a5e1/src/yield/MemecoinYieldVault.sol)

**Inherits:**
[IMemecoinYieldVault](/src/yield/interfaces/IMemecoinYieldVault.sol/interface.IMemecoinYieldVault.md), [OutrunERC20PermitInit](/src/common/OutrunERC20PermitInit.sol/abstract.OutrunERC20PermitInit.md), [OutrunERC20VotesInit](/src/common/governance/OutrunERC20VotesInit.sol/abstract.OutrunERC20VotesInit.md)

Memecoin Yield Vault


## State Variables
### MAX_REDEEM_REQUESTS

```solidity
uint256 public constant MAX_REDEEM_REQUESTS = 5
```


### REDEEM_DELAY

```solidity
uint256 public constant REDEEM_DELAY = 1 days
```


### yieldDispatcher

```solidity
address public yieldDispatcher
```


### asset

```solidity
address public asset
```


### totalAssets

```solidity
uint256 public totalAssets
```


### verseId

```solidity
uint256 public verseId
```


### redeemRequestQueues

```solidity
mapping(address account => RedeemRequest[]) public redeemRequestQueues
```


## Functions
### initialize


```solidity
function initialize(
    string memory _name,
    string memory _symbol,
    address _yieldDispatcher,
    address _asset,
    uint256 _verseId
) external override initializer;
```

### clock


```solidity
function clock() public view override returns (uint48);
```

### CLOCK_MODE


```solidity
function CLOCK_MODE() public pure override returns (string memory);
```

### previewDeposit


```solidity
function previewDeposit(uint256 assets) external view override returns (uint256);
```

### previewRedeem


```solidity
function previewRedeem(uint256 shares) external view override returns (uint256);
```

### accumulateYields

Accumulate yields


```solidity
function accumulateYields(uint256 yield) external override;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`yield`|`uint256`|- The amount of yields to accumulate|


### reAccumulateYields

Re-accumulate yields from unexecuted allocations


```solidity
function reAccumulateYields(bytes32 lzGuid) external override;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`lzGuid`|`bytes32`|- The unique identifier for the allocation LayerZero message.|


### deposit

Mints shares Vault shares to receiver by depositing exactly amount of underlying tokens


```solidity
function deposit(uint256 assets, address receiver) external override returns (uint256);
```

### requestRedeem

Burns exactly shares from owner and request sends assets of underlying tokens to receiver.


```solidity
function requestRedeem(uint256 shares, address receiver) external override returns (uint256);
```

### executeRedeem

Check the redeemable requests in the request queue and execute the redemption.


```solidity
function executeRedeem() external override returns (uint256 redeemedAmount);
```

### _requestWithdraw


```solidity
function _requestWithdraw(address sender, address receiver, uint256 assets, uint256 shares) internal;
```

### _convertToShares


```solidity
function _convertToShares(uint256 assets, uint256 latestTotalAssets) internal view returns (uint256);
```

### _convertToAssets


```solidity
function _convertToAssets(uint256 shares, uint256 latestTotalAssets) internal view returns (uint256);
```

### _deposit


```solidity
function _deposit(address sender, address receiver, uint256 assets, uint256 shares) internal;
```

### _update


```solidity
function _update(address from, address to, uint256 value) internal override(OutrunERC20Init, OutrunERC20VotesInit);
```

### nonces


```solidity
function nonces(address owner) public view override(OutrunERC20PermitInit, OutrunNoncesInit) returns (uint256);
```

