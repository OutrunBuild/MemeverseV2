// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

import {Test, StdInvariant, console2} from "forge-std/Test.sol";

/// @notice Probe beforeInvariant() timing. assert(invCalls >= 2):
///         - PASS => beforeInvariant fires once at END of campaign (invCalls==256).
///         - FAIL => beforeInvariant fires once at start or per-run (invCalls<2).
contract BeforeInvTimingProbe is StdInvariant, Test {
    uint256 public invCalls;

    function setUp() external {
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = this.doThing.selector;
        targetSelector(FuzzSelector({addr: address(this), selectors: sels}));
    }

    function doThing() external {}

    function invariant_Probe() external {
        invCalls++;
    }

    function beforeInvariant() external {
        console2.log("BEFORE_AT_INV_CALLS", invCalls);
        assert(invCalls >= 2);
    }
}
