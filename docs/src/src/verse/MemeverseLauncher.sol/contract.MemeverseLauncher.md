# MemeverseLauncher
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/f6152b6dbfadcd8a23a2d518905418243cf2a5e1/src/verse/MemeverseLauncher.sol)

**Inherits:**
[IMemeverseLauncher](/src/verse/interfaces/IMemeverseLauncher.sol/interface.IMemeverseLauncher.md), [TokenHelper](/src/common/TokenHelper.sol/abstract.TokenHelper.md), Pausable, Ownable

**Title:**
Trapping into the memeverse


## State Variables
### RATIO

```solidity
uint256 public constant RATIO = 10000
```


### localLzEndpoint

```solidity
address public localLzEndpoint
```


### memeverseCommonInfo

```solidity
address public memeverseCommonInfo
```


### oftDispatcher

```solidity
address public oftDispatcher
```


### memeverseRegistrar

```solidity
address public memeverseRegistrar
```


### memeverseProxyDeployer

```solidity
address public memeverseProxyDeployer
```


### memeverseSwapRouter

```solidity
address public memeverseSwapRouter
```


### executorRewardRate

```solidity
uint256 public executorRewardRate
```


### oftReceiveGasLimit

```solidity
uint128 public oftReceiveGasLimit
```


### oftDispatcherGasLimit

```solidity
uint128 public oftDispatcherGasLimit
```


### fundMetaDatas

```solidity
mapping(address UPT => FundMetaData) public fundMetaDatas
```


### memecoinToIds

```solidity
mapping(address memecoin => uint256) public memecoinToIds
```


### memeverses

```solidity
mapping(uint256 verseId => Memeverse) public memeverses
```


### genesisFunds

```solidity
mapping(uint256 verseId => GenesisFund) public genesisFunds
```


### totalClaimablePOL

```solidity
mapping(uint256 verseId => uint256) public totalClaimablePOL
```


### totalPolLiquidity

```solidity
mapping(uint256 verseId => uint256) public totalPolLiquidity
```


### userGenesisData

```solidity
mapping(uint256 verseId => mapping(address account => GenesisData)) public userGenesisData
```


### communitiesMap

```solidity
mapping(uint256 verseId => mapping(uint256 provider => string)) public communitiesMap
```


## Functions
### constructor


```solidity
constructor(
    address _owner,
    address _localLzEndpoint,
    address _memeverseRegistrar,
    address _memeverseProxyDeployer,
    address _oftDispatcher,
    address _memeverseCommonInfo,
    uint256 _executorRewardRate,
    uint128 _oftReceiveGasLimit,
    uint128 _oftDispatcherGasLimit
) Ownable(_owner);
```

### versIdValidate


```solidity
modifier versIdValidate(uint256 verseId) ;
```

### _versIdValidate


```solidity
function _versIdValidate(uint256 verseId) internal view;
```

### getVerseIdByMemecoin

Get the verse id by memecoin.


```solidity
function getVerseIdByMemecoin(address memecoin) external view override returns (uint256 verseId);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`memecoin`|`address`|-The address of the memecoin.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`verseId`|`uint256`|The verse id.|


### getMemeverseByVerseId

Get the memeverse by verse id.


```solidity
function getMemeverseByVerseId(uint256 verseId) external view override returns (Memeverse memory verse);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`verseId`|`uint256`|- The verse id.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`verse`|`Memeverse`|- The memeverse.|


### getMemeverseByMemecoin

Get the memeverse by memecoin.


```solidity
function getMemeverseByMemecoin(address memecoin) external view override returns (Memeverse memory verse);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`memecoin`|`address`|- The address of the memecoin.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`verse`|`Memeverse`|- The memeverse.|


### getStageByVerseId

Get the Stage by verse id.


```solidity
function getStageByVerseId(uint256 verseId) external view override returns (Stage stage);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`verseId`|`uint256`|- The verse id.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`stage`|`Stage`|- The memeverse current stage.|


### getStageByMemecoin

Get the Stage by memecoin.


