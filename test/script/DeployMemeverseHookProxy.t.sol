// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {DeployMemeverseHookProxy} from "../../script/DeployMemeverseHookProxy.s.sol";
import {IOutrunDeployer} from "../../script/IOutrunDeployer.sol";
import {OutrunDeployer} from "../../script/deployment/OutrunDeployer.sol";
import {MemeverseUniswapHook} from "../../src/swap/MemeverseUniswapHook.sol";

contract DeployMemeverseHookProxyTest is Test {
    address internal constant POOL_MANAGER = address(0x1001);
    address internal constant HOOK_OWNER = address(0x1002);
    address internal constant HOOK_TREASURY = address(0x1003);
    address internal constant DEPLOYER_NAMESPACE = address(0x1004);

    OutrunDeployer internal outrunDeployer;
    DeployMemeverseHookProxy internal script;

    function setUp() external {
        outrunDeployer = new OutrunDeployer(address(this));
        script = new DeployMemeverseHookProxy();
    }

    function testMinesSaltForOutrunDeployerAddressWithExpectedHookFlags() external view {
        (bytes32 salt, address proxy) =
            script.mineProxySalt(IOutrunDeployer(address(outrunDeployer)), DEPLOYER_NAMESPACE);

        assertEq(uint160(proxy) & script.uniswapV4HookFlagMask(), script.memeverseHookFlags());
        assertEq(outrunDeployer.getDeployed(DEPLOYER_NAMESPACE, salt), proxy);
    }

    function testMineProxySaltSkipsOccupiedMatchingAddress() external {
        (bytes32 occupiedSalt, address occupiedProxy) =
            script.mineProxySalt(IOutrunDeployer(address(outrunDeployer)), DEPLOYER_NAMESPACE);
        vm.etch(occupiedProxy, hex"01");

        (bytes32 nextSalt, address nextProxy) =
            script.mineProxySalt(IOutrunDeployer(address(outrunDeployer)), DEPLOYER_NAMESPACE);

        assertTrue(nextSalt != occupiedSalt);
        assertTrue(nextProxy != occupiedProxy);
        assertEq(uint160(nextProxy) & script.uniswapV4HookFlagMask(), script.memeverseHookFlags());
    }

    function testSameSaltPredictsDeterministicAddress() external view {
        bytes32 salt = bytes32(uint256(123));
        address predicted = outrunDeployer.getDeployed(DEPLOYER_NAMESPACE, salt);

        assertEq(outrunDeployer.getDeployed(DEPLOYER_NAMESPACE, salt), predicted);
    }

    function testDifferentDeployerNamespacePredictsDifferentAddress() external view {
        bytes32 salt = bytes32(uint256(123));

        assertTrue(
            outrunDeployer.getDeployed(DEPLOYER_NAMESPACE, salt) != outrunDeployer.getDeployed(address(0x9999), salt)
        );
    }

    function testDeployProxyInitializesHookAtMinedAddress() external {
        vm.etch(POOL_MANAGER, hex"01");
        outrunDeployer.transferOwnership(address(script));

        (bytes32 salt, address predictedProxy) =
            script.mineProxySalt(IOutrunDeployer(address(outrunDeployer)), address(script));
        vm.prank(address(script));
        (address implementation, address proxy) = script.deployHookProxy(
            IOutrunDeployer(address(outrunDeployer)),
            address(script),
            IPoolManager(POOL_MANAGER),
            HOOK_OWNER,
            HOOK_TREASURY
        );
        MemeverseUniswapHook hook = MemeverseUniswapHook(proxy);

        assertEq(outrunDeployer.getDeployed(address(script), salt), predictedProxy);
        assertEq(proxy, predictedProxy);
        assertGt(implementation.code.length, 0);
        assertGt(proxy.code.length, 0);
        assertEq(uint160(proxy) & script.uniswapV4HookFlagMask(), script.memeverseHookFlags());
        assertEq(hook.owner(), HOOK_OWNER);
        assertEq(hook.treasury(), HOOK_TREASURY);
        assertEq(address(hook.poolManager()), POOL_MANAGER);
        assertEq(address(uint160(uint256(vm.load(proxy, ERC1967Utils.IMPLEMENTATION_SLOT)))), implementation);
    }

    function testDeployProxyRejectsPoolManagerWithoutCode() external {
        vm.prank(address(script));
        vm.expectRevert(abi.encodeWithSelector(DeployMemeverseHookProxy.PoolManagerCodeNotReady.selector, POOL_MANAGER));
        script.deployHookProxy(
            IOutrunDeployer(address(outrunDeployer)),
            address(script),
            IPoolManager(POOL_MANAGER),
            HOOK_OWNER,
            HOOK_TREASURY
        );
    }

    function testDeployProxyRejectsMismatchedDeployerNamespace() external {
        vm.etch(POOL_MANAGER, hex"01");
        address wrongNamespace = address(0xBEEF);
        vm.expectRevert(
            abi.encodeWithSelector(
                DeployMemeverseHookProxy.DeployerNamespaceMismatch.selector, address(this), wrongNamespace
            )
        );
        script.deployHookProxy(
            IOutrunDeployer(address(outrunDeployer)),
            wrongNamespace,
            IPoolManager(POOL_MANAGER),
            HOOK_OWNER,
            HOOK_TREASURY
        );
    }
}
