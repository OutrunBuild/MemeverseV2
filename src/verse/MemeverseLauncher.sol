// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IOAppCore} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppCore.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {IOFT, SendParam, MessagingFee} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {TokenHelper} from "../common/token/TokenHelper.sol";
import {InitialPriceCalculator} from "./libraries/InitialPriceCalculator.sol";
import {IMemecoin} from "../token/interfaces/IMemecoin.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IMemeverseLauncher} from "./interfaces/IMemeverseLauncher.sol";
import {IPol} from "../token/interfaces/IPol.sol";
import {ILzEndpointRegistry} from "../common/omnichain/interfaces/ILzEndpointRegistry.sol";
import {IMemecoinYieldVault} from "../yield/interfaces/IMemecoinYieldVault.sol";
import {IYieldDispatcher} from "./interfaces/IYieldDispatcher.sol";
import {IMemeverseProxyDeployer} from "./interfaces/IMemeverseProxyDeployer.sol";
import {IMemeverseSwapRouter} from "../swap/interfaces/IMemeverseSwapRouter.sol";
import {IMemeverseUniswapHook} from "../swap/interfaces/IMemeverseUniswapHook.sol";

/**
 * @title Trapping into the memeverse
 */
contract MemeverseLauncher is IMemeverseLauncher, TokenHelper, Pausable, Ownable {
    using OptionsBuilder for bytes;
    using PoolIdLibrary for PoolKey;

    uint256 public constant RATIO = 10000;
    uint256 internal constant UNLOCK_PROTECTION_WINDOW = 24 hours;
    uint256 internal constant MAX_SUPPORTED_FUND_BASED_AMOUNT = (1 << 64) - 1;
    address public localLzEndpoint;
    address public lzEndpointRegistry;
    address public yieldDispatcher;
    address public memeverseRegistrar;
    address public memeverseProxyDeployer;
    address public memeverseSwapRouter;
    address public memeverseUniswapHook;

    uint256 public executorRewardRate;
    uint256 public preorderCapRatio;
    uint256 public preorderVestingDuration;
    uint128 public oftReceiveGasLimit;
    uint128 public yieldDispatcherGasLimit;

    struct PreorderState {
        uint256 totalFunds;
        uint256 settledMemecoin;
        uint40 settlementTimestamp;
    }

    mapping(address UPT => FundMetaData) public fundMetaDatas;
    mapping(address memecoin => uint256) public memecoinToIds;
    mapping(address pol => uint256) public polToIds;
    mapping(uint256 verseId => Memeverse) public memeverses;
    mapping(uint256 verseId => GenesisFund) public genesisFunds;
    mapping(uint256 verseId => PreorderState) internal preorderStates;
    mapping(uint256 verseId => uint256) public totalClaimablePOL;
    mapping(uint256 verseId => uint256) public totalPolLiquidity;
    mapping(uint256 verseId => mapping(address account => GenesisData)) public userGenesisData;
    mapping(uint256 verseId => mapping(address account => PreorderData)) public userPreorderData;
    mapping(uint256 verseId => mapping(uint256 provider => string)) public communitiesMap; // provider -> 0:Website, 1:X, 2:Discord, 3:Telegram, >4:Others

    constructor(
        address _owner,
        address _localLzEndpoint,
        address _memeverseRegistrar,
        address _memeverseProxyDeployer,
        address _yieldDispatcher,
        address _lzEndpointRegistry,
        uint256 _executorRewardRate,
        uint128 _oftReceiveGasLimit,
        uint128 _yieldDispatcherGasLimit,
        uint256 _preorderCapRatio,
        uint256 _preorderVestingDuration
    ) Ownable(_owner) {
        require(_preorderCapRatio != 0 && _preorderVestingDuration != 0, ZeroInput());
        require(_preorderCapRatio <= RATIO, FeeRateOverFlow());

        localLzEndpoint = _localLzEndpoint;
        memeverseRegistrar = _memeverseRegistrar;
        memeverseProxyDeployer = _memeverseProxyDeployer;
        lzEndpointRegistry = _lzEndpointRegistry;
        yieldDispatcher = _yieldDispatcher;
        executorRewardRate = _executorRewardRate;
        preorderCapRatio = _preorderCapRatio;
        preorderVestingDuration = _preorderVestingDuration;
        oftReceiveGasLimit = _oftReceiveGasLimit;
        yieldDispatcherGasLimit = _yieldDispatcherGasLimit;
    }

    modifier versIdValidate(uint256 verseId) {
        _versIdValidate(verseId);
        _;
    }

    function _versIdValidate(uint256 verseId) internal view {
        require(memeverses[verseId].memecoin != address(0), InvalidVerseId());
    }

    function _verseIdOfRegisteredMemecoin(address memecoin) internal view returns (uint256 verseId) {
        require(memecoin != address(0), ZeroInput());
        verseId = memecoinToIds[memecoin];
        _versIdValidate(verseId);
    }

    /**
     * @notice Get the verse id by memecoin.
     * @dev Returns 0 when the memecoin has not been registered.
     * @param memecoin -The address of the memecoin.
     * @return verseId The verse id.
     */
    function getVerseIdByMemecoin(address memecoin) external view override returns (uint256 verseId) {
        require(memecoin != address(0), ZeroInput());
        verseId = memecoinToIds[memecoin];
    }

    /**
     * @notice Get the memeverse by verse id.
     * @dev Reverts when `verseId` is not registered.
     * @param verseId - The verse id.
     * @return verse - The memeverse.
     */
    function getMemeverseByVerseId(uint256 verseId) external view override returns (Memeverse memory verse) {
        _versIdValidate(verseId);
        verse = memeverses[verseId];
    }

    /**
     * @notice Get the memeverse by memecoin.
     * @dev Reverts when the memecoin is zero or not registered.
     * @param memecoin - The address of the memecoin.
     * @return verse - The memeverse.
     */
    function getMemeverseByMemecoin(address memecoin) external view override returns (Memeverse memory verse) {
        verse = memeverses[_verseIdOfRegisteredMemecoin(memecoin)];
    }

    /**
     * @notice Get the Stage by verse id.
     * @dev Reverts when `verseId` is not registered.
     * @param verseId - The verse id.
     * @return stage - The memeverse current stage.
     */
    function getStageByVerseId(uint256 verseId) external view override returns (Stage stage) {
        _versIdValidate(verseId);
        stage = memeverses[verseId].currentStage;
    }

    /**
     * @notice Get the Stage by memecoin.
     * @dev Returns the current stage for the memecoin's registered verse.
     * @param memecoin - The address of the memecoin.
     * @return stage - The memeverse current stage.
     */
    function getStageByMemecoin(address memecoin) external view override returns (Stage stage) {
        stage = memeverses[_verseIdOfRegisteredMemecoin(memecoin)].currentStage;
    }

    /**
     * @notice Get the yield vault by verse id.
     * @dev Reverts when `verseId` is zero.
     * @param verseId - The verse id.
     * @return yieldVault - The yield vault.
     */
    function getYieldVaultByVerseId(uint256 verseId) external view override returns (address yieldVault) {
        _versIdValidate(verseId);
        yieldVault = memeverses[verseId].yieldVault;
    }

    /**
     * @notice Get the governor by verse id.
     * @dev Reverts when `verseId` is zero.
     * @param verseId - The verse id.
     * @return governor - The governor.
     */
    function getGovernorByVerseId(uint256 verseId) external view override returns (address governor) {
        _versIdValidate(verseId);
        governor = memeverses[verseId].governor;
    }

    /**
     * @notice Preview claimable POL token of caller after Genesis stage.
     * @dev Uses the caller's stored genesis contribution as the claim basis.
     * @param verseId - Memeverse id
     * @return claimableAmount - The claimable amount.
     */
    function claimablePOLToken(uint256 verseId) public view override returns (uint256 claimableAmount) {
        _versIdValidate(verseId);
        Memeverse storage verse = memeverses[verseId];
        require(verse.currentStage >= Stage.Locked, NotReachedLockedStage());

        GenesisData storage genesisData = userGenesisData[verseId][msg.sender];
        if (genesisData.isClaimed) return 0;

        uint256 userFunds = genesisData.genesisFund;
        uint256 totalClaimable = totalClaimablePOL[verseId];
        GenesisFund storage genesisFund = genesisFunds[verseId];
        claimableAmount = totalClaimable * userFunds / (genesisFund.totalMemecoinFunds + genesisFund.totalPolFunds);
    }

    /**
     * @notice Preview claimable preorder memecoin of caller after preorder settlement.
     * @dev Uses the caller's stored preorder purchase and claim data as the claim basis.
     * @param verseId Memeverse id.
     * @return amount The currently claimable preorder memecoin amount.
     */
    function claimablePreorderMemecoin(uint256 verseId) public view override returns (uint256 amount) {
        _versIdValidate(verseId);
        Memeverse storage verse = memeverses[verseId];
        require(verse.currentStage >= Stage.Locked, NotReachedLockedStage());

        PreorderState storage preorderState = preorderStates[verseId];
        uint40 settlementTimestamp = preorderState.settlementTimestamp;
        if (settlementTimestamp == 0) return 0;

        PreorderData storage preorderData = userPreorderData[verseId][msg.sender];
        uint256 userFunds = preorderData.funds;
        uint256 totalFunds = preorderState.totalFunds;
        if (userFunds == 0 || totalFunds == 0) return 0;

        uint256 purchasedMemecoin = preorderState.settledMemecoin * userFunds / totalFunds;
        if (purchasedMemecoin <= preorderData.claimedMemecoin) return 0;

        uint256 elapsed = block.timestamp > settlementTimestamp ? block.timestamp - settlementTimestamp : 0;
        if (elapsed >= preorderVestingDuration) {
            return purchasedMemecoin - preorderData.claimedMemecoin;
        }

        uint256 vested = purchasedMemecoin * elapsed / preorderVestingDuration;
        if (vested <= preorderData.claimedMemecoin) return 0;
        return vested - preorderData.claimedMemecoin;
    }

    /**
     * @notice Preview the currently remaining preorder capacity for a verse.
     * @dev Capacity is computed from current memecoin-side genesis funds and the configured cap ratio.
     * @param verseId Memeverse id.
     * @return remaining The remaining preorder UPT capacity.
     */
    function previewPreorderCapacity(uint256 verseId) public view override returns (uint256 remaining) {
        require(verseId != 0, ZeroInput());
        uint256 maxCapacity = genesisFunds[verseId].totalMemecoinFunds * preorderCapRatio / RATIO;
        uint256 usedCapacity = preorderStates[verseId].totalFunds;
        if (usedCapacity >= maxCapacity) return 0;
        return maxCapacity - usedCapacity;
    }

    /**
     * @notice Preview Genesis liquidity market maker fees for DAO Treasury (UPT) and Yield Vault (Memecoin).
     * @dev Aggregates the claimable LP fees from the memecoin/UPT and pol/UPT pools.
     * @param verseId - Memeverse id
     * @return UPTFee - The UPT fee.
     * @return memecoinFee - The memecoin fee.
     */
    function previewGenesisMakerFees(uint256 verseId)
        public
        view
        override
        returns (uint256 UPTFee, uint256 memecoinFee)
    {
        _versIdValidate(verseId);
        Memeverse storage verse = memeverses[verseId];
        require(verse.currentStage >= Stage.Locked, NotReachedLockedStage());

        address UPT = verse.UPT;
        (memecoinFee, UPTFee) = _previewPairFees(verse.memecoin, UPT);
        (, uint256 polPairUPTFee) = _previewPairFees(verse.pol, UPT);
        UPTFee += polPairUPTFee;
    }

    /**
     * @dev Quote the LZ fee for the redemption and distribution of fees
     * @param verseId - Memeverse id
     * @return lzFee - The LZ fee.
     * @notice The LZ fee is only charged when the governance chain is not the same as the current chain,
     *         and msg.value needs to be greater than the quoted lzFee for the redeemAndDistributeFees transaction.
     */
    function quoteDistributionLzFee(uint256 verseId) external view override returns (uint256 lzFee) {
        _versIdValidate(verseId);
        Memeverse storage verse = memeverses[verseId];
        uint32 govChainId = verse.omnichainIds[0];
        if (govChainId == block.chainid) return 0;

        (uint256 UPTFee, uint256 memecoinFee) = previewGenesisMakerFees(verseId);
        uint32 govEndpointId = ILzEndpointRegistry(lzEndpointRegistry).lzEndpointIdOfChain(govChainId);
        bytes memory yieldDispatcherOptions = OptionsBuilder.newOptions()
            .addExecutorLzReceiveOption(oftReceiveGasLimit, 0).addExecutorLzComposeOption(0, yieldDispatcherGasLimit, 0);

        if (UPTFee != 0) {
            (, MessagingFee memory govMessagingFee) = _buildSendParamAndMessagingFee(
                govEndpointId, UPTFee, verse.UPT, verse.governor, TokenType.UPT, yieldDispatcherOptions
            );
            lzFee += govMessagingFee.nativeFee;
        }

        if (memecoinFee != 0) {
            (, MessagingFee memory memecoinMessagingFee) = _buildSendParamAndMessagingFee(
                govEndpointId, memecoinFee, verse.memecoin, verse.yieldVault, TokenType.MEMECOIN, yieldDispatcherOptions
            );
            lzFee += memecoinMessagingFee.nativeFee;
        }
    }

    /**
     * @dev Genesis memeverse by depositing UPT
     * @param verseId - Memeverse id
     * @param amountInUPT - Amount of UPT
     * @param user - Address of user participating in the genesis
     * @notice Approve fund token first
     */
    function genesis(uint256 verseId, uint128 amountInUPT, address user)
        external
        override
        versIdValidate(verseId)
        whenNotPaused
    {
        require(verseId != 0 && amountInUPT != 0 && user != address(0), ZeroInput());
        Memeverse storage verse = memeverses[verseId];
        require(verse.currentStage == Stage.Genesis, NotGenesisStage());

        _transferIn(verse.UPT, msg.sender, amountInUPT);

        uint128 increasedMemecoinFund;
        uint128 increasedPolFund;
        unchecked {
            increasedPolFund = amountInUPT / 4;
            increasedMemecoinFund = amountInUPT - increasedPolFund;
        }

        GenesisFund storage genesisFund = genesisFunds[verseId];
        uint256 currentMemecoinFunds = genesisFund.totalMemecoinFunds;
        uint256 currentPolFunds = genesisFund.totalPolFunds;
        if (currentMemecoinFunds + increasedMemecoinFund > type(uint128).max) {
            revert GenesisFundOverflowed(verseId, currentMemecoinFunds, increasedMemecoinFund);
        }
        if (currentPolFunds + increasedPolFund > type(uint128).max) {
            revert GenesisFundOverflowed(verseId, currentPolFunds, increasedPolFund);
        }
        unchecked {
            genesisFund.totalMemecoinFunds += increasedMemecoinFund;
            genesisFund.totalPolFunds += increasedPolFund;
            userGenesisData[verseId][user].genesisFund += amountInUPT;
        }

        emit Genesis(verseId, user, increasedMemecoinFund, increasedPolFund);
    }

    /**
     * @notice Deposit UPT into the preorder pool during Genesis.
     * @dev The preorder pool is capped relative to the current memecoin-side genesis funds.
     * @param verseId Memeverse id.
     * @param amountInUPT Amount of UPT.
     * @param user Address of user participating in preorder.
     */
    function preorder(uint256 verseId, uint128 amountInUPT, address user)
        external
        override
        versIdValidate(verseId)
        whenNotPaused
    {
        require(verseId != 0 && amountInUPT != 0 && user != address(0), ZeroInput());
        Memeverse storage verse = memeverses[verseId];
        require(verse.currentStage == Stage.Genesis, NotGenesisStage());

        PreorderState storage preorderState = preorderStates[verseId];
        uint256 nextTotalPreorderFunds = preorderState.totalFunds + amountInUPT;
        require(
            nextTotalPreorderFunds <= genesisFunds[verseId].totalMemecoinFunds * preorderCapRatio / RATIO,
            InvalidLength()
        );

        _transferIn(verse.UPT, msg.sender, amountInUPT);
        preorderState.totalFunds = nextTotalPreorderFunds;
        userPreorderData[verseId][user].funds += amountInUPT;
    }

    /**
     * @notice Adaptively change the Memeverse stage.
     * @dev Advances from `Genesis` to `Locked` or `Refund`, and from `Locked` to `Unlocked` when eligible.
     * @param verseId - Memeverse id
     * @return currentStage - The current stage.
     */
    function changeStage(uint256 verseId)
        external
        override
        versIdValidate(verseId)
        whenNotPaused
        returns (Stage currentStage)
    {
        require(verseId != 0, ZeroInput());
        uint256 currentTime = block.timestamp;
        Memeverse storage verse = memeverses[verseId];
        currentStage = verse.currentStage;
        require(currentStage != Stage.Refund && currentStage != Stage.Unlocked, ReachedFinalStage());

        if (currentStage == Stage.Genesis) {
            // Genesis is the only stage that can resolve into either a successful launch or a refund outcome.
            currentStage = _handleGenesisStage(verseId, currentTime, verse);
        } else if (currentStage == Stage.Locked && currentTime > verse.unlockTime) {
            verse.currentStage = Stage.Unlocked;
            // The public-swap cooldown starts when the stage flip is actually executed, not at the preset unlock time.
            _activatePostUnlockPublicSwapProtection(verse);
            currentStage = Stage.Unlocked;
        }

        emit ChangeStage(verseId, currentStage);
    }

    /**
     * @dev Handle Genesis stage logic
     * @param verseId - Memeverse id
     * @param currentTime - Current timestamp
     * @param verse - Memeverse storage reference
     * @return currentStage - The current stage
     */
    function _handleGenesisStage(uint256 verseId, uint256 currentTime, Memeverse storage verse)
        internal
        returns (Stage currentStage)
    {
        address UPT = verse.UPT;
        GenesisFund storage genesisFund = genesisFunds[verseId];
        uint128 totalMemecoinFunds = genesisFund.totalMemecoinFunds;
        uint128 totalPolFunds = genesisFund.totalPolFunds;
        bool meetMinTotalFund = totalMemecoinFunds + totalPolFunds >= fundMetaDatas[UPT].minTotalFund;
        uint256 endTime = verse.endTime;

        if ((verse.flashGenesis && meetMinTotalFund) || (currentTime > endTime && meetMinTotalFund)) {
            // Either flashGenesis short-circuits once the minimum fund is reached, or the normal path resolves at endTime.
            _deployAndSetupMemeverse(verseId, verse, UPT, totalMemecoinFunds, totalPolFunds);
            verse.currentStage = Stage.Locked;
            return Stage.Locked;
        }

        // Missing the minimum at `endTime` permanently sends the verse into the refund branch; there is no partial launch path.
        require(currentTime > endTime, StillInGenesisStage(endTime));
        verse.currentStage = Stage.Refund;
        return Stage.Refund;
    }

    /**
     * @dev Deploy and setup memeverse components
     * @param verseId - Memeverse id
     * @param verse - Memeverse storage reference
     * @param UPT - UPT address
     * @param totalMemecoinFunds - Total memecoin funds
     * @param totalPolFunds - Total liquid proof funds
     */
    function _deployAndSetupMemeverse(
        uint256 verseId,
        Memeverse storage verse,
        address UPT,
        uint128 totalMemecoinFunds,
        uint128 totalPolFunds
    ) internal {
        string memory name = verse.name;
        string memory symbol = verse.symbol;
        address memecoin = verse.memecoin;
        address pol = verse.pol;
        uint32 govChainId = verse.omnichainIds[0];

        // Deploy Yield Vault, DAO Governor and Incentivizer
        (address yieldVault, address governor, address incentivizer) =
            _deployGovernanceComponents(verseId, govChainId, name, symbol, UPT, memecoin, pol);
        verse.yieldVault = yieldVault;
        verse.governor = governor;
        verse.incentivizer = incentivizer;

        // Deploy liquidity
        _deployLiquidity(verseId, UPT, memecoin, pol, totalMemecoinFunds, totalPolFunds);
    }

    /**
     * @dev Deploy governance components
     * @param verseId - Memeverse id
     * @param govChainId - Governance chain id
     * @param name - Token name
     * @param symbol - Token symbol
     * @param UPT - UPT address
     * @param memecoin - Memecoin address
     * @param pol - POL address
     */
    function _deployGovernanceComponents(
        uint256 verseId,
        uint32 govChainId,
        string memory name,
        string memory symbol,
        address UPT,
        address memecoin,
        address pol
    ) internal returns (address yieldVault, address governor, address incentivizer) {
        uint256 proposalThreshold = IMemecoin(memecoin).totalSupply() / 50;

        if (govChainId == block.chainid) {
            // On the governance chain we deploy concrete contracts immediately because fee distribution will target them locally.
            yieldVault = IMemeverseProxyDeployer(memeverseProxyDeployer).deployYieldVault(verseId);
            IMemecoinYieldVault(yieldVault)
                .initialize(
                    string(abi.encodePacked("Staked ", name)),
                    string(abi.encodePacked("s", symbol)),
                    yieldDispatcher,
                    memecoin,
                    verseId
                );
            (governor, incentivizer) = IMemeverseProxyDeployer(memeverseProxyDeployer)
                .deployGovernorAndIncentivizer(name, UPT, memecoin, pol, yieldVault, verseId, proposalThreshold);
        } else {
            // Remote governance chains receive bridged assets later, so launcher only records the deterministic target addresses here.
            yieldVault = IMemeverseProxyDeployer(memeverseProxyDeployer).predictYieldVaultAddress(verseId);
            (governor, incentivizer) =
                IMemeverseProxyDeployer(memeverseProxyDeployer).computeGovernorAndIncentivizerAddress(verseId);
        }
    }

    /**
     * @dev Deploy liquidity pools
     * @param verseId - Memeverse id
     * @param UPT - UPT address
     * @param memecoin - Memecoin address
     * @param pol - POL address
     * @param totalMemecoinFunds - Total memecoin funds
     * @param totalPolFunds - Total liquid proof funds
     */
    function _deployLiquidity(
        uint256 verseId,
        address UPT,
        address memecoin,
        address pol,
        uint128 totalMemecoinFunds,
        uint128 totalPolFunds
    ) internal {
        _safeApproveInf(UPT, memeverseSwapRouter);
        _safeApproveInf(memecoin, memeverseSwapRouter);
        _safeApproveInf(pol, memeverseSwapRouter);
        _safeApproveInf(UPT, memeverseUniswapHook);

        // The memecoin pool must exist first because preorder settlement spends UPT into that freshly launched pool.
        uint256 memecoinAmount = totalMemecoinFunds * fundMetaDatas[UPT].fundBasedAmount;
        uint160 memecoinStartPrice =
            InitialPriceCalculator.calculateMemecoinStartPriceX96(memecoin, UPT, fundMetaDatas[UPT].fundBasedAmount);
        IMemecoin(memecoin).mint(address(this), memecoinAmount);

        (uint128 memecoinLiquidity, PoolKey memory poolKey) = IMemeverseSwapRouter(memeverseSwapRouter)
            .createPoolAndAddLiquidity(
                memecoin, UPT, memecoinAmount, totalMemecoinFunds, memecoinStartPrice, address(this), block.timestamp
            );

        _settleLaunchPreorder(verseId, poolKey, UPT, memecoin);

        // POL supply mirrors the memecoin LP position created above, then a third is redeployed into the POL/UPT pool.
        IPol(pol).mint(address(this), memecoinLiquidity);
        IPol(pol).setPoolId(poolKey.toId());

        // Deploy POL liquidity
        uint256 deployedPOL = memecoinLiquidity / 3;
        uint160 polStartPrice =
            InitialPriceCalculator.calculateInitialSqrtPriceX96(pol, UPT, deployedPOL, totalPolFunds);
        (uint128 polLiquidity,) = IMemeverseSwapRouter(memeverseSwapRouter)
            .createPoolAndAddLiquidity(
                pol, UPT, deployedPOL, totalPolFunds, polStartPrice, address(this), block.timestamp
            );

        totalPolLiquidity[verseId] = polLiquidity;
        totalClaimablePOL[verseId] = memecoinLiquidity - deployedPOL;
    }

    function _settleLaunchPreorder(uint256 verseId, PoolKey memory poolKey, address UPT, address memecoin) internal {
        PreorderState storage preorderState = preorderStates[verseId];
        uint256 totalFunds = preorderState.totalFunds;
        if (totalFunds == 0) return;

        bool zeroForOne = Currency.unwrap(poolKey.currency0) == UPT;
        // Settlement goes through the hook's dedicated launch path so preorder accounting stays isolated from public swap flow.
        BalanceDelta delta = IMemeverseUniswapHook(memeverseUniswapHook)
            .executeLaunchSettlement(
                IMemeverseUniswapHook.LaunchSettlementParams({
                    key: poolKey,
                    params: SwapParams({
                        zeroForOne: zeroForOne, amountSpecified: -int256(totalFunds), sqrtPriceLimitX96: 0
                    }),
                    recipient: address(this),
                    amountInMaximum: totalFunds
                })
            );

        uint256 settledMemecoin = _deltaAmountForToken(delta, zeroForOne, memecoin, poolKey);
        // Later vesting claims split this aggregate fill pro rata by each user's preorder funds and anchor to this timestamp.
        preorderState.settledMemecoin = settledMemecoin;
        preorderState.settlementTimestamp = uint40(block.timestamp);
    }

    function _deltaAmountForToken(BalanceDelta delta, bool zeroForOne, address token, PoolKey memory poolKey)
        internal
        pure
        returns (uint256 amount)
    {
        if (Currency.unwrap(poolKey.currency0) == token) {
            int128 amount0 = delta.amount0();
            return amount0 > 0 ? uint256(uint128(amount0)) : 0;
        }

        if (Currency.unwrap(poolKey.currency1) == token) {
            int128 amount1 = delta.amount1();
            return amount1 > 0 ? uint256(uint128(amount1)) : 0;
        }

        zeroForOne;
        return 0;
    }

    /**
     * @notice Refund UPT after genesis failed because the omnichain funds did not meet the minimum requirement.
     * @dev Marks the caller as refunded before transferring funds out.
     * @param verseId - Memeverse id
     * @return genesisFund - The refunded genesis contribution amount.
     */
    function refund(uint256 verseId)
        external
        override
        versIdValidate(verseId)
        whenNotPaused
        returns (uint256 genesisFund)
    {
        Memeverse storage verse = memeverses[verseId];
        require(verse.currentStage == Stage.Refund, NotRefundStage());

        address msgSender = msg.sender;
        GenesisData storage genesisData = userGenesisData[verseId][msgSender];
        genesisFund = genesisData.genesisFund;
        require(genesisFund > 0 && !genesisData.isRefunded, InvalidRefund());

        genesisData.isRefunded = true;
        _transferOut(verse.UPT, msgSender, genesisFund);

        emit Refund(verseId, msgSender, genesisFund);
    }

    /**
     * @notice Refund UPT after preorder became invalid because Genesis failed.
     * @dev Marks the caller as refunded before transferring funds out.
     * @param verseId Memeverse id.
     * @return preorderFund The refunded preorder contribution amount.
     */
    function refundPreorder(uint256 verseId)
        external
        override
        versIdValidate(verseId)
        whenNotPaused
        returns (uint256 preorderFund)
    {
        Memeverse storage verse = memeverses[verseId];
        require(verse.currentStage == Stage.Refund, NotRefundStage());

        address msgSender = msg.sender;
        PreorderData storage preorderData = userPreorderData[verseId][msgSender];
        preorderFund = preorderData.funds;
        require(preorderFund > 0 && !preorderData.isRefunded, InvalidRefund());

        preorderData.isRefunded = true;
        _transferOut(verse.UPT, msgSender, preorderFund);
    }

    /**
     * @notice Claim POL token in stage Locked.
     * @dev Transfers the caller's proportional claimable liquid proof balance.
     * @param verseId - Memeverse id
     * @return amount - The claimed POL amount.
     */
    function claimPOLToken(uint256 verseId)
        external
        override
        versIdValidate(verseId)
        whenNotPaused
        returns (uint256 amount)
    {
        amount = claimablePOLToken(verseId);
        require(amount != 0, NoPOLAvailable());

        address msgSender = msg.sender;
        userGenesisData[verseId][msgSender].isClaimed = true;
        _transferOut(memeverses[verseId].pol, msgSender, amount);

        emit ClaimPOLToken(verseId, msgSender, amount);
    }

    /**
     * @notice Claim unlocked preorder memecoin after preorder settlement.
     * @dev Transfers the caller's currently vested preorder memecoin balance.
     * @param verseId Memeverse id.
     * @return amount The claimed preorder memecoin amount.
     */
    function claimUnlockedPreorderMemecoin(uint256 verseId)
        external
        override
        versIdValidate(verseId)
        whenNotPaused
        returns (uint256 amount)
    {
        amount = claimablePreorderMemecoin(verseId);
        require(amount != 0, NoPOLAvailable());

        address msgSender = msg.sender;
        userPreorderData[verseId][msgSender].claimedMemecoin += amount;
        _transferOut(memeverses[verseId].memecoin, msgSender, amount);
    }

    /**
     * @dev Redeem transaction fees and distribute them to the owner(UPT) and vault(Memecoin)
     * @param verseId - Memeverse id
     * @param rewardReceiver - Address of executor reward receiver
     * @return govFee - The Gov fee.
     * @return memecoinFee - The memecoin fee.
     * @return polFee - The pol fee.
     * @return executorReward  - The executor reward.
     * @notice Anyone who calls this method will be rewarded with executorReward.
     */
    function redeemAndDistributeFees(uint256 verseId, address rewardReceiver)
        external
        payable
        override
        versIdValidate(verseId)
        whenNotPaused
        returns (uint256 govFee, uint256 memecoinFee, uint256 polFee, uint256 executorReward)
    {
        require(rewardReceiver != address(0), ZeroInput());
        Memeverse storage verse = memeverses[verseId];
        require(verse.currentStage >= Stage.Locked, NotReachedLockedStage());

        address UPT = verse.UPT;
        address memecoin = verse.memecoin;
        address pol = verse.pol;

        uint256 UPTFee;
        uint256 polPairUPTFee;
        (memecoinFee, UPTFee) = _claimPairFees(memecoin, UPT);
        (polFee, polPairUPTFee) = _claimPairFees(pol, UPT);
        UPTFee += polPairUPTFee;

        if (UPTFee == 0 && memecoinFee == 0 && polFee == 0) return (0, 0, 0, 0);
        // POL pair fees are burned before distribution so the LP proof supply stays aligned with the remaining claim surface.
        if (polFee != 0) IPol(pol).burn(address(this), polFee);

        unchecked {
            executorReward = UPTFee * executorRewardRate / RATIO;
            govFee = UPTFee - executorReward;
        }
        // Anyone can execute fee redemption; only the UPT-side fee is split with the caller as an execution incentive.
        if (executorReward != 0) _transferOut(UPT, rewardReceiver, executorReward);

        uint32 govChainId = verse.omnichainIds[0];
        address governor = verse.governor;
        address yieldVault = verse.yieldVault;

        if (govChainId == block.chainid) {
            if (msg.value != 0) revert InvalidLzFee(0, msg.value);
            // Same-chain governance routes through YieldDispatcher's compose entry so local and remote fee flows share one sink.
            if (govFee != 0) {
                _transferOut(UPT, yieldDispatcher, govFee);
                IYieldDispatcher(yieldDispatcher)
                    .lzCompose(UPT, bytes32(0), abi.encode(governor, TokenType.UPT, govFee), address(0), "");
            }
            if (memecoinFee != 0) {
                _transferOut(memecoin, yieldDispatcher, memecoinFee);
                IYieldDispatcher(yieldDispatcher)
                    .lzCompose(
                        memecoin, bytes32(0), abi.encode(yieldVault, TokenType.MEMECOIN, memecoinFee), address(0), ""
                    );
            }
        } else {
            // Cross-chain governance prebuilds both OFT sends, then requires the caller to fund exactly the combined native messaging fee.
            uint32 govEndpointId = ILzEndpointRegistry(lzEndpointRegistry).lzEndpointIdOfChain(govChainId);
            bytes memory yieldDispatcherOptions = OptionsBuilder.newOptions()
                .addExecutorLzReceiveOption(oftReceiveGasLimit, 0)
                .addExecutorLzComposeOption(0, yieldDispatcherGasLimit, 0);

            SendParam memory sendUPTParam;
            MessagingFee memory govMessagingFee;
            if (govFee != 0) {
                (sendUPTParam, govMessagingFee) = _buildSendParamAndMessagingFee(
                    govEndpointId, govFee, UPT, governor, TokenType.UPT, yieldDispatcherOptions
                );
            }

            SendParam memory sendMemecoinParam;
            MessagingFee memory memecoinMessagingFee;
            if (memecoinFee != 0) {
                (sendMemecoinParam, memecoinMessagingFee) = _buildSendParamAndMessagingFee(
                    govEndpointId, memecoinFee, memecoin, yieldVault, TokenType.MEMECOIN, yieldDispatcherOptions
                );
            }

            uint256 requiredLzFee = govMessagingFee.nativeFee + memecoinMessagingFee.nativeFee;
            if (msg.value != requiredLzFee) revert InvalidLzFee(requiredLzFee, msg.value);
            if (govFee != 0) {
                // solhint-disable-next-line check-send-result
                IOFT(UPT).send{value: govMessagingFee.nativeFee}(sendUPTParam, govMessagingFee, msg.sender);
            }
            if (memecoinFee != 0) {
                // solhint-disable-next-line check-send-result,multiple-sends
                IOFT(memecoin).send{value: memecoinMessagingFee.nativeFee}(
                    sendMemecoinParam, memecoinMessagingFee, msg.sender
                );
            }
        }

        emit RedeemAndDistributeFees(verseId, govFee, memecoinFee, polFee, executorReward);
    }

    /**
     * @dev Burn POL to redeem the locked memecoin liquidity
     * @notice Redeem locked memecoin liquidity by burning POL.
     * @param verseId - Memeverse id
     * @param amountInPOL - Burned liquid proof token amount
     * @notice User must have approved this contract to spend POL
     * @return amountInLP - The redeemed LP amount.
     */
    function redeemMemecoinLiquidity(uint256 verseId, uint256 amountInPOL)
        external
        override
        versIdValidate(verseId)
        whenNotPaused
        returns (uint256 amountInLP)
    {
        require(amountInPOL != 0, ZeroInput());

        Memeverse storage verse = memeverses[verseId];
        require(verse.currentStage == Stage.Unlocked, NotUnlockedStage());

        IPol(verse.pol).burn(msg.sender, amountInPOL);

        amountInLP = amountInPOL;
        address lpToken = _pairLpToken(verse.memecoin, verse.UPT);
        require(IERC20(lpToken).balanceOf(address(this)) >= amountInLP, InsufficientLPBalance());

        _transferOut(lpToken, msg.sender, amountInLP);
        emit RedeemMemecoinLiquidity(verseId, msg.sender, amountInLP);
    }

    /**
     * @notice Redeem the locked POL liquidity.
     * @dev Uses the caller's genesis contribution share to determine LP redemption.
     * @param verseId - Memeverse id
     * @return amountInLP - The redeemed LP amount.
     */
    function redeemPolLiquidity(uint256 verseId)
        external
        override
        versIdValidate(verseId)
        whenNotPaused
        returns (uint256 amountInLP)
    {
        Memeverse storage verse = memeverses[verseId];
        require(verse.currentStage == Stage.Unlocked, NotUnlockedStage());

        address msgSender = msg.sender;
        GenesisData storage genesisData = userGenesisData[verseId][msgSender];
        uint256 userFunds = genesisData.genesisFund;
        require(userFunds > 0 && !genesisData.isRedeemed, InvalidRedeem());

        GenesisFund storage genesisFund = genesisFunds[verseId];
        amountInLP =
            totalPolLiquidity[verseId] * userFunds / (genesisFund.totalMemecoinFunds + genesisFund.totalPolFunds);

        address lpToken = _pairLpToken(verse.pol, verse.UPT);
        require(IERC20(lpToken).balanceOf(address(this)) >= amountInLP, InsufficientLPBalance());

        genesisData.isRedeemed = true;
        _transferOut(lpToken, msgSender, amountInLP);
        emit RedeemPolLiquidity(verseId, msgSender, amountInLP);
    }

    /**
     * @notice Mints POL by adding `UPT/memecoin` liquidity after the verse reaches `Stage.Locked`.
     * @dev When `amountOutDesired == 0`, the router spends up to the provided budgets and the launcher derives the
     * actual spend from post-call balances. When `amountOutDesired != 0`, the launcher first asks the router for the
     * exact token amounts required for the target LP liquidity and then adds that exact liquidity.
     * @param verseId Memeverse id.
     * @param amountInUPTDesired Maximum UPT budget transferred into the launcher.
     * @param amountInMemecoinDesired Maximum memecoin budget transferred into the launcher.
     * @param amountInUPTMin Minimum UPT spend accepted by the router in auto-liquidity mode.
     * @param amountInMemecoinMin Minimum memecoin spend accepted by the router in auto-liquidity mode.
     * @param amountOutDesired Desired POL amount. If zero, the launcher mints the amount implied by the provided budgets.
     * @param deadline Transaction deadline forwarded to the router.
     * @return amountInUPT The consumed UPT amount.
     * @return amountInMemecoin The consumed memecoin amount.
     * @return amountOut The minted POL amount.
     */
    function mintPOLToken(
        uint256 verseId,
        uint256 amountInUPTDesired,
        uint256 amountInMemecoinDesired,
        uint256 amountInUPTMin,
        uint256 amountInMemecoinMin,
        uint256 amountOutDesired,
        uint256 deadline
    )
        external
        override
        versIdValidate(verseId)
        returns (uint256 amountInUPT, uint256 amountInMemecoin, uint256 amountOut)
    {
        require(amountInUPTDesired != 0 && amountInMemecoinDesired != 0, ZeroInput());
        Memeverse storage verse = memeverses[verseId];
        require(verse.currentStage >= Stage.Locked, NotReachedLockedStage());

        address UPT = verse.UPT;
        address memecoin = verse.memecoin;
        _prepareMintPOLTokenInputs(UPT, memecoin, amountInUPTDesired, amountInMemecoinDesired);
        (amountInUPT, amountInMemecoin, amountOut) = _executeMintPOLTokenLiquidity(
            UPT,
            memecoin,
            amountInUPTDesired,
            amountInMemecoinDesired,
            amountInUPTMin,
            amountInMemecoinMin,
            amountOutDesired,
            deadline
        );
        address pol = verse.pol;
        IPol(pol).mint(msg.sender, amountOut);
        _refundMintPOLTokenInputs(
            UPT, memecoin, amountInUPTDesired, amountInMemecoinDesired, amountInUPT, amountInMemecoin
        );

        emit MintPOLToken(verseId, memecoin, pol, msg.sender, amountOut);
    }

    /**
     * @notice Register a new memeverse.
     * @dev Deploys memecoin and POL proxies, initializes them, and stores verse metadata.
     * @param name - Name of memecoin
     * @param symbol - Symbol of memecoin
     * @param uniqueId - Unique verseId
     * @param endTime - Genesis stage end time
     * @param unlockTime - Unlock time of liquidity
     * @param omnichainIds - ChainIds of the token's omnichain(EVM)
     * @param UPT - Genesis fund types
     * @param flashGenesis - Enable FlashGenesis mode
     */
    function registerMemeverse(
        string calldata name,
        string calldata symbol,
        uint256 uniqueId,
        uint128 endTime,
        uint128 unlockTime,
        uint32[] calldata omnichainIds,
        address UPT,
        bool flashGenesis
    ) external override whenNotPaused {
        require(msg.sender == memeverseRegistrar, PermissionDenied());

        (address memecoin, address pol) = _deployAndInitializeVerseTokens(uniqueId, name, symbol);
        _lzConfigure(memecoin, pol, omnichainIds);
        Memeverse storage verse = memeverses[uniqueId];
        verse.name = name;
        verse.symbol = symbol;
        verse.UPT = UPT;
        verse.memecoin = memecoin;
        verse.pol = pol;
        verse.endTime = endTime;
        verse.unlockTime = unlockTime;
        verse.omnichainIds = omnichainIds;
        verse.flashGenesis = flashGenesis;

        memeverses[uniqueId] = verse;
        memecoinToIds[memecoin] = uniqueId;
        polToIds[pol] = uniqueId;

        emit RegisterMemeverse(uniqueId, verse);
    }

    function _prepareMintPOLTokenInputs(
        address UPT,
        address memecoin,
        uint256 amountInUPTDesired,
        uint256 amountInMemecoinDesired
    ) internal {
        _transferIn(UPT, msg.sender, amountInUPTDesired);
        _transferIn(memecoin, msg.sender, amountInMemecoinDesired);
        _safeApproveInf(UPT, memeverseSwapRouter);
        _safeApproveInf(memecoin, memeverseSwapRouter);
    }

    function _executeMintPOLTokenLiquidity(
        address UPT,
        address memecoin,
        uint256 amountInUPTDesired,
        uint256 amountInMemecoinDesired,
        uint256 amountInUPTMin,
        uint256 amountInMemecoinMin,
        uint256 amountOutDesired,
        uint256 deadline
    ) internal returns (uint256 amountInUPT, uint256 amountInMemecoin, uint256 amountOut) {
        if (amountOutDesired == 0) {
            return _mintPOLTokenWithAutoLiquidity(
                UPT,
                memecoin,
                amountInUPTDesired,
                amountInMemecoinDesired,
                amountInUPTMin,
                amountInMemecoinMin,
                deadline
            );
        }

        return _mintPOLTokenWithExactLiquidity(
            UPT, memecoin, amountInUPTDesired, amountInMemecoinDesired, amountOutDesired, deadline
        );
    }

    function _mintPOLTokenWithAutoLiquidity(
        address UPT,
        address memecoin,
        uint256 amountInUPTDesired,
        uint256 amountInMemecoinDesired,
        uint256 amountInUPTMin,
        uint256 amountInMemecoinMin,
        uint256 deadline
    ) internal returns (uint256 amountInUPT, uint256 amountInMemecoin, uint256 amountOut) {
        uint256 uptBefore = IERC20(UPT).balanceOf(address(this));
        uint256 memecoinBefore = IERC20(memecoin).balanceOf(address(this));

        amountOut = IMemeverseSwapRouter(memeverseSwapRouter)
            .addLiquidity(
                Currency.wrap(UPT),
                Currency.wrap(memecoin),
                amountInUPTDesired,
                amountInMemecoinDesired,
                amountInUPTMin,
                amountInMemecoinMin,
                address(this),
                deadline
            );

        uint256 uptAfter = IERC20(UPT).balanceOf(address(this));
        uint256 memecoinAfter = IERC20(memecoin).balanceOf(address(this));
        amountInUPT = uptBefore - uptAfter;
        amountInMemecoin = memecoinBefore - memecoinAfter;
    }

    function _mintPOLTokenWithExactLiquidity(
        address UPT,
        address memecoin,
        uint256 amountInUPTDesired,
        uint256 amountInMemecoinDesired,
        uint256 amountOutDesired,
        uint256 deadline
    ) internal returns (uint256 amountInUPT, uint256 amountInMemecoin, uint256 amountOut) {
        require(amountOutDesired <= type(uint128).max, InvalidLength());
        (amountInUPT, amountInMemecoin) = IMemeverseSwapRouter(memeverseSwapRouter)
            .quoteAmountsForLiquidity(UPT, memecoin, uint128(amountOutDesired));
        if (amountInUPT > amountInUPTDesired) {
            revert IMemeverseSwapRouter.InputAmountExceedsMaximum(amountInUPT, amountInUPTDesired);
        }
        if (amountInMemecoin > amountInMemecoinDesired) {
            revert IMemeverseSwapRouter.InputAmountExceedsMaximum(amountInMemecoin, amountInMemecoinDesired);
        }

        amountOut = IMemeverseSwapRouter(memeverseSwapRouter)
            .addLiquidity(
                Currency.wrap(UPT),
                Currency.wrap(memecoin),
                amountInUPT,
                amountInMemecoin,
                amountInUPT,
                amountInMemecoin,
                address(this),
                deadline
            );
    }

    function _refundMintPOLTokenInputs(
        address UPT,
        address memecoin,
        uint256 amountInUPTDesired,
        uint256 amountInMemecoinDesired,
        uint256 amountInUPT,
        uint256 amountInMemecoin
    ) internal {
        uint256 UPTRefund = amountInUPTDesired - amountInUPT;
        uint256 memecoinRefund = amountInMemecoinDesired - amountInMemecoin;
        if (UPTRefund > 0) _transferOut(UPT, msg.sender, UPTRefund);
        if (memecoinRefund > 0) _transferOut(memecoin, msg.sender, memecoinRefund);
    }

    function _deployAndInitializeVerseTokens(uint256 uniqueId, string calldata name, string calldata symbol)
        internal
        returns (address memecoin, address pol)
    {
        memecoin = IMemeverseProxyDeployer(memeverseProxyDeployer).deployMemecoin(uniqueId);
        pol = IMemeverseProxyDeployer(memeverseProxyDeployer).deployPOL(uniqueId);
        IMemecoin(memecoin).initialize(name, symbol, address(this), address(this));
        IPol(pol)
            .initialize(
                string(abi.encodePacked("POL-", name)),
                string(abi.encodePacked("POL-", symbol)),
                memecoin,
                address(this),
                address(this)
            );
    }

    /**
     * @dev Memecoin Layerzero configure. See: https://docs.layerzero.network/v2/developers/evm/create-lz-oapp/configuring-pathways
     */
    function _lzConfigure(address memecoin, address pol, uint32[] memory omnichainIds) internal {
        uint32 currentChainId = uint32(block.chainid);
        uint256 omnichainIdsLength = omnichainIds.length;

        // Use default config
        for (uint256 i = 0; i < omnichainIdsLength;) {
            uint32 omnichainId = omnichainIds[i];
            unchecked {
                ++i;
            }
            if (omnichainId == currentChainId) continue;

            uint32 remoteEndpointId = ILzEndpointRegistry(lzEndpointRegistry).lzEndpointIdOfChain(omnichainId);
            require(remoteEndpointId != 0, InvalidOmnichainId(omnichainId));

            IOAppCore(memecoin).setPeer(remoteEndpointId, bytes32(uint256(uint160(memecoin))));
            IOAppCore(pol).setPeer(remoteEndpointId, bytes32(uint256(uint160(pol))));
        }
    }

    /**
     * @notice Remove native gas dust from the contract.
     * @dev Transfers the full native balance to `receiver`.
     * @param receiver - The recipient of the native dust.
     */
    function removeGasDust(address receiver) external override onlyOwner {
        uint256 dust = address(this).balance;
        _transferOut(NATIVE, receiver, dust);

        emit RemoveGasDust(receiver, dust);
    }

    /**
     * @notice Pause state-changing launcher entrypoints.
     * @dev Only callable by the owner.
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause state-changing launcher entrypoints.
     * @dev Only callable by the owner.
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Set the memeverse swap router contract.
     * @dev Only callable by the owner.
     * @param _memeverseSwapRouter - Address of memeverseSwapRouter
     */
    function setMemeverseSwapRouter(address _memeverseSwapRouter) external override onlyOwner {
        require(_memeverseSwapRouter != address(0), ZeroInput());
        _validateLaunchSettlementConfig(_memeverseSwapRouter, memeverseUniswapHook);

        memeverseSwapRouter = _memeverseSwapRouter;

        emit SetMemeverseSwapRouter(_memeverseSwapRouter);
    }

    /// @notice Set the memeverse hook contract.
    /// @dev Only callable by the owner. The hook is write-once because existing live pools are namespaced by hook.
    /// @param _memeverseUniswapHook Address of the Memeverse hook.
    function setMemeverseUniswapHook(address _memeverseUniswapHook) external override onlyOwner {
        require(_memeverseUniswapHook != address(0), ZeroInput());
        if (memeverseUniswapHook != address(0)) revert HookAlreadyConfigured();
        address routerAddress = memeverseSwapRouter;
        if (routerAddress != address(0)) {
            _validateLaunchSettlementConfig(routerAddress, _memeverseUniswapHook);
        } else {
            address boundLauncher = IMemeverseUniswapHook(_memeverseUniswapHook).launcher();
            require(boundLauncher == address(this), InvalidLaunchSettlementConfig());
        }

        memeverseUniswapHook = _memeverseUniswapHook;
    }

    function _validateLaunchSettlementConfig(address routerAddress, address hookAddress) internal view {
        require(hookAddress != address(0), InvalidLaunchSettlementConfig());
        IMemeverseSwapRouter router = IMemeverseSwapRouter(routerAddress);
        address routerHookAddress = address(router.hook());
        address boundLauncher = IMemeverseUniswapHook(hookAddress).launcher();
        require(routerHookAddress == hookAddress && boundLauncher == address(this), InvalidLaunchSettlementConfig());
    }

    function _activatePostUnlockPublicSwapProtection(Memeverse storage verse) internal {
        uint40 resumeTime = uint40(block.timestamp + UNLOCK_PROTECTION_WINDOW);
        IMemeverseUniswapHook hook = IMemeverseUniswapHook(memeverseUniswapHook);

        // Both protected pools resume public swaps off the same transition-time anchor to avoid immediate arbitrage against unlock exits.
        hook.setPublicSwapResumeTime(verse.memecoin, verse.UPT, resumeTime);
        hook.setPublicSwapResumeTime(verse.pol, verse.UPT, resumeTime);
    }

    /**
     * @notice Set the LayerZero endpoint registry contract.
     * @dev Only callable by the owner.
     * @param _lzEndpointRegistry - Address of LzEndpointRegistry
     */
    function setLzEndpointRegistry(address _lzEndpointRegistry) external override onlyOwner {
        require(_lzEndpointRegistry != address(0), ZeroInput());

        lzEndpointRegistry = _lzEndpointRegistry;

        emit SetLzEndpointRegistry(_lzEndpointRegistry);
    }

    /**
     * @notice Set the memeverse registrar contract.
     * @dev Only callable by the owner.
     * @param _memeverseRegistrar - Address of memeverseRegistrar
     */
    function setMemeverseRegistrar(address _memeverseRegistrar) external override onlyOwner {
        require(_memeverseRegistrar != address(0), ZeroInput());

        memeverseRegistrar = _memeverseRegistrar;

        emit SetMemeverseRegistrar(_memeverseRegistrar);
    }

    /**
     * @notice Set the memeverse proxy deployer contract.
     * @dev Only callable by the owner.
     * @param _memeverseProxyDeployer - Address of memeverseProxyDeployer
     */
    function setMemeverseProxyDeployer(address _memeverseProxyDeployer) external override onlyOwner {
        require(_memeverseProxyDeployer != address(0), ZeroInput());

        memeverseProxyDeployer = _memeverseProxyDeployer;

        emit SetMemeverseProxyDeployer(_memeverseProxyDeployer);
    }

    /**
     * @notice Set the yield dispatcher contract.
     * @dev Only callable by the owner.
     * @param _yieldDispatcher - Address of yieldDispatcher
     */
    function setYieldDispatcher(address _yieldDispatcher) external override onlyOwner {
        require(_yieldDispatcher != address(0), ZeroInput());

        yieldDispatcher = _yieldDispatcher;

        emit SetYieldDispatcher(_yieldDispatcher);
    }

    /**
     * @notice Set fund metadata for a UPT token.
     * @dev Only callable by the owner.
     * @param _upt - Genesis fund type
     * @param _minTotalFund - The minimum participation genesis fund corresponding to UPT
     * @param _fundBasedAmount - // The number of Memecoins minted per unit of Memecoin genesis fund
     */
    function setFundMetaData(address _upt, uint256 _minTotalFund, uint256 _fundBasedAmount)
        external
        override
        onlyOwner
    {
        require(_minTotalFund != 0 && _fundBasedAmount != 0, ZeroInput());
        require(
            _fundBasedAmount <= MAX_SUPPORTED_FUND_BASED_AMOUNT,
            FundBasedAmountTooHigh(_fundBasedAmount, MAX_SUPPORTED_FUND_BASED_AMOUNT)
        );

        fundMetaDatas[_upt] = FundMetaData(_minTotalFund, _fundBasedAmount);

        emit SetFundMetaData(_upt, _minTotalFund, _fundBasedAmount);
    }

    /**
     * @notice Set the executor reward rate.
     * @dev Only callable by the owner.
     * @param _executorRewardRate - Executor reward rate
     */
    function setExecutorRewardRate(uint256 _executorRewardRate) external override onlyOwner {
        require(_executorRewardRate < RATIO, FeeRateOverFlow());

        executorRewardRate = _executorRewardRate;

        emit SetExecutorRewardRate(_executorRewardRate);
    }

    /**
     * @notice Set preorder cap and vesting parameters.
     * @dev Only callable by the owner.
     * @param _preorderCapRatio Preorder capacity ratio in `RATIO` precision.
     * @param _preorderVestingDuration Vesting duration for preorder memecoin.
     */
    function setPreorderConfig(uint256 _preorderCapRatio, uint256 _preorderVestingDuration)
        external
        override
        onlyOwner
    {
        require(_preorderCapRatio != 0 && _preorderVestingDuration != 0, ZeroInput());
        require(_preorderCapRatio <= RATIO, FeeRateOverFlow());

        preorderCapRatio = _preorderCapRatio;
        preorderVestingDuration = _preorderVestingDuration;

        emit SetPreorderConfig(_preorderCapRatio, _preorderVestingDuration);
    }

    /**
     * @notice Set gas limits for OFT receive and yield dispatcher.
     * @dev Only callable by the owner.
     * @param _oftReceiveGasLimit - Gas limit for OFT receive
     * @param _yieldDispatcherGasLimit - Gas limit for yield dispatcher
     */
    function setGasLimits(uint128 _oftReceiveGasLimit, uint128 _yieldDispatcherGasLimit) external override onlyOwner {
        require(_oftReceiveGasLimit > 0 && _yieldDispatcherGasLimit > 0, ZeroInput());

        oftReceiveGasLimit = _oftReceiveGasLimit;
        yieldDispatcherGasLimit = _yieldDispatcherGasLimit;

        emit SetGasLimits(_oftReceiveGasLimit, _yieldDispatcherGasLimit);
    }

    /**
     * @notice Set external metadata for a memeverse.
     * @dev Callable by the verse governor or the registrar.
     * @param verseId - Memeverse id
     * @param uri - IPFS URI of memecoin icon
     * @param description - Description
     * @param communities - Community(Website, X, Discord, Telegram and Others)
     */
    function setExternalInfo(
        uint256 verseId,
        string calldata uri,
        string calldata description,
        string[] calldata communities
    ) external override {
        require(msg.sender == memeverses[verseId].governor || msg.sender == memeverseRegistrar, PermissionDenied());
        require(bytes(description).length < 256, InvalidLength());

        if (bytes(uri).length != 0) memeverses[verseId].uri = uri;
        if (bytes(description).length != 0) memeverses[verseId].desc = description;
        if (communities.length != 0) {
            uint256 communitiesLength = communities.length;
            for (uint256 i = 0; i < communitiesLength;) {
                communitiesMap[verseId][i] = communities[i];
                unchecked {
                    ++i;
                }
            }
        }

        emit SetExternalInfo(verseId, uri, description, communities);
    }

    function _buildSendParamAndMessagingFee(
        uint32 govEndpointId,
        uint256 amount,
        address token,
        address receiver,
        TokenType tokenType,
        bytes memory yieldDispatcherOptions
    ) internal view returns (SendParam memory sendParam, MessagingFee memory messagingFee) {
        sendParam = SendParam({
            dstEid: govEndpointId,
            to: bytes32(uint256(uint160(yieldDispatcher))),
            amountLD: amount,
            minAmountLD: 0,
            extraOptions: yieldDispatcherOptions,
            composeMsg: abi.encode(receiver, tokenType),
            oftCmd: abi.encode()
        });
        messagingFee = IOFT(token).quoteSend(sendParam, false);
    }

    function _previewPairFees(address tokenA, address tokenB)
        internal
        view
        returns (uint256 tokenAFee, uint256 tokenBFee)
    {
        (uint256 fee0, uint256 fee1) =
            IMemeverseSwapRouter(memeverseSwapRouter).previewClaimableFees(tokenA, tokenB, address(this));
        return _mapPairFees(tokenA, tokenB, fee0, fee1);
    }

    function _claimPairFees(address tokenA, address tokenB) internal returns (uint256 tokenAFee, uint256 tokenBFee) {
        PoolKey memory key = IMemeverseSwapRouter(memeverseSwapRouter).getHookPoolKey(tokenA, tokenB);
        (uint256 fee0, uint256 fee1) =
            IMemeverseSwapRouter(memeverseSwapRouter).claimFees(key, address(this), block.timestamp, 0, 0, 0);
        return _mapPairFees(tokenA, tokenB, fee0, fee1);
    }

    function _pairLpToken(address tokenA, address tokenB) internal view returns (address lpToken) {
        return IMemeverseSwapRouter(memeverseSwapRouter).lpToken(tokenA, tokenB);
    }

    function _mapPairFees(address tokenA, address tokenB, uint256 fee0, uint256 fee1)
        internal
        pure
        returns (uint256 tokenAFee, uint256 tokenBFee)
    {
        if (tokenA < tokenB) {
            return (fee0, fee1);
        }
        return (fee1, fee0);
    }
}
