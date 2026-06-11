// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {MemeverseScript} from "../../script/MemeverseScript.s.sol";

contract MockScriptLauncher {
    address public polend;
    address public polSplitter;
    address public memeverseSwapRouter;
    address public memeverseUniswapHook;
    mapping(address => FundMetaData) internal metadata;

    struct FundMetaData {
        uint256 minTotalFund;
        uint256 fundBasedAmount;
    }

    function setPolend(address polend_) external {
        polend = polend_;
    }

    function setPolSplitter(address polSplitter_) external {
        polSplitter = polSplitter_;
    }

    function setMemeverseSwapRouter(address router_) external {
        memeverseSwapRouter = router_;
    }

    function setMemeverseUniswapHook(address hook_) external {
        memeverseUniswapHook = hook_;
    }

    function setFundMetaData(address uAsset, uint256 minTotalFund, uint256 fundBasedAmount) external {
        metadata[uAsset] = FundMetaData({minTotalFund: minTotalFund, fundBasedAmount: fundBasedAmount});
    }

    function fundMetaDatas(address uAsset) external view returns (uint256 minTotalFund, uint256 fundBasedAmount) {
        FundMetaData memory data = metadata[uAsset];
        return (data.minTotalFund, data.fundBasedAmount);
    }
}

contract MockScriptPOLend {
    address public launcher;
    address public splitter;
    mapping(address => DustState) internal dustStates;

    struct DustState {
        uint128 reserve;
        uint128 maxReserve;
    }

    constructor(address launcher_, address splitter_) {
        launcher = launcher_;
        splitter = splitter_;
    }

    function setSplitter(address splitter_) external {
        splitter = splitter_;
    }

    function setSettlementDustState(address uAsset, uint128 reserve, uint128 maxReserve) external {
        dustStates[uAsset] = DustState({reserve: reserve, maxReserve: maxReserve});
    }

    function settlementDustStates(address uAsset) external view returns (uint128 reserve, uint128 maxReserve) {
        DustState memory state = dustStates[uAsset];
        return (state.reserve, state.maxReserve);
    }
}

contract MockScriptPOLSplitter {
    address public launcher;
    address public polend;

    constructor(address launcher_, address polend_) {
        launcher = launcher_;
        polend = polend_;
    }

    function setPolend(address polend_) external {
        polend = polend_;
    }
}

contract MockScriptPOLSplitterWithoutPolendGetter {
    address public launcher;

    constructor(address launcher_) {
        launcher = launcher_;
    }
}

contract MockScriptHook {
    address public launcher;
    address public poolInitializer;

    constructor(address launcher_, address poolInitializer_) {
        launcher = launcher_;
        poolInitializer = poolInitializer_;
    }
}

contract MockScriptRouter {
    address public hook;

    constructor(address hook_) {
        hook = hook_;
    }
}

contract MockScriptRegistrationCenter {
    mapping(address => bool) public supportedUAssets;

    function setSupportedUAsset(address uAsset, bool isSupported) external {
        supportedUAssets[uAsset] = isSupported;
    }
}

contract MemeverseScriptHarness is MemeverseScript {
    function setDeploymentAddresses(address ueth, address uusd, address launcher, address polend, address polSplitter)
        external
    {
        UETH = ueth;
        UUSD = uusd;
        MEMEVERSE_LAUNCHER = launcher;
        POLEND = polend;
        POLSPLITTER = polSplitter;
    }

    function requireDeploymentReady() external view {
        _requireDeploymentReady();
    }

    function requireSwapReady(address router, address hook) external view {
        _requireSwapReady(router, hook);
    }

    function openSupportedUAssetsAfterReadinessForTest(address registrationCenter, address router, address hook)
        external
    {
        _openSupportedUAssetsAfterReadiness(registrationCenter, router, hook);
    }

    function optionalEnvAddressForTest(string memory name) external view returns (address) {
        return _optionalEnvAddress(name);
    }

    function setBroadcastSender(address sender) external {
        deployer = sender;
    }
}

