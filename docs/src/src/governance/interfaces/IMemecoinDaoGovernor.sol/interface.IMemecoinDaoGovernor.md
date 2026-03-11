# IMemecoinDaoGovernor
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/5f1e475fc32b5b93b8a81ca9d545cacad2f7567c/src/governance/interfaces/IMemecoinDaoGovernor.sol)

**Title:**
MemecoinDaoGovernor interface


## Functions
### initialize


```solidity
function initialize(
    string memory _name,
    IVotes _token,
    uint48 _votingDelay,
    uint32 _votingPeriod,
    uint256 _proposalThreshold,
    uint256 _quorumNumerator,
    address _governanceCycleIncentivizer
) external;
```

### governanceCycleIncentivizer


```solidity
function governanceCycleIncentivizer() external view returns (address);
```

### receiveTreasuryIncome


```solidity
function receiveTreasuryIncome(address token, uint256 amount) external;
```

### sendTreasuryAssets


```solidity
function sendTreasuryAssets(address token, address to, uint256 amount) external;
```

## Errors
### UserHasUnfinalizedProposal

```solidity
error UserHasUnfinalizedProposal();
```

## Structs
### MemecoinDaoGovernorStorage

```solidity
struct MemecoinDaoGovernorStorage {
    IGovernanceCycleIncentivizer _governanceCycleIncentivizer;
    mapping(address => uint256) userUnfinalizedProposalId;
}
```

