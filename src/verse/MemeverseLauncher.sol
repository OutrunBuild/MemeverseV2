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

import {TokenHelper} from "../common/token/TokenHelper.sol";
import {InitialPriceCalculator} from "./libraries/InitialPriceCalculator.sol";
import {IMemecoin} from "../token/interfaces/IMemecoin.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IMemeverseLauncher} from "./interfaces/IMemeverseLauncher.sol";
import {IMemeLiquidProof} from "../token/interfaces/IMemeLiquidProof.sol";
import {ILzEndpointRegistry} from "../common/omnichain/interfaces/ILzEndpointRegistry.sol";
import {IMemecoinYieldVault} from "../yield/interfaces/IMemecoinYieldVault.sol";
import {IMemeverseOFTDispatcher} from "./interfaces/IMemeverseOFTDispatcher.sol";
import {IMemeverseProxyDeployer} from "./interfaces/IMemeverseProxyDeployer.sol";
import {IMemeverseSwapRouter} from "../swap/interfaces/IMemeverseSwapRouter.sol";

/**
 * @title Trapping into the memeverse
 */
contract MemeverseLauncher is IMemeverseLauncher, TokenHelper, Pausable, Ownable {
    using OptionsBuilder for bytes;
    using PoolIdLibrary for PoolKey;

    uint256 public constant RATIO = 10000;
    uint256 internal constant MAX_SUPPORTED_FUND_BASED_AMOUNT = (1 << 64) - 1;

    address public localLzEndpoint;
    address public lzEndpointRegistry;
    address public oftDispatcher;
    address public memeverseRegistrar;
    address public memeverseProxyDeployer;
    address public memeverseSwapRouter;

    uint256 public executorRewardRate;
    uint128 public oftReceiveGasLimit;
    uint128 public oftDispatcherGasLimit;

    mapping(address UPT => FundMetaData) public fundMetaDatas;
    mapping(address memecoin => uint256) public memecoinToIds;
    mapping(uint256 verseId => Memeverse) public memeverses;
    mapping(uint256 verseId => GenesisFund) public genesisFunds;
    mapping(uint256 verseId => uint256) public totalClaimablePOL;
    mapping(uint256 verseId => uint256) public totalPolLiquidity;
    mapping(uint256 verseId => mapping(address account => GenesisData)) public userGenesisData;
    mapping(uint256 verseId => mapping(uint256 provider => string)) public communitiesMap; // provider -> 0:Website, 1:X, 2:Discord, 3:Telegram, >4:Others

    constructor(
        address _owner,
        address _localLzEndpoint,
        address _memeverseRegistrar,
        address _memeverseProxyDeployer,
        address _oftDispatcher,
        address _lzEndpointRegistry,
        uint256 _executorRewardRate,
        uint128 _oftReceiveGasLimit,
        uint128 _oftDispatcherGasLimit
    ) Ownable(_owner) {
        localLzEndpoint = _localLzEndpoint;
        memeverseRegistrar = _memeverseRegistrar;
        memeverseProxyDeployer = _memeverseProxyDeployer;
        lzEndpointRegistry = _lzEndpointRegistry;
        oftDispatcher = _oftDispatcher;
        executorRewardRate = _executorRewardRate;
        oftReceiveGasLimit = _oftReceiveGasLimit;
        oftDispatcherGasLimit = _oftDispatcherGasLimit;
    }

    modifier versIdValidate(uint256 verseId) {
        _versIdValidate(verseId);
        _;
    }

    function _versIdValidate(uint256 verseId) internal view {
        require(memeverses[verseId].memecoin != address(0), InvalidVerseId());
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
     * @dev Reverts when `verseId` is zero.
     * @param verseId - The verse id.
     * @return verse - The memeverse.
     */
    function getMemeverseByVerseId(uint256 verseId) external view override returns (Memeverse memory verse) {
        require(verseId != 0, ZeroInput());
        verse = memeverses[verseId];
    }

    /**
     * @notice Get the memeverse by memecoin.
     * @dev Returns an empty struct when the memecoin is not registered.
     * @param memecoin - The address of the memecoin.
     * @return verse - The memeverse.
     */
    function getMemeverseByMemecoin(address memecoin) external view override returns (Memeverse memory verse) {
        require(memecoin != address(0), ZeroInput());
        verse = memeverses[memecoinToIds[memecoin]];
    }

    /**
     * @notice Get the Stage by verse id.
     * @dev Reverts when `verseId` is zero.
     * @param verseId - The verse id.
     * @return stage - The memeverse current stage.
     */
    function getStageByVerseId(uint256 verseId) external view override returns (Stage stage) {
        require(verseId != 0, ZeroInput());
        stage = memeverses[verseId].currentStage;
    }

    /**
     * @notice Get the Stage by memecoin.
     * @dev Returns the current stage for the memecoin's registered verse.
     * @param memecoin - The address of the memecoin.
     * @return stage - The memeverse current stage.
     */
    function getStageByMemecoin(address memecoin) external view override returns (Stage stage) {
        require(memecoin != address(0), ZeroInput());
        stage = memeverses[memecoinToIds[memecoin]].currentStage;
    }

    /**
     * @notice Get the yield vault by verse id.
     * @dev Reverts when `verseId` is zero.
     * @param verseId - The verse id.
     * @return yieldVault - The yield vault.
     */
    function getYieldVaultByVerseId(uint256 verseId) external view override returns (address yieldVault) {
        require(verseId != 0, ZeroInput());
        yieldVault = memeverses[verseId].yieldVault;
    }

    /**
     * @notice Get the governor by verse id.
     * @dev Reverts when `verseId` is zero.
     * @param verseId - The verse id.
     * @return governor - The governor.
     */
    function getGovernorByVerseId(uint256 verseId) external view override returns (address governor) {
        require(verseId != 0, ZeroInput());
        governor = memeverses[verseId].governor;
    }

    /**
     * @notice Preview claimable POL token of caller after Genesis stage.
     * @dev Uses the caller's stored genesis contribution as the claim basis.
     * @param verseId - Memeverse id
     * @return claimableAmount - The claimable amount.
     */
    function claimablePOLToken(uint256 verseId) public view override returns (uint256 claimableAmount) {
        require(verseId != 0, ZeroInput());
        Memeverse storage verse = memeverses[verseId];
        require(verse.currentStage >= Stage.Locked, NotReachedLockedStage());

        uint256 userFunds = userGenesisData[verseId][msg.sender].genesisFund;
        uint256 totalClaimable = totalClaimablePOL[verseId];
        GenesisFund storage genesisFund = genesisFunds[verseId];
        claimableAmount =
            totalClaimable * userFunds / (genesisFund.totalMemecoinFunds + genesisFund.totalLiquidProofFunds);
    }

    /**
     * @notice Preview Genesis liquidity market maker fees for DAO Treasury (UPT) and Yield Vault (Memecoin).
     * @dev Aggregates the claimable LP fees from the memecoin/UPT and liquidProof/UPT pools.
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
        require(verseId != 0, ZeroInput());
        Memeverse storage verse = memeverses[verseId];
        require(verse.currentStage >= Stage.Locked, NotReachedLockedStage());

        address UPT = verse.UPT;
        (memecoinFee, UPTFee) = _previewPairFees(verse.memecoin, UPT);
        (, uint256 polPairUPTFee) = _previewPairFees(verse.liquidProof, UPT);
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
        require(verseId != 0, ZeroInput());
        Memeverse storage verse = memeverses[verseId];
        uint32 govChainId = verse.omnichainIds[0];
        if (govChainId == block.chainid) return 0;

        (uint256 UPTFee, uint256 memecoinFee) = previewGenesisMakerFees(verseId);
        uint32 govEndpointId = ILzEndpointRegistry(lzEndpointRegistry).lzEndpointIdOfChain(govChainId);
        bytes memory oftDispatcherOptions = OptionsBuilder.newOptions()
            .addExecutorLzReceiveOption(oftReceiveGasLimit, 0).addExecutorLzComposeOption(0, oftDispatcherGasLimit, 0);

        if (UPTFee != 0) {
            (, MessagingFee memory govMessagingFee) = _buildSendParamAndMessagingFee(
                govEndpointId, UPTFee, verse.UPT, verse.governor, TokenType.UPT, oftDispatcherOptions
            );
            lzFee += govMessagingFee.nativeFee;
        }

        if (memecoinFee != 0) {
            (, MessagingFee memory memecoinMessagingFee) = _buildSendParamAndMessagingFee(
                govEndpointId, memecoinFee, verse.memecoin, verse.yieldVault, TokenType.MEMECOIN, oftDispatcherOptions
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
        uint128 increasedLiquidProofFund;
        unchecked {
            increasedLiquidProofFund = amountInUPT / 4;
            increasedMemecoinFund = amountInUPT - increasedLiquidProofFund;
        }

        GenesisFund storage genesisFund = genesisFunds[verseId];
        unchecked {
            genesisFund.totalMemecoinFunds += increasedMemecoinFund;
            genesisFund.totalLiquidProofFunds += increasedLiquidProofFund;
            userGenesisData[verseId][user].genesisFund += amountInUPT;
        }

        emit Genesis(verseId, user, increasedMemecoinFund, increasedLiquidProofFund);
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
            currentStage = _handleGenesisStage(verseId, currentTime, verse);
        } else if (currentStage == Stage.Locked && currentTime > verse.unlockTime) {
            verse.currentStage = Stage.Unlocked;
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
        uint128 totalLiquidProofFunds = genesisFund.totalLiquidProofFunds;
        bool meetMinTotalFund = totalMemecoinFunds + totalLiquidProofFunds >= fundMetaDatas[UPT].minTotalFund;
        uint256 endTime = verse.endTime;
        require(
            endTime != 0 && meetMinTotalFund && (currentTime > endTime || verse.flashGenesis),
            StillInGenesisStage(endTime)
        );

        if (!meetMinTotalFund) {
            verse.currentStage = Stage.Refund;
            return Stage.Refund;
        } else {
            _deployAndSetupMemeverse(verseId, verse, UPT, totalMemecoinFunds, totalLiquidProofFunds);
            verse.currentStage = Stage.Locked;
            return Stage.Locked;
        }
    }

    /**
     * @dev Deploy and setup memeverse components
     * @param verseId - Memeverse id
     * @param verse - Memeverse storage reference
     * @param UPT - UPT address
     * @param totalMemecoinFunds - Total memecoin funds
     * @param totalLiquidProofFunds - Total liquid proof funds
     */
    function _deployAndSetupMemeverse(
        uint256 verseId,
        Memeverse storage verse,
        address UPT,
        uint128 totalMemecoinFunds,
        uint128 totalLiquidProofFunds
    ) internal {
        string memory name = verse.name;
        string memory symbol = verse.symbol;
        address memecoin = verse.memecoin;
        address pol = verse.liquidProof;
        uint32 govChainId = verse.omnichainIds[0];

        // Deploy Yield Vault, DAO Governor and Incentivizer
        (address yieldVault, address governor, address incentivizer) =
            _deployGovernanceComponents(verseId, govChainId, name, symbol, UPT, memecoin, pol);
        verse.yieldVault = yieldVault;
        verse.governor = governor;
        verse.incentivizer = incentivizer;

        // Deploy liquidity
        _deployLiquidity(verseId, UPT, memecoin, pol, totalMemecoinFunds, totalLiquidProofFunds);
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
            yieldVault = IMemeverseProxyDeployer(memeverseProxyDeployer).deployYieldVault(verseId);
            IMemecoinYieldVault(yieldVault)
                .initialize(
                    string(abi.encodePacked("Staked ", name)),
                    string(abi.encodePacked("s", symbol)),
                    oftDispatcher,
                    memecoin,
                    verseId
                );
            (governor, incentivizer) = IMemeverseProxyDeployer(memeverseProxyDeployer)
                .deployGovernorAndIncentivizer(name, UPT, memecoin, pol, yieldVault, verseId, proposalThreshold);
        } else {
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
     * @param totalLiquidProofFunds - Total liquid proof funds
     */
    function _deployLiquidity(
        uint256 verseId,
        address UPT,
        address memecoin,
        address pol,
        uint128 totalMemecoinFunds,
        uint128 totalLiquidProofFunds
    ) internal {
        // Deploy memecoin liquidity
        uint256 memecoinAmount = totalMemecoinFunds * fundMetaDatas[UPT].fundBasedAmount;
        uint160 memecoinStartPrice =
            InitialPriceCalculator.calculateMemecoinStartPriceX96(memecoin, UPT, fundMetaDatas[UPT].fundBasedAmount);
        IMemecoin(memecoin).mint(address(this), memecoinAmount);

        (uint128 memecoinLiquidity, PoolKey memory poolKey) = IMemeverseSwapRouter(memeverseSwapRouter)
            .createPoolAndAddLiquidity(
                memecoin,
                UPT,
                memecoinAmount,
                totalMemecoinFunds,
                memecoinStartPrice,
                address(this),
                address(this),
                block.timestamp
            );

        // Mint liquidity proof token
        IMemeLiquidProof(pol).mint(address(this), memecoinLiquidity);
        IMemeLiquidProof(pol).setPoolId(poolKey.toId());

        // Deploy POL liquidity
        uint256 deployedPOL = memecoinLiquidity / 3;
        uint160 polStartPrice =
            InitialPriceCalculator.calculateInitialSqrtPriceX96(pol, UPT, deployedPOL, totalLiquidProofFunds);
        (uint128 polLiquidity,) = IMemeverseSwapRouter(memeverseSwapRouter)
            .createPoolAndAddLiquidity(
                pol,
                UPT,
                deployedPOL,
                totalLiquidProofFunds,
                polStartPrice,
                address(this),
                address(this),
                block.timestamp
            );

        totalPolLiquidity[verseId] = polLiquidity;
        totalClaimablePOL[verseId] = memecoinLiquidity - deployedPOL;
    }

    /**
     * @notice Refund UPT after genesis failed because the omnichain funds did not meet the minimum requirement.
     * @dev Marks the caller as refunded before transferring funds out.
     * @param verseId - Memeverse id
     * @return genesisFund - The refunded genesis contribution amount.
     */
    function refund(uint256 verseId) external override whenNotPaused returns (uint256 genesisFund) {
        require(verseId != 0, ZeroInput());
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
     * @notice Claim POL token in stage Locked.
     * @dev Transfers the caller's proportional claimable liquid proof balance.
     * @param verseId - Memeverse id
     * @return amount - The claimed POL amount.
     */
    function claimPOLToken(uint256 verseId) external override whenNotPaused returns (uint256 amount) {
        require(verseId != 0, ZeroInput());
        amount = claimablePOLToken(verseId);
        require(amount != 0, NoPOLAvailable());

        address msgSender = msg.sender;
        userGenesisData[verseId][msgSender].isClaimed = true;
        _transferOut(memeverses[verseId].liquidProof, msgSender, amount);

        emit ClaimPOLToken(verseId, msgSender, amount);
    }

    /**
     * @dev Redeem transaction fees and distribute them to the owner(UPT) and vault(Memecoin)
     * @param verseId - Memeverse id
     * @param rewardReceiver - Address of executor reward receiver
     * @return govFee - The Gov fee.
     * @return memecoinFee - The memecoin fee.
     * @return liquidProofFee - The liquidProof fee.
     * @return executorReward  - The executor reward.
     * @notice Anyone who calls this method will be rewarded with executorReward.
     */
    function redeemAndDistributeFees(uint256 verseId, address rewardReceiver)
        external
        payable
        override
        whenNotPaused
        returns (uint256 govFee, uint256 memecoinFee, uint256 liquidProofFee, uint256 executorReward)
    {
        require(verseId != 0 && rewardReceiver != address(0), ZeroInput());
        Memeverse storage verse = memeverses[verseId];
        require(verse.currentStage >= Stage.Locked, NotReachedLockedStage());

        address UPT = verse.UPT;
        address memecoin = verse.memecoin;
        address liquidProof = verse.liquidProof;

        uint256 UPTFee;
        uint256 polPairUPTFee;
        (memecoinFee, UPTFee) = _claimPairFees(memecoin, UPT);
        (liquidProofFee, polPairUPTFee) = _claimPairFees(liquidProof, UPT);
        UPTFee += polPairUPTFee;

        if (UPTFee == 0 && memecoinFee == 0 && liquidProofFee == 0) return (0, 0, 0, 0);
        if (liquidProofFee != 0) IMemeLiquidProof(liquidProof).burn(address(this), liquidProofFee);

        unchecked {
            executorReward = UPTFee * executorRewardRate / RATIO;
            govFee = UPTFee - executorReward;
        }
        if (executorReward != 0) _transferOut(UPT, rewardReceiver, executorReward);

        uint32 govChainId = verse.omnichainIds[0];
        address governor = verse.governor;
        address yieldVault = verse.yieldVault;

        if (govChainId == block.chainid) {
            if (govFee != 0) {
                _transferOut(UPT, oftDispatcher, govFee);
                IMemeverseOFTDispatcher(oftDispatcher)
                    .lzCompose(UPT, bytes32(0), abi.encode(governor, TokenType.UPT, govFee), address(0), "");
            }
            if (memecoinFee != 0) {
                _transferOut(memecoin, oftDispatcher, memecoinFee);
                IMemeverseOFTDispatcher(oftDispatcher)
                    .lzCompose(
                        memecoin, bytes32(0), abi.encode(yieldVault, TokenType.MEMECOIN, memecoinFee), address(0), ""
                    );
            }
        } else {
            uint32 govEndpointId = ILzEndpointRegistry(lzEndpointRegistry).lzEndpointIdOfChain(govChainId);
            bytes memory oftDispatcherOptions = OptionsBuilder.newOptions()
                .addExecutorLzReceiveOption(oftReceiveGasLimit, 0)
                .addExecutorLzComposeOption(0, oftDispatcherGasLimit, 0);

            SendParam memory sendUPTParam;
            MessagingFee memory govMessagingFee;
            if (govFee != 0) {
                (sendUPTParam, govMessagingFee) = _buildSendParamAndMessagingFee(
                    govEndpointId, govFee, UPT, governor, TokenType.UPT, oftDispatcherOptions
                );
            }

            SendParam memory sendMemecoinParam;
            MessagingFee memory memecoinMessagingFee;
            if (memecoinFee != 0) {
                (sendMemecoinParam, memecoinMessagingFee) = _buildSendParamAndMessagingFee(
                    govEndpointId, memecoinFee, memecoin, yieldVault, TokenType.MEMECOIN, oftDispatcherOptions
                );
            }

            require(msg.value >= govMessagingFee.nativeFee + memecoinMessagingFee.nativeFee, InsufficientLzFee());
            if (govFee != 0) {
                IOFT(UPT).send{value: govMessagingFee.nativeFee}(sendUPTParam, govMessagingFee, msg.sender);
            }
            if (memecoinFee != 0) {
                IOFT(memecoin).send{value: memecoinMessagingFee.nativeFee}(
                    sendMemecoinParam, memecoinMessagingFee, msg.sender
                );
            }
        }

        emit RedeemAndDistributeFees(verseId, govFee, memecoinFee, liquidProofFee, executorReward);
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
        whenNotPaused
        returns (uint256 amountInLP)
    {
        require(amountInPOL != 0, ZeroInput());

        Memeverse storage verse = memeverses[verseId];
        require(verse.currentStage == Stage.Unlocked, NotUnlockedStage());

        IMemeLiquidProof(verse.liquidProof).burn(msg.sender, amountInPOL);

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
    function redeemPolLiquidity(uint256 verseId) external override whenNotPaused returns (uint256 amountInLP) {
        Memeverse storage verse = memeverses[verseId];
        require(verse.currentStage == Stage.Unlocked, NotUnlockedStage());

        address msgSender = msg.sender;
        GenesisData storage genesisData = userGenesisData[verseId][msgSender];
        uint256 userFunds = genesisData.genesisFund;
        require(userFunds > 0 && !genesisData.isRedeemed, InvalidRedeem());

        GenesisFund storage genesisFund = genesisFunds[verseId];
        amountInLP = totalPolLiquidity[verseId] * userFunds
            / (genesisFund.totalMemecoinFunds + genesisFund.totalLiquidProofFunds);

        address lpToken = _pairLpToken(verse.liquidProof, verse.UPT);
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
    ) external override returns (uint256 amountInUPT, uint256 amountInMemecoin, uint256 amountOut) {
        require(verseId != 0 && amountInUPTDesired != 0 && amountInMemecoinDesired != 0, ZeroInput());
        Memeverse storage verse = memeverses[verseId];
        require(verse.currentStage >= Stage.Locked, NotReachedLockedStage());

        address UPT = verse.UPT;
        address memecoin = verse.memecoin;
        uint256 uptBefore = IERC20(UPT).balanceOf(address(this));
        uint256 memecoinBefore = IERC20(memecoin).balanceOf(address(this));

        _transferIn(UPT, msg.sender, amountInUPTDesired);
        _transferIn(memecoin, msg.sender, amountInMemecoinDesired);
        _safeApproveInf(UPT, memeverseSwapRouter);
        _safeApproveInf(memecoin, memeverseSwapRouter);

        if (amountOutDesired == 0) {
            amountOut = IMemeverseSwapRouter(memeverseSwapRouter)
                .addLiquidity(
                    Currency.wrap(UPT),
                    Currency.wrap(memecoin),
                    amountInUPTDesired,
                    amountInMemecoinDesired,
                    amountInUPTMin,
                    amountInMemecoinMin,
                    address(this),
                    address(this),
                    deadline
                );

            uint256 uptAfter = IERC20(UPT).balanceOf(address(this));
            uint256 memecoinAfter = IERC20(memecoin).balanceOf(address(this));
            amountInUPT = uptBefore + amountInUPTDesired - uptAfter;
            amountInMemecoin = memecoinBefore + amountInMemecoinDesired - memecoinAfter;
        } else {
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
                    address(this),
                    deadline
                );
        }

        uint256 UPTRefund = amountInUPTDesired - amountInUPT;
        uint256 memecoinRefund = amountInMemecoinDesired - amountInMemecoin;
        if (UPTRefund > 0) _transferOut(UPT, msg.sender, UPTRefund);
        if (memecoinRefund > 0) _transferOut(memecoin, msg.sender, memecoinRefund);
        address liquidProof = verse.liquidProof;
        IMemeLiquidProof(liquidProof).mint(msg.sender, amountOut);

        emit MintPOLToken(verseId, memecoin, liquidProof, msg.sender, amountOut);
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

        address memecoin = IMemeverseProxyDeployer(memeverseProxyDeployer).deployMemecoin(uniqueId);
        address pol = IMemeverseProxyDeployer(memeverseProxyDeployer).deployPOL(uniqueId);
        IMemecoin(memecoin).initialize(name, symbol, address(this), address(this));
        IMemeLiquidProof(pol)
            .initialize(
                string(abi.encodePacked("POL-", name)),
                string(abi.encodePacked("POL-", symbol)),
                memecoin,
                address(this),
                address(this)
            );

        _lzConfigure(memecoin, pol, omnichainIds);

        Memeverse storage verse = memeverses[uniqueId];
        verse.name = name;
        verse.symbol = symbol;
        verse.UPT = UPT;
        verse.memecoin = memecoin;
        verse.liquidProof = pol;
        verse.endTime = endTime;
        verse.unlockTime = unlockTime;
        verse.omnichainIds = omnichainIds;
        verse.flashGenesis = flashGenesis;

        memeverses[uniqueId] = verse;
        memecoinToIds[memecoin] = uniqueId;

        emit RegisterMemeverse(uniqueId, verse);
    }

    /**
     * @dev Memecoin Layerzero configure. See: https://docs.layerzero.network/v2/developers/evm/create-lz-oapp/configuring-pathways
     */
    function _lzConfigure(address memecoin, address pol, uint32[] memory omnichainIds) internal {
        uint32 currentChainId = uint32(block.chainid);

        // Use default config
        for (uint256 i = 0; i < omnichainIds.length;) {
            uint32 omnichainId = omnichainIds[i];
            unchecked {
                i++;
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
    function removeGasDust(address receiver) external override {
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

        memeverseSwapRouter = _memeverseSwapRouter;

        emit SetMemeverseSwapRouter(_memeverseSwapRouter);
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
     * @notice Set the memeverse OFT dispatcher contract.
     * @dev Only callable by the owner.
     * @param _oftDispatcher - Address of oftDispatcher
     */
    function setOFTDispatcher(address _oftDispatcher) external override onlyOwner {
        require(_oftDispatcher != address(0), ZeroInput());

        oftDispatcher = _oftDispatcher;

        emit SetOFTDispatcher(_oftDispatcher);
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
     * @notice Set gas limits for OFT receive and yield dispatcher.
     * @dev Only callable by the owner.
     * @param _oftReceiveGasLimit - Gas limit for OFT receive
     * @param _oftDispatcherGasLimit - Gas limit for yield dispatcher
     */
    function setGasLimits(uint128 _oftReceiveGasLimit, uint128 _oftDispatcherGasLimit) external override onlyOwner {
        require(_oftReceiveGasLimit > 0 && _oftDispatcherGasLimit > 0, ZeroInput());

        oftReceiveGasLimit = _oftReceiveGasLimit;
        oftDispatcherGasLimit = _oftDispatcherGasLimit;

        emit SetGasLimits(_oftReceiveGasLimit, _oftDispatcherGasLimit);
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
            for (uint256 i = 0; i < communities.length;) {
                communitiesMap[verseId][i] = communities[i];
                unchecked {
                    i++;
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
        bytes memory oftDispatcherOptions
    ) internal view returns (SendParam memory sendParam, MessagingFee memory messagingFee) {
        sendParam = SendParam({
            dstEid: govEndpointId,
            to: bytes32(uint256(uint160(oftDispatcher))),
            amountLD: amount,
            minAmountLD: 0,
            extraOptions: oftDispatcherOptions,
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
