// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {IMemeverseLauncher} from "../../src/verse/interfaces/IMemeverseLauncher.sol";

contract MemeverseLauncherFourPoolPlanTest is Test {
    function testBootstrapPolPlan_StoresOnlyConsumedFields() external pure {
        IMemeverseLauncher.BootstrapPolPlan memory plan;
        plan.polForPolUAsset = 1;
        plan.normalPolToSplit = 2;
        plan.leveragedPolToSplit = 3;
        plan.polForPtPol = 4;

        assertEq(abi.encode(plan).length, 4 * 32, "unexpected field count");
    }
}
