# GovernanceCycleIncentivizerUpgradeable
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/5f1e475fc32b5b93b8a81ca9d545cacad2f7567c/src/governance/GovernanceCycleIncentivizerUpgradeable.sol)

**Inherits:**
[IGovernanceCycleIncentivizer](/src/governance/interfaces/IGovernanceCycleIncentivizer.sol/interface.IGovernanceCycleIncentivizer.md), [Initializable](/src/common/Initializable.sol/abstract.Initializable.md), UUPSUpgradeable

External expansion of {Governor} for governance cycle incentive.


## State Variables
### RATIO

```solidity
uint256 public constant RATIO = 10000
```


### CYCLE_DURATION

```solidity
uint256 public constant CYCLE_DURATION = 90 days
```


### MAX_TOKENS_LIMIT

```solidity
uint256 public constant MAX_TOKENS_LIMIT = 50
```


### GovernanceCycleIncentivizerStorageLocation

```solidity
bytes32 private constant GovernanceCycleIncentivizerStorageLocation =
    0x173bbd0db440ff8dcb0efb05aced4279e21e45a07b4974973a371552ef840a00
```


## Functions
### _getGovernanceCycleIncentivizerStorage


```solidity
function _getGovernanceCycleIncentivizerStorage()
    private
    pure
    returns (GovernanceCycleIncentivizerStorage storage $);
```

### __GovernanceCycleIncentivizer_init


```solidity
function __GovernanceCycleIncentivizer_init(address governor, address[] calldata initTreasuryTokens)
    internal
    onlyInitializing;
```

### onlyGovernance


```solidity
modifier onlyGovernance() ;
```

### _onlyGovernance


```solidity
function _onlyGovernance() internal view;
```

### constructor


```solidity
constructor() ;
```

### initialize

Initialize the governanceCycleIncentivizer.


```solidity
function initialize(address governor, address[] calldata initFundTokens) external override initializer;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`governor`|`address`|- The DAO Governor|
|`initFundTokens`|`address[]`|- The initial DAO fund tokens.|


### currentCycleId

Get current cycle ID


```solidity
function currentCycleId() external view override returns (uint256);
```

### metaData

Get the contract meta data


```solidity
function metaData()
    external
    view
    override
    returns (
        uint128 _currentCycleId,
        uint128 _rewardRatio,
        address _governor,
        address[] memory _treasuryTokenList,
        address[] memory _rewardTokenList
    );
```

### cycleInfo

Get cycle meta info


```solidity
function cycleInfo(uint128 cycleId)
    external
    view
    override
    returns (
        uint128 startTime,
        uint128 endTime,
        uint256 totalVotes,
        address[] memory treasuryTokenList,
        address[] memory rewardTokenList
    );
```

### getUserVotesCount

Get user votes count


```solidity
function getUserVotesCount(address user, uint128 cycleId) external view override returns (uint256);
```

### isTreasuryToken

Check treasury token


```solidity
function isTreasuryToken(uint128 cycleId, address token) external view override returns (bool);
```

### isRewardToken

Check reward token


```solidity
function isRewardToken(uint128 cycleId, address token) external view override returns (bool);
```

### getClaimableReward

Get the specific token rewards claimable by the user for the previous cycle


```solidity
function getClaimableReward(address user, address token) external view override returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`user`|`address`|- The user address|
|`token`|`address`|- The token address|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The specific token rewards claimable by the user for the previous cycle|


### getClaimableReward

Get all registered token rewards claimable by the user for the previous cycle


```solidity
function getClaimableReward(address user)
    external
    view
    override
    returns (address[] memory tokens, uint256[] memory rewards);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`user`|`address`|- The user address|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`tokens`|`address[]`|- Tokens Array of token addresses|
|`rewards`|`uint256[]`|- All registered token rewards|


### getRemainingClaimableRewards

Get the specific token remaining rewards claimable for the previous cycle


```solidity
function getRemainingClaimableRewards(address token) external view override returns (uint256 remainingReward);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|- The token address|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`remainingReward`|`uint256`|- The specific token remaining rewards claimable|


### getRemainingClaimableRewards

Get all registered token remaining rewards claimable for the previous cycle


```solidity
function getRemainingClaimableRewards()
    external
    view
    override
    returns (address[] memory tokens, uint256[] memory rewards);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`tokens`|`address[]`|- Tokens Array of token addresses|
|`rewards`|`uint256[]`|- All registered token rewards|


### getTreasuryBalance

Get treasury balance for a specific cycle


```solidity
function getTreasuryBalance(uint128 cycleId, address token) external view override returns (uint256);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`cycleId`|`uint128`|- The cycle ID|
|`token`|`address`|- The token address|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`<none>`|`uint256`|The treasury balance for the specific cycle|


### getTreasuryBalances

Get all registered tokens' treasury balances for a specific cycle


```solidity
function getTreasuryBalances(uint128 cycleId)
    external
    view
    override
    returns (address[] memory tokens, uint256[] memory balances);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`cycleId`|`uint128`|- The cycle ID|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`tokens`|`address[]`|- Tokens Array of token addresses|
|`balances`|`uint256[]`|- Balances Array of corresponding treasury balances|


### receiveTreasuryIncome

Receive treasury income


```solidity
function receiveTreasuryIncome(address token, uint256 amount) external override;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|- The token address|
|`amount`|`uint256`|- The amount|


### sendTreasuryAssets

All actions to transfer assets from the DAO treasury MUST call this function

Transfer treasury assets to another address


```solidity
function sendTreasuryAssets(address token, address to, uint256 amount) external override onlyGovernance;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|- The token address|
|`to`|`address`|- The receiver address|
|`amount`|`uint256`|- The amount to transfer|


### finalizeCurrentCycle

End current cycle and start new cycle


```solidity
function finalizeCurrentCycle() external override;
```

### claimReward

Claim reward


```solidity
function claimReward() external override onlyGovernance;
```

### accumCycleVotes

Accumulate cycle votes


```solidity
function accumCycleVotes(address user, uint256 votes) external override onlyGovernance;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`user`|`address`|- The user address|
|`votes`|`uint256`|- The number of votes|


### registerTreasuryToken

MUST confirm that the registered token is not a malicious token

Register for receivable treasury token


```solidity
function registerTreasuryToken(address token) public override onlyGovernance;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|- The token address|


### registerRewardToken

MUST confirm that the registered token is not a malicious token

Register for reward token，it MUST first be registered as a treasury token.


```solidity
function registerRewardToken(address token) public override onlyGovernance;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|- The token address|


### unregisterTreasuryToken

Unregister for receivable treasury token


```solidity
function unregisterTreasuryToken(address token) external override onlyGovernance;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|- The token address|


### unregisterRewardToken

Unregister for reward token


```solidity
function unregisterRewardToken(address token) external override onlyGovernance;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|- The token address|


### updateRewardRatio

Update reward ratio


```solidity
function updateRewardRatio(uint128 newRatio) external override onlyGovernance;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newRatio`|`uint128`|- The new reward ratio (basis points)|


### _registerTreasuryToken


```solidity
function _registerTreasuryToken(address token, GovernanceCycleIncentivizerStorage storage $) internal;
```

### _registerRewardToken


```solidity
function _registerRewardToken(address token, GovernanceCycleIncentivizerStorage storage $) internal;
```

### _unregisterRewardToken


```solidity
function _unregisterRewardToken(address token, GovernanceCycleIncentivizerStorage storage $) internal;
```

### _authorizeUpgrade

Allowing upgrades to the implementation contract only through governance proposals.


```solidity
function _authorizeUpgrade(address newImplementation) internal override onlyGovernance;
```