```solidity
function getStageByMemecoin(address memecoin) external view override returns (Stage stage);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`memecoin`|`address`|- The address of the memecoin.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`stage`|`Stage`|- The memeverse current stage.|


### getYieldVaultByVerseId

Get the yield vault by verse id.


```solidity
function getYieldVaultByVerseId(uint256 verseId) external view override returns (address yieldVault);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`verseId`|`uint256`|- The verse id.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`yieldVault`|`address`|- The yield vault.|


### getGovernorByVerseId

Get the governor by verse id.


```solidity
function getGovernorByVerseId(uint256 verseId) external view override returns (address governor);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`verseId`|`uint256`|- The verse id.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`governor`|`address`|- The governor.|


### claimablePOLToken

Preview claimable POL token of user after Genesis Stage


```solidity
function claimablePOLToken(uint256 verseId) public view override returns (uint256 claimableAmount);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`verseId`|`uint256`|- Memeverse id|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`claimableAmount`|`uint256`|- The claimable amount.|


### previewGenesisMakerFees

Preview Genesis liquidity market maker fees for DAO Treasury (UPT) and Yield Vault(Memecoin)


```solidity
function previewGenesisMakerFees(uint256 verseId)
    public
    view
    override
    returns (uint256 UPTFee, uint256 memecoinFee);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`verseId`|`uint256`|- Memeverse id|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`UPTFee`|`uint256`|- The UPT fee.|
|`memecoinFee`|`uint256`|- The memecoin fee.|


### quoteDistributionLzFee

The LZ fee is only charged when the governance chain is not the same as the current chain,
and msg.value needs to be greater than the quoted lzFee for the redeemAndDistributeFees transaction.

Quote the LZ fee for the redemption and distribution of fees


```solidity
function quoteDistributionLzFee(uint256 verseId) external view override returns (uint256 lzFee);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`verseId`|`uint256`|- Memeverse id|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`lzFee`|`uint256`|- The LZ fee.|


### genesis

Approve fund token first

Genesis memeverse by depositing UPT


```solidity
function genesis(uint256 verseId, uint128 amountInUPT, address user)
    external
    override
    versIdValidate(verseId)
    whenNotPaused;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`verseId`|`uint256`|- Memeverse id|
|`amountInUPT`|`uint128`|- Amount of UPT|
|`user`|`address`|- Address of user participating in the genesis|


### changeStage

Adaptively change the Memeverse stage


```solidity
function changeStage(uint256 verseId)
    external
    override
    versIdValidate(verseId)
    whenNotPaused
    returns (Stage currentStage);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`verseId`|`uint256`|- Memeverse id|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`currentStage`|`Stage`|- The current stage.|


### _handleGenesisStage

Handle Genesis stage logic


```solidity
function _handleGenesisStage(uint256 verseId, uint256 currentTime, Memeverse storage verse)
    internal
    returns (Stage currentStage);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`verseId`|`uint256`|- Memeverse id|
|`currentTime`|`uint256`|- Current timestamp|
|`verse`|`Memeverse`|- Memeverse storage reference|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`currentStage`|`Stage`|- The current stage|


### _deployAndSetupMemeverse

Deploy and setup memeverse components


```solidity
function _deployAndSetupMemeverse(
    uint256 verseId,
    Memeverse storage verse,
    address UPT,
    uint128 totalMemecoinFunds,
    uint128 totalLiquidProofFunds
) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`verseId`|`uint256`|- Memeverse id|
|`verse`|`Memeverse`|- Memeverse storage reference|
|`UPT`|`address`|- UPT address|
|`totalMemecoinFunds`|`uint128`|- Total memecoin funds|
|`totalLiquidProofFunds`|`uint128`|- Total liquid proof funds|


### _deployGovernanceComponents

Deploy governance components


```solidity
function _deployGovernanceComponents(
    uint256 verseId,
    uint32 govChainId,
    string memory name,
    string memory symbol,
    address UPT,
    address memecoin,
    address pol
) internal returns (address yieldVault, address governor, address incentivizer);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`verseId`|`uint256`|- Memeverse id|
|`govChainId`|`uint32`|- Governance chain id|
|`name`|`string`|- Token name|
|`symbol`|`string`|- Token symbol|
|`UPT`|`address`|- UPT address|
|`memecoin`|`address`|- Memecoin address|
|`pol`|`address`|- POL address|


### _deployLiquidity

Deploy liquidity pools


```solidity
function _deployLiquidity(
    uint256 verseId,
    address UPT,
    address memecoin,
    address pol,
    uint128 totalMemecoinFunds,
    uint128 totalLiquidProofFunds
) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`verseId`|`uint256`|- Memeverse id|
|`UPT`|`address`|- UPT address|
|`memecoin`|`address`|- Memecoin address|
|`pol`|`address`|- POL address|
|`totalMemecoinFunds`|`uint128`|- Total memecoin funds|
|`totalLiquidProofFunds`|`uint128`|- Total liquid proof funds|


