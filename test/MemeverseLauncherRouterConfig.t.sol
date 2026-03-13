// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {MemeverseLauncher} from "../src/verse/MemeverseLauncher.sol";
import {IMemeverseLauncher} from "../src/verse/interfaces/IMemeverseLauncher.sol";

contract MemeverseLauncherRouterConfigTest is Test {
    MemeverseLauncher internal launcher;

    /// @notice Deploys a fresh launcher instance for router configuration tests.
    /// @dev Reuses the production constructor path so config setters are exercised on a real deployment.
    function setUp() external {
        launcher = new MemeverseLauncher(
            address(this), address(0x1), address(0x2), address(0x3), address(0x4), address(0x5), 25, 115_000, 135_000
        );
    }

    /// @notice Verifies `setMemeverseSwapRouter` stores the new router address.
    /// @dev Confirms owner configuration updates the persisted router reference.
    function testSetMemeverseSwapRouterStoresAddress() external {
        address router = address(0xBEEF);

        launcher.setMemeverseSwapRouter(router);

        assertEq(launcher.memeverseSwapRouter(), router);
    }

    /// @notice Verifies oversized `fundBasedAmount` values are rejected at config time.
    /// @dev The launcher should reject unsupported price ratios before any pool bootstrap occurs.
    function testSetFundMetaDataRevertsWhenFundBasedAmountTooHigh() external {
        uint256 tooHigh = uint256(1 << 64);

        vm.expectRevert(
            abi.encodeWithSelector(IMemeverseLauncher.FundBasedAmountTooHigh.selector, tooHigh, uint256((1 << 64) - 1))
        );
        launcher.setFundMetaData(address(0xBEEF), 1 ether, tooHigh);
    }
}
