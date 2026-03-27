// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {ILayerZeroComposer} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroComposer.sol";

import {IMemeverseOFTEnum} from "../../common/types/IMemeverseOFTEnum.sol";

interface IYieldDispatcher is IMemeverseOFTEnum, ILayerZeroComposer {
    event OFTProcessed(
        bytes32 indexed guid,
        address indexed token,
        TokenType indexed tokenType,
        address receiver,
        uint256 amount,
        bool isBurned
    );

    error AlreadyExecuted();

    error PermissionDenied();
}
