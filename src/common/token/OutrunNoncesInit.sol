// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

import {Initializable} from "../access/Initializable.sol";

/**
 * @dev Provides tracking nonces for addresses. Nonces will only increment.
 */
abstract contract OutrunNoncesInit is Initializable {
    /**
     * @dev The nonce used for an `account` is not the expected current nonce.
     */
    error InvalidAccountNonce(address account, uint256 currentNonce);

    /// @custom:storage-location erc7201:outrun.storage.Nonces
    struct NoncesStorage {
        mapping(address account => uint256) _nonces;
    }

    function _getNoncesStorage() private pure returns (NoncesStorage storage $) {
        assembly {
            // erc7201("outrun.storage.Nonces")
            mstore(0x00, "outrun.storage.Nonces")
            mstore(0x00, sub(keccak256(0x00, 21), 1))
            $.slot := and(keccak256(0x00, 0x20), not(0xff))
        }
    }

    function __OutrunNonces_init() internal onlyInitializing {}

    function __OutrunNonces_init_unchained() internal onlyInitializing {}

    /// @notice Reads the next nonce that `owner` can spend.
    /// @dev The nonce increases monotonically after each successful signed action.
    /// @param owner Account to query.
    /// @return nonce Current nonce value for `owner`.
    function nonces(address owner) public view virtual returns (uint256) {
        NoncesStorage storage $ = _getNoncesStorage();
        return $._nonces[owner];
    }

    /**
     * @dev Consumes a nonce.
     *
     * Returns the current value and increments nonce.
     */
    function _useNonce(address owner) internal virtual returns (uint256) {
        NoncesStorage storage $ = _getNoncesStorage();
        // For each account, the nonce has an initial value of 0, can only be incremented by one, and cannot be
        // decremented or reset. This guarantees that the nonce never overflows.
        unchecked {
            // It is important to do x++ and not ++x here.
            // solhint-disable-next-line gas-increment-by-one
            return $._nonces[owner]++;
        }
    }

    /**
     * @dev Same as {_useNonce} but checking that `nonce` is the next valid for `owner`.
     */
    function _useCheckedNonce(address owner, uint256 nonce) internal virtual {
        uint256 current = _useNonce(owner);
        if (nonce != current) {
            revert InvalidAccountNonce(owner, current);
        }
    }
}
