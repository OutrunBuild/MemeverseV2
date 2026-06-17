// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {
    MessagingFee,
    MessagingReceipt
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

import {OutrunOAppCoreInit} from "../../../src/common/omnichain/oapp/OutrunOAppCoreInit.sol";
import {OutrunOAppSenderInit} from "../../../src/common/omnichain/oapp/OutrunOAppSenderInit.sol";

contract OAppSenderHarness is OutrunOAppSenderInit {
    constructor(address endpoint_) OutrunOAppCoreInit(endpoint_) {}

    /// @notice Initialize.
    /// @param owner_ See implementation.
    /// @param delegate_ See implementation.
    function initialize(address owner_, address delegate_) external initializer {
        __OutrunOwnable_init(owner_);
        __OutrunOAppSender_init(delegate_);
    }

    /// @notice Quote external.
    /// @param dstEid See implementation.
    /// @param message See implementation.
    /// @param options See implementation.
    /// @param payInLzToken See implementation.
    /// @return See implementation.
    function quoteExternal(uint32 dstEid, bytes memory message, bytes memory options, bool payInLzToken)
        external
        view
        returns (MessagingFee memory)
    {
        return _quote(dstEid, message, options, payInLzToken);
    }

    /// @notice Send external.
    /// @param dstEid See implementation.
    /// @param message See implementation.
    /// @param options See implementation.
    /// @param fee See implementation.
    /// @param refundAddress See implementation.
    /// @return See implementation.
    function sendExternal(
        uint32 dstEid,
        bytes memory message,
        bytes memory options,
        MessagingFee memory fee,
        address refundAddress
    ) external payable returns (MessagingReceipt memory) {
        return _lzSend(dstEid, message, options, fee, refundAddress);
    }
}
