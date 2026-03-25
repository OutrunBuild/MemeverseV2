// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {MemeverseLauncher} from "../../src/verse/MemeverseLauncher.sol";
import {IMemeverseLauncher} from "../../src/verse/interfaces/IMemeverseLauncher.sol";

contract MockLaunchSettlementHookConfig {
    address internal settlementCaller;

    constructor(address settlementCaller_) {
        settlementCaller = settlementCaller_;
    }

    /// @notice Returns the configured settlement caller.
    /// @dev Mirrors the real hook accessor for config validation.
    /// @return caller Configured settlement caller.
    function launchSettlementCaller() external view returns (address) {
        return settlementCaller;
    }

    /// @notice Updates the settlement caller used by the mock hook.
    /// @dev Allows tests to switch callers when validating router config.
    /// @param settlementCaller_ New settlement caller stored by the mock.
    function setLaunchSettlementCaller(address settlementCaller_) external {
        settlementCaller = settlementCaller_;
    }
}

contract MockLaunchSettlementRouterConfig {
    address internal settlementOperator;
    address internal hookAddress;

    constructor(address settlementOperator_, address hookAddress_) {
        settlementOperator = settlementOperator_;
        hookAddress = hookAddress_;
    }

    /// @notice Returns the configured settlement operator.
    /// @dev Matches the router accessor used in config validation tests.
    /// @return operator Configured settlement operator.
    function launchSettlementOperator() external view returns (address) {
        return settlementOperator;
    }

    /// @notice Returns the configured hook address.
    /// @dev Lets tests simulate the hook pointer the router expects.
    /// @return hookAddress_ Configured hook address.
    function hook() external view returns (address) {
        return hookAddress;
    }
}

