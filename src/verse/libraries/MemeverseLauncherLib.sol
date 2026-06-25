// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {IOFT, SendParam, MessagingFee} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";

import {IMemeverseOFTEnum} from "../../common/types/IMemeverseOFTEnum.sol";
import {IMemeverseSwapRouter} from "../../swap/interfaces/IMemeverseSwapRouter.sol";
import {IMemeverseUniswapHook} from "../../swap/interfaces/IMemeverseUniswapHook.sol";
import {IMemeverseLauncher} from "../interfaces/IMemeverseLauncher.sol";

/// @title MemeverseLauncherLib
/// @notice Internal helpers shared between the MemeverseLauncher facade and its MemeverseBootstrap /
///         MemeverseFeeDistributor / MemeverseFeePreviewReader siblings: settlement-wiring validation,
///         genesis-funds arithmetic, and the pure fee-mapping / executor-reward split used by both the
///         distributor and the preview reader.
/// @dev Functions are `internal`, so they compile inline into each caller. Under both call paths
///      (facade setters and the sibling's `deployLiquidity`) the caller runs in the proxy's
///      delegatecall context, so `address(this)` resolves to the proxy and the wiring check stays
///      consistent. Keep this library to helpers genuinely used by BOTH contracts — do not let it
///      grow into a catch-all dumping ground.
library MemeverseLauncherLib {
    /// @dev Upper bound on combined genesis funds; guards the addition in `checkedTotalGenesisFunds`
    ///      and the remaining-cap projections in the facade.
    uint256 internal constant MAX_SUPPORTED_TOTAL_GENESIS_FUNDS = type(uint128).max;

    /// @dev Ratio basis (10000) used by `splitExecutorReward`. Single source of truth shared by the
    ///      distributor and preview reader so the two callers cannot drift.
    uint256 internal constant RATIO = 10000;

    /// @notice Reverts unless the swap-router, uniswap-hook, and launcher are mutually wired:
    ///         the router points at the hook, the hook is bound to this launcher, and the hook's
    ///         pool initializer is the router. Guards preorder settlement at both the config gate
    ///         and the bootstrap runtime gate.
    function validateSettlementWiring(address routerAddress, address hookAddress) internal view {
        require(
            routerAddress != address(0) && hookAddress != address(0),
            IMemeverseLauncher.InvalidPreorderSettlementConfig()
        );
        IMemeverseSwapRouter router = IMemeverseSwapRouter(routerAddress);
        IMemeverseUniswapHook hook = IMemeverseUniswapHook(hookAddress);
        require(
            address(router.hook()) == hookAddress && hook.launcher() == address(this)
                && hook.poolInitializer() == routerAddress,
            IMemeverseLauncher.InvalidPreorderSettlementConfig()
        );
    }

    /// @notice Returns `normalFunds + leveragedDebt`, reverting if the sum exceeds the supported cap.
    function checkedTotalGenesisFunds(uint256 normalFunds, uint256 leveragedDebt)
        internal
        pure
        returns (uint256 totalFunds)
    {
        totalFunds = normalFunds + leveragedDebt;
        if (totalFunds > MAX_SUPPORTED_TOTAL_GENESIS_FUNDS) {
            revert IMemeverseLauncher.TotalGenesisFundsTooHigh(totalFunds, MAX_SUPPORTED_TOTAL_GENESIS_FUNDS);
        }
    }

    /// @notice Order two collected pair-fee amounts so the returned tuple matches `(tokenA, tokenB)`
    ///         regardless of pool token0/token1 ordering.
    /// @dev Shared by `MemeverseFeeDistributor._mapPairFees` and `MemeverseFeePreviewReader._mapPairFees`
    ///      so the two callers cannot drift.
    /// @param tokenA First token in the caller-facing pair.
    /// @param tokenB Second token in the caller-facing pair.
    /// @param fee0 Fee amount collected for the pool's token0.
    /// @param fee1 Fee amount collected for the pool's token1.
    /// @return tokenAFee Fee amount attributed to `tokenA`.
    /// @return tokenBFee Fee amount attributed to `tokenB`.
    function mapPairFees(address tokenA, address tokenB, uint256 fee0, uint256 fee1)
        internal
        pure
        returns (uint256 tokenAFee, uint256 tokenBFee)
    {
        if (tokenA < tokenB) {
            return (fee0, fee1);
        }
        return (fee1, fee0);
    }

    /// @notice Split a main-pool uAsset fee into the executor reward and governor share using ratio basis `RATIO`.
    /// @dev Shared by `MemeverseFeeDistributor._splitExecutorReward` and
    ///      `MemeverseFeePreviewReader._splitExecutorReward`; the wrappers only differ in how they read
    ///      `executorRewardRate` (storage vs. proxy getter). Uses `FullMath.mulDiv` so the multiplication
    ///      cannot overflow before the divide.
    /// @param uAssetFee Total uAsset fee collected from the main pool.
    /// @param executorRewardRate Basis-points rate (denominator `RATIO`) of `uAssetFee` paid to the executor.
    /// @return govFee Remaining share routed to governance.
    /// @return executorReward Share paid out as the executor incentive.
    function splitExecutorReward(uint256 uAssetFee, uint256 executorRewardRate)
        internal
        pure
        returns (uint256 govFee, uint256 executorReward)
    {
        executorReward = FullMath.mulDiv(uAssetFee, executorRewardRate, RATIO);
        govFee = uAssetFee - executorReward;
    }

    /// @notice Build the LayerZero OFT `SendParam` for a fee-distribution send and quote its messaging fee.
    /// @dev Shared by `MemeverseFeeDistributor._buildSendParamAndMessagingFee` and
    ///      `MemeverseFeePreviewReader._buildSendParamAndMessagingFee` so the two callers cannot drift on the
    ///      SendParam structure (dstEid / `to` = yieldDispatcher / composeMsg / extraOptions). Both callers
    ///      already pass every input as a parameter, so the body is identical and inlines without storage reads.
    /// @param govEndpointId Destination LayerZero endpoint id.
    /// @param amount Token amount to bridge (`amountLD`).
    /// @param token OFT token being sent (used to quote).
    /// @param receiver Endpoint-side receiver encoded into `composeMsg`.
    /// @param tokenType Token-type tag encoded into `composeMsg`.
    /// @param yieldDispatcherOptions Executor gas options appended to the send.
    /// @param yieldDispatcher Address the OFT send is addressed to (`SendParam.to`).
    /// @return sendParam The constructed OFT send parameter.
    /// @return messagingFee The quoted native + lzToken messaging fee.
    function buildSendParamAndMessagingFee(
        uint32 govEndpointId,
        uint256 amount,
        address token,
        address receiver,
        IMemeverseOFTEnum.TokenType tokenType,
        bytes memory yieldDispatcherOptions,
        address yieldDispatcher
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
}
