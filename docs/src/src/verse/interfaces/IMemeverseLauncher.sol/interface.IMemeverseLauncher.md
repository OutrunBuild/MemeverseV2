# IMemeverseLauncher
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/f6152b6dbfadcd8a23a2d518905418243cf2a5e1/src/verse/interfaces/IMemeverseLauncher.sol)

**Inherits:**
[MemeverseOFTEnum](/src/common/MemeverseOFTEnum.sol/interface.MemeverseOFTEnum.md)

**Title:**
MemeverseLauncher interface


## Functions
### getVerseIdByMemecoin


```solidity
function getVerseIdByMemecoin(address memecoin) external view returns (uint256 verseId);
```

### getMemeverseByVerseId


```solidity
function getMemeverseByVerseId(uint256 verseId) external view returns (Memeverse memory verse);
```

### getMemeverseByMemecoin


```solidity
function getMemeverseByMemecoin(address memecoin) external view returns (Memeverse memory verse);
```

### getStageByVerseId


```solidity
function getStageByVerseId(uint256 verseId) external view returns (Stage stage);
```

### getStageByMemecoin


```solidity
function getStageByMemecoin(address memecoin) external view returns (Stage stage);
```

### getYieldVaultByVerseId


```solidity
function getYieldVaultByVerseId(uint256 verseId) external view returns (address yieldVault);
```

### getGovernorByVerseId


```solidity
function getGovernorByVerseId(uint256 verseId) external view returns (address governor);
```

### claimablePOLToken


```solidity
function claimablePOLToken(uint256 verseId) external view returns (uint256 claimableAmount);
```

### previewGenesisMakerFees


```solidity
function previewGenesisMakerFees(uint256 verseId) external view returns (uint256 UPTFee, uint256 memecoinFee);
```

### quoteDistributionLzFee


```solidity
function quoteDistributionLzFee(uint256 verseId) external view returns (uint256 lzFee);
```

### genesis


```solidity
function genesis(uint256 verseId, uint128 amountInUPT, address user) external;
```

### changeStage


```solidity
function changeStage(uint256 verseId) external returns (Stage currentStage);
```

### refund


```solidity
function refund(uint256 verseId) external returns (uint256 userFunds);
```

### claimPOLToken


```solidity
function claimPOLToken(uint256 verseId) external returns (uint256 amount);
```

### redeemAndDistributeFees


```solidity
function redeemAndDistributeFees(uint256 verseId, address rewardReceiver)
    external
    payable
    returns (uint256 govFee, uint256 memecoinFee, uint256 liquidProofFee, uint256 executorReward);
```

### redeemMemecoinLiquidity


```solidity
function redeemMemecoinLiquidity(uint256 verseId, uint256 amountInPOL) external returns (uint256 amountInLP);
```

### redeemPolLiquidity


```solidity
function redeemPolLiquidity(uint256 verseId) external returns (uint256 amountInLP);
```

### mintPOLToken


```solidity
function mintPOLToken(
    uint256 verseId,
    uint256 amountInUPTDesired,
    uint256 amountInMemecoinDesired,
    uint256 amountInUPTMin,
    uint256 amountInMemecoinMin,
    uint256 amountOutDesired,
    uint256 deadline
) external returns (uint256 amountInUPT, uint256 amountInMemecoin, uint256 amountOut);
```

### registerMemeverse


```solidity
function registerMemeverse(
    string calldata name,
    string calldata symbol,
    uint256 uniqueId,
    uint128 endTime,
    uint128 unlockTime,
    uint32[] calldata omnichainIds,
    address UPT,
    bool flashGenesis
) external;
```

### removeGasDust


```solidity
function removeGasDust(address receiver) external;
```

### setMemeverseSwapRouter


```solidity
function setMemeverseSwapRouter(address memeverseSwapRouter) external;
```

### setMemeverseCommonInfo


```solidity
function setMemeverseCommonInfo(address memeverseCommonInfo) external;
```

### setMemeverseRegistrar


```solidity
function setMemeverseRegistrar(address memeverseRegistrar) external;
```

### setMemeverseProxyDeployer


```solidity
function setMemeverseProxyDeployer(address memeverseProxyDeployer) external;
```

### setOFTDispatcher


```solidity
function setOFTDispatcher(address oftDispatcher) external;
```

### setFundMetaData


```solidity
function setFundMetaData(address upt, uint256 minTotalFund, uint256 fundBasedAmount) external;
```

### setExecutorRewardRate


```solidity
function setExecutorRewardRate(uint256 executorRewardRate) external;
```

### setGasLimits


```solidity
function setGasLimits(uint128 oftReceiveGasLimit, uint128 oftDispatcherGasLimit) external;
```

### setExternalInfo


```solidity
function setExternalInfo(
    uint256 verseId,
    string calldata uri,
    string calldata description,
    string[] calldata communities
) external;
```

## Events
### Genesis

```solidity
event Genesis(
    uint256 indexed verseId,
    address indexed depositer,
    uint128 increasedMemecoinFund,
    uint128 increasedLiquidProofFund
);
```

### ChangeStage

```solidity
event ChangeStage(uint256 indexed verseId, Stage currentStage);
```

### Refund

```solidity
event Refund(uint256 indexed verseId, address indexed receiver, uint256 refundAmount);
```

### ClaimPOLToken

