// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {MemeverseLauncher} from "../src/verse/MemeverseLauncher.sol";

contract MemeverseLauncherRouterConfigTest is Test {
    MemeverseLauncher internal launcher;

    function setUp() external {
        launcher = new MemeverseLauncher(
            address(this), address(0x1), address(0x2), address(0x3), address(0x4), address(0x5), 25, 115_000, 135_000
        );
    }

    function testSetMemeverseSwapRouterStoresAddress() external {
        address router = address(0xBEEF);

        launcher.setMemeverseSwapRouter(router);

        assertEq(launcher.memeverseSwapRouter(), router);
    }
}
