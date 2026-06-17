// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

import {OutrunERC20Init} from "../../../src/common/token/OutrunERC20Init.sol";

contract ERC20Harness is OutrunERC20Init {
    /// @notice Initialize.
    /// @param name_ See implementation.
    /// @param symbol_ See implementation.
    function initialize(string memory name_, string memory symbol_) external initializer {
        __OutrunERC20_init(name_, symbol_);
    }

    /// @notice Mint test.
    /// @param to See implementation.
    /// @param amount See implementation.
    function mintTest(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /// @notice Burn test.
    /// @param from See implementation.
    /// @param amount See implementation.
    function burnTest(address from, uint256 amount) external {
        _burn(from, amount);
    }
}
