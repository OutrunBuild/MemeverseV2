// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {IMemeverseOFTEnum} from "../../common/types/IMemeverseOFTEnum.sol";

/**
 * @title MemeverseLauncher interface
 */
interface IMemeverseLauncher is IMemeverseOFTEnum {
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

    struct PreorderData {
        uint256 funds; // The amount of UPT user has contributed to the preorder pool
        uint256 claimedMemecoin; // The amount of preorder memecoin already claimed by the user
        bool isRefunded; // Whether the user has refunded the preorder contribution
    }

    /// @notice Resolves a memecoin back to its registered verse id.
    /// @dev Returns zero when the memecoin has never been registered through the launcher.
    /// @param memecoin Memecoin address to resolve.
    /// @return verseId Registered verse id, or zero when the memecoin is unknown.
    function getVerseIdByMemecoin(address memecoin) external view returns (uint256 verseId);

    /// @notice Loads the full launcher metadata for a verse id.
    /// @dev Reverts when the verse id does not map to a registered memeverse.
    /// @param verseId Verse id to inspect.
    /// @return verse Stored memeverse metadata.
    function getMemeverseByVerseId(uint256 verseId) external view returns (Memeverse memory verse);

    /// @notice Loads launcher metadata by memecoin address.
    /// @dev Reverts when `memecoin` is zero or does not belong to a registered verse.
    /// @param memecoin Memecoin address to inspect.
    /// @return verse Stored memeverse metadata.
    function getMemeverseByMemecoin(address memecoin) external view returns (Memeverse memory verse);

    /// @notice Reads the current lifecycle stage for a verse id.
    /// @dev Reverts when the verse id is unknown.
    /// @param verseId Verse id to inspect.
    /// @return stage Current launcher stage.
    function getStageByVerseId(uint256 verseId) external view returns (Stage stage);

    /// @notice Reads the current lifecycle stage for a memecoin.
    /// @dev Resolves the memecoin into its verse id before reading launcher state.
    /// @param memecoin Memecoin address to inspect.
    /// @return stage Current launcher stage.
    function getStageByMemecoin(address memecoin) external view returns (Stage stage);

    /// @notice Resolves the yield vault configured for a verse id.
    /// @dev Reverts when the verse id is unknown.
    /// @param verseId Verse id to inspect.
    /// @return yieldVault Configured yield-vault address.
    function getYieldVaultByVerseId(uint256 verseId) external view returns (address yieldVault);

    /// @notice Resolves the governor configured for a verse id.
    /// @dev Reverts when the verse id is unknown.
    /// @param verseId Verse id to inspect.
    /// @return governor Configured governor address.
    function getGovernorByVerseId(uint256 verseId) external view returns (address governor);

    /// @notice Quotes the caller's currently claimable POL amount.
    /// @dev Derived from the caller's genesis participation share and any prior claim status.
    /// @param verseId Verse id to inspect.
    /// @return claimableAmount Claimable POL amount for the caller.
    function claimablePOLToken(uint256 verseId) external view returns (uint256 claimableAmount);

    /// @notice Previews the launcher-owned maker fees currently available for distribution.
    /// @dev Aggregates fee claims across the verse's memecoin/UPT and POL/UPT pools.
    /// @param verseId Verse id to inspect.
    /// @return UPTFee Claimable UPT-side fee amount.
    /// @return memecoinFee Claimable memecoin-side fee amount.
    function previewGenesisMakerFees(uint256 verseId) external view returns (uint256 UPTFee, uint256 memecoinFee);

    /// @notice Quotes the LayerZero fee required to distribute accrued fees.
    /// @dev Returns zero when the governance chain is local and no cross-chain dispatch is needed.
    /// @param verseId The memeverse id.
    /// @return lzFee The quoted LayerZero native fee.
    function quoteDistributionLzFee(uint256 verseId) external view returns (uint256 lzFee);

    /// @notice Contributes UPT into a verse during Genesis.
    /// @dev The launcher splits the contribution between the memecoin and liquid-proof bootstrap buckets.
    /// @param verseId Target verse id.
    /// @param amountInUPT UPT amount being contributed.
    /// @param user Account credited for the contribution.
    function genesis(uint256 verseId, uint128 amountInUPT, address user) external;