### refund

Refund UPT after genesis Failed, total omnichain funds didn't meet the minimum funding requirement


```solidity
function refund(uint256 verseId) external override whenNotPaused returns (uint256 genesisFund);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`verseId`|`uint256`|- Memeverse id|


### claimPOLToken

Claim POL token in stage Locked


```solidity
function claimPOLToken(uint256 verseId) external override whenNotPaused returns (uint256 amount);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`verseId`|`uint256`|- Memeverse id|


### redeemAndDistributeFees

Anyone who calls this method will be rewarded with executorReward.

Redeem transaction fees and distribute them to the owner(UPT) and vault(Memecoin)


```solidity
function redeemAndDistributeFees(uint256 verseId, address rewardReceiver)
    external
    payable
    override
    whenNotPaused
    returns (uint256 govFee, uint256 memecoinFee, uint256 liquidProofFee, uint256 executorReward);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`verseId`|`uint256`|- Memeverse id|
|`rewardReceiver`|`address`|- Address of executor reward receiver|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`govFee`|`uint256`|- The Gov fee.|
|`memecoinFee`|`uint256`|- The memecoin fee.|
|`liquidProofFee`|`uint256`|- The liquidProof fee.|
|`executorReward`|`uint256`| - The executor reward.|


### redeemMemecoinLiquidity

User must have approved this contract to spend POL

Burn POL to redeem the locked memecoin liquidity


```solidity
function redeemMemecoinLiquidity(uint256 verseId, uint256 amountInPOL)
    external
    override
    whenNotPaused
    returns (uint256 amountInLP);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`verseId`|`uint256`|- Memeverse id|
|`amountInPOL`|`uint256`|- Burned liquid proof token amount|


### redeemPolLiquidity

Redeem the locked POL liquidity


```solidity
function redeemPolLiquidity(uint256 verseId) external override whenNotPaused returns (uint256 amountInLP);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`verseId`|`uint256`|- Memeverse id|


### mintPOLToken

Mint POL token by add memecoin liquidity when currentStage >= Stage.Locked.


```solidity
function mintPOLToken(
    uint256 verseId,
    uint256 amountInUPTDesired,
    uint256 amountInMemecoinDesired,
    uint256 amountInUPTMin,
    uint256 amountInMemecoinMin,
    uint256 amountOutDesired,
    uint256 deadline
) external override returns (uint256 amountInUPT, uint256 amountInMemecoin, uint256 amountOut);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`verseId`|`uint256`|- Memeverse id|
|`amountInUPTDesired`|`uint256`|- Amount of UPT transfered into Launcher|
|`amountInMemecoinDesired`|`uint256`|- Amount of transfered into Launcher|
|`amountInUPTMin`|`uint256`|- Minimum amount of UPT|
|`amountInMemecoinMin`|`uint256`|- Minimum amount of memecoin|
|`amountOutDesired`|`uint256`|- Amount of POL token desired, If the amountOut is 0, the output quantity will be automatically calculated.|
|`deadline`|`uint256`|- Transaction deadline|


### registerMemeverse

Register memeverse


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
) external override whenNotPaused;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`name`|`string`|- Name of memecoin|
|`symbol`|`string`|- Symbol of memecoin|
|`uniqueId`|`uint256`|- Unique verseId|
|`endTime`|`uint128`|- Genesis stage end time|
|`unlockTime`|`uint128`|- Unlock time of liquidity|
|`omnichainIds`|`uint32[]`|- ChainIds of the token's omnichain(EVM)|
|`UPT`|`address`|- Genesis fund types|
|`flashGenesis`|`bool`|- Enable FlashGenesis mode|


### _lzConfigure

