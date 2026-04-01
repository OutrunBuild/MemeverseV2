// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {MemeverseLauncher} from "../../src/verse/MemeverseLauncher.sol";
import {IMemeverseLauncher} from "../../src/verse/interfaces/IMemeverseLauncher.sol";

contract MockLaunchSettlementHookConfig {
    address internal boundLauncher;

    constructor(address boundLauncher_) {
        boundLauncher = boundLauncher_;
    }

    /// @notice Returns the configured launcher binding.
    /// @dev Mirrors the real hook accessor for launcher validation.
    /// @return launcher_ Configured launcher binding.
    function launcher() external view returns (address launcher_) {
        return boundLauncher;
    }

    /// @notice Updates the launcher binding used by the mock hook.
    /// @dev Allows tests to require explicit hook-to-launcher binding.
    /// @param boundLauncher_ New launcher stored by the mock.
    function setLauncher(address boundLauncher_) external {
        boundLauncher = boundLauncher_;
    }
}

contract MockLaunchSettlementRouterConfig {
    address internal hookAddress;

    constructor(address hookAddress_) {
        hookAddress = hookAddress_;
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

    function _setMemeverseUniswapHook(address hookAddress) internal returns (bool ok, bytes memory data) {
        return address(launcher).call(abi.encodeWithSignature("setMemeverseUniswapHook(address)", hookAddress));
    }

    function _readMemeverseUniswapHook() internal view returns (bool ok, address hookAddress) {
        (bool success, bytes memory data) =
            address(launcher).staticcall(abi.encodeWithSignature("memeverseUniswapHook()"));
        if (!success || data.length != 32) return (false, address(0));
        return (true, abi.decode(data, (address)));
    }

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

    /// @notice Test swap infra config requires a bound hook and a matching router->hook edge.
    /// @dev The launcher should reject either side of the double binding when the approved wiring is wrong.
    function testSetMemeverseSwapInfra_RequiresMatchingHookAndRouterBindings() external {
        MockLaunchSettlementHookConfig invalidLauncherHook = new MockLaunchSettlementHookConfig(OTHER);
        (bool invalidHookOk, bytes memory invalidHookData) = _setMemeverseUniswapHook(address(invalidLauncherHook));
        assertFalse(invalidHookOk, "hook with wrong launcher should fail");
        assertEq(bytes4(invalidHookData), IMemeverseLauncher.InvalidLaunchSettlementConfig.selector, "hook revert");

        MockLaunchSettlementHookConfig configuredHook = new MockLaunchSettlementHookConfig(address(launcher));
        (bool setHookOk, bytes memory setHookData) = _setMemeverseUniswapHook(address(configuredHook));
        assertTrue(setHookOk, string(setHookData));

        MockLaunchSettlementHookConfig mismatchedRouterHook = new MockLaunchSettlementHookConfig(address(launcher));
        MockLaunchSettlementRouterConfig mismatchedRouter =
            new MockLaunchSettlementRouterConfig(address(mismatchedRouterHook));

        vm.expectRevert(IMemeverseLauncher.InvalidLaunchSettlementConfig.selector);
        launcher.setMemeverseSwapRouter(address(mismatchedRouter));

        vm.expectRevert(IMemeverseLauncher.ZeroInput.selector);
        launcher.setMemeverseSwapRouter(address(0));

        MockLaunchSettlementRouterConfig settledRouter = new MockLaunchSettlementRouterConfig(address(configuredHook));
        launcher.setMemeverseSwapRouter(address(settledRouter));
        assertEq(launcher.memeverseSwapRouter(), address(settledRouter));

        (bool readHookOk, address storedHook) = _readMemeverseUniswapHook();
        assertTrue(readHookOk, "hook getter missing");
        assertEq(storedHook, address(configuredHook));
    }

    /// @notice Verifies the launcher hook binding is write-once while routers may still rebind to the same hook.
    /// @dev This prevents unlock protection from drifting to a different hook namespace after pools already exist.
    function testSetMemeverseSwapInfra_HookIsWriteOnceButRouterCanRebindToSameHook() external {
        MockLaunchSettlementHookConfig configuredHook = new MockLaunchSettlementHookConfig(address(launcher));
        (bool firstSetOk, bytes memory firstSetData) = _setMemeverseUniswapHook(address(configuredHook));
        assertTrue(firstSetOk, string(firstSetData));

        MockLaunchSettlementRouterConfig firstRouter = new MockLaunchSettlementRouterConfig(address(configuredHook));
        MockLaunchSettlementRouterConfig secondRouter = new MockLaunchSettlementRouterConfig(address(configuredHook));

        launcher.setMemeverseSwapRouter(address(firstRouter));
        launcher.setMemeverseSwapRouter(address(secondRouter));
        assertEq(launcher.memeverseSwapRouter(), address(secondRouter), "router should rebind");

        vm.expectRevert();
        launcher.setMemeverseUniswapHook(address(configuredHook));
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
