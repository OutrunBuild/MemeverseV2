// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {OutrunOFTInit} from "../../../src/common/omnichain/oft/OutrunOFTInit.sol";

contract OFTHarness is OutrunOFTInit {
    constructor(address endpoint_) OutrunOFTInit(endpoint_) {}

    /// @notice Initialize.
    /// @param owner_ See implementation.
    /// @param name_ See implementation.
    /// @param symbol_ See implementation.
    /// @param delegate_ See implementation.
    function initialize(address owner_, string memory name_, string memory symbol_, address delegate_)
        external
        initializer
    {
        __OutrunOFT_init(name_, symbol_, delegate_);
        __OutrunOwnable_init(owner_);
    }

    /// @notice Mint test.
    /// @param to See implementation.
    /// @param amount See implementation.
    function mintTest(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /// @notice Seed compose.
    /// @param guid See implementation.
    /// @param composer See implementation.
    /// @param ubo See implementation.
    /// @param amount See implementation.
    /// @param executed See implementation.
    function seedCompose(bytes32 guid, address composer, address ubo, uint256 amount, bool executed) external {
        ComposeTxStatus storage txStatus = _getOFTCoreStorage().composeTxs[guid];
        txStatus.composer = composer;
        txStatus.UBO = ubo;
        txStatus.amount = amount;
        txStatus.isExecuted = executed;
    }
}
