// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title OutrunOwnableUpgradeable
 * @notice Lightweight Ownable base for contracts that use OpenZeppelin upgradeable initialization.
 * @dev Uses the same ERC7201 namespace as the non-OZ Outrun ownable base so ownership lives at
 *      `outrun.storage.Ownable`.
 */
abstract contract OutrunOwnableUpgradeable is Initializable {
    /// @custom:storage-location erc7201:outrun.storage.Ownable
    struct OwnableStorage {
        address _owner;
    }

    // keccak256(abi.encode(uint256(keccak256("outrun.storage.Ownable")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant OWNABLE_STORAGE_LOCATION =
        0x7f241041d6960443a72c6e46e3b41069d0f1a8933ddb434b1da86a3f3cba9f00;

    function _getOwnableStorage() private pure returns (OwnableStorage storage $) {
        assembly {
            $.slot := OWNABLE_STORAGE_LOCATION
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

    /// @notice Initializes ownership for the proxy during the OZ initializer flow.
    /// @dev Must only be called while OpenZeppelin `Initializable` is in its initializing state.
    /// @param initialOwner Address that becomes the initial owner.
    function __OutrunOwnable_init(address initialOwner) internal onlyInitializing {
        require(initialOwner != address(0), OwnableInvalidOwner(address(0)));
        OwnableStorage storage $ = _getOwnableStorage();
        $._owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        require(owner() == msg.sender, OwnableUnauthorizedAccount(msg.sender));
    }

    /// @notice Reads the address that currently holds ownership.
    /// @return ownerAddress Current owner address.
    function owner() public view virtual returns (address) {
        OwnableStorage storage $ = _getOwnableStorage();
        return $._owner;
    }

    /// @notice Transfers ownership to `newOwner`.
    /// @dev Reverts when `newOwner` is the zero address.
    /// @param newOwner Address that will become the next owner.
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), OwnableInvalidOwner(address(0)));
        OwnableStorage storage $ = _getOwnableStorage();
        $._owner = newOwner;
        emit OwnershipTransferred(msg.sender, newOwner);
    }
}
