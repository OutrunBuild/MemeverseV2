// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

import {Origin} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppReceiver.sol";

import {OutrunOAppCoreInit} from "../../../src/common/omnichain/oapp/OutrunOAppCoreInit.sol";
import {OutrunOAppReceiverInit} from "../../../src/common/omnichain/oapp/OutrunOAppReceiverInit.sol";

contract OAppReceiverHarness is OutrunOAppReceiverInit {
    uint32 public lastSrcEid;
    bytes32 public lastSender;
    bytes32 public lastGuid;
    bytes public lastMessage;
    address public lastExecutor;

    constructor(address endpoint_) OutrunOAppCoreInit(endpoint_) {}

    /// @notice Initialize.
    /// @param owner_ See implementation.
    /// @param delegate_ See implementation.
    function initialize(address owner_, address delegate_) external initializer {
        __OutrunOwnable_init(owner_);
        __OutrunOAppReceiver_init(delegate_);
    }

    function _lzReceive(Origin calldata origin, bytes32 guid, bytes calldata message, address executor, bytes calldata)
        internal
        override
    {
        lastSrcEid = origin.srcEid;
        lastSender = origin.sender;
        lastGuid = guid;
        lastMessage = message;
        lastExecutor = executor;
    }
}
