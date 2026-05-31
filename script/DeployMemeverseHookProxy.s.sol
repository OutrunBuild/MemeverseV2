// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {BaseScript} from "./BaseScript.s.sol";
import {IOutrunDeployer} from "./IOutrunDeployer.sol";
import {MemeverseUniswapHook} from "../src/swap/MemeverseUniswapHook.sol";

/// @title DeployMemeverseHookProxy
/// @notice Deploys the production Memeverse Uniswap v4 hook implementation and ERC1967 proxy.
contract DeployMemeverseHookProxy is BaseScript {
    uint160 internal constant MEMEVERSE_HOOK_FLAGS = 0x28cc;
    uint160 internal constant UNISWAP_V4_HOOK_FLAG_MASK = 0x3fff;
    uint256 internal constant MAX_SALT_SEARCH = 1_000_000;

    error PoolManagerCodeNotReady(address poolManager);
    error ProxySaltNotFound(uint256 checkedSalts);
    error ProxyDeploymentMismatch(address expected, address actual);
    error HookFlagMismatch(address hook);
    error DeployerNamespaceMismatch(address expected, address provided);

    /// @notice Executes the deployment using environment-provided production addresses.
    /// @return implementation The deployed hook implementation address.
    /// @return proxy The deployed ERC1967 proxy hook address.
    function run() public broadcaster returns (address implementation, address proxy) {
        IOutrunDeployer outrunDeployer = IOutrunDeployer(vm.envAddress("OUTRUN_DEPLOYER"));
        IPoolManager poolManager = IPoolManager(vm.envAddress("POOL_MANAGER"));
        address hookOwner = vm.envAddress("HOOK_OWNER");
        address hookTreasury = vm.envAddress("HOOK_TREASURY");
        _requirePoolManagerCode(poolManager);

        implementation = address(new MemeverseUniswapHook(poolManager));
        proxy = _deployProxy(outrunDeployer, deployer, implementation, hookOwner, hookTreasury);
    }

    /// @notice Deploys the implementation and a mined ERC1967 proxy through OutrunDeployer.
    /// @param outrunDeployer CREATE3 deployer used for the proxy address.
    /// @param deployerNamespace Address that will be the effective msg.sender when
    ///   OutrunDeployer.deploy() is called. Must match msg.sender unless called inside
    ///   a Foundry broadcast that sets msg.sender to this address.
    /// @param poolManager Uniswap v4 pool manager stored in the hook implementation immutable state.
    /// @param hookOwner Owner used for proxy initialization.
    /// @param hookTreasury Treasury used for proxy initialization.
    /// @return implementation The deployed hook implementation address.
    /// @return proxy The deployed ERC1967 proxy hook address.
    function deployHookProxy(
        IOutrunDeployer outrunDeployer,
        address deployerNamespace,
        IPoolManager poolManager,
        address hookOwner,
        address hookTreasury
    ) public returns (address implementation, address proxy) {
        // OutrunDeployer.deploy() hashes msg.sender into the CREATE3 salt, so the
        // caller must match deployerNamespace or the predicted address will diverge.
        if (msg.sender != deployerNamespace) {
            revert DeployerNamespaceMismatch(msg.sender, deployerNamespace);
        }
        _requirePoolManagerCode(poolManager);

        implementation = address(new MemeverseUniswapHook(poolManager));
        proxy = _deployProxy(outrunDeployer, deployerNamespace, implementation, hookOwner, hookTreasury);
    }

    /// @notice Returns the expected Memeverse hook permission flags.
    /// @return flags The low-bit Uniswap v4 hook flag value required on the proxy address.
    function memeverseHookFlags() public pure returns (uint160 flags) {
        return MEMEVERSE_HOOK_FLAGS;
    }

    /// @notice Returns the Uniswap v4 hook flag mask.
    /// @return mask The low-bit mask applied to hook addresses.
    function uniswapV4HookFlagMask() public pure returns (uint160 mask) {
        return UNISWAP_V4_HOOK_FLAG_MASK;
    }

    /// @notice Builds ERC1967Proxy creation code for CREATE3 deployment.
    /// @param implementation Hook implementation address passed to the proxy constructor.
    /// @param initializeData Initializer calldata passed to the proxy constructor.
    /// @return creationCode Complete proxy creation code including constructor args.
    function proxyCreationCode(address implementation, bytes memory initializeData)
        public
        pure
        returns (bytes memory creationCode)
    {
        return abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(implementation, initializeData));
    }

    /// @notice Mines an OutrunDeployer salt whose proxy address has the required Uniswap v4 hook flags.
    /// @dev The proxy address, not the implementation address, is what Uniswap v4 checks for hook permissions.
    /// @param outrunDeployer CREATE3 deployer used for address prediction.
    /// @param deployerNamespace Address that will call `OutrunDeployer.deploy`.
    /// @return salt First salt found in the bounded deterministic search.
    /// @return proxy Predicted proxy address carrying the required hook flags.
    function mineProxySalt(IOutrunDeployer outrunDeployer, address deployerNamespace)
        public
        view
        returns (bytes32 salt, address proxy)
    {
        for (uint256 i; i < MAX_SALT_SEARCH; ++i) {
            salt = bytes32(i);
            proxy = outrunDeployer.getDeployed(deployerNamespace, salt);
            if ((uint160(proxy) & UNISWAP_V4_HOOK_FLAG_MASK) == MEMEVERSE_HOOK_FLAGS && proxy.code.length == 0) {
                return (salt, proxy);
            }
        }

        revert ProxySaltNotFound(MAX_SALT_SEARCH);
    }

    function _deployProxy(
        IOutrunDeployer outrunDeployer,
        address deployerNamespace,
        address implementation,
        address hookOwner,
        address hookTreasury
    ) internal returns (address proxy) {
        bytes memory initializeData = abi.encodeCall(MemeverseUniswapHook.initialize, (hookOwner, hookTreasury));
        bytes memory creationCode = proxyCreationCode(implementation, initializeData);
        (bytes32 salt, address expectedProxy) = mineProxySalt(outrunDeployer, deployerNamespace);

        proxy = outrunDeployer.deploy(salt, creationCode);
        if (proxy != expectedProxy) revert ProxyDeploymentMismatch(expectedProxy, proxy);
        if ((uint160(proxy) & UNISWAP_V4_HOOK_FLAG_MASK) != MEMEVERSE_HOOK_FLAGS) revert HookFlagMismatch(proxy);
    }

    function _requirePoolManagerCode(IPoolManager poolManager) internal view {
        address poolManagerAddress = address(poolManager);
        if (poolManagerAddress.code.length == 0) revert PoolManagerCodeNotReady(poolManagerAddress);
    }
}
