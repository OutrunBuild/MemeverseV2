// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {MemeverseOFTEnum} from "../../common/MemeverseOFTEnum.sol";

/**
 * @title MemeverseLauncher interface
 */
interface IMemeverseLauncher is MemeverseOFTEnum {
    enum Stage {
        Genesis,
        Refund,
        Locked,
        Unlocked
    }

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

    struct FundMetaData {
        uint256 minTotalFund; // The minimum participation genesis fund corresponding to UPT
        uint256 fundBasedAmount; // The number of Memecoins minted per unit of Memecoin genesis fund
    }

    struct GenesisFund {
        uint128 totalMemecoinFunds; // Initial fundraising(UPT) for memecoin liquidity
        uint128 totalLiquidProofFunds; // Initial fundraising(UPT) for liquidProof liquidity
    }

    struct GenesisData {
        uint256 genesisFund; // The amount of UPT user has contributed to the genesis fund
        bool isRefunded; // Whether the user has refunded the UPT
        bool isClaimed; // Whether the user has claimed the POL
        bool isRedeemed; // Whether the user has redeemed the POL liquidity
    }

    /// @notice Returns the verse id registered for a memecoin.
    /// @dev Returns zero when the memecoin is not registered.
    /// @param memecoin The memecoin address.
    /// @return verseId The registered verse id.
    function getVerseIdByMemecoin(address memecoin) external view returns (uint256 verseId);

    /// @notice Returns the memeverse metadata for a verse id.
    /// @dev Callers are expected to pass a non-zero registered verse id.
    /// @param verseId The memeverse id.
    /// @return verse The stored memeverse metadata.
    function getMemeverseByVerseId(uint256 verseId) external view returns (Memeverse memory verse);

    /// @notice Returns the memeverse metadata for a memecoin.
    /// @dev Returns the verse mapped from the memecoin address.
    /// @param memecoin The memecoin address.
    /// @return verse The stored memeverse metadata.
    function getMemeverseByMemecoin(address memecoin) external view returns (Memeverse memory verse);

    /// @notice Returns the current lifecycle stage for a verse id.
    /// @dev Callers are expected to pass a non-zero registered verse id.
    /// @param verseId The memeverse id.
    /// @return stage The current stage.
    function getStageByVerseId(uint256 verseId) external view returns (Stage stage);

    /// @notice Returns the current lifecycle stage for a memecoin.
    /// @dev Resolves the memecoin to its registered verse before reading the stage.
    /// @param memecoin The memecoin address.
    /// @return stage The current stage.
    function getStageByMemecoin(address memecoin) external view returns (Stage stage);

    /// @notice Returns the yield vault configured for a verse id.
    /// @dev Callers are expected to pass a non-zero registered verse id.
    /// @param verseId The memeverse id.
    /// @return yieldVault The configured yield vault.
    function getYieldVaultByVerseId(uint256 verseId) external view returns (address yieldVault);

    /// @notice Returns the governor configured for a verse id.
    /// @dev Callers are expected to pass a non-zero registered verse id.
    /// @param verseId The memeverse id.
    /// @return governor The configured governor.
    function getGovernorByVerseId(uint256 verseId) external view returns (address governor);

    /// @notice Returns the caller's currently claimable POL amount.
    /// @dev Uses the caller's stored genesis participation for the specified verse.
    /// @param verseId The memeverse id.
    /// @return claimableAmount The claimable POL amount.
    function claimablePOLToken(uint256 verseId) external view returns (uint256 claimableAmount);

    /// @notice Returns the previewed Genesis LP fee distribution.
    /// @dev Aggregates the claimable UPT and memecoin fees across launcher-managed pools.
    /// @param verseId The memeverse id.
    /// @return UPTFee The previewed UPT fee amount.
    /// @return memecoinFee The previewed memecoin fee amount.
    function previewGenesisMakerFees(uint256 verseId) external view returns (uint256 UPTFee, uint256 memecoinFee);

    /// @notice Quotes the LayerZero fee required to distribute accrued fees.
    /// @dev Returns zero when the governance chain is local and no cross-chain dispatch is needed.
    /// @param verseId The memeverse id.
    /// @return lzFee The quoted LayerZero native fee.
    function quoteDistributionLzFee(uint256 verseId) external view returns (uint256 lzFee);

    /// @notice Deposits UPT into a verse during Genesis.
    /// @dev Splits the deposit between memecoin and liquid-proof genesis buckets.
    /// @param verseId The memeverse id.
    /// @param amountInUPT The contributed UPT amount.
    /// @param user The account credited for the contribution.
    function genesis(uint256 verseId, uint128 amountInUPT, address user) external;

