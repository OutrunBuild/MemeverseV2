# MemeverseProxyDeployer
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/f6152b6dbfadcd8a23a2d518905418243cf2a5e1/src/verse/MemeverseProxyDeployer.sol)

**Inherits:**
[IMemeverseProxyDeployer](/src/verse/interfaces/IMemeverseProxyDeployer.sol/interface.IMemeverseProxyDeployer.md), Ownable

**Title:**
MemeverseProxyDeployer Contract


## State Variables
### memeverseLauncher

```solidity
address public immutable memeverseLauncher
```


### memecoinImplementation

```solidity
address public immutable memecoinImplementation
```


### polImplementation

```solidity
address public immutable polImplementation
```


### vaultImplementation

```solidity
address public immutable vaultImplementation
```


### governorImplementation

```solidity
address public immutable governorImplementation
```


### incentivizerImplementation

```solidity
address public immutable incentivizerImplementation
```


### quorumNumerator

```solidity
uint256 public quorumNumerator
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
constructor(
    address _owner,
    address _memeverseLauncher,
    address _memecoinImplementation,
    address _polImplementation,
    address _vaultImplementation,
    address _governorImplementation,
    address _incentivizerImplementation,
    uint256 _quorumNumerator
) Ownable(_owner);
```

### predictYieldVaultAddress

Predict memecoin yield vault address


```solidity
function predictYieldVaultAddress(uint256 uniqueId) external view override returns (address);
```

### computeGovernorAndIncentivizerAddress

Compute memecoin DAO governor and Incentivizer contract address


```solidity
function computeGovernorAndIncentivizerAddress(uint256 uniqueId)
    external
    view
    override
    returns (address governor, address incentivizer);
```

### deployMemecoin

Deploy memecoin proxy contract


```solidity
function deployMemecoin(uint256 uniqueId) external override onlyMemeverseLauncher returns (address memecoin);
```

### deployPOL

Deploy POL proxy contract


```solidity
function deployPOL(uint256 uniqueId) external override onlyMemeverseLauncher returns (address pol);
```

### deployYieldVault

Deploy memecoin yield vault proxy contract


```solidity
function deployYieldVault(uint256 uniqueId) external override onlyMemeverseLauncher returns (address yieldVault);
```

### deployGovernorAndIncentivizer

Deploy Memecoin DAO governor and Incentivizer proxy contract


```solidity
function deployGovernorAndIncentivizer(
    string calldata memecoinName,
    address UPT,
    address memecoin,
    address pol,
    address yieldVault,
    uint256 uniqueId,
    uint256 proposalThreshold
) external override onlyMemeverseLauncher returns (address governor, address incentivizer);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`memecoinName`|`string`|- The name of memecoin|
|`UPT`|`address`||
|`memecoin`|`address`||
|`pol`|`address`||
|`yieldVault`|`address`||
|`uniqueId`|`uint256`|- The verseId|
|`proposalThreshold`|`uint256`|- Proposal Threshold|


### setQuorumNumerator

Set quorumNumerator


```solidity
function setQuorumNumerator(uint256 _quorumNumerator) external override onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_quorumNumerator`|`uint256`|- quorumNumerator|


