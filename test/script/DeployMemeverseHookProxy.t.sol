// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {Bytes32AddressLib} from "solmate/utils/Bytes32AddressLib.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

import {DeployMemeverseHookProxy} from "../../script/DeployMemeverseHookProxy.s.sol";
import {IOutrunDeployer} from "../../script/IOutrunDeployer.sol";
import {OutrunDeployer} from "../../script/deployment/OutrunDeployer.sol";
import {IMemeverseDynamicFeeEngine} from "../../src/swap/interfaces/IMemeverseDynamicFeeEngine.sol";
import {IMemeversePreorderSettlementExecutor} from "../../src/swap/interfaces/IMemeversePreorderSettlementExecutor.sol";
import {MemeverseDynamicFeeEngine} from "../../src/swap/MemeverseDynamicFeeEngine.sol";
import {MemeverseUniswapHook} from "../../src/swap/MemeverseUniswapHook.sol";

contract DeployMemeverseHookProxyHarness is DeployMemeverseHookProxy {
    function exposedComputeEngineImpl(IOutrunDeployer outrunDeployer, address deployerNamespace, uint256 nonce)
        external
        view
        returns (bytes32 salt, address impl)
    {
        return _computeEngineImpl(outrunDeployer, deployerNamespace, nonce);
    }

    function exposedComputeEngineProxy(IOutrunDeployer outrunDeployer, address deployerNamespace, uint256 nonce)
        external
        view
        returns (bytes32 salt, address engine)
    {
        return _computeEngineProxy(outrunDeployer, deployerNamespace, nonce);
    }

    function exposedComputeHookImpl(IOutrunDeployer outrunDeployer, address deployerNamespace, uint256 nonce)
        external
        view
        returns (bytes32 salt, address impl)
    {
        return _computeHookImpl(outrunDeployer, deployerNamespace, nonce);
    }

    function exposedComputeLpTokenImpl(IOutrunDeployer outrunDeployer, address deployerNamespace, uint256 nonce)
        external
        view
        returns (bytes32 salt, address impl)
    {
        return _computeLpTokenImpl(outrunDeployer, deployerNamespace, nonce);
    }

    function exposedComputePreorderSettlementExecutor(
        IOutrunDeployer outrunDeployer,
        address deployerNamespace,
        uint256 nonce
    ) external view returns (bytes32 salt, address executor) {
        return _computePreorderSettlementExecutor(outrunDeployer, deployerNamespace, nonce);
    }

    function exposedDeployEngineImpl(
        IOutrunDeployer outrunDeployer,
        address deployerNamespace,
        uint256 nonce,
        IPoolManager poolManager
    ) external {
        _deployEngineImpl(outrunDeployer, deployerNamespace, nonce, poolManager);
    }

    function exposedDeployEngineProxy(
        IOutrunDeployer outrunDeployer,
        address deployerNamespace,
        uint256 nonce,
        address engineImpl,
        address engineOwner,
        address authorizedHook
    ) external {
        _deployEngineProxy(outrunDeployer, deployerNamespace, nonce, engineImpl, engineOwner, authorizedHook);
    }

    function exposedDeployHookImpl(
        IOutrunDeployer outrunDeployer,
        address deployerNamespace,
        uint256 nonce,
        IPoolManager poolManager
    ) external {
        _deployHookImpl(outrunDeployer, deployerNamespace, nonce, poolManager);
    }

    function exposedDeployLpTokenImpl(IOutrunDeployer outrunDeployer, address deployerNamespace, uint256 nonce)
        external
    {
        _deployLpTokenImpl(outrunDeployer, deployerNamespace, nonce);
    }

    function exposedDeployPreorderSettlementExecutor(
        IOutrunDeployer outrunDeployer,
        address deployerNamespace,
        uint256 nonce,
        address hookProxy
    ) external {
        _deployPreorderSettlementExecutor(outrunDeployer, deployerNamespace, nonce, hookProxy);
    }

    function exposedSelectProxySalt(
        IOutrunDeployer outrunDeployer,
        address deployerNamespace,
        uint256 nonce,
        address hookOwner,
        address hookTreasury,
        IPoolManager poolManager
    ) external view returns (bytes32 salt, address proxy, bool reuseExistingProxy) {
        return _selectProxySalt(outrunDeployer, deployerNamespace, nonce, hookOwner, hookTreasury, poolManager);
    }
}

contract FakeDeploymentEngine {
    address internal fakeOwner;
    address internal fakeAuthorizedHook;
    IPoolManager internal fakePoolManager;

    function initializeFake(address owner_, address authorizedHook_, IPoolManager poolManager_) external {
        fakeOwner = owner_;
        fakeAuthorizedHook = authorizedHook_;
        fakePoolManager = poolManager_;
    }

    function owner() external view returns (address) {
        return fakeOwner;
    }

    function authorizedHook() external view returns (address) {
        return fakeAuthorizedHook;
    }

    function poolManager() external view returns (IPoolManager) {
        return fakePoolManager;
    }
}

contract FakeDeploymentHook {
    address internal fakeOwner;
    address internal fakeTreasury;
    IPoolManager internal fakePoolManager;
    IMemeverseDynamicFeeEngine internal fakeEngine;
    address internal fakeLpTokenImplementation;
    IMemeversePreorderSettlementExecutor internal fakePreorderSettlementExecutor;

    function initializeFake(
        address owner_,
        address treasury_,
        IPoolManager poolManager_,
        IMemeverseDynamicFeeEngine engine_
    ) external {
        fakeOwner = owner_;
        fakeTreasury = treasury_;
        fakePoolManager = poolManager_;
        fakeEngine = engine_;
    }

    function owner() external view returns (address) {
        return fakeOwner;
    }

    function treasury() external view returns (address) {
        return fakeTreasury;
    }

    function poolManager() external view returns (IPoolManager) {
        return fakePoolManager;
    }

    function dynamicFeeEngine() external view returns (IMemeverseDynamicFeeEngine) {
        return fakeEngine;
    }

    function lpTokenImplementation() external view returns (address) {
        return fakeLpTokenImplementation;
    }

    function preorderSettlementExecutor() external view returns (IMemeversePreorderSettlementExecutor) {
        return fakePreorderSettlementExecutor;
    }
}