    /// @notice Contributes UPT into the preorder pool during Genesis.
    /// @dev Preorder capacity scales with the current memecoin-side genesis funding.
    /// @param verseId Target verse id.
    /// @param amountInUPT UPT amount being contributed.
    /// @param user Account credited for the preorder participation.
    function preorder(uint256 verseId, uint128 amountInUPT, address user) external;

    /// @notice Advances a verse to the next valid launcher stage.
    /// @dev Depending on timing and funding, this may settle Genesis, deploy liquidity, or move into Refund/Unlocked.
    /// @param verseId Target verse id.
    /// @return currentStage Stage after the transition attempt.
    function changeStage(uint256 verseId) external returns (Stage currentStage);

    /// @notice Refunds the caller's Genesis contribution in Refund stage.
    /// @dev Returns the exact UPT amount previously recorded for the caller.
    /// @param verseId Verse id being refunded.
    /// @return userFunds Refunded UPT amount.
    function refund(uint256 verseId) external returns (uint256 userFunds);

    /// @notice Refunds the caller's preorder contribution in Refund stage.
    /// @dev Returns the exact preorder UPT amount previously recorded for the caller.
    /// @param verseId Verse id being refunded.
    /// @return preorderFund Refunded preorder UPT amount.
    function refundPreorder(uint256 verseId) external returns (uint256 preorderFund);

    /// @notice Claims the caller's POL allocation once Genesis has settled.
    /// @dev Amount is derived from the caller's recorded Genesis participation share.
    /// @param verseId Verse id being claimed.
    /// @return amount POL amount transferred to the caller.
    function claimPOLToken(uint256 verseId) external returns (uint256 amount);

    /// @notice Quotes how much preorder memecoin the caller can unlock right now.
    /// @dev Uses the caller's settled preorder share and the linear vesting schedule.
    /// @param verseId Verse id to inspect.
    /// @return amount Currently claimable preorder memecoin amount.
    function claimablePreorderMemecoin(uint256 verseId) external view returns (uint256 amount);

    /// @notice Claims the caller's unlocked preorder memecoin allocation.
    /// @dev Transfers the caller's currently unlocked preorder memecoin amount.
    /// @param verseId The memeverse id.
    /// @return amount The claimed preorder memecoin amount.
    function claimUnlockedPreorderMemecoin(uint256 verseId) external returns (uint256 amount);

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

    /// @notice Repoints the launcher to a new swap router.
    /// @dev Implementations are expected to guard this with their admin or owner flow.
    /// @param memeverseSwapRouter The new router address.
    function setMemeverseSwapRouter(address memeverseSwapRouter) external;

    /// @notice Exposes the hook configured for launch settlement and unlock-protection writes.
    /// @dev The launcher stores this explicitly instead of resolving it from the router on each use.
    /// @return memeverseHook The configured hook address.
    function memeverseUniswapHook() external view returns (address memeverseHook);

    /// @notice Initializes the launcher's hook binding.
    /// @dev The hook binding is write-once because live pool identities include the hook address.
    /// @param memeverseHook The hook address to bind permanently.
    function setMemeverseUniswapHook(address memeverseHook) external;

    /// @notice Repoints the launcher to a new LayerZero endpoint registry.
    /// @dev Implementations are expected to guard this with their admin or owner flow.
    /// @param lzEndpointRegistry The new endpoint registry contract address.
    function setLzEndpointRegistry(address lzEndpointRegistry) external;

    /// @notice Replaces the registrar contract reference used by the launcher.
    /// @dev Implementations are expected to guard this with their admin or owner flow.
    /// @param memeverseRegistrar The new registrar address.
    function setMemeverseRegistrar(address memeverseRegistrar) external;

    /// @notice Replaces the proxy deployer used for verse module deployment.
    /// @dev Implementations are expected to guard this with their admin or owner flow.
    /// @param memeverseProxyDeployer The new proxy deployer address.
    function setMemeverseProxyDeployer(address memeverseProxyDeployer) external;

