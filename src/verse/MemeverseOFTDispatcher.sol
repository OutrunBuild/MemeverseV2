// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {OFTComposeMsgCodec} from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";

import {TokenHelper} from "../common/token/TokenHelper.sol";
import {IBurnable} from "../common/interfaces/IBurnable.sol";
import {IOFTCompose} from "../common/omnichain/oft/IOFTCompose.sol";
import {IMemecoinYieldVault} from "../yield/interfaces/IMemecoinYieldVault.sol";
import {IMemeverseOFTDispatcher} from "./interfaces/IMemeverseOFTDispatcher.sol";
import {IMemecoinDaoGovernor} from "../governance/interfaces/IMemecoinDaoGovernor.sol";

/**
 * @title Memeverse OFT Dispatcher
 * @dev The contract is designed to interact with LayerZero's Omnichain Fungible Token (OFT) Standard,
 *      accepts Memecoin Yield from other chains and then forwards it to the corresponding yield vault.
 */
contract MemeverseOFTDispatcher is IMemeverseOFTDispatcher, TokenHelper, Ownable {
    using Strings for string;

    address public immutable localEndpoint;
    address public immutable memeverseLauncher;

    constructor(address _owner, address _localEndpoint, address _memeverseLauncher) Ownable(_owner) {
        localEndpoint = _localEndpoint;
        memeverseLauncher = _memeverseLauncher;
    }

    /// @notice Processes an incoming OFT compose payload for protocol treasury routing.
    /// @dev Accepts compose callbacks either from the local endpoint or directly from the launcher when it uses the
    /// local same-chain fast path.
    /// @param token Bridged token being routed.
    /// @param guid LayerZero compose guid used for replay protection.
    /// @param message Encoded treasury-routing payload.
    /// @param executor Compose executor reported by LayerZero.
    /// @param extraData Extra compose metadata, currently ignored.
    function lzCompose(address token, bytes32 guid, bytes calldata message, address executor, bytes calldata extraData)
        external
        payable
        override
    {
        executor;
        extraData;
        require(msg.sender == localEndpoint || msg.sender == memeverseLauncher, PermissionDenied());
        if (msg.sender == localEndpoint) {
            require(!IOFTCompose(token).getComposeTxExecutedStatus(guid), AlreadyExecuted());
        }

        bool isBurned;
        uint256 amount;
        TokenType tokenType;
        address receiver;
        if (msg.sender == memeverseLauncher) {
            (receiver, tokenType, amount) = abi.decode(message, (address, TokenType, uint256));
        } else {
            amount = OFTComposeMsgCodec.amountLD(message);
            (receiver, tokenType) = abi.decode(OFTComposeMsgCodec.composeMsg(message), (address, TokenType));
            IOFTCompose(token).notifyComposeExecuted(guid);
        }

        if (tokenType == TokenType.MEMECOIN) {
            if (receiver.code.length == 0) {
                IBurnable(token).burn(amount);
                isBurned = true;
            } else {
                _safeApproveInf(token, receiver);
                IMemecoinYieldVault(receiver).accumulateYields(amount);
            }
        } else if (tokenType == TokenType.UPT) {
            if (receiver.code.length == 0) {
                IBurnable(token).burn(amount);
                isBurned = true;
            } else {
                _safeApproveInf(token, receiver);
                IMemecoinDaoGovernor(receiver).receiveTreasuryIncome(token, amount);
            }
        }

        emit OFTProcessed(guid, token, tokenType, receiver, amount, isBurned);
    }
}
