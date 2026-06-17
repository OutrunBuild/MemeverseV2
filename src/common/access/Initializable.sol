// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

/**
 * @dev This contract is just for minimal proxy
 */
abstract contract Initializable {
    error NotInitializing();
    error AlreadyInitialized();

    struct InitializableStorage {
        bool initialized;
        bool initializing;
    }

    function _getInitializableStorage() private pure returns (InitializableStorage storage $) {
        assembly {
            // erc7201("outrun.storage.Initializable")
            mstore(0x00, "outrun.storage.Initializable")
            mstore(0x00, sub(keccak256(0x00, 28), 1))
            $.slot := and(keccak256(0x00, 0x20), not(0xff))
        }
    }

    // Lock initialization in logic contract
    constructor() {
        _getInitializableStorage().initialized = true;
    }

    modifier initializer() {
        InitializableStorage storage $ = _getInitializableStorage();
        if ($.initialized) {
            revert AlreadyInitialized();
        }

        $.initialized = true;
        $.initializing = true;
        _;
        $.initializing = false;
    }

    modifier onlyInitializing() {
        _checkInitializing();
        _;
    }

    function _checkInitializing() internal view {
        if (!_getInitializableStorage().initializing) {
            revert NotInitializing();
        }
    }
}