    /// @notice Advances a verse to its next lifecycle stage when conditions are met.
    /// @dev This may trigger pool deployment and liquidity lock flows.
    /// @param verseId The memeverse id.
    /// @return currentStage The stage after the transition attempt.
    function changeStage(uint256 verseId) external returns (Stage currentStage);

    /// @notice Refunds a caller's genesis contribution when the verse is in Refund stage.
    /// @dev Returns the caller's refunded UPT amount.
    /// @param verseId The memeverse id.
    /// @return userFunds The refunded UPT amount.
    function refund(uint256 verseId) external returns (uint256 userFunds);

    /// @notice Claims the caller's POL allocation after Genesis locks.
    /// @dev Uses the caller's stored genesis participation share for the verse.
    /// @param verseId The memeverse id.
    /// @return amount The claimed POL amount.
    function claimPOLToken(uint256 verseId) external returns (uint256 amount);

    /// @notice Redeems launcher-managed fees and distributes them to protocol recipients.
    /// @dev May perform same-chain transfers or cross-chain dispatches depending on verse configuration.
    /// @param verseId The memeverse id.
    /// @param rewardReceiver The receiver of the executor reward.
    /// @return govFee The distributed governor fee amount.
    /// @return memecoinFee The distributed memecoin fee amount.
    /// @return liquidProofFee The distributed liquid-proof fee amount.
    /// @return executorReward The distributed executor reward amount.
    function redeemAndDistributeFees(uint256 verseId, address rewardReceiver)
        external
        payable
        returns (uint256 govFee, uint256 memecoinFee, uint256 liquidProofFee, uint256 executorReward);

    /// @notice Redeems memecoin-side LP using POL.
    /// @dev Burns the caller's POL and returns the corresponding memecoin LP amount.
    /// @param verseId The memeverse id.
    /// @param amountInPOL The POL amount to redeem.
    /// @return amountInLP The redeemed memecoin LP amount.
    function redeemMemecoinLiquidity(uint256 verseId, uint256 amountInPOL) external returns (uint256 amountInLP);

    /// @notice Redeems the caller's liquid-proof LP share.
    /// @dev Each address can redeem its launcher-tracked liquid-proof LP once.
    /// @param verseId The memeverse id.
    /// @return amountInLP The redeemed liquid-proof LP amount.
    function redeemPolLiquidity(uint256 verseId) external returns (uint256 amountInLP);

    /// @notice Mints POL against supplied UPT and memecoin liquidity.
    /// @dev Uses the verse's router configuration to source the exact liquidity requirements.
    /// @param verseId The memeverse id.
    /// @param amountInUPTDesired The desired UPT budget.
    /// @param amountInMemecoinDesired The desired memecoin budget.
    /// @param amountInUPTMin The minimum accepted UPT spend.
    /// @param amountInMemecoinMin The minimum accepted memecoin spend.
    /// @param amountOutDesired The desired POL output amount.
    /// @param deadline The latest valid execution timestamp.
    /// @return amountInUPT The actual UPT amount spent.
    /// @return amountInMemecoin The actual memecoin amount spent.
    /// @return amountOut The POL amount minted.
    function mintPOLToken(
        uint256 verseId,
        uint256 amountInUPTDesired,
        uint256 amountInMemecoinDesired,
        uint256 amountInUPTMin,
        uint256 amountInMemecoinMin,
        uint256 amountOutDesired,
        uint256 deadline
    ) external returns (uint256 amountInUPT, uint256 amountInMemecoin, uint256 amountOut);

    /// @notice Registers a new memeverse.
    /// @dev Deploys and stores verse metadata for a new memecoin launch.
    /// @param name The memecoin name.
    /// @param symbol The memecoin symbol.
    /// @param uniqueId The unique identifier used to derive the verse id.
    /// @param endTime The Genesis end timestamp.
    /// @param unlockTime The liquidity unlock timestamp.
    /// @param omnichainIds The supported omnichain ids with governance chain first.
    /// @param UPT The fundraising token address.
    /// @param flashGenesis Whether early stage transition is enabled once minimum funding is met.
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

    /// @notice Withdraws stranded native gas dust from the launcher.
    /// @dev Intended for owner cleanup of residual native balances.
    /// @param receiver The recipient of the dust amount.
    function removeGasDust(address receiver) external;

    /// @notice Updates the swap router used by the launcher.
    /// @dev Expected to be restricted by the implementation's access control.
    /// @param memeverseSwapRouter The new router address.
    function setMemeverseSwapRouter(address memeverseSwapRouter) external;

    /// @notice Updates the shared memeverse info contract.
    /// @dev Expected to be restricted by the implementation's access control.
    /// @param memeverseCommonInfo The new common-info contract address.
    function setMemeverseCommonInfo(address memeverseCommonInfo) external;

