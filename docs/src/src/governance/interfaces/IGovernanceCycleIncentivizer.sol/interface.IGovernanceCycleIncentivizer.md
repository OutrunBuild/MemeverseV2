# IGovernanceCycleIncentivizer
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/5f1e475fc32b5b93b8a81ca9d545cacad2f7567c/src/governance/interfaces/IGovernanceCycleIncentivizer.sol)

External expansion of {Governor} for governance cycle incentive.


## Functions
### initialize

Initialize the governanceCycleIncentivizer.


```solidity
function initialize(address governor, address[] calldata initFundTokens) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`governor`|`address`|- The DAO Governor|
|`initFundTokens`|`address[]`|- The initial DAO fund tokens.|


### currentCycleId

Get current cycle ID


```solidity
function currentCycleId() external view returns (uint256);
```

### metaData

Get the contract meta data


```solidity
function metaData()
    external
    view
    returns (
        uint128 currentCycleId,
        uint128 rewardRatio,
        address governor,
        address[] memory treasuryTokenList,
        address[] memory rewardTokenList
    );
```

### cycleInfo

Get cycle meta info


```solidity
function cycleInfo(uint128 cycleId)
    external
    view
    returns (
        uint128 startTime,
        uint128 endTime,
        uint256 totalVotes,
        address[] memory treasuryTokenList,
        address[] memory rewardTokenList
    );
```

### getUserVotesCount

Get user votes


```solidity
function getUserVotesCount(address user, uint128 cycleId) external view returns (uint256);
```

### isTreasuryToken

Check treasury token


```solidity
function isTreasuryToken(uint128 cycleId, address token) external view returns (bool);
```

### isRewardToken

Check reward token


```solidity
function isRewardToken(uint128 cycleId, address token) external view returns (bool);
```

### getClaimableReward

Get the specific token rewards claimable by the user for the previous cycle


```solidity
function getClaimableReward(address user, address token) external view returns (uint256);
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
function getClaimableReward(address user) external view returns (address[] memory tokens, uint256[] memory rewards);
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
function getRemainingClaimableRewards(address token) external view returns (uint256 remainingReward);
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
function getRemainingClaimableRewards() external view returns (address[] memory tokens, uint256[] memory rewards);
```
**Returns**

|Name|Type|Description|
|----|----|-----------|
|`tokens`|`address[]`|- Tokens Array of token addresses|
|`rewards`|`uint256[]`|- All registered token rewards|


### getTreasuryBalance

Get treasury balance for a specific cycle


```solidity
function getTreasuryBalance(uint128 cycleId, address token) external view returns (uint256);
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
function receiveTreasuryIncome(address token, uint256 amount) external;
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
function sendTreasuryAssets(address token, address to, uint256 amount) external;
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
function finalizeCurrentCycle() external;
```

### claimReward

Claim reward


```solidity
function claimReward() external;
```

### accumCycleVotes

Accumulate cycle votes


```solidity
function accumCycleVotes(address user, uint256 votes) external;
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
function registerTreasuryToken(address token) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|- The token address|


### registerRewardToken

MUST confirm that the registered token is not a malicious token

Register for reward token，it MUST first be registered as a treasury token.


```solidity
function registerRewardToken(address token) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|- The token address|


### unregisterTreasuryToken

Unregister for receivable treasury token


```solidity
function unregisterTreasuryToken(address token) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|- The token address|


### unregisterRewardToken

Unregister for reward token


```solidity
function unregisterRewardToken(address token) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|- The token address|


### updateRewardRatio

Update reward ratio


```solidity
function updateRewardRatio(uint128 newRatio) external;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newRatio`|`uint128`|- The new reward ratio (basis points)|


## Events
### CycleFinalized

```solidity
event CycleFinalized(
    uint128 indexed cycleId,
    uint128 endTime,
    address[] treasuryTokens,
    uint256[] balances,
    address[] rewardTokens,
    uint256[] rewards
);
```

### CycleStarted

```solidity
event CycleStarted(
    uint128 indexed cycleId, uint128 startTime, uint128 endTime, address[] tokens, uint256[] balances
);
```

### RewardTokenRegistered

```solidity
event RewardTokenRegistered(address indexed token);
```

### RewardTokenUnregistered

```solidity
event RewardTokenUnregistered(address indexed token);
```

### TreasuryTokenRegistered

```solidity
event TreasuryTokenRegistered(address indexed token);
```

### TreasuryTokenUnregistered

```solidity
event TreasuryTokenUnregistered(address indexed token);
```

### RewardRatioUpdated

```solidity
event RewardRatioUpdated(uint256 oldRatio, uint256 newRatio);
```

### RewardClaimed

```solidity
event RewardClaimed(address indexed user, uint128 indexed cycleId, address indexed token, uint256 amount);
```

### TreasuryReceived

```solidity
event TreasuryReceived(uint256 indexed cycleId, address indexed token, address indexed sender, uint256 amount);
```

### TreasurySent

```solidity
event TreasurySent(uint256 indexed cycleId, address indexed token, address indexed receiver, uint256 amount);
```

### AccumCycleVotes

```solidity
event AccumCycleVotes(uint256 indexed cycleId, address indexed user, uint256 votes);
```

## Errors
### ZeroInput

```solidity
error ZeroInput();
```

### CycleNotEnded

```solidity
error CycleNotEnded();
```

### RegisteredToken

```solidity
error RegisteredToken();
```

### NonTreasuryToken

```solidity
error NonTreasuryToken();
```

### PermissionDenied

```solidity
error PermissionDenied();
```

### NoRewardsToClaim

```solidity
error NoRewardsToClaim();
```

### NonRegisteredToken

```solidity
error NonRegisteredToken();
```

### InvalidRewardRatio

```solidity
error InvalidRewardRatio();
```

### OutOfMaxTokensLimit

```solidity
error OutOfMaxTokensLimit();
```

### InsufficientTreasuryBalance

```solidity
error InsufficientTreasuryBalance();
```

## Structs
### Cycle

```solidity
struct Cycle {
    uint128 startTime;
    uint128 endTime;
    uint256 totalVotes;
    mapping(address => uint256) treasuryBalances;
    mapping(address => uint256) rewardBalances;
    mapping(address => uint256) userVotes;
    address[] treasuryTokenList;
    address[] rewardTokenList;
}
```

### GovernanceCycleIncentivizerStorage

```solidity
struct GovernanceCycleIncentivizerStorage {
    uint128 _rewardRatio;
    uint128 _currentCycleId;
    address _governor;
    address[] _rewardTokenList;
    address[] _treasuryTokenList;
    mapping(uint128 cycleId => Cycle) _cycles;
    mapping(address token => bool) _rewardTokens;
    mapping(address token => bool) _treasuryTokens;
}
```

