// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.30;

import {OutrunOwnableInit} from "../../common/access/OutrunOwnableInit.sol";
import {OutrunERC20Init} from "../../common/token/OutrunERC20Init.sol";

contract SplitterToken is OutrunERC20Init, OutrunOwnableInit {
    error PermissionDenied();

    address public splitter;

    modifier onlySplitter() {
        if (msg.sender != splitter) revert PermissionDenied();
        _;
    }

    function initialize(string calldata name_, string calldata symbol_, address splitter_) external initializer {
        __OutrunERC20_init(name_, symbol_);
        __OutrunOwnable_init(splitter_);
        splitter = splitter_;
    }

    function mint(address to, uint256 amount) external onlySplitter {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlySplitter {
        _burn(from, amount);
    }
}
