// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {OFTComposeMsgCodec} from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";

import {TokenHelper} from "../common/token/TokenHelper.sol";
import {IOFTCompose} from "../common/omnichain/oft/IOFTCompose.sol";
import {IMemecoinYieldVault} from "../yield/interfaces/IMemecoinYieldVault.sol";
import {IOmnichainMemecoinStaker} from "./interfaces/IOmnichainMemecoinStaker.sol";

/**
 * @title Omnichain Memecoin Staker
 * @dev The contract is designed to interact with LayerZero's Omnichain Fungible Token (OFT) Standard,
 *      accepts Memecoin and stakes to the yield vault.
 */
contract OmnichainMemecoinStaker is IOmnichainMemecoinStaker, TokenHelper {
    address public immutable localEndpoint;

    constructor(address _localEndpoint) {
        localEndpoint = _localEndpoint;
    }

    /// @notice Executes lz compose.
    /// @dev See the implementation for behavior details.
    /// @param memecoin The memecoin value.
    /// @param guid The guid value.
    /// @param message The message value.
    /// @param executor The executor value.
    /// @param extraData The extraData value.
    function lzCompose(
        address memecoin,
        bytes32 guid,
        bytes calldata message,
        address executor,
        bytes calldata extraData
    ) external payable override {
        executor;
        extraData;
        require(msg.sender == localEndpoint, PermissionDenied());
        require(!IOFTCompose(memecoin).getComposeTxExecutedStatus(guid), AlreadyExecuted());

        uint256 amount = OFTComposeMsgCodec.amountLD(message);
        (address receiver, address yieldVault) = abi.decode(OFTComposeMsgCodec.composeMsg(message), (address, address));
        if (yieldVault.code.length == 0) {
            _transferOut(memecoin, receiver, amount);
        } else {
            _safeApproveInf(memecoin, yieldVault);
            IMemecoinYieldVault(yieldVault).deposit(amount, receiver);
        }
        IOFTCompose(memecoin).notifyComposeExecuted(guid);

        emit OmnichainMemecoinStakingProcessed(guid, memecoin, yieldVault, receiver, amount);
    }
}
