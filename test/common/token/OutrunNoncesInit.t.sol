// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import {OutrunNoncesInit} from "../../../src/common/token/OutrunNoncesInit.sol";
import {NoncesHarness} from "../../mocks/infrastructure/NoncesHarness.sol";

contract OutrunNoncesInitTest is Test {
    using Clones for address;

    address internal constant ALICE = address(0xA11CE);

    NoncesHarness internal implementation;
    NoncesHarness internal harness;

    /// @notice Set up.
    function setUp() external {
        implementation = new NoncesHarness();
        harness = NoncesHarness(address(implementation).clone());
        harness.initialize();
    }

    /// @notice Test use nonce returns current value and increments.
    function testUseNonceReturnsCurrentValueAndIncrements() external {
        assertEq(harness.nonces(ALICE), 0);
        assertEq(harness.useNonce(ALICE), 0);
        assertEq(harness.nonces(ALICE), 1);
        assertEq(harness.useNonce(ALICE), 1);
        assertEq(harness.nonces(ALICE), 2);
    }

    /// @notice Test use checked nonce rejects unexpected nonce.
    function testUseCheckedNonceRejectsUnexpectedNonce() external {
        harness.useCheckedNonce(ALICE, 0);
        assertEq(harness.nonces(ALICE), 1);

        vm.expectRevert(abi.encodeWithSelector(OutrunNoncesInit.InvalidAccountNonce.selector, ALICE, 1));
        harness.useCheckedNonce(ALICE, 0);
    }

    /// @notice Test nonces are isolated across different addresses.
    function testNonceIsolationAcrossAddresses() external {
        address bob = address(0xB0B);

        assertEq(harness.nonces(ALICE), 0);
        assertEq(harness.nonces(bob), 0);

        harness.useNonce(ALICE);
        harness.useNonce(ALICE);
        assertEq(harness.nonces(ALICE), 2);
        assertEq(harness.nonces(bob), 0);

        harness.useNonce(bob);
        assertEq(harness.nonces(ALICE), 2);
        assertEq(harness.nonces(bob), 1);
    }
}