    /// @notice Replaces the yield dispatcher contract reference.
    /// @dev Implementations are expected to guard this with their admin or owner flow.
    /// @param yieldDispatcher The new yield dispatcher address.
    function setYieldDispatcher(address yieldDispatcher) external;

    /// @notice Sets the fund metadata used for a UPT fundraising token.
    /// @dev `fundBasedAmount` controls launcher-side bootstrap pricing and may be bounded by the implementation.
    /// @param upt The fundraising token address.
    /// @param minTotalFund The minimum total genesis fund required for the token.
    /// @param fundBasedAmount The memecoin amount minted per unit of fundraising token.
    function setFundMetaData(address upt, uint256 minTotalFund, uint256 fundBasedAmount) external;

    /// @notice Updates the executor reward rate used by fee distribution.
    /// @dev Implementations are expected to guard this with their admin or owner flow.
    /// @param executorRewardRate The new reward rate in protocol ratio units.
    function setExecutorRewardRate(uint256 executorRewardRate) external;

    /// @notice Updates the launcher-wide preorder cap and vesting configuration.
    /// @dev Implementations are expected to guard this with their admin or owner flow.
    /// @param preorderCapRatio The preorder capacity ratio in `RATIO` precision.
    /// @param preorderVestingDuration The linear vesting duration for preorder memecoin.
    function setPreorderConfig(uint256 preorderCapRatio, uint256 preorderVestingDuration) external;

    /// @notice Updates the gas budgets used for launcher cross-chain calls.
    /// @dev Implementations are expected to guard this with their admin or owner flow.
    /// @param oftReceiveGasLimit The gas limit used for OFT receives.
    /// @param yieldDispatcherGasLimit The gas limit used for yield dispatcher compose dispatches.
    function setGasLimits(uint128 oftReceiveGasLimit, uint128 yieldDispatcherGasLimit) external;

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

    /// @notice Quotes the preorder capacity still open for a verse.
    /// @dev Capacity is derived from the current memecoin-side genesis funds and the configured cap ratio.
    /// @param verseId The memeverse id.
    /// @return remaining The remaining preorder UPT capacity.
    function previewPreorderCapacity(uint256 verseId) external view returns (uint256 remaining);

    error ZeroInput();

    error InvalidLength();

    error InvalidRefund();

    error InvalidRedeem();

    error NoPOLAvailable();

    error InvalidLaunchSettlementConfig();

    error HookAlreadyConfigured();

    error NotRefundStage();

    error InvalidVerseId();

    error NotGenesisStage();

    error FeeRateOverFlow();

    error PermissionDenied();

    error NotUnlockedStage();

    error InsufficientLzFee();

    error InvalidLzFee(uint256 expected, uint256 actual);

    error ReachedFinalStage();

    error InsufficientLPBalance();

    error NotReachedLockedStage();

    error StillInGenesisStage(uint256 endTime);

    error InvalidOmnichainId(uint32 omnichainId);

    error FundBasedAmountTooHigh(uint256 fundBasedAmount, uint256 maxSupportedFundBasedAmount);

    error GenesisFundOverflowed(uint256 verseId, uint256 currentTotal, uint256 amountToAdd);

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

    event SetLzEndpointRegistry(address lzEndpointRegistry);

    event SetMemeverseRegistrar(address memeverseRegistrar);

    event SetMemeverseProxyDeployer(address memeverseProxyDeployer);

    event SetYieldDispatcher(address yieldDispatcher);

    event SetFundMetaData(address indexed upt, uint256 minTotalFund, uint256 fundBasedAmount);

    event SetExecutorRewardRate(uint256 executorRewardRate);

    event SetPreorderConfig(uint256 preorderCapRatio, uint256 preorderVestingDuration);

    event SetGasLimits(uint128 oftReceiveGasLimit, uint128 yieldDispatcherGasLimit);

    event SetExternalInfo(uint256 indexed verseId, string uri, string description, string[] community);

    event SetUnlockProtectionWindow(uint256 previousWindow, uint256 newWindow);
}