contract DeployMemeverseHookProxyTest is Test {
    using Bytes32AddressLib for bytes32;

    address internal constant POOL_MANAGER = address(0x1001);
    address internal constant HOOK_OWNER = address(0x1002);
    address internal constant HOOK_TREASURY = address(0x1003);
    address internal constant DEPLOYER_NAMESPACE = address(0x1004);

    // Same constant as DeployMemeverseHookProxy — solmate CREATE3 minimal proxy bytecode hash.
    bytes32 internal constant CREATE3_PROXY_BYTECODE_HASH = keccak256(hex"67363d3d37363d34f03d5260086018f3");

    OutrunDeployer internal outrunDeployer;
    DeployMemeverseHookProxyHarness internal script;

    function setUp() external {
        outrunDeployer = new OutrunDeployer(address(this));
        script = new DeployMemeverseHookProxyHarness();
        vm.setEnv("EXPECTED_HOOK_IMPLEMENTATION_CODEHASH", vm.toString(bytes32(0)));
        vm.setEnv("EXPECTED_ENGINE_IMPLEMENTATION_CODEHASH", vm.toString(bytes32(0)));
        vm.setEnv("EXPECTED_LP_TOKEN_IMPLEMENTATION_CODEHASH", vm.toString(bytes32(0)));
        vm.setEnv("EXPECTED_PREORDER_SETTLEMENT_EXECUTOR_CODEHASH", vm.toString(bytes32(0)));
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

        (bytes32 salt, address predictedProxy,) = script.exposedSelectProxySalt(
            IOutrunDeployer(address(outrunDeployer)),
            address(script),
            1,
            HOOK_OWNER,
            HOOK_TREASURY,
            IPoolManager(POOL_MANAGER)
        );
        vm.prank(address(script));
        DeployMemeverseHookProxy.DeploymentResult memory r = script.deployHookProxy(
            IOutrunDeployer(address(outrunDeployer)),
            address(script),
            IPoolManager(POOL_MANAGER),
            HOOK_OWNER,
            HOOK_TREASURY,
            1
        );
        MemeverseUniswapHook hook = MemeverseUniswapHook(r.hookProxy);

        assertEq(outrunDeployer.getDeployed(address(script), salt), predictedProxy);
        assertEq(r.hookProxy, predictedProxy);
        assertGt(r.hookImplementation.code.length, 0);
        assertGt(r.hookProxy.code.length, 0);
        assertGt(r.engineImplementation.code.length, 0);
        assertGt(r.engineProxy.code.length, 0);
        assertGt(r.lpTokenImplementation.code.length, 0);
        assertGt(r.preorderSettlementExecutor.code.length, 0);
        assertEq(uint160(r.hookProxy) & script.uniswapV4HookFlagMask(), script.memeverseHookFlags());
        assertEq(hook.owner(), HOOK_OWNER);
        assertEq(hook.treasury(), HOOK_TREASURY);
        assertEq(address(hook.poolManager()), POOL_MANAGER);
        assertEq(hook.lpTokenImplementation(), r.lpTokenImplementation);
        assertEq(address(hook.preorderSettlementExecutor()), r.preorderSettlementExecutor);
        assertGt(address(hook.dynamicFeeEngine()).code.length, 0);
        assertEq(address(hook.dynamicFeeEngine().poolManager()), POOL_MANAGER);
        IMemeverseDynamicFeeEngine engine = hook.dynamicFeeEngine();
        assertEq(MemeverseDynamicFeeEngine(address(engine)).owner(), r.hookProxy);
        vm.prank(r.hookProxy);
        engine.refreshBeforeSwap(
            IMemeverseDynamicFeeEngine.RefreshBeforeSwapParams({
                poolId: PoolId.wrap(bytes32(uint256(0x1234))), preSqrtPriceX96: 79228162514264337593543950336
            })
        );
        assertEq(
            address(uint160(uint256(vm.load(r.hookProxy, ERC1967Utils.IMPLEMENTATION_SLOT)))), r.hookImplementation
        );
    }

    function testRunReadsDeploymentNonceFromEnv() external {
        uint256 privateKey = 1;
        address deploymentSender = vm.addr(privateKey);
        uint256 deploymentNonce = 7;
        vm.etch(POOL_MANAGER, hex"01");
        outrunDeployer.transferOwnership(deploymentSender);
        vm.setEnv("PRIVATE_KEY", vm.toString(privateKey));
        vm.setEnv("OUTRUN_DEPLOYER", vm.toString(address(outrunDeployer)));
        vm.setEnv("POOL_MANAGER", vm.toString(POOL_MANAGER));
        vm.setEnv("HOOK_OWNER", vm.toString(HOOK_OWNER));
        vm.setEnv("HOOK_TREASURY", vm.toString(HOOK_TREASURY));
        vm.setEnv("DEPLOYMENT_NONCE", vm.toString(deploymentNonce));
        script.setUp();

        (bytes32 expectedHookImplSalt, address expectedHookImpl) =
            script.exposedComputeHookImpl(IOutrunDeployer(address(outrunDeployer)), deploymentSender, deploymentNonce);
        (bytes32 expectedLpTokenImplSalt, address expectedLpTokenImpl) = script.exposedComputeLpTokenImpl(
            IOutrunDeployer(address(outrunDeployer)), deploymentSender, deploymentNonce
        );
        (bytes32 expectedPreorderSettlementExecutorSalt, address expectedPreorderSettlementExecutor) = script.exposedComputePreorderSettlementExecutor(
            IOutrunDeployer(address(outrunDeployer)), deploymentSender, deploymentNonce
        );

        DeployMemeverseHookProxy.DeploymentResult memory r = script.run();

        assertEq(r.hookImplementation, expectedHookImpl);
        assertEq(r.lpTokenImplementation, expectedLpTokenImpl);
        assertEq(r.preorderSettlementExecutor, expectedPreorderSettlementExecutor);
        assertGt(r.hookProxy.code.length, 0);
        assertEq(outrunDeployer.getDeployed(deploymentSender, expectedHookImplSalt), expectedHookImpl);
        assertEq(outrunDeployer.getDeployed(deploymentSender, expectedLpTokenImplSalt), expectedLpTokenImpl);
        assertEq(
            outrunDeployer.getDeployed(deploymentSender, expectedPreorderSettlementExecutorSalt),
            expectedPreorderSettlementExecutor
        );
    }

    function testDeployProxyRejectsPoolManagerWithoutCode() external {
        vm.prank(address(script));
        vm.expectRevert(abi.encodeWithSelector(DeployMemeverseHookProxy.PoolManagerCodeNotReady.selector, POOL_MANAGER));
        script.deployHookProxy(
            IOutrunDeployer(address(outrunDeployer)),
            address(script),
            IPoolManager(POOL_MANAGER),
            HOOK_OWNER,
            HOOK_TREASURY,
            1
        );
    }

    function testReusesExistingEngineProxy() external {
        vm.etch(POOL_MANAGER, hex"01");
        outrunDeployer.transferOwnership(address(script));

        // First deploy: creates engine proxy + hook proxy
        vm.prank(address(script));
        DeployMemeverseHookProxy.DeploymentResult memory first = script.deployHookProxy(
            IOutrunDeployer(address(outrunDeployer)),
            address(script),
            IPoolManager(POOL_MANAGER),
            HOOK_OWNER,
            HOOK_TREASURY,
            1
        );
        assertGt(first.engineProxy.code.length, 0);
        assertGt(first.lpTokenImplementation.code.length, 0);
        assertGt(first.preorderSettlementExecutor.code.length, 0);
        _setExpectedImplementationCodehashes(first.hookProxy);

        // Second deploy with same nonce: idempotent through the already validated hook proxy.
        vm.prank(address(script));
        DeployMemeverseHookProxy.DeploymentResult memory second = script.deployHookProxy(
            IOutrunDeployer(address(outrunDeployer)),
            address(script),
            IPoolManager(POOL_MANAGER),
            HOOK_OWNER,
            HOOK_TREASURY,
            1
        );

        // All addresses must be identical — deterministic CREATE3 salts guarantee this.
        assertEq(second.hookImplementation, first.hookImplementation);
        assertEq(second.hookProxy, first.hookProxy);
        assertEq(second.engineImplementation, first.engineImplementation);
        assertEq(second.engineProxy, first.engineProxy);
        assertEq(second.lpTokenImplementation, first.lpTokenImplementation);
        assertEq(second.preorderSettlementExecutor, first.preorderSettlementExecutor);

        // State is intact: owner, poolManager, and engine authorization unchanged.
        assertEq(MemeverseUniswapHook(second.hookProxy).owner(), HOOK_OWNER);
        assertEq(address(MemeverseUniswapHook(second.hookProxy).poolManager()), POOL_MANAGER);
        assertEq(MemeverseUniswapHook(second.hookProxy).lpTokenImplementation(), first.lpTokenImplementation);
        assertEq(
            address(MemeverseUniswapHook(second.hookProxy).preorderSettlementExecutor()),
            first.preorderSettlementExecutor
        );
        assertEq(MemeverseDynamicFeeEngine(first.engineProxy).owner(), first.hookProxy);
        assertEq(address(MemeverseDynamicFeeEngine(first.engineProxy).poolManager()), POOL_MANAGER);
    }

    function testSameNonceReuseRejectsStaleHookImplementationBytecode() external {
        vm.etch(POOL_MANAGER, hex"01");
        outrunDeployer.transferOwnership(address(script));

        vm.prank(address(script));
        DeployMemeverseHookProxy.DeploymentResult memory r = script.deployHookProxy(
            IOutrunDeployer(address(outrunDeployer)),
            address(script),
            IPoolManager(POOL_MANAGER),
            HOOK_OWNER,
            HOOK_TREASURY,
            1
        );

        bytes32 expectedCodehash = r.hookImplementation.codehash;
        _setExpectedImplementationCodehashes(r.hookProxy);
        FakeDeploymentHook staleHookImplementation = new FakeDeploymentHook();
        vm.etch(r.hookImplementation, address(staleHookImplementation).code);
        bytes32 currentCodehash = r.hookImplementation.codehash;

        vm.prank(address(script));
        vm.expectRevert(
            abi.encodeWithSelector(
                DeployMemeverseHookProxy.ExistingHookImplementationCodehashMismatch.selector,
                r.hookImplementation,
                expectedCodehash,
                currentCodehash
            )
        );
        script.deployHookProxy(
            IOutrunDeployer(address(outrunDeployer)),
            address(script),
            IPoolManager(POOL_MANAGER),
            HOOK_OWNER,
            HOOK_TREASURY,
            1
        );
    }

    function testSameNonceReuseRejectsStaleEngineImplementationBytecode() external {
        vm.etch(POOL_MANAGER, hex"01");
        outrunDeployer.transferOwnership(address(script));

        vm.prank(address(script));
        DeployMemeverseHookProxy.DeploymentResult memory r = script.deployHookProxy(
            IOutrunDeployer(address(outrunDeployer)),
            address(script),
            IPoolManager(POOL_MANAGER),
            HOOK_OWNER,
            HOOK_TREASURY,
            1
        );

        bytes32 expectedCodehash = r.engineImplementation.codehash;
        _setExpectedImplementationCodehashes(r.hookProxy);
        FakeDeploymentEngine staleEngineImplementation = new FakeDeploymentEngine();
        vm.etch(r.engineImplementation, address(staleEngineImplementation).code);
        bytes32 currentCodehash = r.engineImplementation.codehash;

        vm.prank(address(script));
        vm.expectRevert(
            abi.encodeWithSelector(
                DeployMemeverseHookProxy.ExistingEngineImplementationCodehashMismatch.selector,
                r.engineImplementation,
                expectedCodehash,
                currentCodehash
            )
        );
        script.deployHookProxy(
            IOutrunDeployer(address(outrunDeployer)),
            address(script),
            IPoolManager(POOL_MANAGER),
            HOOK_OWNER,
            HOOK_TREASURY,
            1
        );
    }

    function testSameNonceReuseRejectsStaleLPTokenImplementationBytecode() external {
        vm.etch(POOL_MANAGER, hex"01");
        outrunDeployer.transferOwnership(address(script));

        vm.prank(address(script));
        DeployMemeverseHookProxy.DeploymentResult memory r = script.deployHookProxy(
            IOutrunDeployer(address(outrunDeployer)),
            address(script),
            IPoolManager(POOL_MANAGER),
            HOOK_OWNER,
            HOOK_TREASURY,
            1
        );

        bytes32 expectedCodehash = r.lpTokenImplementation.codehash;
        _setExpectedImplementationCodehashes(r.hookProxy);
        FakeDeploymentHook staleImplementation = new FakeDeploymentHook();
        vm.etch(r.lpTokenImplementation, address(staleImplementation).code);
        bytes32 currentCodehash = r.lpTokenImplementation.codehash;

        vm.prank(address(script));
        vm.expectRevert(
            abi.encodeWithSelector(
                DeployMemeverseHookProxy.ExistingLPTokenImplementationCodehashMismatch.selector,
                r.lpTokenImplementation,
                expectedCodehash,
                currentCodehash
            )
        );
        script.deployHookProxy(
            IOutrunDeployer(address(outrunDeployer)),
            address(script),
            IPoolManager(POOL_MANAGER),
            HOOK_OWNER,
            HOOK_TREASURY,
            1
        );
    }

    function testSameNonceReuseRejectsSlotSpoofedHookProxyBytecode() external {
        vm.etch(POOL_MANAGER, hex"01");
        outrunDeployer.transferOwnership(address(script));

        vm.prank(address(script));
        DeployMemeverseHookProxy.DeploymentResult memory r = script.deployHookProxy(
            IOutrunDeployer(address(outrunDeployer)),
            address(script),
            IPoolManager(POOL_MANAGER),
            HOOK_OWNER,
            HOOK_TREASURY,
            1
        );

        _setExpectedImplementationCodehashes(r.hookProxy);
        bytes32 expectedProxyCodehash = keccak256(type(ERC1967Proxy).runtimeCode);
        IMemeverseDynamicFeeEngine engine = MemeverseUniswapHook(r.hookProxy).dynamicFeeEngine();
        FakeDeploymentHook fakeHook = new FakeDeploymentHook();
        vm.etch(r.hookProxy, address(fakeHook).code);
        FakeDeploymentHook(r.hookProxy).initializeFake(HOOK_OWNER, HOOK_TREASURY, IPoolManager(POOL_MANAGER), engine);
        vm.store(r.hookProxy, ERC1967Utils.IMPLEMENTATION_SLOT, bytes32(uint256(uint160(r.hookImplementation))));

        vm.prank(address(script));
        vm.expectRevert(
            abi.encodeWithSelector(
                DeployMemeverseHookProxy.ExistingHookProxyCodehashMismatch.selector,
                r.hookProxy,
                expectedProxyCodehash,
                r.hookProxy.codehash
            )
        );
        script.deployHookProxy(
            IOutrunDeployer(address(outrunDeployer)),
            address(script),
            IPoolManager(POOL_MANAGER),
            HOOK_OWNER,
            HOOK_TREASURY,
            1
        );
    }

    function testSameNonceReuseRejectsSlotSpoofedEngineProxyBytecode() external {
        vm.etch(POOL_MANAGER, hex"01");
        outrunDeployer.transferOwnership(address(script));

        vm.prank(address(script));
        DeployMemeverseHookProxy.DeploymentResult memory r = script.deployHookProxy(
            IOutrunDeployer(address(outrunDeployer)),
            address(script),
            IPoolManager(POOL_MANAGER),
            HOOK_OWNER,
            HOOK_TREASURY,
            1
        );

        _setExpectedImplementationCodehashes(r.hookProxy);
        bytes32 expectedProxyCodehash = keccak256(type(ERC1967Proxy).runtimeCode);
        FakeDeploymentEngine fakeEngine = new FakeDeploymentEngine();
        vm.etch(r.engineProxy, address(fakeEngine).code);
        FakeDeploymentEngine(r.engineProxy).initializeFake(r.hookProxy, r.hookProxy, IPoolManager(POOL_MANAGER));
        vm.store(r.engineProxy, ERC1967Utils.IMPLEMENTATION_SLOT, bytes32(uint256(uint160(r.engineImplementation))));

        vm.prank(address(script));
        vm.expectRevert(
            abi.encodeWithSelector(
                DeployMemeverseHookProxy.ExistingEngineProxyCodehashMismatch.selector,
                r.engineProxy,
                expectedProxyCodehash,
                r.engineProxy.codehash
            )
        );
        script.deployHookProxy(
            IOutrunDeployer(address(outrunDeployer)),
            address(script),
            IPoolManager(POOL_MANAGER),
            HOOK_OWNER,
            HOOK_TREASURY,
            1
        );
    }

    function testNewNonceDeploysNewHookProxyInsteadOfReusingOlderProxy() external {
        vm.etch(POOL_MANAGER, hex"01");
        outrunDeployer.transferOwnership(address(script));

        vm.prank(address(script));
        DeployMemeverseHookProxy.DeploymentResult memory first = script.deployHookProxy(
            IOutrunDeployer(address(outrunDeployer)),
            address(script),
            IPoolManager(POOL_MANAGER),
            HOOK_OWNER,
            HOOK_TREASURY,
            1
        );

        vm.prank(address(script));
        DeployMemeverseHookProxy.DeploymentResult memory second = script.deployHookProxy(
            IOutrunDeployer(address(outrunDeployer)),
            address(script),
            IPoolManager(POOL_MANAGER),
            HOOK_OWNER,
            HOOK_TREASURY,
            2
        );

        assertTrue(second.hookProxy != first.hookProxy);
        assertGt(second.hookProxy.code.length, 0);
        assertEq(
            MemeverseDynamicFeeEngine(address(MemeverseUniswapHook(second.hookProxy).dynamicFeeEngine())).owner(),
            second.hookProxy
        );
        assertEq(MemeverseUniswapHook(second.hookProxy).dynamicFeeEngine().authorizedHook(), second.hookProxy);
    }

    function testOccupiedGlobalFirstHookFlagAddressDoesNotBlockNonceProxyDeploy() external {
        vm.etch(POOL_MANAGER, hex"01");
        outrunDeployer.transferOwnership(address(script));

        address globalFirstProxy = script.getPredictedProxy(IOutrunDeployer(address(outrunDeployer)), address(script));
        vm.etch(globalFirstProxy, hex"01");

        vm.prank(address(script));
        DeployMemeverseHookProxy.DeploymentResult memory r = script.deployHookProxy(
            IOutrunDeployer(address(outrunDeployer)),
            address(script),
            IPoolManager(POOL_MANAGER),
            HOOK_OWNER,
            HOOK_TREASURY,
            1
        );

        assertTrue(r.hookProxy != globalFirstProxy);
        assertGt(r.hookProxy.code.length, 0);
        assertEq(
            MemeverseDynamicFeeEngine(address(MemeverseUniswapHook(r.hookProxy).dynamicFeeEngine())).owner(),
            r.hookProxy
        );
        assertEq(MemeverseUniswapHook(r.hookProxy).dynamicFeeEngine().authorizedHook(), r.hookProxy);
    }

    function testNonceScopedPredictedProxyMatchesDeployedProxy() external {
        if (vm.isContext(VmSafe.ForgeContext.Coverage)) return;

        vm.etch(POOL_MANAGER, hex"01");
        outrunDeployer.transferOwnership(address(script));

        uint256 nonce = 11;
        address predictedProxy = script.getPredictedProxy(
            IOutrunDeployer(address(outrunDeployer)),
            address(script),
            nonce,
            HOOK_OWNER,
            HOOK_TREASURY,
            IPoolManager(POOL_MANAGER)
        );

        vm.prank(address(script));
        DeployMemeverseHookProxy.DeploymentResult memory r = script.deployHookProxy(
            IOutrunDeployer(address(outrunDeployer)),
            address(script),
            IPoolManager(POOL_MANAGER),
            HOOK_OWNER,
            HOOK_TREASURY,
            nonce
        );

        assertEq(r.hookProxy, predictedProxy);
    }

    function testNonceScopedSelectedPredictionSkipsDirtyCandidate() external {
        vm.etch(POOL_MANAGER, hex"01");
        outrunDeployer.transferOwnership(address(script));

        uint256 nonce = 498;
        address firstCandidate =
            script.getPredictedProxy(IOutrunDeployer(address(outrunDeployer)), address(script), nonce);
        vm.etch(firstCandidate, hex"01");

        address predictedProxy = script.getPredictedProxy(
            IOutrunDeployer(address(outrunDeployer)),
            address(script),
            nonce,
            HOOK_OWNER,
            HOOK_TREASURY,
            IPoolManager(POOL_MANAGER)
        );

        vm.prank(address(script));
        DeployMemeverseHookProxy.DeploymentResult memory r = script.deployHookProxy(
            IOutrunDeployer(address(outrunDeployer)),
            address(script),
            IPoolManager(POOL_MANAGER),
            HOOK_OWNER,
            HOOK_TREASURY,
            nonce
        );

        assertTrue(predictedProxy != firstCandidate);
        assertEq(r.hookProxy, predictedProxy);
    }

    function testSpoofedSameNonceCandidateIsNotReused() external {
        vm.etch(POOL_MANAGER, hex"01");
        outrunDeployer.transferOwnership(address(script));

        uint256 nonce = 1;
        (, address spoofedProxy,) = script.exposedSelectProxySalt(
            IOutrunDeployer(address(outrunDeployer)),
            address(script),
            nonce,
            HOOK_OWNER,
            HOOK_TREASURY,
            IPoolManager(POOL_MANAGER)
        );

        FakeDeploymentEngine fakeEngineTemplate = new FakeDeploymentEngine();
        FakeDeploymentHook fakeHookTemplate = new FakeDeploymentHook();
        address fakeEngine = address(0x2005);
        vm.etch(fakeEngine, address(fakeEngineTemplate).code);
        FakeDeploymentEngine(fakeEngine).initializeFake(spoofedProxy, spoofedProxy, IPoolManager(POOL_MANAGER));
        vm.etch(spoofedProxy, address(fakeHookTemplate).code);
        FakeDeploymentHook(spoofedProxy)
            .initializeFake(
                HOOK_OWNER, HOOK_TREASURY, IPoolManager(POOL_MANAGER), IMemeverseDynamicFeeEngine(fakeEngine)
            );

        vm.prank(address(script));
        DeployMemeverseHookProxy.DeploymentResult memory r = script.deployHookProxy(
            IOutrunDeployer(address(outrunDeployer)),
            address(script),
            IPoolManager(POOL_MANAGER),
            HOOK_OWNER,
            HOOK_TREASURY,
            nonce
        );

        assertTrue(r.hookProxy != spoofedProxy);
        assertGt(r.hookProxy.code.length, 0);
    }

    function testDeployProxyRejectsExistingProxyWhenBoundEngineOwnerIsNotProxy() external {
        vm.etch(POOL_MANAGER, hex"01");
        outrunDeployer.transferOwnership(address(script));

        vm.prank(address(script));
        DeployMemeverseHookProxy.DeploymentResult memory r = script.deployHookProxy(
            IOutrunDeployer(address(outrunDeployer)),
            address(script),
            IPoolManager(POOL_MANAGER),
            HOOK_OWNER,
            HOOK_TREASURY,
            1
        );

        address engine = address(MemeverseUniswapHook(r.hookProxy).dynamicFeeEngine());
        _setExpectedImplementationCodehashes(r.hookProxy);
        bytes32 ownableOwnerSlot = 0x9016d09d72d40fdae2fd8ceac6b6234c7706214fd39c1cd1e609a0528c199300;
        vm.store(engine, ownableOwnerSlot, bytes32(uint256(uint160(HOOK_OWNER))));

        vm.prank(address(script));
        vm.expectRevert(
            abi.encodeWithSelector(
                DeployMemeverseHookProxy.ExistingEngineOwnerMismatch.selector, engine, r.hookProxy, HOOK_OWNER
            )
        );
        script.deployHookProxy(
            IOutrunDeployer(address(outrunDeployer)),
            address(script),
            IPoolManager(POOL_MANAGER),
            HOOK_OWNER,
            HOOK_TREASURY,
            1
        );
    }

    function testDeployProxyRejectsInvalidExistingProxyBeforeConsumingNonceSalts() external {
        vm.etch(POOL_MANAGER, hex"01");
        outrunDeployer.transferOwnership(address(script));

        vm.prank(address(script));
        DeployMemeverseHookProxy.DeploymentResult memory first = script.deployHookProxy(
            IOutrunDeployer(address(outrunDeployer)),
            address(script),
            IPoolManager(POOL_MANAGER),
            HOOK_OWNER,
            HOOK_TREASURY,
            1
        );

        address engine = address(MemeverseUniswapHook(first.hookProxy).dynamicFeeEngine());
        bytes32 ownableOwnerSlot = 0x9016d09d72d40fdae2fd8ceac6b6234c7706214fd39c1cd1e609a0528c199300;
        vm.store(engine, ownableOwnerSlot, bytes32(uint256(uint160(HOOK_OWNER))));

        uint256 nextNonce = 2;
        (, address nextEngineImpl) =
            script.exposedComputeEngineImpl(IOutrunDeployer(address(outrunDeployer)), address(script), nextNonce);
        (, address nextEngine) =
            script.exposedComputeEngineProxy(IOutrunDeployer(address(outrunDeployer)), address(script), nextNonce);
        (, address nextHookImpl) =
            script.exposedComputeHookImpl(IOutrunDeployer(address(outrunDeployer)), address(script), nextNonce);

        vm.prank(address(script));
        DeployMemeverseHookProxy.DeploymentResult memory second = script.deployHookProxy(
            IOutrunDeployer(address(outrunDeployer)),
            address(script),
            IPoolManager(POOL_MANAGER),
            HOOK_OWNER,
            HOOK_TREASURY,
            nextNonce
        );

        assertTrue(second.hookProxy != first.hookProxy);
        assertGt(nextEngineImpl.code.length, 0);
        assertGt(nextEngine.code.length, 0);
        assertGt(nextHookImpl.code.length, 0);
        assertEq(
            MemeverseDynamicFeeEngine(address(MemeverseUniswapHook(second.hookProxy).dynamicFeeEngine())).owner(),
            second.hookProxy
        );
    }

    function testDeployProxyRejectsConsumedCreate3Salt() external {
        vm.etch(POOL_MANAGER, hex"01");
        outrunDeployer.transferOwnership(address(script));

        // Simulate a previous failed deploy: the CREATE3 minimal proxy was deployed
        // (CREATE2 succeeded) but the inner CREATE failed (e.g. initialization reverted).
        // The final proxy address has no code, but the CREATE3 proxy is occupied.
        (bytes32 salt,,) = script.exposedSelectProxySalt(
            IOutrunDeployer(address(outrunDeployer)),
            address(script),
            1,
            HOOK_OWNER,
            HOOK_TREASURY,
            IPoolManager(POOL_MANAGER)
        );
        bytes32 hashedSalt = keccak256(abi.encodePacked(address(script), salt));
        address create3Proxy = keccak256(
                abi.encodePacked(bytes1(0xFF), address(outrunDeployer), hashedSalt, CREATE3_PROXY_BYTECODE_HASH)
            ).fromLast20Bytes();
        vm.etch(create3Proxy, hex"01");

        // Re-running with the same nonce should revert with a clear error indicating
        // the CREATE3 salt is consumed, not the opaque "DEPLOYMENT_FAILED" from solmate.
        vm.prank(address(script));
        vm.expectRevert(
            abi.encodeWithSelector(DeployMemeverseHookProxy.Create3SaltConsumed.selector, salt, create3Proxy)
        );
        script.deployHookProxy(
            IOutrunDeployer(address(outrunDeployer)),
            address(script),
            IPoolManager(POOL_MANAGER),
            HOOK_OWNER,
            HOOK_TREASURY,
            1
        );
    }

    function testDeployProxyRejectsConsumedHookProxySaltBeforeIntermediateDeploys() external {
        vm.etch(POOL_MANAGER, hex"01");
        outrunDeployer.transferOwnership(address(script));

        uint256 nonce = 1;
        (bytes32 hookProxySalt,,) = script.exposedSelectProxySalt(
            IOutrunDeployer(address(outrunDeployer)),
            address(script),
            nonce,
            HOOK_OWNER,
            HOOK_TREASURY,
            IPoolManager(POOL_MANAGER)
        );
        address hookCreate3Proxy = _create3ProxyAddress(address(script), hookProxySalt);
        vm.etch(hookCreate3Proxy, hex"01");

        (bytes32 engineImplSalt, address engineImpl) =
            script.exposedComputeEngineImpl(IOutrunDeployer(address(outrunDeployer)), address(script), nonce);
        (, address engine) =
            script.exposedComputeEngineProxy(IOutrunDeployer(address(outrunDeployer)), address(script), nonce);
        (, address hookImpl) =
            script.exposedComputeHookImpl(IOutrunDeployer(address(outrunDeployer)), address(script), nonce);

        // If hook proxy salt validation is late, this occupied engine CREATE3 proxy is hit first.
        vm.etch(_create3ProxyAddress(address(script), engineImplSalt), hex"01");

        vm.prank(address(script));
        vm.expectRevert(
            abi.encodeWithSelector(
                DeployMemeverseHookProxy.Create3SaltConsumed.selector, hookProxySalt, hookCreate3Proxy
            )
        );
        script.deployHookProxy(
            IOutrunDeployer(address(outrunDeployer)),
            address(script),
            IPoolManager(POOL_MANAGER),
            HOOK_OWNER,
            HOOK_TREASURY,
            nonce
        );

        assertEq(engineImpl.code.length, 0);
        assertEq(engine.code.length, 0);
        assertEq(hookImpl.code.length, 0);
    }

    function testDeployProxyRejectsOccupiedEngineImplementationBeforeEngineProxySaltUse() external {
        vm.etch(POOL_MANAGER, hex"01");
        outrunDeployer.transferOwnership(address(script));

        uint256 nonce = 1;
        (, address engineImpl) =
            script.exposedComputeEngineImpl(IOutrunDeployer(address(outrunDeployer)), address(script), nonce);
        (bytes32 engineSalt,) =
            script.exposedComputeEngineProxy(IOutrunDeployer(address(outrunDeployer)), address(script), nonce);
        address engineCreate3Proxy = _create3ProxyAddress(address(script), engineSalt);

        vm.etch(engineImpl, hex"01");

        vm.prank(address(script));
        vm.expectRevert(
            abi.encodeWithSelector(
                DeployMemeverseHookProxy.ExistingIntermediateDeploymentNotReusable.selector, engineImpl
            )
        );
        script.deployHookProxy(
            IOutrunDeployer(address(outrunDeployer)),
            address(script),
            IPoolManager(POOL_MANAGER),
            HOOK_OWNER,
            HOOK_TREASURY,
            nonce
        );

        assertEq(engineCreate3Proxy.code.length, 0);
    }

    function testDeployProxyRejectsOccupiedEngineProxyBeforeHookImplementationSaltUse() external {
        vm.etch(POOL_MANAGER, hex"01");
        outrunDeployer.transferOwnership(address(script));

        uint256 nonce = 1;
        (, address engine) =
            script.exposedComputeEngineProxy(IOutrunDeployer(address(outrunDeployer)), address(script), nonce);
        (bytes32 hookImplSalt,) =
            script.exposedComputeHookImpl(IOutrunDeployer(address(outrunDeployer)), address(script), nonce);
        address hookImplCreate3Proxy = _create3ProxyAddress(address(script), hookImplSalt);

        vm.etch(engine, hex"01");

        vm.prank(address(script));
        vm.expectRevert(
            abi.encodeWithSelector(DeployMemeverseHookProxy.ExistingIntermediateDeploymentNotReusable.selector, engine)
        );
        script.deployHookProxy(
            IOutrunDeployer(address(outrunDeployer)),
            address(script),
            IPoolManager(POOL_MANAGER),
            HOOK_OWNER,
            HOOK_TREASURY,
            nonce
        );

        assertEq(hookImplCreate3Proxy.code.length, 0);
    }

    function testDeployProxyRejectsOccupiedHookImplementationBeforeHookProxySaltUse() external {
        vm.etch(POOL_MANAGER, hex"01");
        outrunDeployer.transferOwnership(address(script));

        uint256 nonce = 1;
        (bytes32 hookProxySalt,,) = script.exposedSelectProxySalt(
            IOutrunDeployer(address(outrunDeployer)),
            address(script),
            nonce,
            HOOK_OWNER,
            HOOK_TREASURY,
            IPoolManager(POOL_MANAGER)
        );
        address hookCreate3Proxy = _create3ProxyAddress(address(script), hookProxySalt);
        (, address hookImpl) =
            script.exposedComputeHookImpl(IOutrunDeployer(address(outrunDeployer)), address(script), nonce);

        vm.etch(hookImpl, hex"01");

        vm.prank(address(script));
        vm.expectRevert(
            abi.encodeWithSelector(
                DeployMemeverseHookProxy.ExistingIntermediateDeploymentNotReusable.selector, hookImpl
            )
        );
        script.deployHookProxy(
            IOutrunDeployer(address(outrunDeployer)),
            address(script),
            IPoolManager(POOL_MANAGER),
            HOOK_OWNER,
            HOOK_TREASURY,
            nonce
        );

        assertEq(hookCreate3Proxy.code.length, 0);
    }

    function testDeployEngineImplRejectsConsumedCreate3Salt() external {
        vm.etch(POOL_MANAGER, hex"01");
        outrunDeployer.transferOwnership(address(script));

        uint256 nonce = 1;
        (bytes32 salt,) =
            script.exposedComputeEngineImpl(IOutrunDeployer(address(outrunDeployer)), address(script), nonce);
        address create3Proxy = _create3ProxyAddress(address(script), salt);
        vm.etch(create3Proxy, hex"01");

        vm.expectRevert(
            abi.encodeWithSelector(
                DeployMemeverseHookProxy.EngineImplementationCreate3SaltConsumed.selector, salt, create3Proxy
            )
        );
        script.exposedDeployEngineImpl(
            IOutrunDeployer(address(outrunDeployer)), address(script), nonce, IPoolManager(POOL_MANAGER)
        );
    }

    function testDeployLPTokenImplRejectsConsumedCreate3Salt() external {
        vm.etch(POOL_MANAGER, hex"01");
        outrunDeployer.transferOwnership(address(script));

        uint256 nonce = 1;
        (bytes32 salt,) =
            script.exposedComputeLpTokenImpl(IOutrunDeployer(address(outrunDeployer)), address(script), nonce);
        address create3Proxy = _create3ProxyAddress(address(script), salt);
        vm.etch(create3Proxy, hex"01");

        vm.expectRevert(
            abi.encodeWithSelector(
                DeployMemeverseHookProxy.LPTokenImplementationCreate3SaltConsumed.selector, salt, create3Proxy
            )
        );
        script.exposedDeployLpTokenImpl(IOutrunDeployer(address(outrunDeployer)), address(script), nonce);
    }

    function testDeployPreorderSettlementExecutorRejectsConsumedCreate3Salt() external {
        vm.etch(POOL_MANAGER, hex"01");
        outrunDeployer.transferOwnership(address(script));

        uint256 nonce = 1;
        (bytes32 salt,) = script.exposedComputePreorderSettlementExecutor(
            IOutrunDeployer(address(outrunDeployer)), address(script), nonce
        );
        address create3Proxy = _create3ProxyAddress(address(script), salt);
        vm.etch(create3Proxy, hex"01");

        vm.expectRevert(
            abi.encodeWithSelector(
                DeployMemeverseHookProxy.PreorderSettlementExecutorCreate3SaltConsumed.selector, salt, create3Proxy
            )
        );
        script.exposedDeployPreorderSettlementExecutor(
            IOutrunDeployer(address(outrunDeployer)), address(script), nonce, address(script)
        );
    }

    function testDeployEngineProxyRejectsConsumedCreate3Salt() external {
        vm.etch(POOL_MANAGER, hex"01");
        outrunDeployer.transferOwnership(address(script));

        uint256 nonce = 1;
        address engineImpl = address(0x2001);
        address engineOwner = address(0x2002);
        address authorizedHook = address(0x2003);
        (bytes32 salt,) =
            script.exposedComputeEngineProxy(IOutrunDeployer(address(outrunDeployer)), address(script), nonce);
        address create3Proxy = _create3ProxyAddress(address(script), salt);
        vm.etch(create3Proxy, hex"01");

        vm.expectRevert(
            abi.encodeWithSelector(DeployMemeverseHookProxy.EngineProxyCreate3SaltConsumed.selector, salt, create3Proxy)
        );
        script.exposedDeployEngineProxy(
            IOutrunDeployer(address(outrunDeployer)), address(script), nonce, engineImpl, engineOwner, authorizedHook
        );
    }

    function testDeployHookImplRejectsConsumedCreate3Salt() external {
        vm.etch(POOL_MANAGER, hex"01");
        outrunDeployer.transferOwnership(address(script));

        uint256 nonce = 1;
        (bytes32 salt,) =
            script.exposedComputeHookImpl(IOutrunDeployer(address(outrunDeployer)), address(script), nonce);
        address create3Proxy = _create3ProxyAddress(address(script), salt);
        vm.etch(create3Proxy, hex"01");

        vm.expectRevert(
            abi.encodeWithSelector(
                DeployMemeverseHookProxy.HookImplementationCreate3SaltConsumed.selector, salt, create3Proxy
            )
        );
        script.exposedDeployHookImpl(
            IOutrunDeployer(address(outrunDeployer)), address(script), nonce, IPoolManager(POOL_MANAGER)
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
            HOOK_TREASURY,
            1
        );
    }

    function _create3ProxyAddress(address deployerNamespace, bytes32 salt)
        internal
        view
        returns (address create3Proxy)
    {
        bytes32 hashedSalt = keccak256(abi.encodePacked(deployerNamespace, salt));
        create3Proxy = keccak256(
                abi.encodePacked(bytes1(0xFF), address(outrunDeployer), hashedSalt, CREATE3_PROXY_BYTECODE_HASH)
            ).fromLast20Bytes();
    }

    function _setExpectedImplementationCodehashes(address proxy) internal {
        address hookImplementation = address(uint160(uint256(vm.load(proxy, ERC1967Utils.IMPLEMENTATION_SLOT))));
        address engine = address(MemeverseUniswapHook(proxy).dynamicFeeEngine());
        address engineImplementation = address(uint160(uint256(vm.load(engine, ERC1967Utils.IMPLEMENTATION_SLOT))));
        vm.setEnv("EXPECTED_HOOK_IMPLEMENTATION_CODEHASH", vm.toString(hookImplementation.codehash));
        vm.setEnv("EXPECTED_ENGINE_IMPLEMENTATION_CODEHASH", vm.toString(engineImplementation.codehash));
        address lpTokenImplementation = MemeverseUniswapHook(proxy).lpTokenImplementation();
        vm.setEnv("EXPECTED_LP_TOKEN_IMPLEMENTATION_CODEHASH", vm.toString(lpTokenImplementation.codehash));
        address preorderSettlementExecutor = address(MemeverseUniswapHook(proxy).preorderSettlementExecutor());
        vm.setEnv("EXPECTED_PREORDER_SETTLEMENT_EXECUTOR_CODEHASH", vm.toString(preorderSettlementExecutor.codehash));
    }
}
