// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (access/Ownable.sol)
pragma solidity ^0.8.35;

import {Initializable} from "./Initializable.sol";

/**
 * @dev Outrun's minimal-proxy-friendly Ownable implementation, adapted from OpenZeppelin.
 */
abstract contract OutrunOwnableInit is Initializable {
    /// @custom:storage-location erc7201:outrun.storage.Ownable
    struct OwnableStorage {
        address _owner;
    }

    function _getOwnableStorage() private pure returns (OwnableStorage storage $) {
        assembly {
            // erc7201("outrun.storage.Ownable")
            mstore(0x00, "outrun.storage.Ownable")
            mstore(0x00, sub(keccak256(0x00, 22), 1))
            $.slot := and(keccak256(0x00, 0x20), not(0xff))
        }
    }

    /**
     * @dev The caller account is not authorized to perform an operation.
     */
    error OwnableUnauthorizedAccount(address account);

    /**
     * @dev The owner is not a valid owner account. (eg. `address(0)`)
     */
    error OwnableInvalidOwner(address owner);

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the address provided by the deployer as the initial owner.
     */
    function __OutrunOwnable_init(address initialOwner) internal onlyInitializing {
        __OutrunOwnable_init_unchained(initialOwner);
    }

    function __OutrunOwnable_init_unchained(address initialOwner) internal onlyInitializing {
        if (initialOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(initialOwner);
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /// @notice Reads the address that currently holds ownership.
    /// @dev Returns zero only after ownership has been renounced.
    /// @return ownerAddress Current owner address.
    function owner() public view virtual returns (address) {
        OwnableStorage storage $ = _getOwnableStorage();
        return $._owner;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        if (owner() != msg.sender) {
            revert OwnableUnauthorizedAccount(msg.sender);
        }
    }

    /// @notice Renounces ownership of the contract.
    /// @dev Sets owner to `address(0)`, disabling `onlyOwner` operations.
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /// @notice Transfers ownership to `newOwner`.
    /// @dev Reverts when `newOwner` is the zero address.
    /// @param newOwner Address that will become the next owner.
    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        OwnableStorage storage $ = _getOwnableStorage();
        address oldOwner = $._owner;
        $._owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}
