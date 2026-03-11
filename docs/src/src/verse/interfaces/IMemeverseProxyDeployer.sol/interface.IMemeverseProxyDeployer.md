# IMemeverseProxyDeployer
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/f6152b6dbfadcd8a23a2d518905418243cf2a5e1/src/verse/interfaces/IMemeverseProxyDeployer.sol)

Interface for the Memeverse Proxy Contract Deployer.


## Functions
### predictYieldVaultAddress


```solidity
function predictYieldVaultAddress(uint256 uniqueId) external view returns (address);
```

### computeGovernorAndIncentivizerAddress


```solidity
function computeGovernorAndIncentivizerAddress(uint256 uniqueId)
    external
    view
    returns (address governor, address incentivizer);
```

### deployMemecoin


```solidity
function deployMemecoin(uint256 uniqueId) external returns (address memecoin);
```

### deployPOL


```solidity
function deployPOL(uint256 uniqueId) external returns (address pol);
```

### deployYieldVault


```solidity
function deployYieldVault(uint256 uniqueId) external returns (address yieldVault);
```

### deployGovernorAndIncentivizer


```solidity
function deployGovernorAndIncentivizer(
    string calldata memecoinName,
    address UPT,
    address memecoin,
    address pol,
    address yieldVault,
    uint256 uniqueId,
    uint256 proposalThreshold
) external returns (address governor, address incentivizer);
```

### setQuorumNumerator


```solidity
function setQuorumNumerator(uint256 quorumNumerator) external;
```

## Events
### DeployMemecoin

```solidity
event DeployMemecoin(uint256 indexed uniqueId, address memecoin);
```

### DeployPOL

```solidity
event DeployPOL(uint256 indexed uniqueId, address pol);
```

### DeployYieldVault

```solidity
event DeployYieldVault(uint256 indexed uniqueId, address yieldVault);
```

### DeployGovernorAndIncentivizer

```solidity
event DeployGovernorAndIncentivizer(uint256 indexed uniqueId, address governor, address incentivizer);
```

### SetQuorumNumerator

```solidity
event SetQuorumNumerator(uint256 quorumNumerator);
```

## Errors
### ZeroInput

```solidity
error ZeroInput();
```

### PermissionDenied

```solidity
error PermissionDenied();
```

