// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

import {OutrunOAppCoreInit} from "../../../src/common/omnichain/oapp/OutrunOAppCoreInit.sol";

contract OAppCoreHarness is OutrunOAppCoreInit {
    constructor(address endpoint_) OutrunOAppCoreInit(endpoint_) {}

    /// @notice Initialize.
    /// @param owner_ See implementation.
    /// @param delegate_ See implementation.
    function initialize(address owner_, address delegate_) external initializer {
        __OutrunOwnable_init(owner_);
        __OutrunOAppCore_init(delegate_);
    }

    /// @notice O app version.
    /// @return senderVersion See implementation.
    /// @return receiverVersion See implementation.
    function oAppVersion() public pure override returns (uint64 senderVersion, uint64 receiverVersion) {
        return (1, 1);
    }

    /// @notice Exposed get peer.
    /// @param eid See implementation.
    /// @return See implementation.
    function exposedGetPeer(uint32 eid) external view returns (bytes32) {
        return _getPeerOrRevert(eid);
    }
}