    /// @notice Updates the registrar contract reference.
    /// @dev Expected to be restricted by the implementation's access control.
    /// @param memeverseRegistrar The new registrar address.
    function setMemeverseRegistrar(address memeverseRegistrar) external;

    /// @notice Updates the proxy deployer contract reference.
    /// @dev Expected to be restricted by the implementation's access control.
    /// @param memeverseProxyDeployer The new proxy deployer address.
    function setMemeverseProxyDeployer(address memeverseProxyDeployer) external;

    /// @notice Updates the OFT dispatcher contract reference.
    /// @dev Expected to be restricted by the implementation's access control.
    /// @param oftDispatcher The new OFT dispatcher address.
    function setOFTDispatcher(address oftDispatcher) external;

    /// @notice Sets the fund metadata used for a UPT fundraising token.
    /// @dev `fundBasedAmount` controls launcher-side bootstrap pricing and may be bounded by the implementation.
    /// @param upt The fundraising token address.
    /// @param minTotalFund The minimum total genesis fund required for the token.
    /// @param fundBasedAmount The memecoin amount minted per unit of fundraising token.
    function setFundMetaData(address upt, uint256 minTotalFund, uint256 fundBasedAmount) external;

    /// @notice Updates the executor reward rate.
    /// @dev Expected to be restricted by the implementation's access control.
    /// @param executorRewardRate The new reward rate in protocol ratio units.
    function setExecutorRewardRate(uint256 executorRewardRate) external;

    /// @notice Updates the gas limits used for cross-chain operations.
    /// @dev Expected to be restricted by the implementation's access control.
    /// @param oftReceiveGasLimit The gas limit used for OFT receives.
    /// @param oftDispatcherGasLimit The gas limit used for OFT compose dispatches.
    function setGasLimits(uint128 oftReceiveGasLimit, uint128 oftDispatcherGasLimit) external;

    /// @notice Updates the external metadata for a verse.
    /// @dev Stores presentation metadata and community links for the verse.
    /// @param verseId The memeverse id.
    /// @param uri The external metadata URI.
    /// @param description The external description text.
    /// @param communities The community link list.
    function setExternalInfo(
        uint256 verseId,
        string calldata uri,
        string calldata description,
        string[] calldata communities
    ) external;

    error ZeroInput();

    error InvalidLength();

    error InvalidRefund();

    error InvalidRedeem();

    error NoPOLAvailable();

    error NotRefundStage();

    error InvalidVerseId();

    error NotGenesisStage();

    error FeeRateOverFlow();

    error PermissionDenied();

    error NotUnlockedStage();

    error InsufficientLzFee();

    error ReachedFinalStage();

    error InsufficientLPBalance();

    error NotReachedLockedStage();

    error StillInGenesisStage(uint256 endTime);

    error InvalidOmnichainId(uint32 omnichainId);

    error FundBasedAmountTooHigh(uint256 fundBasedAmount, uint256 maxSupportedFundBasedAmount);

    event Genesis(
        uint256 indexed verseId,
        address indexed depositer,
        uint128 increasedMemecoinFund,
        uint128 increasedLiquidProofFund
    );

    event ChangeStage(uint256 indexed verseId, Stage currentStage);

    event Refund(uint256 indexed verseId, address indexed receiver, uint256 refundAmount);

    event ClaimPOLToken(uint256 indexed verseId, address indexed receiver, uint256 claimedAmount);

    event RedeemAndDistributeFees(
        uint256 indexed verseId, uint256 govFee, uint256 memecoinFee, uint256 liquidProofFee, uint256 executorReward
    );

    event RedeemMemecoinLiquidity(uint256 indexed verseId, address indexed receiver, uint256 memecoinLiquidity);

    event RedeemPolLiquidity(uint256 indexed verseId, address indexed receiver, uint256 polLiquidity);

    event MintPOLToken(
        uint256 indexed verseId, address indexed memecoin, address indexed liquidProof, address receiver, uint256 amount
    );

    event RegisterMemeverse(uint256 indexed verseId, Memeverse verse);

    event RemoveGasDust(address indexed receiver, uint256 dust);

    event SetMemeverseSwapRouter(address memeverseSwapRouter);

    event SetMemeverseCommonInfo(address memeverseCommonInfo);

    event SetMemeverseRegistrar(address memeverseRegistrar);

    event SetMemeverseProxyDeployer(address memeverseProxyDeployer);

    event SetOFTDispatcher(address oftDispatcher);

    event SetFundMetaData(address indexed upt, uint256 minTotalFund, uint256 fundBasedAmount);

    event SetExecutorRewardRate(uint256 executorRewardRate);

    event SetGasLimits(uint128 oftReceiveGasLimit, uint128 oftDispatcherGasLimit);

    event SetExternalInfo(uint256 indexed verseId, string uri, string description, string[] community);
}
