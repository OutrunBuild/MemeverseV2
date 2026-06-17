// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";

import {TokenHelper} from "../../../src/common/token/TokenHelper.sol";
import {FalseApproveToken, RejectETHReceiver} from "../../mocks/common/CommonMocks.sol";
import {TokenHelperHarness} from "../../mocks/infrastructure/TokenHelperHarness.sol";

contract TokenHelperTest is Test {
    TokenHelperHarness internal harness;

    function setUp() external {
        harness = new TokenHelperHarness();
    }

    function testTransferInNativeRevertsWithNativeValueMismatch() external {
        vm.expectRevert(abi.encodeWithSelector(TokenHelper.NativeValueMismatch.selector, 1 ether, 0.5 ether));
        harness.transferInNative{value: 0.5 ether}(1 ether);
    }

    function testTransferOutNativeRevertsWithNativeTransferFailed() external {
        RejectETHReceiver receiver = new RejectETHReceiver();
        vm.deal(address(harness), 1 ether);

        vm.expectRevert(TokenHelper.NativeTransferFailed.selector);
        harness.transferOutNative(address(receiver), 1 ether);
    }

    function testSafeApproveRevertsWithSafeApproveFailed() external {
        FalseApproveToken token = new FalseApproveToken();

        vm.expectRevert(
            abi.encodeWithSelector(TokenHelper.SafeApproveFailed.selector, address(token), address(this), 123)
        );
        harness.safeApproveToken(address(token), address(this), 123);
    }
}