contract MemeverseScriptTest is Test {
    address internal constant UETH = address(0x1001);
    address internal constant UUSD = address(0x1002);
    uint256 internal constant POLSPLITTER_STORAGE_LOCATION =
        0xab504a6dee30096d32ccac13a30a002829c5eeb4c38a0196ed16a6c4e9faca00;

    MemeverseScriptHarness internal script;
    MockScriptLauncher internal launcher;
    MockScriptPOLend internal polend;
    MockScriptPOLSplitter internal splitter;

    function setUp() external {
        script = new MemeverseScriptHarness();
        launcher = new MockScriptLauncher();
        splitter = new MockScriptPOLSplitter(address(launcher), address(0));
        polend = new MockScriptPOLend(address(launcher), address(splitter));
        splitter.setPolend(address(polend));

        launcher.setPolend(address(polend));
        launcher.setPolSplitter(address(splitter));
        launcher.setFundMetaData(UETH, 1, 1);
        launcher.setFundMetaData(UUSD, 1, 1);
        script.setDeploymentAddresses(UETH, UUSD, address(launcher), address(polend), address(splitter));
    }

    function testReadinessRevertsWhenUethReserveMaxIsZero() external {
        polend.setSettlementDustState(UETH, 0, 0);
        polend.setSettlementDustState(UUSD, 0, 1);

        vm.expectRevert("UETH_RESERVE_NOT_READY");
        script.requireDeploymentReady();
    }

    function testSwapReadinessRejectsHookFlagsAndAcceptsExpectedFlags() external {
        address badHook = address(uint160(0x28cd));
        address goodHook = address(uint160(0x28cc));

        MockScriptRouter badRouter = new MockScriptRouter(badHook);
        MockScriptRouter goodRouter = new MockScriptRouter(goodHook);
        MockScriptHook hookImpl = new MockScriptHook(address(launcher), address(goodRouter));

        vm.etch(badHook, address(hookImpl).code);
        vm.etch(goodHook, address(hookImpl).code);
        vm.mockCall(badHook, abi.encodeWithSignature("launcher()"), abi.encode(address(launcher)));
        vm.mockCall(badHook, abi.encodeWithSignature("poolInitializer()"), abi.encode(address(badRouter)));
        vm.mockCall(goodHook, abi.encodeWithSignature("launcher()"), abi.encode(address(launcher)));
        vm.mockCall(goodHook, abi.encodeWithSignature("poolInitializer()"), abi.encode(address(goodRouter)));
        _mockEngineOnHook(goodHook);

        launcher.setMemeverseSwapRouter(address(badRouter));
        launcher.setMemeverseUniswapHook(badHook);

        vm.expectRevert("HOOK_FLAGS_NOT_READY");
        script.requireSwapReady(address(badRouter), badHook);

        launcher.setMemeverseSwapRouter(address(goodRouter));
        launcher.setMemeverseUniswapHook(goodHook);

        script.requireSwapReady(address(goodRouter), goodHook);
    }

    function testSwapReadinessRevertsWhenEngineCodeMissing() external {
        (address readyRouter, address readyHook) = _configureReadySwap();
        // Overwrite dynamicFeeEngine() to return an address with no code.
        vm.mockCall(readyHook, abi.encodeWithSignature("dynamicFeeEngine()"), abi.encode(address(0xDEAD)));

        vm.expectRevert("ENGINE_CODE_NOT_READY");
        script.requireSwapReady(readyRouter, readyHook);
    }

    function testSwapReadinessRevertsWhenEngineAuthorizedHookMismatch() external {
        (address readyRouter, address readyHook) = _configureReadySwap();
        address engineAddr = address(0xAEEE);
        // Override authorizedHook to a different address.
        vm.mockCall(engineAddr, abi.encodeWithSignature("authorizedHook()"), abi.encode(address(0xBAD)));

        vm.expectRevert("ENGINE_AUTHORIZED_HOOK_NOT_READY");
        script.requireSwapReady(readyRouter, readyHook);
    }

    function testSwapReadinessRevertsWhenEngineOwnerMismatch() external {
        (address readyRouter, address readyHook) = _configureReadySwap();
        address engineAddr = address(0xAEEE);
        // Override owner to a different address.
        vm.mockCall(engineAddr, abi.encodeWithSignature("owner()"), abi.encode(address(0xBAD)));

        vm.expectRevert("ENGINE_OWNER_NOT_READY");
        script.requireSwapReady(readyRouter, readyHook);
    }

    function testSwapReadinessRevertsWhenEnginePoolManagerMismatch() external {
        (address readyRouter, address readyHook) = _configureReadySwap();
        address engineAddr = address(0xAEEE);
        // Override poolManager to a different address.
        vm.mockCall(engineAddr, abi.encodeWithSignature("poolManager()"), abi.encode(address(0xBAD)));

        vm.expectRevert("ENGINE_POOL_MANAGER_NOT_READY");
        script.requireSwapReady(readyRouter, readyHook);
    }

    function testReadinessFallsBackToSplitterStorageWhenPolendGetterIsMissing() external {
        MockScriptPOLSplitterWithoutPolendGetter splitterWithoutGetter =
            new MockScriptPOLSplitterWithoutPolendGetter(address(launcher));
        bytes32 polendSlot = bytes32(POLSPLITTER_STORAGE_LOCATION + 3);

        launcher.setPolSplitter(address(splitterWithoutGetter));
        polend.setSplitter(address(splitterWithoutGetter));
        polend.setSettlementDustState(UETH, 0, 1);
        polend.setSettlementDustState(UUSD, 0, 1);
        script.setDeploymentAddresses(UETH, UUSD, address(launcher), address(polend), address(splitterWithoutGetter));

        vm.store(address(splitterWithoutGetter), polendSlot, bytes32(uint256(uint160(address(polend)))));
        script.requireDeploymentReady();

        vm.store(address(splitterWithoutGetter), polendSlot, bytes32(uint256(uint160(address(0xBEEF)))));

        vm.expectRevert("POLSPLITTER_POLEND_NOT_READY");
        script.requireDeploymentReady();
    }

    function testOpenSupportedUAssetsAfterReadinessDoesNotOpenWhenReadinessFails() external {
        MockScriptRegistrationCenter center = new MockScriptRegistrationCenter();
        (address readyRouter, address readyHook) = _configureReadySwap();
        polend.setSettlementDustState(UETH, 0, 0);
        polend.setSettlementDustState(UUSD, 0, 1);

        vm.expectRevert("UETH_RESERVE_NOT_READY");
        script.openSupportedUAssetsAfterReadinessForTest(address(center), readyRouter, readyHook);

        assertFalse(center.supportedUAssets(UETH));
        assertFalse(center.supportedUAssets(UUSD));
    }

    function testOpenSupportedUAssetsAfterReadinessRejectsMissingRegistrationCenterCode() external {
        (address readyRouter, address readyHook) = _configureReadySwap();
        polend.setSettlementDustState(UETH, 0, 1);
        polend.setSettlementDustState(UUSD, 0, 1);

        vm.expectRevert("REGISTRATION_CENTER_CODE_NOT_READY");
        script.openSupportedUAssetsAfterReadinessForTest(address(0xCAFE), readyRouter, readyHook);
    }

    function testOpenSupportedUAssetsAfterReadinessOpensWhenReadinessPasses() external {
        MockScriptRegistrationCenter center = new MockScriptRegistrationCenter();
        (address readyRouter, address readyHook) = _configureReadySwap();
        polend.setSettlementDustState(UETH, 0, 1);
        polend.setSettlementDustState(UUSD, 0, 1);

        script.openSupportedUAssetsAfterReadinessForTest(address(center), readyRouter, readyHook);

        assertTrue(center.supportedUAssets(UETH));
        assertTrue(center.supportedUAssets(UUSD));
    }

    function testPublicOpenSupportedUAssetsLoadsEnvAndOpensWhenReady() external {
        MemeverseScriptHarness publicEntryScript = new MemeverseScriptHarness();
        publicEntryScript.setBroadcastSender(address(this));
        MockScriptRegistrationCenter center = new MockScriptRegistrationCenter();
        (address readyRouter, address readyHook) = _configureReadySwap();
        polend.setSettlementDustState(UETH, 0, 1);
        polend.setSettlementDustState(UUSD, 0, 1);
        _setReadinessEnv(address(launcher), address(polend), address(splitter));

        publicEntryScript.openSupportedUAssetsAfterReadiness(address(center), readyRouter, readyHook);

        assertTrue(center.supportedUAssets(UETH));
        assertTrue(center.supportedUAssets(UUSD));
    }

    function testOptionalEnvAddressReturnsZeroWhenMissing() external view {
        assertEq(script.optionalEnvAddressForTest("MEMEVERSE_SCRIPT_OPTIONAL_ADDRESS_MISSING_FOR_TEST"), address(0));
    }

    function testOptionalEnvAddressReturnsEnvValueWhenPresent() external {
        vm.setEnv("MEMEVERSE_SCRIPT_OPTIONAL_ADDRESS_PRESENT_FOR_TEST", "0x0000000000000000000000000000000000001234");

        assertEq(
            script.optionalEnvAddressForTest("MEMEVERSE_SCRIPT_OPTIONAL_ADDRESS_PRESENT_FOR_TEST"), address(0x1234)
        );
    }

    function _configureReadySwap() internal returns (address readyRouter, address readyHook) {
        readyHook = address(uint160(0x28cc));
        MockScriptRouter router = new MockScriptRouter(readyHook);
        MockScriptHook hookImpl = new MockScriptHook(address(launcher), address(router));
        vm.etch(readyHook, address(hookImpl).code);
        vm.mockCall(readyHook, abi.encodeWithSignature("launcher()"), abi.encode(address(launcher)));
        vm.mockCall(readyHook, abi.encodeWithSignature("poolInitializer()"), abi.encode(address(router)));
        _mockEngineOnHook(readyHook);
        launcher.setMemeverseSwapRouter(address(router));
        launcher.setMemeverseUniswapHook(readyHook);
        return (address(router), readyHook);
    }

    function _mockEngineOnHook(address readyHook) internal returns (address engineAddr) {
        engineAddr = address(0xAEEE);
        // vm.etch does not copy storage, so mock each getter individually.
        vm.mockCall(readyHook, abi.encodeWithSignature("dynamicFeeEngine()"), abi.encode(engineAddr));
        vm.mockCall(readyHook, abi.encodeWithSignature("poolManager()"), abi.encode(address(0xBBBB)));
        vm.mockCall(engineAddr, abi.encodeWithSignature("authorizedHook()"), abi.encode(readyHook));
        vm.mockCall(engineAddr, abi.encodeWithSignature("owner()"), abi.encode(readyHook));
        vm.mockCall(engineAddr, abi.encodeWithSignature("poolManager()"), abi.encode(address(0xBBBB)));
    }

    function _setReadinessEnv(address launcher_, address polend_, address splitter_) internal {
        vm.setEnv("UETH", vm.toString(UETH));
        vm.setEnv("UUSD", vm.toString(UUSD));
        vm.setEnv("MEMEVERSE_LAUNCHER", vm.toString(launcher_));
        vm.setEnv("POLEND", vm.toString(polend_));
        vm.setEnv("POLSPLITTER", vm.toString(splitter_));
    }
}