```solidity
event ClaimPOLToken(uint256 indexed verseId, address indexed receiver, uint256 claimedAmount);
```

### RedeemAndDistributeFees

```solidity
event RedeemAndDistributeFees(
    uint256 indexed verseId, uint256 govFee, uint256 memecoinFee, uint256 liquidProofFee, uint256 executorReward
);
```

### RedeemMemecoinLiquidity

```solidity
event RedeemMemecoinLiquidity(uint256 indexed verseId, address indexed receiver, uint256 memecoinLiquidity);
```

### RedeemPolLiquidity

```solidity
event RedeemPolLiquidity(uint256 indexed verseId, address indexed receiver, uint256 polLiquidity);
```

### MintPOLToken

```solidity
event MintPOLToken(
    uint256 indexed verseId, address indexed memecoin, address indexed liquidProof, address receiver, uint256 amount
);
```

### RegisterMemeverse

```solidity
event RegisterMemeverse(uint256 indexed verseId, Memeverse verse);
```

### RemoveGasDust

```solidity
event RemoveGasDust(address indexed receiver, uint256 dust);
```

### SetMemeverseSwapRouter

```solidity
event SetMemeverseSwapRouter(address memeverseSwapRouter);
```

### SetMemeverseCommonInfo

```solidity
event SetMemeverseCommonInfo(address memeverseCommonInfo);
```

### SetMemeverseRegistrar

```solidity
event SetMemeverseRegistrar(address memeverseRegistrar);
```

### SetMemeverseProxyDeployer

```solidity
event SetMemeverseProxyDeployer(address memeverseProxyDeployer);
```

### SetOFTDispatcher

```solidity
event SetOFTDispatcher(address oftDispatcher);
```

### SetFundMetaData

```solidity
event SetFundMetaData(address indexed upt, uint256 minTotalFund, uint256 fundBasedAmount);
```

### SetExecutorRewardRate

```solidity
event SetExecutorRewardRate(uint256 executorRewardRate);
```

### SetGasLimits

```solidity
event SetGasLimits(uint128 oftReceiveGasLimit, uint128 oftDispatcherGasLimit);
```

### SetExternalInfo

```solidity
event SetExternalInfo(uint256 indexed verseId, string uri, string description, string[] community);
```

## Errors
### ZeroInput

```solidity
error ZeroInput();
```

### InvalidLength

```solidity
error InvalidLength();
```

### InvalidRefund

```solidity
error InvalidRefund();
```

### InvalidRedeem

```solidity
error InvalidRedeem();
```

### NoPOLAvailable

```solidity
error NoPOLAvailable();
```

### NotRefundStage

```solidity
error NotRefundStage();
```

### InvalidVerseId

```solidity
error InvalidVerseId();
```

### NotGenesisStage

```solidity
error NotGenesisStage();
```

### FeeRateOverFlow

```solidity
error FeeRateOverFlow();
```

### PermissionDenied

```solidity
error PermissionDenied();
```

### NotUnlockedStage

```solidity
error NotUnlockedStage();
```

### InsufficientLzFee

```solidity
error InsufficientLzFee();
```

### ReachedFinalStage

```solidity
error ReachedFinalStage();
```

### InsufficientLPBalance

```solidity
error InsufficientLPBalance();
```

### NotReachedLockedStage

```solidity
error NotReachedLockedStage();
```

### StillInGenesisStage

```solidity
error StillInGenesisStage(uint256 endTime);
```

### InvalidOmnichainId

```solidity
error InvalidOmnichainId(uint32 omnichainId);
```

## Structs
### Memeverse

```solidity
struct Memeverse {
    string name; // Token name
    string symbol; // Token symbol
    string uri; // Token icon uri
    string desc; // Description
    address UPT; // Genesis fund UPT address
    address memecoin; // Omnichain memecoin address
    address liquidProof; // POL token address
    address yieldVault; // Memecoin yield vault
    address governor; // Memecoin DAO governor
    address incentivizer; // Governance cycle incentivizer
    uint128 endTime; // End time of Genesis stage
    uint128 unlockTime; // UnlockTime of liquidity
    uint32[] omnichainIds; // ChainIds of the token's omnichain(EVM),The first chainId is main governance chain
    Stage currentStage; // Current stage
    bool flashGenesis; // Allowing the transition to the liquidity lock stage once the minimum funding requirement is met, without waiting for the genesis stage to end.
}
```

### FundMetaData

```solidity
struct FundMetaData {
    uint256 minTotalFund; // The minimum participation genesis fund corresponding to UPT
    uint256 fundBasedAmount; // The number of Memecoins minted per unit of Memecoin genesis fund
}
```

### GenesisFund

```solidity
struct GenesisFund {
    uint128 totalMemecoinFunds; // Initial fundraising(UPT) for memecoin liquidity
    uint128 totalLiquidProofFunds; // Initial fundraising(UPT) for liquidProof liquidity
}
```

### GenesisData

```solidity
struct GenesisData {
    uint256 genesisFund; // The amount of UPT user has contributed to the genesis fund
    bool isRefunded; // Whether the user has refunded the UPT
    bool isClaimed; // Whether the user has claimed the POL
    bool isRedeemed; // Whether the user has redeemed the POL liquidity
}
```

## Enums
### Stage

```solidity
enum Stage {
    Genesis,
    Refund,
    Locked,
    Unlocked
}
```