contract MemeverseLauncherConfigTest is Test {
    address internal constant OTHER = address(0xBEEF);

    MemeverseLauncher internal launcher;

    /// @notice Set up.
    /// @dev Deploys the launcher with dummy dependencies for the configuration tests.
    function setUp() external {
        launcher = new MemeverseLauncher(
            address(this),
            address(0x1),
            address(0x2),
            address(0x3),
            address(0x4),
            address(0x5),
            25,
            115_000,
            135_000,
            2_500,
            7 days
        );
    }

    /// @notice Test constructor stores preorder config.
    /// @dev Ensures the given cap ratio and vesting duration survive in storage.
    function testConstructorStoresPreorderConfig() external view {
        assertEq(launcher.preorderCapRatio(), 2_500);
        assertEq(launcher.preorderVestingDuration(), 7 days);
    }

    /// @notice Test pause and unpause are owner only.
    /// @dev Verifies only the owner can toggle the paused state.
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
    /// @dev Confirms the setter validates both the operator and hook before storing.
    function testSetMemeverseSwapRouterStoresAddressAndRejectsZero() external {
        MockLaunchSettlementHookConfig hook = new MockLaunchSettlementHookConfig(address(0xCAFE));
        MockLaunchSettlementRouterConfig invalidOperatorRouter =
            new MockLaunchSettlementRouterConfig(OTHER, address(hook));
        MockLaunchSettlementRouterConfig invalidCallerRouter =
            new MockLaunchSettlementRouterConfig(address(launcher), address(hook));

        vm.expectRevert(IMemeverseLauncher.InvalidLaunchSettlementConfig.selector);
        launcher.setMemeverseSwapRouter(address(invalidOperatorRouter));

        vm.expectRevert(IMemeverseLauncher.InvalidLaunchSettlementConfig.selector);
        launcher.setMemeverseSwapRouter(address(invalidCallerRouter));

        vm.expectRevert(IMemeverseLauncher.ZeroInput.selector);
        launcher.setMemeverseSwapRouter(address(0));

        MockLaunchSettlementHookConfig settledHook = new MockLaunchSettlementHookConfig(address(0xD00D));
        MockLaunchSettlementRouterConfig settledRouter =
            new MockLaunchSettlementRouterConfig(address(launcher), address(settledHook));
        settledHook.setLaunchSettlementCaller(address(settledRouter));
        launcher.setMemeverseSwapRouter(address(settledRouter));
        assertEq(launcher.memeverseSwapRouter(), address(settledRouter));
    }

    /// @notice Test set lz endpoint registry stores address and rejects zero.
    /// @dev Asserts the registry setter complains about zero addresses.
    function testSetLzEndpointRegistryStoresAddressAndRejectsZero() external {
        launcher.setLzEndpointRegistry(address(0xBEEF));
        assertEq(launcher.lzEndpointRegistry(), address(0xBEEF));

        vm.expectRevert(IMemeverseLauncher.ZeroInput.selector);
        launcher.setLzEndpointRegistry(address(0));
    }

    /// @notice Test set memeverse registrar stores address and rejects zero.
    /// @dev Ensures the registrar setter rejects zero and persists valid values.
    function testSetMemeverseRegistrarStoresAddressAndRejectsZero() external {
        launcher.setMemeverseRegistrar(address(0xBEEF));
        assertEq(launcher.memeverseRegistrar(), address(0xBEEF));

        vm.expectRevert(IMemeverseLauncher.ZeroInput.selector);
        launcher.setMemeverseRegistrar(address(0));
    }

    /// @notice Test set memeverse proxy deployer stores address and rejects zero.
    /// @dev Checks the proxy deployer setter enforces non-zero input.
    function testSetMemeverseProxyDeployerStoresAddressAndRejectsZero() external {
        launcher.setMemeverseProxyDeployer(address(0xBEEF));
        assertEq(launcher.memeverseProxyDeployer(), address(0xBEEF));

        vm.expectRevert(IMemeverseLauncher.ZeroInput.selector);
        launcher.setMemeverseProxyDeployer(address(0));
    }

    /// @notice Test set oftdispatcher stores address and rejects zero.
    /// @dev Guards the OFT dispatcher setter against zero inputs.
    function testSetYieldDispatcherStoresAddressAndRejectsZero() external {
        launcher.setYieldDispatcher(address(0xBEEF));
        assertEq(launcher.yieldDispatcher(), address(0xBEEF));

        vm.expectRevert(IMemeverseLauncher.ZeroInput.selector);
        launcher.setYieldDispatcher(address(0));
    }

    /// @notice Test set fund meta data stores values and guards inputs.
    /// @dev Verifies the metadata setter stores limits and rejects invalid caps.
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
    /// @dev Asserts the fee rate setter guards against overflow values.
    function testSetExecutorRewardRateStoresValueAndRejectsOverflow() external {
        launcher.setExecutorRewardRate(9999);
        assertEq(launcher.executorRewardRate(), 9999);

        vm.expectRevert(IMemeverseLauncher.FeeRateOverFlow.selector);
        launcher.setExecutorRewardRate(10_000);
    }

    /// @notice Test set preorder config stores values and rejects zero.
    /// @dev Confirms the preorder setter enforces non-zero caps and valid ranges.
    function testSetPreorderConfigStoresValuesAndRejectsZero() external {
        launcher.setPreorderConfig(2_000, 14 days);
        assertEq(launcher.preorderCapRatio(), 2_000);
        assertEq(launcher.preorderVestingDuration(), 14 days);

        vm.expectRevert(IMemeverseLauncher.ZeroInput.selector);
        launcher.setPreorderConfig(0, 14 days);

        vm.expectRevert(IMemeverseLauncher.ZeroInput.selector);
        launcher.setPreorderConfig(2_000, 0);

        vm.expectRevert(IMemeverseLauncher.FeeRateOverFlow.selector);
        launcher.setPreorderConfig(10_001, 14 days);
    }

    /// @notice Test set gas limits stores values and rejects zero.
    /// @dev Makes sure each gas-limit setter requires a non-zero throttle.
    function testSetGasLimitsStoresValuesAndRejectsZero() external {
        launcher.setGasLimits(1, 2);
        assertEq(launcher.oftReceiveGasLimit(), 1);
        assertEq(launcher.yieldDispatcherGasLimit(), 2);

        vm.expectRevert(IMemeverseLauncher.ZeroInput.selector);
        launcher.setGasLimits(0, 1);
    }

    /// @notice Test remove gas dust transfers balance to receiver.
    /// @dev Verifies the owner-only dust sweep actually sends the native balance.
    function testRemoveGasDustTransfersBalanceToReceiver() external {
        vm.deal(address(launcher), 1 ether);
        uint256 before = address(this).balance;

        launcher.removeGasDust(address(this));

        assertEq(address(this).balance, before + 1 ether);
        assertEq(address(launcher).balance, 0);
    }

    /// @notice Accepts native value when config tests inadvertently send ETH.
    /// @dev Provides a payable fallback so the test contract can hold refunds.
    receive() external payable {}
}