Memecoin Layerzero configure. See: https://docs.layerzero.network/v2/developers/evm/create-lz-oapp/configuring-pathways


```solidity
function _lzConfigure(address memecoin, address pol, uint32[] memory omnichainIds) internal;
```

### removeGasDust

Remove gas dust from the contract


```solidity
function removeGasDust(address receiver) external override;
```

### pause


```solidity
function pause() external onlyOwner;
```

### unpause


```solidity
function unpause() external onlyOwner;
```

### setMemeverseSwapRouter

Set memeverse swap router contract


```solidity
function setMemeverseSwapRouter(address _memeverseSwapRouter) external override onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_memeverseSwapRouter`|`address`|- Address of memeverseSwapRouter|


### setMemeverseCommonInfo

Set memeverse common info contract


```solidity
function setMemeverseCommonInfo(address _memeverseCommonInfo) external override onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_memeverseCommonInfo`|`address`|- Address of memeverseCommonInfo|


### setMemeverseRegistrar

Set memeverse registrar contract


```solidity
function setMemeverseRegistrar(address _memeverseRegistrar) external override onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_memeverseRegistrar`|`address`|- Address of memeverseRegistrar|


### setMemeverseProxyDeployer

Set memeverse proxy deployer contract


```solidity
function setMemeverseProxyDeployer(address _memeverseProxyDeployer) external override onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_memeverseProxyDeployer`|`address`|- Address of memeverseProxyDeployer|


### setOFTDispatcher

Set memeverse oftDispatcher contract


```solidity
function setOFTDispatcher(address _oftDispatcher) external override onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_oftDispatcher`|`address`|- Address of oftDispatcher|


### setFundMetaData

Set fundMetaData


```solidity
function setFundMetaData(address _upt, uint256 _minTotalFund, uint256 _fundBasedAmount)
    external
    override
    onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_upt`|`address`|- Genesis fund type|
|`_minTotalFund`|`uint256`|- The minimum participation genesis fund corresponding to UPT|
|`_fundBasedAmount`|`uint256`|- // The number of Memecoins minted per unit of Memecoin genesis fund|


### setExecutorRewardRate

Set executor reward rate


```solidity
function setExecutorRewardRate(uint256 _executorRewardRate) external override onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_executorRewardRate`|`uint256`|- Executor reward rate|


### setGasLimits

Set gas limits for OFT receive and yield dispatcher


```solidity
function setGasLimits(uint128 _oftReceiveGasLimit, uint128 _oftDispatcherGasLimit) external override onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_oftReceiveGasLimit`|`uint128`|- Gas limit for OFT receive|
|`_oftDispatcherGasLimit`|`uint128`|- Gas limit for yield dispatcher|


### setExternalInfo

Set external info


```solidity
function setExternalInfo(
    uint256 verseId,
    string calldata uri,
    string calldata description,
    string[] calldata communities
) external override;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`verseId`|`uint256`|- Memeverse id|
|`uri`|`string`|- IPFS URI of memecoin icon|
|`description`|`string`|- Description|
|`communities`|`string[]`|- Community(Website, X, Discord, Telegram and Others)|


### _addExactTokensForLiquidity


```solidity
function _addExactTokensForLiquidity(
    address UPT,
    address memecoin,
    uint256 amountInUPTDesired,
    uint256 amountInMemecoinDesired,
    uint256 amountInUPTMin,
    uint256 amountInMemecoinMin,
    uint256 triggerTime,
    uint256 deadline
) internal returns (uint256 amountInUPT, uint256 amountInMemecoin, uint256 amountOut);
```

### _addTokensForExactLiquidity


```solidity
function _addTokensForExactLiquidity(
    address UPT,
    address memecoin,
    uint256 amountOutDesired,
    uint256 amountInUPTDesired,
    uint256 amountInMemecoinDesired,
    uint256 deadline
) internal returns (uint256 amountInUPT, uint256 amountInMemecoin, uint256 amountOut);
```

### _buildSendParamAndMessagingFee


```solidity
function _buildSendParamAndMessagingFee(
    uint32 govEndpointId,
    uint256 amount,
    address token,
    address receiver,
    TokenType tokenType,
    bytes memory oftDispatcherOptions
) internal view returns (SendParam memory sendParam, MessagingFee memory messagingFee);
```

