// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {IOFT, SendParam, MessagingFee} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";

import {TokenHelper} from "../common/token/TokenHelper.sol";
import {IMemeverseOFTEnum} from "../common/types/IMemeverseOFTEnum.sol";
import {IPol} from "../token/interfaces/IPol.sol";
import {IPOLend} from "../polend/interfaces/IPOLend.sol";
import {IPOLSplitter} from "../polend/interfaces/IPOLSplitter.sol";
import {IMemeverseUniswapHook} from "../swap/interfaces/IMemeverseUniswapHook.sol";
import {MemeversePoolKeyLib} from "../swap/libraries/MemeversePoolKeyLib.sol";
import {ILzEndpointRegistry} from "../common/omnichain/interfaces/ILzEndpointRegistry.sol";
import {IYieldDispatcher} from "./interfaces/IYieldDispatcher.sol";
import {IMemeverseLauncher} from "./interfaces/IMemeverseLauncher.sol";
import {MemeverseLauncherStorage} from "./interfaces/IMemeverseLauncherStorage.sol";
import {MemeverseLauncherLib} from "./libraries/MemeverseLauncherLib.sol";
import {IMemeverseFeeDistributor} from "./interfaces/IMemeverseFeeDistributor.sol";

/// @title MemeverseFeeDistributor
/// @notice Delegatecall-only sibling holding the fee collection and distribution chain relocated from
///         MemeverseLauncher. Binds the SAME ERC-7201 slot so under delegatecall it operates on
///         the proxy's MemeverseLauncherStorage. No Initializable, no own storage, empty constructor.
contract MemeverseFeeDistributor layout at erc7201("outrun.storage.MemeverseLauncher")
    is
    TokenHelper,
    IMemeverseFeeDistributor
{
    using OptionsBuilder for bytes;

    MemeverseLauncherStorage private memeverseLauncherStorage;

    constructor() {}

    // === relocated fee distribution chain (from MemeverseLauncher) ===
    //
    // Nested types (Memeverse, RedeemedFeeState, Stage, TokenType, NormalFeeState,
    // PendingAuxiliaryGovFeeState, etc.) are declared inside interface IMemeverseLauncher. Unlike the
    // facade (which inherits IMemeverseLauncher and can use bare names), this sibling only inherits
    // TokenHelper, so every reference below is qualified as IMemeverseLauncher.X.

    /**
     * @notice Collect redeemed fees, burn POL, split the executor reward, and distribute the rest.
     * @dev Invoked via delegatecall by the facade's `redeemAndDistributeFees`. The facade performs the
     *      `rewardReceiver` / verse-id / stage validation and emits `RedeemAndDistributeFees` after
     *      decoding the return values; this entry only runs the collect -> burn -> split -> distribute
     *      block so both `_transferOut` exits (executor reward + distribution) share one delegatecall
     *      and the `TokenHelper` reentrancy lock's acquire/release lifecycle stays whole (design §7).
     *      `msg.value` is the caller-supplied LayerZero native fee and is preserved across the
     *      delegatecall, hence `payable`.
     *      Delegatecall-only by construction, not by a runtime guard: the sibling's own storage is
     *      permanently uninitialized, so a direct (non-delegatecall) call reads an empty verse and
     *      reverts on the resulting external call to address(0). A msg.sender guard would be wrong
     *      here — under delegatecall msg.sender is the facade's caller (arbitrary), not the facade.
     * @param verseId Memeverse id.
     * @param rewardReceiver Receiver of the executor reward.
     * @param polSplitter The launcher's configured POLSplitter address (forwarded by the facade).
     * @return govFee The distributed governor fee amount.
     * @return memecoinFee The distributed memecoin fee amount.
     * @return polFee The distributed POL fee amount.
     * @return executorReward The distributed executor reward amount.
     */
    function collectAndDistributeFees(uint256 verseId, address rewardReceiver, address polSplitter)
        external
        payable
        override
        returns (uint256 govFee, uint256 memecoinFee, uint256 polFee, uint256 executorReward, bool hadFees)
    {
        IMemeverseLauncher.Memeverse storage verse = memeverseLauncherStorage.memeverses[verseId];
        IMemeverseLauncher.RedeemedFeeState memory fees = _collectRedeemedFees(verseId, verse, polSplitter);
        if (_hasNoRedeemedFees(fees)) {
            if (msg.value != 0) revert IMemeverseLauncher.InvalidLzFee(0, msg.value);
            return (0, 0, 0, 0, false);
        }
        if (fees.polFee != 0) IPol(verse.pol).burn(address(this), fees.polFee);

        (govFee, executorReward) = _splitExecutorReward(fees.uAssetFee);
        // Anyone can execute fee redemption; only the uAsset-side fee is split with the caller as an execution incentive.
        if (executorReward != 0) _transferOut(verse.uAsset, rewardReceiver, executorReward);

        memecoinFee = fees.memecoinFee;
        polFee = fees.polFee;
        govFee = _distributeRedeemedFees(verseId, verse, govFee, fees, polSplitter);
        hadFees = true;
    }

    /**
     * @notice Capture and accrue auxiliary-pool fees when a verse transitions Locked -> Unlocked.
     * @dev Invoked via delegatecall by the facade's `changeStage` Locked->Unlocked branch. Burns the
     *      captured POL fee and accumulates the governance share into `pendingAuxiliaryGovFeeStates`.
     *      Delegatecall-only by construction (see `collectAndDistributeFees` dev note).
     * @param verseId Memeverse id.
     * @param polSplitter The launcher's configured POLSplitter address (forwarded by the facade).
     * @param hook The launcher's configured MemeverseUniswapHook address (forwarded by the facade).
     */
    function captureLockedAuxiliaryFees(uint256 verseId, address polSplitter, address hook) external override {
        IMemeverseLauncher.Memeverse storage verse = memeverseLauncherStorage.memeverses[verseId];
        _captureLockedAuxiliaryFees(verseId, verse, polSplitter, hook);
    }

    function _collectRedeemedFees(uint256 verseId, IMemeverseLauncher.Memeverse storage verse, address _polSplitter)
        internal
        returns (IMemeverseLauncher.RedeemedFeeState memory fees)
    {
        address _hook = memeverseLauncherStorage.memeverseUniswapHook;
        (fees.memecoinFee, fees.uAssetFee) = _claimPairFees(verse.memecoin, verse.uAsset, _hook);

        address pt = IPOLSplitter(_polSplitter).getPT(verseId);
        (fees.auxiliaryGovUAssetFee, fees.auxiliaryGovPTFee, fees.polFee) = _claimAndAccrueAuxiliaryFees(
            verseId, verse, pt, verse.currentStage == IMemeverseLauncher.Stage.Locked, _hook
        );

        fees = _mergePendingAuxiliaryGovFees(verseId, fees, _polSplitter);
    }

    function _mergePendingAuxiliaryGovFees(
        uint256 verseId,
        IMemeverseLauncher.RedeemedFeeState memory fees,
        address _polSplitter
    ) internal returns (IMemeverseLauncher.RedeemedFeeState memory) {
        IMemeverseLauncher.PendingAuxiliaryGovFeeState storage pendingGovFeeState =
            memeverseLauncherStorage.pendingAuxiliaryGovFeeStates[verseId];
        uint256 pendingUAssetFee = pendingGovFeeState.pendingUAssetFee;
        uint256 pendingPTFee = pendingGovFeeState.pendingPTFee;
        uint256 auxiliaryGovPTFee = fees.auxiliaryGovPTFee + pendingPTFee;

        fees.auxiliaryGovUAssetFee += pendingUAssetFee;
        if (auxiliaryGovPTFee != 0) {
            if (IPOLSplitter(_polSplitter).previewPTToUAsset(verseId, auxiliaryGovPTFee) == 0) {
                pendingGovFeeState.pendingPTFee = auxiliaryGovPTFee;
                fees.auxiliaryGovPTFee = 0;
            } else {
                fees.auxiliaryGovPTFee = auxiliaryGovPTFee;
                pendingGovFeeState.pendingPTFee = 0;
            }
        }
        if (pendingUAssetFee != 0) pendingGovFeeState.pendingUAssetFee = 0;

        return fees;
    }

    function _hasNoRedeemedFees(IMemeverseLauncher.RedeemedFeeState memory fees) internal pure returns (bool) {
        return fees.uAssetFee == 0 && fees.memecoinFee == 0 && fees.polFee == 0 && fees.auxiliaryGovUAssetFee == 0
            && fees.auxiliaryGovPTFee == 0;
    }

    function _distributeRedeemedFees(
        uint256 verseId,
        IMemeverseLauncher.Memeverse storage verse,
        uint256 govFee,
        IMemeverseLauncher.RedeemedFeeState memory fees,
        address _polSplitter
    ) internal returns (uint256) {
        if (verse.omnichainIds[0] == block.chainid) {
            return _distributeRedeemedFeesSameChain(verseId, verse, govFee, fees, _polSplitter);
        }
        return _distributeRedeemedFeesCrossChain(verseId, verse, govFee, fees, _polSplitter);
    }

    function _distributeRedeemedFeesSameChain(
        uint256 verseId,
        IMemeverseLauncher.Memeverse storage verse,
        uint256 govFee,
        IMemeverseLauncher.RedeemedFeeState memory fees,
        address _polSplitter
    ) internal returns (uint256) {
        if (msg.value != 0) {
            revert IMemeverseLauncher.InvalidLzFee(0, msg.value);
        }
        address _yieldDispatcher = memeverseLauncherStorage.yieldDispatcher;
        address _polend = memeverseLauncherStorage.polend;

        uint256 auxiliaryGovUAssetHeldByLauncher = fees.auxiliaryGovUAssetFee;
        if (fees.auxiliaryGovPTFee != 0) {
            if (verse.currentStage == IMemeverseLauncher.Stage.Locked) {
                fees.auxiliaryGovUAssetFee += IPOLend(_polend)
                    .preRedeemPTFee(verseId, fees.auxiliaryGovPTFee, _yieldDispatcher);
            } else {
                fees.auxiliaryGovUAssetFee += IPOLSplitter(_polSplitter)
                    .redeemPT(verseId, fees.auxiliaryGovPTFee, _yieldDispatcher);
            }
            fees.auxiliaryGovPTFee = 0;
        }

        uint256 transferToDispatcher = govFee + auxiliaryGovUAssetHeldByLauncher;
        govFee += fees.auxiliaryGovUAssetFee;
        // Same-chain governance routes through YieldDispatcher's dedicated same-chain entry so local and remote fee
        // flows share one settlement sink.
        if (govFee != 0) {
            if (transferToDispatcher != 0) {
                _transferOut(verse.uAsset, _yieldDispatcher, transferToDispatcher);
            }
            IYieldDispatcher(_yieldDispatcher)
                .distributeSameChain(verse.uAsset, verse.governor, IMemeverseOFTEnum.TokenType.UASSET, govFee);
        }
        if (fees.memecoinFee != 0) {
            _transferOut(verse.memecoin, _yieldDispatcher, fees.memecoinFee);
            IYieldDispatcher(_yieldDispatcher)
                .distributeSameChain(
                    verse.memecoin, verse.yieldVault, IMemeverseOFTEnum.TokenType.MEMECOIN, fees.memecoinFee
                );
        }

        return govFee;
    }

    function _distributeRedeemedFeesCrossChain(
        uint256 verseId,
        IMemeverseLauncher.Memeverse storage verse,
        uint256 govFee,
        IMemeverseLauncher.RedeemedFeeState memory fees,
        address _polSplitter
    ) internal returns (uint256) {
        if (fees.auxiliaryGovPTFee != 0) {
            uint256 convertedUAssetAmount;
            if (verse.currentStage == IMemeverseLauncher.Stage.Locked) {
                convertedUAssetAmount = IPOLend(memeverseLauncherStorage.polend)
                    .preRedeemPTFee(verseId, fees.auxiliaryGovPTFee, address(this));
            } else {
                convertedUAssetAmount =
                    IPOLSplitter(_polSplitter).redeemPT(verseId, fees.auxiliaryGovPTFee, address(this));
            }
            fees.auxiliaryGovUAssetFee += convertedUAssetAmount;
            fees.auxiliaryGovPTFee = 0;
        }

        govFee += fees.auxiliaryGovUAssetFee;
        _sendRedeemedFeesCrossChain(verse, govFee, fees.memecoinFee);
        return govFee;
    }

    function _sendRedeemedFeesCrossChain(
        IMemeverseLauncher.Memeverse storage verse,
        uint256 govFee,
        uint256 memecoinFee
    ) internal {
        // Cross-chain governance prebuilds both OFT sends, then requires the caller to fund exactly the combined native messaging fee.
        uint32 govEndpointId =
            ILzEndpointRegistry(memeverseLauncherStorage.lzEndpointRegistry).lzEndpointIdOfChain(verse.omnichainIds[0]);
        bytes memory yieldDispatcherOptions = OptionsBuilder.newOptions()
            .addExecutorLzReceiveOption(memeverseLauncherStorage.oftReceiveGasLimit, 0)
            .addExecutorLzComposeOption(0, memeverseLauncherStorage.yieldDispatcherGasLimit, 0);
        // Cache yieldDispatcher once (R2-02): both OFT send-param builds consume the same address.
        address _yieldDispatcher = memeverseLauncherStorage.yieldDispatcher;

        SendParam memory sendUAssetParam;
        MessagingFee memory govMessagingFee;
        if (govFee != 0) {
            (sendUAssetParam, govMessagingFee) = _buildSendParamAndMessagingFee(
                govEndpointId,
                govFee,
                verse.uAsset,
                verse.governor,
                IMemeverseOFTEnum.TokenType.UASSET,
                yieldDispatcherOptions,
                _yieldDispatcher
            );
        }

        SendParam memory sendMemecoinParam;
        MessagingFee memory memecoinMessagingFee;
        if (memecoinFee != 0) {
            (sendMemecoinParam, memecoinMessagingFee) = _buildSendParamAndMessagingFee(
                govEndpointId,
                memecoinFee,
                verse.memecoin,
                verse.yieldVault,
                IMemeverseOFTEnum.TokenType.MEMECOIN,
                yieldDispatcherOptions,
                _yieldDispatcher
            );
        }

        uint256 requiredLzFee = govMessagingFee.nativeFee + memecoinMessagingFee.nativeFee;
        if (msg.value != requiredLzFee) revert IMemeverseLauncher.InvalidLzFee(requiredLzFee, msg.value);
        if (govFee != 0) {
            // solhint-disable-next-line check-send-result
            IOFT(verse.uAsset).send{value: govMessagingFee.nativeFee}(sendUAssetParam, govMessagingFee, msg.sender);
        }
        if (memecoinFee != 0) {
            // solhint-disable-next-line check-send-result,multiple-sends
            IOFT(verse.memecoin).send{value: memecoinMessagingFee.nativeFee}(
                sendMemecoinParam, memecoinMessagingFee, msg.sender
            );
        }
    }

    // Shared via MemeverseLauncherLib.splitExecutorReward; the reader uses the same lib helper.
    function _splitExecutorReward(uint256 uAssetFee) internal view returns (uint256 govFee, uint256 executorReward) {
        return MemeverseLauncherLib.splitExecutorReward(uAssetFee, memeverseLauncherStorage.executorRewardRate);
    }

    // Shared via MemeverseLauncherLib.buildSendParamAndMessagingFee; the reader uses the same lib helper.
    function _buildSendParamAndMessagingFee(
        uint32 govEndpointId,
        uint256 amount,
        address token,
        address receiver,
        IMemeverseOFTEnum.TokenType tokenType,
        bytes memory yieldDispatcherOptions,
        address yieldDispatcher
    ) internal view returns (SendParam memory sendParam, MessagingFee memory messagingFee) {
        return MemeverseLauncherLib.buildSendParamAndMessagingFee(
                govEndpointId, amount, token, receiver, tokenType, yieldDispatcherOptions, yieldDispatcher
            );
    }

    function _captureLockedAuxiliaryFees(
        uint256 verseId,
        IMemeverseLauncher.Memeverse storage verse,
        address polSplitterAddress,
        address hook
    ) internal {
        address pt = IPOLSplitter(polSplitterAddress).getPT(verseId);
        (uint256 govUAssetFee, uint256 govPTFee, uint256 burnedPolFee) =
            _claimAndAccrueAuxiliaryFees(verseId, verse, pt, true, hook);
        if (burnedPolFee != 0) IPol(verse.pol).burn(address(this), burnedPolFee);

        IMemeverseLauncher.PendingAuxiliaryGovFeeState storage pendingGovFeeState =
            memeverseLauncherStorage.pendingAuxiliaryGovFeeStates[verseId];
        pendingGovFeeState.pendingUAssetFee += govUAssetFee;
        pendingGovFeeState.pendingPTFee += govPTFee;
    }

    function _claimAndAccrueAuxiliaryFees(
        uint256 verseId,
        IMemeverseLauncher.Memeverse storage verse,
        address pt,
        bool preserveNormalShare,
        address _hook
    ) internal returns (uint256 govUAssetFee, uint256 govPTFee, uint256 burnedPolFee) {
        (uint256 polUAssetPolFee, uint256 polUAssetUAssetFee) = _claimPairFees(verse.pol, verse.uAsset, _hook);
        burnedPolFee = polUAssetPolFee;

        uint256 totalAuxiliaryUAssetFee = polUAssetUAssetFee;
        uint256 totalPTFee;
        if (pt != address(0)) {
            (uint256 ptUAssetPTFee, uint256 ptUAssetUAssetFee) = _claimPairFees(pt, verse.uAsset, _hook);
            (uint256 ptPolPTFee, uint256 ptPolPolFee) = _claimPairFees(pt, verse.pol, _hook);
            totalAuxiliaryUAssetFee += ptUAssetUAssetFee;
            totalPTFee = ptUAssetPTFee + ptPolPTFee;
            burnedPolFee += ptPolPolFee;
        }

        (govUAssetFee, govPTFee) =
            _accrueAuxiliaryFeeShares(verseId, totalAuxiliaryUAssetFee, totalPTFee, preserveNormalShare);
    }

    function _accrueAuxiliaryFeeShares(
        uint256 verseId,
        uint256 totalUAssetFee,
        uint256 totalPTFee,
        bool preserveNormalShare
    ) internal returns (uint256 govUAssetFee, uint256 govPTFee) {
        (govUAssetFee, govPTFee) = _splitAuxiliaryGovFees(verseId, totalUAssetFee, totalPTFee, preserveNormalShare);
        if (!preserveNormalShare) return (govUAssetFee, govPTFee);

        IMemeverseLauncher.NormalFeeState storage feeState = memeverseLauncherStorage.normalFeeStates[verseId];
        feeState.accUAssetFee += totalUAssetFee - govUAssetFee;
        feeState.accPTFee += totalPTFee - govPTFee;
    }

    function _splitAuxiliaryGovFees(
        uint256 verseId,
        uint256 totalUAssetFee,
        uint256 totalPTFee,
        bool preserveNormalShare
    ) internal view returns (uint256 govUAssetFee, uint256 govPTFee) {
        if (!preserveNormalShare) return (totalUAssetFee, totalPTFee);
        uint256 normalFunds = memeverseLauncherStorage.totalNormalFunds[verseId];
        uint256 totalLeveragedDebt = IPOLend(memeverseLauncherStorage.polend).getTotalLeveragedDebt(verseId);
        uint256 totalFunds = MemeverseLauncherLib.checkedTotalGenesisFunds(normalFunds, totalLeveragedDebt);
        if (totalFunds == 0) return (totalUAssetFee, totalPTFee);

        govUAssetFee = FullMath.mulDiv(totalUAssetFee, totalLeveragedDebt, totalFunds);
        govPTFee = FullMath.mulDiv(totalPTFee, totalLeveragedDebt, totalFunds);
    }

    function _claimPairFees(address tokenA, address tokenB, address _hook)
        internal
        returns (uint256 tokenAFee, uint256 tokenBFee)
    {
        PoolKey memory key = MemeversePoolKeyLib.hookPoolKey(tokenA, tokenB, _hook);
        (uint256 fee0, uint256 fee1) = IMemeverseUniswapHook(_hook)
            .claimFeesCore(IMemeverseUniswapHook.ClaimFeesCoreParams({key: key, recipient: address(this)}));
        return _mapPairFees(tokenA, tokenB, fee0, fee1);
    }

    // Shared via MemeverseLauncherLib.mapPairFees; the reader uses the same lib helper.
    function _mapPairFees(address tokenA, address tokenB, uint256 fee0, uint256 fee1)
        internal
        pure
        returns (uint256 tokenAFee, uint256 tokenBFee)
    {
        return MemeverseLauncherLib.mapPairFees(tokenA, tokenB, fee0, fee1);
    }
}
