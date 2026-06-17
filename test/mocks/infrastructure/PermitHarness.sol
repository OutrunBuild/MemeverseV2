// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {OutrunERC20PermitInit} from "../../../src/common/token/OutrunERC20PermitInit.sol";

contract PermitHarness is OutrunERC20PermitInit {
    bytes32 internal constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    /// @notice Initialize.
    /// @param name_ See implementation.
    /// @param symbol_ See implementation.
    function initialize(string memory name_, string memory symbol_) external initializer {
        __OutrunERC20_init(name_, symbol_);
        __OutrunERC20Permit_init(name_);
    }

    /// @notice Mint test.
    /// @param to See implementation.
    /// @param amount See implementation.
    function mintTest(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /// @notice Permit digest.
    /// @param owner See implementation.
    /// @param spender See implementation.
    /// @param value See implementation.
    /// @param deadline See implementation.
    /// @return See implementation.
    function permitDigest(address owner, address spender, uint256 value, uint256 deadline)
        external
        view
        returns (bytes32)
    {
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces(owner), deadline));
        return _hashTypedDataV4(structHash);
    }
}
