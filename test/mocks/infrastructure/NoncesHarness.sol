// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

import {OutrunNoncesInit} from "../../../src/common/token/OutrunNoncesInit.sol";

contract NoncesHarness is OutrunNoncesInit {
    /// @notice Initialize.
    function initialize() external initializer {
        __OutrunNonces_init();
    }

    /// @notice Use nonce.
    /// @param owner See implementation.
    /// @return See implementation.
    function useNonce(address owner) external returns (uint256) {
        return _useNonce(owner);
    }

    /// @notice Use checked nonce.
    /// @param owner See implementation.
    /// @param nonce See implementation.
    function useCheckedNonce(address owner, uint256 nonce) external {
        _useCheckedNonce(owner, nonce);
    }
}
