// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

import {TokenHelper} from "../../../src/common/token/TokenHelper.sol";

contract TokenHelperHarness is TokenHelper {
    function transferInNative(uint256 amount) external payable {
        _transferIn(NATIVE, msg.sender, amount);
    }

    function transferOutNative(address to, uint256 amount) external payable {
        _transferOut(NATIVE, to, amount);
    }

    function safeApproveToken(address token, address spender, uint256 value) external {
        _safeApprove(token, spender, value);
    }

    receive() external payable {}
}
