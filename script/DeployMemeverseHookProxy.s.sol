// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Bytes32AddressLib} from "solmate/utils/Bytes32AddressLib.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {BaseScript} from "./BaseScript.s.sol";
import {IOutrunDeployer} from "./IOutrunDeployer.sol";
import {MemeverseDynamicFeeEngine} from "../src/swap/MemeverseDynamicFeeEngine.sol";
import {MemeverseUniswapHook} from "../src/swap/MemeverseUniswapHook.sol";
import {IMemeverseDynamicFeeEngine} from "../src/swap/interfaces/IMemeverseDynamicFeeEngine.sol";

/// @title DeployMemeverseHookProxy
/// @notice Deploys the production Memeverse Uniswap v4 hook implementation and ERC1967 proxy.
contract DeployMemeverseHookProxy is BaseScript {
    using Bytes32AddressLib for bytes32;

    uint160 internal constant MEMEVERSE_HOOK_FLAGS = 0x28cc;
    uint160 internal constant UNISWAP_V4_HOOK_FLAG_MASK = 0x3fff;
    uint256 internal constant MAX_SALT_SEARCH = 1_000_000;
    bytes32 internal constant CREATE3_PROXY_BYTECODE_HASH = keccak256(hex"67363d3d37363d34f03d5260086018f3");
    bytes internal constant ENGINE_IMPL_SALT_SEED =
        hex"4d656d65766572736544796e616d6963466565456e67696e65496d706c656d656e746174696f6e";
    bytes internal constant HOOK_IMPL_SALT_SEED =
        hex"4d656d657665727365556e6973776170486f6f6b496d706c656d656e746174696f6e";

    error PoolManagerCodeNotReady(address poolManager);
    error ProxySaltNotFound(uint256 checkedSalts);
    error ProxyDeploymentMismatch(address expected, address actual);
    error HookFlagMismatch(address hook);
    error DeployerNamespaceMismatch(address expected, address provided);
    error Create3SaltConsumed(bytes32 salt, address create3Proxy);
    error EngineImplementationCreate3SaltConsumed(bytes32 salt, address create3Proxy);
    error EngineProxyCreate3SaltConsumed(bytes32 salt, address create3Proxy);
    error HookImplementationCreate3SaltConsumed(bytes32 salt, address create3Proxy);
    error ExistingIntermediateDeploymentNotReusable(address deployed);
    error ExistingHookOwnerMismatch(address hook, address expectedOwner, address actualOwner);
    error ExistingHookTreasuryMismatch(address hook, address expectedTreasury, address actualTreasury);
    error ExistingHookPoolManagerMismatch(address hook, address expectedPoolManager, address actualPoolManager);
    error ExistingHookImplementationMismatch(
        address hook, address expectedImplementation, address actualImplementation
    );
    error ExistingHookEngineMismatch(address hook, address expectedEngine, address actualEngine);
    error ExistingEngineAuthorizedHookMismatch(address engine, address expectedHook, address actualHook);
    error ExistingEngineOwnerMismatch(address engine, address expectedOwner, address actualOwner);
    error ExistingEnginePoolManagerMismatch(address engine, address expectedPoolManager, address actualPoolManager);
    error ExistingHookImplementationCodehashMismatch(
        address implementation, bytes32 expectedCodehash, bytes32 currentCodehash
    );
    error ExistingEngineImplementationCodehashMismatch(
        address implementation, bytes32 expectedCodehash, bytes32 currentCodehash
    );
    error ExistingHookProxyCodehashMismatch(address proxy, bytes32 expectedCodehash, bytes32 currentCodehash);
    error ExistingEngineProxyCodehashMismatch(address engine, bytes32 expectedCodehash, bytes32 currentCodehash);
    error ExpectedHookImplementationCodehashNotSet();
    error ExpectedEngineImplementationCodehashNotSet();
    error ZeroAddressNotAllowed();

    /// @notice Complete deployment artifacts for the Memeverse hook + engine split.
    struct DeploymentResult {
        address engineImplementation;
        address engineProxy;
        address hookImplementation;
        address hookProxy;
    }

    /// @notice Executes the deployment using environment-provided production addresses.
    /// @dev All four contracts (engine impl, engine proxy, hook impl, hook proxy) are deployed
    ///      via OutrunDeployer (CREATE3) with named salts. Addresses are deterministic per
    ///      (deployer, nonce) pair. A complete same-nonce hook proxy deployment is reusable
    ///      only after validating the proxy and its engine bindings. Intermediate CREATE3
    ///      addresses are not reusable without that final hook proxy proof.
    ///      If a CREATE3 minimal proxy was deployed but the inner contract creation failed
    ///      (salt consumed, final address empty), re-running reverts with a path-specific
    ///      consumed-salt error.
    ///
    ///      ATOMICITY: this function executes all four CREATE3 deployments in a single
    ///      transaction. If any step fails (hook proxy deployment, validation, etc.),
    ///      the entire transaction reverts — no intermediate CREATE3 salts are consumed
    ///      and no zombie contracts remain on-chain.
    ///
    ///      Deployment order (must not be reordered):
    ///        1. Engine implementation (stateless bytecode, safe to redeploy)
    ///        2. Engine proxy — initialized immediately with the predicted hook proxy address
    ///           as owner and authorizedHook. The hook proxy address is known before deployment
    ///           because it is mined from the CREATE3 salt.
    ///        3. Hook implementation (stateless bytecode, safe to redeploy)
    ///        4. Hook proxy — initialized with (hookOwner, hookTreasury, engine proxy)
    ///
    ///      The engine proxy must be initialized before the hook proxy because the hook's
    ///      initialize() validates engine.authorizedHook() == address(this). The predicted
    ///      hook proxy address is used because the actual address is not yet deployed.
    ///
    ///      WARNING: do NOT extract individual deployment steps into separate transactions.
    ///      A partial deployment (e.g. engine proxy deployed but hook proxy failed in a
    ///      separate transaction) leaves the engine proxy initialized with a non-existent
    ///      owner, permanently bricking it. The consumed CREATE3 salts require incrementing
    ///      the nonce to recover.
    /// @return result All four deployed addresses: engine impl/proxy and hook impl/proxy.
    function run() public returns (DeploymentResult memory result) {
        return run(vm.envUint("DEPLOYMENT_NONCE"));
    }

    /// @notice Executes the deployment using environment-provided production addresses and deployment nonce.
    /// @dev The nonce is part of the CREATE3 salts and must be incremented for each new deploy.
    /// @param nonce Deployment version nonce.
    /// @return result All four deployed addresses: engine impl/proxy and hook impl/proxy.
    function run(uint256 nonce) public broadcaster returns (DeploymentResult memory result) {
        IOutrunDeployer outrunDeployer = IOutrunDeployer(vm.envAddress("OUTRUN_DEPLOYER"));
        IPoolManager poolManager = IPoolManager(vm.envAddress("POOL_MANAGER"));
        address hookOwner = vm.envAddress("HOOK_OWNER");
        address hookTreasury = vm.envAddress("HOOK_TREASURY");
        _requireNoZeroAddress(hookOwner);
        _requireNoZeroAddress(hookTreasury);
        _requireNoZeroAddress(address(outrunDeployer));
        _requirePoolManagerCode(poolManager);

        (bytes32 proxySalt, address selectedProxy, bool reuseExistingProxy) =
            _selectProxySalt(outrunDeployer, deployer, nonce, hookOwner, hookTreasury, poolManager);
        if (reuseExistingProxy) {
            result.hookProxy = selectedProxy;
            result.hookImplementation = _getExistingImplementation(result.hookProxy);
            result.engineProxy = address(MemeverseUniswapHook(result.hookProxy).dynamicFeeEngine());
            result.engineImplementation = _getExistingImplementation(result.engineProxy);
            return result;
        }

        (, address engineImpl) = _computeEngineImpl(outrunDeployer, deployer, nonce);
        if (engineImpl.code.length == 0) {
            _deployEngineImpl(outrunDeployer, deployer, nonce, poolManager);
        } else {
            revert ExistingIntermediateDeploymentNotReusable(engineImpl);
        }
        (, address engine) = _computeEngineProxy(outrunDeployer, deployer, nonce);
        if (engine.code.length == 0) {
            _deployEngineProxy(outrunDeployer, deployer, nonce, engineImpl, selectedProxy, selectedProxy);
        } else {
            revert ExistingIntermediateDeploymentNotReusable(engine);
        }
        (, address hookImpl) = _computeHookImpl(outrunDeployer, deployer, nonce);
        if (hookImpl.code.length == 0) {
            _deployHookImpl(outrunDeployer, deployer, nonce, poolManager);
        } else {
            revert ExistingIntermediateDeploymentNotReusable(hookImpl);
        }
        address proxy = _deployProxy(
            outrunDeployer, deployer, proxySalt, selectedProxy, hookImpl, hookOwner, hookTreasury, engine
        );
        _validateExistingDeployment(proxy, hookImpl, engine, hookOwner, hookTreasury, poolManager);

        result.engineImplementation = engineImpl;
        result.engineProxy = engine;
        result.hookImplementation = hookImpl;
        result.hookProxy = proxy;
    }

    /// @notice Deploys the implementation and a mined ERC1967 proxy through OutrunDeployer.
    /// @dev ATOMICITY: all four CREATE3 deployments execute in a single call. If any step
    ///      fails, the entire call reverts — no intermediate salts are consumed.
    ///      WARNING: do NOT extract individual steps into separate transactions.
    /// @param outrunDeployer CREATE3 deployer used for the proxy address.
    /// @param deployerNamespace Address that will be the effective msg.sender when
    ///   OutrunDeployer.deploy() is called. Must match msg.sender unless called inside
    ///   a Foundry broadcast that sets msg.sender to this address.
    /// @param poolManager Uniswap v4 pool manager stored in the hook implementation immutable state.
    /// @param hookOwner Owner used for proxy initialization.
    /// @param hookTreasury Treasury used for proxy initialization.
    /// @param nonce Deployment version nonce, incremented for each new deploy.
    /// @return result All four deployed addresses: engine impl/proxy and hook impl/proxy.
    function deployHookProxy(
        IOutrunDeployer outrunDeployer,
        address deployerNamespace,
        IPoolManager poolManager,
        address hookOwner,
        address hookTreasury,
        uint256 nonce
    ) public returns (DeploymentResult memory result) {
        if (msg.sender != deployerNamespace) {
            revert DeployerNamespaceMismatch(msg.sender, deployerNamespace);
        }
        _requireNoZeroAddress(hookOwner);
        _requireNoZeroAddress(hookTreasury);
        _requirePoolManagerCode(poolManager);

        (bytes32 proxySalt, address selectedProxy, bool reuseExistingProxy) =
            _selectProxySalt(outrunDeployer, deployerNamespace, nonce, hookOwner, hookTreasury, poolManager);
        if (reuseExistingProxy) {
            result.hookProxy = selectedProxy;
            result.hookImplementation = _getExistingImplementation(result.hookProxy);
            result.engineProxy = address(MemeverseUniswapHook(result.hookProxy).dynamicFeeEngine());
            result.engineImplementation = _getExistingImplementation(result.engineProxy);
            return result;
        }

        (, address engineImpl) = _computeEngineImpl(outrunDeployer, deployerNamespace, nonce);
        if (engineImpl.code.length == 0) {
            _deployEngineImpl(outrunDeployer, deployerNamespace, nonce, poolManager);
        } else {
            revert ExistingIntermediateDeploymentNotReusable(engineImpl);
        }
        (, address engine) = _computeEngineProxy(outrunDeployer, deployerNamespace, nonce);
        if (engine.code.length == 0) {
            _deployEngineProxy(outrunDeployer, deployerNamespace, nonce, engineImpl, selectedProxy, selectedProxy);
        } else {
            revert ExistingIntermediateDeploymentNotReusable(engine);
        }
        (, address hookImpl) = _computeHookImpl(outrunDeployer, deployerNamespace, nonce);
        if (hookImpl.code.length == 0) {
            _deployHookImpl(outrunDeployer, deployerNamespace, nonce, poolManager);
        } else {
            revert ExistingIntermediateDeploymentNotReusable(hookImpl);
        }
        address proxy = _deployProxy(
            outrunDeployer, deployerNamespace, proxySalt, selectedProxy, hookImpl, hookOwner, hookTreasury, engine
        );
        _validateExistingDeployment(proxy, hookImpl, engine, hookOwner, hookTreasury, poolManager);

        result.engineImplementation = engineImpl;
        result.engineProxy = engine;
        result.hookImplementation = hookImpl;
        result.hookProxy = proxy;
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
    ///      Legacy helper for global bytes32(i) search. Deployment uses nonce-scoped salts.
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

    /// @notice Returns the first global hook-flag-matching proxy address, regardless of deployment status.
    /// @dev Legacy helper for global bytes32(i) search. Deployment idempotency uses
    ///      the nonce-scoped getPredictedProxy(..., nonce) overload.
    /// @param outrunDeployer CREATE3 deployer used for address prediction.
    /// @param deployerNamespace Address that will call `OutrunDeployer.deploy`.
    /// @return proxy First predicted proxy address carrying the required hook flags.
    function getPredictedProxy(IOutrunDeployer outrunDeployer, address deployerNamespace)
        public
        view
        returns (address proxy)
    {
        for (uint256 i; i < MAX_SALT_SEARCH; ++i) {
            proxy = outrunDeployer.getDeployed(deployerNamespace, bytes32(i));
            if ((uint160(proxy) & UNISWAP_V4_HOOK_FLAG_MASK) == MEMEVERSE_HOOK_FLAGS) {
                return proxy;
            }
        }

        revert ProxySaltNotFound(MAX_SALT_SEARCH);
    }

    /// @notice Returns the first nonce-scoped hook-flag candidate, regardless of deployment status.
    /// @dev This does not skip dirty occupied candidates. Use the overload with owner,
    ///      treasury, and poolManager to predict deployHookProxy/run selection.
    /// @param outrunDeployer CREATE3 deployer used for address prediction.
    /// @param deployerNamespace Address that will call `OutrunDeployer.deploy`.
    /// @param nonce Deployment version nonce.
    /// @return proxy First nonce-scoped proxy address carrying the required hook flags.
    function getPredictedProxy(IOutrunDeployer outrunDeployer, address deployerNamespace, uint256 nonce)
        public
        view
        returns (address proxy)
    {
        for (uint256 i; i < MAX_SALT_SEARCH; ++i) {
            bytes32 salt = keccak256(abi.encodePacked("MemeverseUniswapHookProxy", nonce, i));
            proxy = outrunDeployer.getDeployed(deployerNamespace, salt);
            if ((uint160(proxy) & UNISWAP_V4_HOOK_FLAG_MASK) == MEMEVERSE_HOOK_FLAGS) return proxy;
        }

        revert ProxySaltNotFound(MAX_SALT_SEARCH);
    }

    /// @notice Returns the nonce-scoped hook proxy selected by the deployment flow.
    /// @dev Uses the same validation inputs as deployHookProxy/run, so dirty non-hook
    ///      candidates are skipped and valid same-nonce deployments are reused.
    /// @param outrunDeployer CREATE3 deployer used for address prediction.
    /// @param deployerNamespace Address that will call `OutrunDeployer.deploy`.
    /// @param nonce Deployment version nonce.
    /// @param hookOwner Owner expected on a reusable hook proxy.
    /// @param hookTreasury Treasury expected on a reusable hook proxy.
    /// @param poolManager PoolManager expected on a reusable hook and engine.
    /// @return proxy Selected proxy address used by deployHookProxy/run.
    function getPredictedProxy(
        IOutrunDeployer outrunDeployer,
        address deployerNamespace,
        uint256 nonce,
        address hookOwner,
        address hookTreasury,
        IPoolManager poolManager
    ) public view returns (address proxy) {
        (, proxy,) = _selectProxySalt(outrunDeployer, deployerNamespace, nonce, hookOwner, hookTreasury, poolManager);
    }

    /// @notice Mines the nonce-scoped hook proxy salt used by deployHookProxy/run.
    /// @dev Existing code is reusable only when it is the expected same-nonce deployment.
    function _selectProxySalt(
        IOutrunDeployer outrunDeployer,
        address deployerNamespace,
        uint256 nonce,
        address hookOwner,
        address hookTreasury,
        IPoolManager poolManager
    ) internal view returns (bytes32 salt, address proxy, bool reuseExistingProxy) {
        (, address expectedHookImpl) = _computeHookImpl(outrunDeployer, deployerNamespace, nonce);
        (, address expectedEngine) = _computeEngineProxy(outrunDeployer, deployerNamespace, nonce);
        for (uint256 i; i < MAX_SALT_SEARCH; ++i) {
            salt = keccak256(abi.encodePacked("MemeverseUniswapHookProxy", nonce, i));
            proxy = outrunDeployer.getDeployed(deployerNamespace, salt);
            if ((uint160(proxy) & UNISWAP_V4_HOOK_FLAG_MASK) != MEMEVERSE_HOOK_FLAGS) continue;
            if (proxy.code.length == 0) {
                address create3Proxy = _create3ProxyAddress(outrunDeployer, deployerNamespace, salt);
                if (create3Proxy.code.length != 0) revert Create3SaltConsumed(salt, create3Proxy);
                return (salt, proxy, false);
            }
            if (_getExistingImplementation(proxy) != expectedHookImpl) continue;
            _validateExistingImplementationCodehashes(proxy);
            if (_matchesExistingDeployment(
                    proxy, expectedHookImpl, expectedEngine, hookOwner, hookTreasury, poolManager
                )) return (salt, proxy, true);
            _validateExistingDeployment(proxy, expectedHookImpl, expectedEngine, hookOwner, hookTreasury, poolManager);
        }

        revert ProxySaltNotFound(MAX_SALT_SEARCH);
    }

    // ─────────────────────────── Engine Implementation ───────────────────────────

    /// @notice Computes the deterministic engine implementation address.
    /// @param outrunDeployer CREATE3 deployer used for address prediction.
    /// @param deployerNamespace Address that will call `OutrunDeployer.deploy`.
    /// @param nonce Deployment version nonce.
    /// @return salt The computed salt.
    /// @return impl The predicted implementation address.
    function _computeEngineImpl(IOutrunDeployer outrunDeployer, address deployerNamespace, uint256 nonce)
        internal
        view
        returns (bytes32 salt, address impl)
    {
        salt = keccak256(abi.encodePacked(ENGINE_IMPL_SALT_SEED, nonce));
        impl = outrunDeployer.getDeployed(deployerNamespace, salt);
    }

    /// @notice Deploys the engine implementation via OutrunDeployer if not already deployed.
    /// @dev If the final address has no code but the CREATE3 proxy is occupied, the salt is consumed.
    /// @param outrunDeployer CREATE3 deployer used for deployment.
    /// @param deployerNamespace Address that will be the effective msg.sender.
    /// @param nonce Deployment version nonce.
    /// @param poolManager PoolManager stored as immutable in the engine implementation.
    function _deployEngineImpl(
        IOutrunDeployer outrunDeployer,
        address deployerNamespace,
        uint256 nonce,
        IPoolManager poolManager
    ) internal {
        (bytes32 salt, address expectedImpl) = _computeEngineImpl(outrunDeployer, deployerNamespace, nonce);
        address create3Proxy = _create3ProxyAddress(outrunDeployer, deployerNamespace, salt);
        if (create3Proxy.code.length != 0) {
            revert EngineImplementationCreate3SaltConsumed(salt, create3Proxy);
        }
        bytes memory creationCode =
            abi.encodePacked(type(MemeverseDynamicFeeEngine).creationCode, abi.encode(poolManager));
        address deployed = outrunDeployer.deploy(salt, creationCode);
        if (deployed != expectedImpl) revert ProxyDeploymentMismatch(expectedImpl, deployed);
    }

    // ──────────────────────────── Engine Proxy ───────────────────────────────────

    /// @notice Computes the deterministic engine proxy address.
    /// @param outrunDeployer CREATE3 deployer used for address prediction.
    /// @param deployerNamespace Address that will call `OutrunDeployer.deploy`.
    /// @param nonce Deployment version nonce.
    /// @return salt The computed salt.
    /// @return engine The predicted engine proxy address.
    function _computeEngineProxy(IOutrunDeployer outrunDeployer, address deployerNamespace, uint256 nonce)
        internal
        view
        returns (bytes32 salt, address engine)
    {
        salt = keccak256(abi.encodePacked("MemeverseDynamicFeeEngine", nonce));
        engine = outrunDeployer.getDeployed(deployerNamespace, salt);
    }

    /// @notice Deploys the engine ERC1967 proxy via OutrunDeployer if not already deployed.
    /// @dev The engine proxy is initialized immediately with the predicted hook proxy address
    ///      as both owner and authorized caller. This is safe because:
    ///      1. The hook proxy address is deterministically computed from the CREATE3 salt and
    ///         is known before any deployment.
    ///      2. The entire deployHookProxy/run flow executes in a single transaction — if the
    ///         hook proxy deployment fails, the entire transaction reverts and the engine proxy
    ///         deployment is also reverted (no zombie state).
    ///      WARNING: Do NOT call _deployEngineProxy in a standalone transaction without also
    ///      deploying the hook proxy in the same transaction. A partial deployment leaves the
    ///      engine proxy initialized with a non-existent owner, permanently bricking it.
    ///      If the final address has no code but the CREATE3 proxy is occupied, the salt is consumed.
    /// @param outrunDeployer CREATE3 deployer used for deployment.
    /// @param deployerNamespace Address that will be the effective msg.sender.
    /// @param nonce Deployment version nonce.
    /// @param engineImpl Engine implementation address stored in the proxy's implementation slot.
    /// @param engineOwner Permanent engine owner (hook proxy address).
    /// @param authorizedHook Hook proxy address to authorize at init time.
    function _deployEngineProxy(
        IOutrunDeployer outrunDeployer,
        address deployerNamespace,
        uint256 nonce,
        address engineImpl,
        address engineOwner,
        address authorizedHook
    ) internal {
        (bytes32 salt, address expectedEngine) = _computeEngineProxy(outrunDeployer, deployerNamespace, nonce);
        address create3Proxy = _create3ProxyAddress(outrunDeployer, deployerNamespace, salt);
        if (create3Proxy.code.length != 0) {
            revert EngineProxyCreate3SaltConsumed(salt, create3Proxy);
        }
        bytes memory initData = abi.encodeCall(MemeverseDynamicFeeEngine.initialize, (engineOwner, authorizedHook));
        bytes memory creationCode = abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(engineImpl, initData));
        address deployed = outrunDeployer.deploy(salt, creationCode);
        if (deployed != expectedEngine) revert ProxyDeploymentMismatch(expectedEngine, deployed);
    }

    // ─────────────────────────── Hook Implementation ─────────────────────────────

    /// @notice Computes the deterministic hook implementation address.
    /// @param outrunDeployer CREATE3 deployer used for address prediction.
    /// @param deployerNamespace Address that will call `OutrunDeployer.deploy`.
    /// @param nonce Deployment version nonce.
    /// @return salt The computed salt.
    /// @return impl The predicted implementation address.
    function _computeHookImpl(IOutrunDeployer outrunDeployer, address deployerNamespace, uint256 nonce)
        internal
        view
        returns (bytes32 salt, address impl)
    {
        salt = keccak256(abi.encodePacked(HOOK_IMPL_SALT_SEED, nonce));
        impl = outrunDeployer.getDeployed(deployerNamespace, salt);
    }

    /// @notice Deploys the hook implementation via OutrunDeployer if not already deployed.
    /// @dev If the final address has no code but the CREATE3 proxy is occupied, the salt is consumed.
    /// @param outrunDeployer CREATE3 deployer used for deployment.
    /// @param deployerNamespace Address that will be the effective msg.sender.
    /// @param nonce Deployment version nonce.
    /// @param poolManager Uniswap v4 pool manager stored as immutable in the hook implementation.
    function _deployHookImpl(
        IOutrunDeployer outrunDeployer,
        address deployerNamespace,
        uint256 nonce,
        IPoolManager poolManager
    ) internal {
        (bytes32 salt, address expectedImpl) = _computeHookImpl(outrunDeployer, deployerNamespace, nonce);
        address create3Proxy = _create3ProxyAddress(outrunDeployer, deployerNamespace, salt);
        if (create3Proxy.code.length != 0) {
            revert HookImplementationCreate3SaltConsumed(salt, create3Proxy);
        }
        bytes memory creationCode = abi.encodePacked(type(MemeverseUniswapHook).creationCode, abi.encode(poolManager));
        address deployed = outrunDeployer.deploy(salt, creationCode);
        if (deployed != expectedImpl) revert ProxyDeploymentMismatch(expectedImpl, deployed);
    }

    // ───────────────────────────── Hook Proxy ────────────────────────────────────

    function _deployProxy(
        IOutrunDeployer outrunDeployer,
        address deployerNamespace,
        bytes32 salt,
        address expectedProxy,
        address implementation,
        address hookOwner,
        address hookTreasury,
        address hookEngine
    ) internal returns (address proxy) {
        // Detect if the CREATE3 minimal proxy was already deployed for this salt
        // (e.g. a previous run's inner CREATE failed). The salt is permanently consumed
        // and cannot be retried — revert with actionable context instead of the opaque
        // "DEPLOYMENT_FAILED" error from solmate CREATE3.
        address create3Proxy = _create3ProxyAddress(outrunDeployer, deployerNamespace, salt);
        if (create3Proxy.code.length != 0) revert Create3SaltConsumed(salt, create3Proxy);

        bytes memory initializeData = abi.encodeCall(
            MemeverseUniswapHook.initialize, (hookOwner, hookTreasury, IMemeverseDynamicFeeEngine(hookEngine))
        );
        bytes memory creationCode = proxyCreationCode(implementation, initializeData);

        proxy = outrunDeployer.deploy(salt, creationCode);
        if (proxy != expectedProxy) revert ProxyDeploymentMismatch(expectedProxy, proxy);
        if ((uint160(proxy) & UNISWAP_V4_HOOK_FLAG_MASK) != MEMEVERSE_HOOK_FLAGS) revert HookFlagMismatch(proxy);
    }

    // ─────────────────────────────── Utils ───────────────────────────────────────

    function _requirePoolManagerCode(IPoolManager poolManager) internal view {
        address poolManagerAddress = address(poolManager);
        if (poolManagerAddress.code.length == 0) revert PoolManagerCodeNotReady(poolManagerAddress);
    }

    function _requireNoZeroAddress(address addr) internal pure {
        if (addr == address(0)) revert ZeroAddressNotAllowed();
    }

    function _getExistingImplementation(address proxy) internal view returns (address implementation) {
        implementation = address(uint160(uint256(vm.load(proxy, ERC1967Utils.IMPLEMENTATION_SLOT))));
    }

    function _create3ProxyAddress(IOutrunDeployer outrunDeployer, address deployerNamespace, bytes32 salt)
        internal
        pure
        returns (address create3Proxy)
    {
        bytes32 hashedSalt = keccak256(abi.encodePacked(deployerNamespace, salt));
        create3Proxy = keccak256(
                abi.encodePacked(bytes1(0xFF), address(outrunDeployer), hashedSalt, CREATE3_PROXY_BYTECODE_HASH)
            ).fromLast20Bytes();
    }

    function _validateExistingDeployment(
        address proxy,
        address expectedHookImplementation,
        address expectedEngine,
        address expectedHookOwner,
        address expectedHookTreasury,
        IPoolManager expectedPoolManager
    ) internal view {
        address actualImplementation = _getExistingImplementation(proxy);
        if (actualImplementation != expectedHookImplementation) {
            revert ExistingHookImplementationMismatch(proxy, expectedHookImplementation, actualImplementation);
        }

        MemeverseUniswapHook hook = MemeverseUniswapHook(proxy);
        address actualHookOwner = hook.owner();
        if (actualHookOwner != expectedHookOwner) {
            revert ExistingHookOwnerMismatch(proxy, expectedHookOwner, actualHookOwner);
        }

        address actualHookTreasury = hook.treasury();
        if (actualHookTreasury != expectedHookTreasury) {
            revert ExistingHookTreasuryMismatch(proxy, expectedHookTreasury, actualHookTreasury);
        }

        address actualHookPoolManager = address(hook.poolManager());
        if (actualHookPoolManager != address(expectedPoolManager)) {
            revert ExistingHookPoolManagerMismatch(proxy, address(expectedPoolManager), actualHookPoolManager);
        }

        IMemeverseDynamicFeeEngine engine = hook.dynamicFeeEngine();
        if (address(engine) != expectedEngine) {
            revert ExistingHookEngineMismatch(proxy, expectedEngine, address(engine));
        }

        address actualAuthorizedHook = engine.authorizedHook();
        if (actualAuthorizedHook != proxy) {
            revert ExistingEngineAuthorizedHookMismatch(address(engine), proxy, actualAuthorizedHook);
        }

        address actualEngineOwner = MemeverseDynamicFeeEngine(address(engine)).owner();
        if (actualEngineOwner != proxy) {
            revert ExistingEngineOwnerMismatch(address(engine), proxy, actualEngineOwner);
        }

        address actualEnginePoolManager = address(engine.poolManager());
        if (actualEnginePoolManager != address(expectedPoolManager)) {
            revert ExistingEnginePoolManagerMismatch(
                address(engine), address(expectedPoolManager), actualEnginePoolManager
            );
        }
    }

    function _matchesExistingDeployment(
        address proxy,
        address expectedHookImplementation,
        address expectedEngine,
        address expectedHookOwner,
        address expectedHookTreasury,
        IPoolManager expectedPoolManager
    ) internal view returns (bool matchesDeployment) {
        if (expectedHookImplementation.code.length == 0 || expectedEngine.code.length == 0) return false;
        if (_getExistingImplementation(proxy) != expectedHookImplementation) return false;

        MemeverseUniswapHook hook = MemeverseUniswapHook(proxy);

        try hook.owner() returns (address actualHookOwner) {
            if (actualHookOwner != expectedHookOwner) return false;
        } catch {
            return false;
        }

        try hook.treasury() returns (address actualHookTreasury) {
            if (actualHookTreasury != expectedHookTreasury) return false;
        } catch {
            return false;
        }

        try hook.poolManager() returns (IPoolManager actualHookPoolManager) {
            if (address(actualHookPoolManager) != address(expectedPoolManager)) return false;
        } catch {
            return false;
        }

        try hook.dynamicFeeEngine() returns (IMemeverseDynamicFeeEngine engine) {
            if (address(engine) != expectedEngine) return false;

            try engine.authorizedHook() returns (address actualAuthorizedHook) {
                if (actualAuthorizedHook != proxy) return false;
            } catch {
                return false;
            }

            try MemeverseDynamicFeeEngine(address(engine)).owner() returns (address actualEngineOwner) {
                if (actualEngineOwner != proxy) return false;
            } catch {
                return false;
            }

            try engine.poolManager() returns (IPoolManager actualEnginePoolManager) {
                return address(actualEnginePoolManager) == address(expectedPoolManager);
            } catch {
                return false;
            }
        } catch {
            return false;
        }
    }

    function _validateExistingImplementationCodehashes(address proxy) internal view {
        bytes32 expectedProxyCodehash = keccak256(type(ERC1967Proxy).runtimeCode);
        bytes32 currentHookProxyCodehash = proxy.codehash;
        if (currentHookProxyCodehash != expectedProxyCodehash) {
            revert ExistingHookProxyCodehashMismatch(proxy, expectedProxyCodehash, currentHookProxyCodehash);
        }

        bytes32 expectedHookCodehash = vm.envOr(string.concat("EXPECTED_HOOK_", "IMPLEMENTATION_CODEHASH"), bytes32(0));
        if (expectedHookCodehash == bytes32(0)) revert ExpectedHookImplementationCodehashNotSet();

        address hookImplementation = _getExistingImplementation(proxy);
        bytes32 currentHookCodehash = hookImplementation.codehash;
        if (currentHookCodehash != expectedHookCodehash) {
            revert ExistingHookImplementationCodehashMismatch(
                hookImplementation, expectedHookCodehash, currentHookCodehash
            );
        }

        address engine = address(MemeverseUniswapHook(proxy).dynamicFeeEngine());
        bytes32 currentEngineProxyCodehash = engine.codehash;
        if (currentEngineProxyCodehash != expectedProxyCodehash) {
            revert ExistingEngineProxyCodehashMismatch(engine, expectedProxyCodehash, currentEngineProxyCodehash);
        }

        address engineImplementation = _getExistingImplementation(engine);
        bytes32 expectedEngineCodehash =
            vm.envOr(string.concat("EXPECTED_ENGINE_", "IMPLEMENTATION_CODEHASH"), bytes32(0));
        if (expectedEngineCodehash == bytes32(0)) revert ExpectedEngineImplementationCodehashNotSet();

        bytes32 currentEngineCodehash = engineImplementation.codehash;
        if (currentEngineCodehash != expectedEngineCodehash) {
            revert ExistingEngineImplementationCodehashMismatch(
                engineImplementation, expectedEngineCodehash, currentEngineCodehash
            );
        }
    }
}
