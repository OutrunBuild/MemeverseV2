// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {MemeverseLauncher} from "../../src/verse/MemeverseLauncher.sol";
import {IMemeverseLauncher} from "../../src/verse/interfaces/IMemeverseLauncher.sol";

contract MemeverseLauncherConfigTest is Test {
    address internal constant OTHER = address(0xBEEF);

    MemeverseLauncher internal launcher;

    /// @notice Set up.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function setUp() external {
        launcher = new MemeverseLauncher(
            address(this), address(0x1), address(0x2), address(0x3), address(0x4), address(0x5), 25, 115_000, 135_000
        );
    }

    /// @notice Test pause and unpause are owner only.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function testPauseAndUnpauseAreOwnerOnly() external {
        vm.prank(OTHER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, OTHER));
        launcher.pause();

        launcher.pause();
        assertTrue(launcher.paused());

        vm.prank(OTHER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, OTHER));
        launcher.unpause();

        launcher.unpause();
        assertFalse(launcher.paused());
    }

    /// @notice Test set memeverse swap router stores address and rejects zero.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function testSetMemeverseSwapRouterStoresAddressAndRejectsZero() external {
        launcher.setMemeverseSwapRouter(address(0xBEEF));
        assertEq(launcher.memeverseSwapRouter(), address(0xBEEF));

        vm.expectRevert(IMemeverseLauncher.ZeroInput.selector);
        launcher.setMemeverseSwapRouter(address(0));
    }

    /// @notice Test set lz endpoint registry stores address and rejects zero.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function testSetLzEndpointRegistryStoresAddressAndRejectsZero() external {
        launcher.setLzEndpointRegistry(address(0xBEEF));
        assertEq(launcher.lzEndpointRegistry(), address(0xBEEF));

        vm.expectRevert(IMemeverseLauncher.ZeroInput.selector);
        launcher.setLzEndpointRegistry(address(0));
    }

    /// @notice Test set memeverse registrar stores address and rejects zero.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function testSetMemeverseRegistrarStoresAddressAndRejectsZero() external {
        launcher.setMemeverseRegistrar(address(0xBEEF));
        assertEq(launcher.memeverseRegistrar(), address(0xBEEF));

        vm.expectRevert(IMemeverseLauncher.ZeroInput.selector);
        launcher.setMemeverseRegistrar(address(0));
    }

    /// @notice Test set memeverse proxy deployer stores address and rejects zero.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function testSetMemeverseProxyDeployerStoresAddressAndRejectsZero() external {
        launcher.setMemeverseProxyDeployer(address(0xBEEF));
        assertEq(launcher.memeverseProxyDeployer(), address(0xBEEF));

        vm.expectRevert(IMemeverseLauncher.ZeroInput.selector);
        launcher.setMemeverseProxyDeployer(address(0));
    }

    /// @notice Test set oftdispatcher stores address and rejects zero.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function testSetOFTDispatcherStoresAddressAndRejectsZero() external {
        launcher.setOFTDispatcher(address(0xBEEF));
        assertEq(launcher.oftDispatcher(), address(0xBEEF));

        vm.expectRevert(IMemeverseLauncher.ZeroInput.selector);
        launcher.setOFTDispatcher(address(0));
    }

    /// @notice Test set fund meta data stores values and guards inputs.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function testSetFundMetaDataStoresValuesAndGuardsInputs() external {
        launcher.setFundMetaData(address(0xBEEF), 1 ether, 2 ether);
        (uint256 minTotalFund, uint256 fundBasedAmount) = launcher.fundMetaDatas(address(0xBEEF));
        assertEq(minTotalFund, 1 ether);
        assertEq(fundBasedAmount, 2 ether);

        vm.expectRevert(IMemeverseLauncher.ZeroInput.selector);
        launcher.setFundMetaData(address(0xBEEF), 0, 1);

        uint256 tooHigh = uint256(1 << 64);
        vm.expectRevert(
            abi.encodeWithSelector(IMemeverseLauncher.FundBasedAmountTooHigh.selector, tooHigh, uint256((1 << 64) - 1))
        );
        launcher.setFundMetaData(address(0xBEEF), 1 ether, tooHigh);
    }

    /// @notice Test set executor reward rate stores value and rejects overflow.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function testSetExecutorRewardRateStoresValueAndRejectsOverflow() external {
        launcher.setExecutorRewardRate(9999);
        assertEq(launcher.executorRewardRate(), 9999);

        vm.expectRevert(IMemeverseLauncher.FeeRateOverFlow.selector);
        launcher.setExecutorRewardRate(10_000);
    }

    /// @notice Test set gas limits stores values and rejects zero.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function testSetGasLimitsStoresValuesAndRejectsZero() external {
        launcher.setGasLimits(1, 2);
        assertEq(launcher.oftReceiveGasLimit(), 1);
        assertEq(launcher.oftDispatcherGasLimit(), 2);

        vm.expectRevert(IMemeverseLauncher.ZeroInput.selector);
        launcher.setGasLimits(0, 1);
    }

    /// @notice Test remove gas dust transfers balance to receiver.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function testRemoveGasDustTransfersBalanceToReceiver() external {
        vm.deal(address(launcher), 1 ether);
        uint256 before = address(this).balance;

        launcher.removeGasDust(address(this));

        assertEq(address(this).balance, before + 1 ether);
        assertEq(address(launcher).balance, 0);
    }

    receive() external payable {}
}
