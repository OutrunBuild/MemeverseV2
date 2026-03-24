// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import {OutrunNoncesInit} from "../../../src/common/token/OutrunNoncesInit.sol";

contract NoncesHarness is OutrunNoncesInit {
    /// @notice Initialize.
    function initialize() external initializer {
        __OutrunNonces_init();
    }

    /// @notice Use nonce.
    /// @param owner See implementation.
    /// @return See implementation.
    function useNonce(address owner) external returns (uint256) {
        return _useNonce(owner);
    }

    /// @notice Use checked nonce.
    /// @param owner See implementation.
    /// @param nonce See implementation.
    function useCheckedNonce(address owner, uint256 nonce) external {
        _useCheckedNonce(owner, nonce);
    }
}

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
}
