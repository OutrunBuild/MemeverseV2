# MemecoinDaoGovernorUpgradeable
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/f6152b6dbfadcd8a23a2d518905418243cf2a5e1/src/governance/MemecoinDaoGovernorUpgradeable.sol)

**Inherits:**
[IMemecoinDaoGovernor](/src/governance/interfaces/IMemecoinDaoGovernor.sol/interface.IMemecoinDaoGovernor.md), [Initializable](/src/common/Initializable.sol/abstract.Initializable.md), GovernorUpgradeable, GovernorSettingsUpgradeable, GovernorCountingFractionalUpgradeable, GovernorStorageUpgradeable, GovernorVotesUpgradeable, GovernorVotesQuorumFractionUpgradeable, UUPSUpgradeable

**Title:**
Memecoin DAO Governor

This contract is a modified version of the GovernorUpgradeable contract from OpenZeppelin.

It is used to manage the DAO of the Memecoin project, also as Memecoin DAO Treasury.


## State Variables
### MemecoinDaoGovernorStorageLocation

```solidity
bytes32 private constant MemecoinDaoGovernorStorageLocation =
    0x173bbd0db440ff8dcb0efb05aced4279e21e45a07b4974973a371552ef840a00
```


## Functions
### _getMemecoinDaoGovernorStorage


```solidity
function _getMemecoinDaoGovernorStorage() private pure returns (MemecoinDaoGovernorStorage storage $);
```

### __MemecoinDaoGovernor_init


```solidity
function __MemecoinDaoGovernor_init(address _governanceCycleIncentivizer) internal onlyInitializing;
```

### constructor


```solidity
constructor() ;
```

### initialize

Initialize the governor.


```solidity
function initialize(
    string memory _name,
    IVotes _token,
    uint48 _votingDelay,
    uint32 _votingPeriod,
    uint256 _proposalThreshold,
    uint256 _quorumNumerator,
    address _governanceCycleIncentivizer
) external override initializer;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_name`|`string`|- The name of the governor.|
|`_token`|`IVotes`|- The vote token of the governor.|
|`_votingDelay`|`uint48`|- The voting delay.|
|`_votingPeriod`|`uint32`|- The voting period.|
|`_proposalThreshold`|`uint256`|- The proposal threshold.|
|`_quorumNumerator`|`uint256`|- The quorum numerator.|
|`_governanceCycleIncentivizer`|`address`|- The governanceCycleIncentivizer.|


### votingDelay


```solidity
function votingDelay() public view override(GovernorUpgradeable, GovernorSettingsUpgradeable) returns (uint256);
```

### votingPeriod


```solidity
function votingPeriod() public view override(GovernorUpgradeable, GovernorSettingsUpgradeable) returns (uint256);
```

### quorum


```solidity
function quorum(uint256 blockNumber)
    public
    view
    override(GovernorUpgradeable, GovernorVotesQuorumFractionUpgradeable)
    returns (uint256);
```

### proposalThreshold


```solidity
function proposalThreshold()
    public
    view
    override(GovernorUpgradeable, GovernorSettingsUpgradeable)
    returns (uint256);
```

### governanceCycleIncentivizer


```solidity
function governanceCycleIncentivizer() external view override returns (address);
```

### propose


```solidity
function propose(
    address[] memory targets,
    uint256[] memory values,
    bytes[] memory calldatas,
    string memory description
) public override returns (uint256);
```

### execute


```solidity
function execute(
    address[] memory targets,
    uint256[] memory values,
    bytes[] memory calldatas,
    bytes32 descriptionHash
) public payable override returns (uint256);
```

### _cancel


```solidity
function _cancel(
    address[] memory targets,
    uint256[] memory values,
    bytes[] memory calldatas,
    bytes32 descriptionHash
) internal override returns (uint256);
```

### receiveTreasuryIncome

Receive treasury income


```solidity
function receiveTreasuryIncome(address _token, uint256 _amount) external override;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_token`|`address`|- The token address|
|`_amount`|`uint256`|- The amount|


### sendTreasuryAssets

All actions to transfer assets from the DAO treasury MUST call this function

Transfer treasury assets to another address


```solidity
function sendTreasuryAssets(address _token, address _to, uint256 _amount) external override onlyGovernance;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_token`|`address`|- The token address|
|`_to`|`address`|- The receiver address|
|`_amount`|`uint256`|- The amount to transfer|


### _propose


```solidity
function _propose(
    address[] memory targets,
    uint256[] memory values,
    bytes[] memory calldatas,
    string memory description,
    address proposer
) internal override(GovernorUpgradeable, GovernorStorageUpgradeable) returns (uint256);
```

### _castVote


```solidity
function _castVote(uint256 proposalId, address account, uint8 support, string memory reason, bytes memory params)
    internal
    override
    returns (uint256);
```

### _authorizeUpgrade

Allowing upgrades to the implementation contract only through governance proposals.


```solidity
function _authorizeUpgrade(address newImplementation) internal override onlyGovernance;
```

