// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {UlnConfig} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import {IOAppCore} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppCore.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {
    IMessageLibManager,
    SetConfigParam
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";

import "./BaseScript.s.sol";
import {Memecoin} from "../src/token/Memecoin.sol";
import {IOutrunDeployer} from "./IOutrunDeployer.sol";
import {MemePol} from "../src/token/MemePol.sol";
import {MemecoinYieldVault} from "../src/yield/MemecoinYieldVault.sol";
import {MemeverseProxyDeployer} from "../src/verse/deployment/MemeverseProxyDeployer.sol";
import {YieldDispatcher} from "../src/verse/YieldDispatcher.sol";
import {MemeverseRegistrarAtLocal} from "../src/verse/registration/MemeverseRegistrarAtLocal.sol";
import {MemeverseRegistrationCenter} from "../src/verse/registration/MemeverseRegistrationCenter.sol";
import {MemeverseRegistrarOmnichain} from "../src/verse/registration/MemeverseRegistrarOmnichain.sol";
import {MemeverseLauncher, IMemeverseLauncher} from "../src/verse/MemeverseLauncher.sol";
import {OmnichainMemecoinStaker} from "../src/interoperation/OmnichainMemecoinStaker.sol";
import {LzEndpointRegistry} from "../src/common/omnichain/LzEndpointRegistry.sol";
import {ILzEndpointRegistry} from "../src/common/omnichain/interfaces/ILzEndpointRegistry.sol";
import {MemecoinDaoGovernorUpgradeable} from "../src/governance/MemecoinDaoGovernorUpgradeable.sol";
import {IMemeverseRegistrationCenter} from "../src/verse/interfaces/IMemeverseRegistrationCenter.sol";
import {MemeverseOmnichainInteroperation} from "../src/interoperation/MemeverseOmnichainInteroperation.sol";
import {GovernanceCycleIncentivizerUpgradeable} from "../src/governance/GovernanceCycleIncentivizerUpgradeable.sol";

contract MemeverseScript is BaseScript {
    using OptionsBuilder for bytes;

    uint256 public constant DAY = 24 * 3600;
    uint160 internal constant MEMEVERSE_HOOK_FLAGS = 0x28cc;
    uint160 internal constant UNISWAP_V4_HOOK_FLAG_MASK = 0x3fff;
    bytes32 internal constant POLSPLITTER_STORAGE_LOCATION =
        0xab504a6dee30096d32ccac13a30a002829c5eeb4c38a0196ed16a6c4e9faca00;

    address internal owner;
    address internal factory;
    address internal router;

    address internal UUSD;
    address internal UETH;
    address internal OUTRUN_DEPLOYER;

    address internal MEMECOIN_IMPLEMENTATION;
    address internal POL_IMPLEMENTATION;
    address internal MEMECOIN_VAULT_IMPLEMENTATION;
    address internal MEMECOIN_GOVERNOR_IMPLEMENTATION;
    address internal CYCLE_INCENTIVIZER_IMPLEMENTATION;

    address internal MEMEVERSE_REGISTRATION_CENTER;
    address internal MEMEVERSE_COMMON_INFO;
    address internal MEMEVERSE_REGISTRAR;
    address internal MEMEVERSE_PROXY_DEPLOYER;
    address internal MEMEVERSE_LAUNCHER;
    address internal MEMEVERSE_YIELD_DISPATCHER;
    address internal OMNICHAIN_MEMECOIN_STAKER;
    address internal POLEND;
    address internal POLSPLITTER;
    address internal MEMEVERSE_SWAP_ROUTER;
    address internal MEMEVERSE_UNISWAP_HOOK;

    uint32[] public omnichainIds;
    mapping(uint32 chainId => address) public endpoints;
    mapping(uint32 chainId => uint32) public endpointIds;

    /// @notice Executes run.
    /// @dev See the implementation for behavior details.
    function run() public broadcaster {
        _loadScriptEnv();

        // OutrunTODO Testnet id
        omnichainIds = [97, 84532, 421614, 43113, 80002, 57054, 168587773, 534351, 11155111];
        _chainsInit();

        // _getDeployedImplementation(2);

        // _getDeployedRegistrationCenter(2);

        // _getDeployedLzEndpointRegistry(2);
        // _getDeployedMemeverseRegistrar(2);
        // _getDeployedMemeverseProxyDeployer(2);
        // _getDeployedYieldDispatcher(2);
        // _getDeployedMemeverseOmnichainInteroperation(2);
        // _getDeployedOmnichainMemecoinStaker(2);
        // _getDeployedMemeverseLauncher(2);

        // Update OutrunRouter after deployed
        // _deployMemeverseLauncher(2);                 // optimizer-runs: 200
        // _deployMemecoinGovernorImplementation(2);    // optimizer-runs: 2000
        // _deployMemecoinPOLImplementation(2);         // optimizer-runs: 5000
        // _deployImplementation(2);

        // _deployLzEndpointRegistry(2);
        // _deployMemeverseRegistrar(2);
        // _deployMemeverseProxyDeployer(2);
        // _deployYieldDispatcher(2);
        // _deployMemeverseOmnichainInteroperation(2);
        // _deployOmnichainMemecoinStaker(2);

        // _deployRegistrationCenter(2);
        // openSupportedUAssetsAfterReadiness(
        //     MEMEVERSE_REGISTRATION_CENTER,
        //     MEMEVERSE_SWAP_ROUTER,
        //     MEMEVERSE_UNISWAP_HOOK
        // );
    }

    function _loadScriptEnv() internal {
        owner = vm.envAddress("OWNER");
        factory = vm.envAddress("OUTRUN_AMM_FACTORY");
        router = vm.envAddress("LIQUIDITY_ROUTER");
        OUTRUN_DEPLOYER = vm.envAddress("OUTRUN_DEPLOYER");

        MEMECOIN_IMPLEMENTATION = vm.envAddress("MEMECOIN_IMPLEMENTATION");
        POL_IMPLEMENTATION = vm.envAddress("POL_IMPLEMENTATION");
        MEMECOIN_VAULT_IMPLEMENTATION = vm.envAddress("MEMECOIN_VAULT_IMPLEMENTATION");
        MEMECOIN_GOVERNOR_IMPLEMENTATION = vm.envAddress("MEMECOIN_GOVERNOR_IMPLEMENTATION");
        CYCLE_INCENTIVIZER_IMPLEMENTATION = vm.envAddress("CYCLE_INCENTIVIZER_IMPLEMENTATION");

        MEMEVERSE_REGISTRATION_CENTER = vm.envAddress("MEMEVERSE_REGISTRATION_CENTER");
        MEMEVERSE_COMMON_INFO = _envAddressWithFallback("LZ_ENDPOINT_REGISTRY", "MEMEVERSE_COMMON_INFO");
        MEMEVERSE_REGISTRAR = vm.envAddress("MEMEVERSE_REGISTRAR");
        MEMEVERSE_PROXY_DEPLOYER = vm.envAddress("MEMEVERSE_PROXY_DEPLOYER");
        MEMEVERSE_YIELD_DISPATCHER = vm.envAddress("MEMEVERSE_YIELD_DISPATCHER");
        OMNICHAIN_MEMECOIN_STAKER = vm.envAddress("OMNICHAIN_MEMECOIN_STAKER");
        MEMEVERSE_SWAP_ROUTER = _optionalEnvAddress("MEMEVERSE_SWAP_ROUTER");
        MEMEVERSE_UNISWAP_HOOK = _optionalEnvAddress("MEMEVERSE_UNISWAP_HOOK");
        _loadReadinessEnv();
    }

    function _loadReadinessEnv() internal {
        UUSD = vm.envAddress("UUSD");
        UETH = vm.envAddress("UETH");
        MEMEVERSE_LAUNCHER = vm.envAddress("MEMEVERSE_LAUNCHER");
        POLEND = vm.envAddress("POLEND");
        POLSPLITTER = vm.envAddress("POLSPLITTER");
    }

    function _chainsInit() internal {
        endpoints[97] = vm.envAddress("BSC_TESTNET_ENDPOINT");
        endpoints[84532] = vm.envAddress("BASE_SEPOLIA_ENDPOINT");
        endpoints[421614] = vm.envAddress("ARBITRUM_SEPOLIA_ENDPOINT");
        endpoints[43113] = vm.envAddress("AVALANCHE_FUJI_ENDPOINT");
        endpoints[80002] = vm.envAddress("POLYGON_AMOY_ENDPOINT");
        endpoints[57054] = vm.envAddress("SONIC_BLAZE_ENDPOINT");
        endpoints[168587773] = vm.envAddress("BLAST_SEPOLIA_ENDPOINT");
        endpoints[534351] = vm.envAddress("SCROLL_SEPOLIA_ENDPOINT");
        endpoints[11155111] = vm.envAddress("ETHEREUM_SEPOLIA_ENDPOINT");
        // endpoints[10143] = vm.envAddress("MONAD_TESTNET_ENDPOINT");
        // endpoints[11155420] = vm.envAddress("OPTIMISTIC_SEPOLIA_ENDPOINT");
        // endpoints[300] = vm.envAddress("ZKSYNC_SEPOLIA_ENDPOINT");
        // endpoints[59141] = vm.envAddress("LINEA_SEPOLIA_ENDPOINT");

        endpointIds[97] = uint32(vm.envUint("BSC_TESTNET_EID"));
        endpointIds[84532] = uint32(vm.envUint("BASE_SEPOLIA_EID"));
        endpointIds[421614] = uint32(vm.envUint("ARBITRUM_SEPOLIA_EID"));
        endpointIds[43113] = uint32(vm.envUint("AVALANCHE_FUJI_EID"));
        endpointIds[80002] = uint32(vm.envUint("POLYGON_AMOY_EID"));
        endpointIds[57054] = uint32(vm.envUint("SONIC_BLAZE_EID"));
        endpointIds[168587773] = uint32(vm.envUint("BLAST_SEPOLIA_EID"));
        endpointIds[534351] = uint32(vm.envUint("SCROLL_SEPOLIA_EID"));
        endpointIds[11155111] = uint32(vm.envUint("ETHEREUM_SEPOLIA_EID"));
        // endpointIds[10143] = uint32(vm.envUint("MONAD_TESTNET_EID"));
        // endpointIds[11155420] = uint32(vm.envUint("OPTIMISTIC_SEPOLIA_EID"));
        // endpointIds[300] = uint32(vm.envUint("ZKSYNC_SEPOLIA_EID"));
        // endpointIds[59141] = uint32(vm.envUint("LINEA_SEPOLIA_EID"));
    }

    function _getDeployedImplementation(uint256 nonce) internal view {
        bytes32 memecoinSalt = keccak256(abi.encodePacked("MemecoinImplementation", nonce));
        bytes32 memecoinPOLSalt = keccak256(abi.encodePacked("MemecoinPOLImplementation", nonce));
        bytes32 memecoinYieldVaultSalt = keccak256(abi.encodePacked("MemecoinYieldVaultImplementation", nonce));
        bytes32 memecoinDaoGovernorSalt = keccak256(abi.encodePacked("MemecoinDaoGovernorImplementation", nonce));
        bytes32 cycleIncentivizerSalt = keccak256(abi.encodePacked("GovernanceCycleIncentivizerImplementation", nonce));

        address deployedMemecoinImplementation = IOutrunDeployer(OUTRUN_DEPLOYER).getDeployed(owner, memecoinSalt);
        address deployedMemecoinPOLImplementation = IOutrunDeployer(OUTRUN_DEPLOYER).getDeployed(owner, memecoinPOLSalt);
        address deployedMemecoinYieldVaultImplementation =
            IOutrunDeployer(OUTRUN_DEPLOYER).getDeployed(owner, memecoinYieldVaultSalt);
        address deployedMemecoinDaoGovernorImplementation =
            IOutrunDeployer(OUTRUN_DEPLOYER).getDeployed(owner, memecoinDaoGovernorSalt);
        address deployedCycleIncentivizerImplementation =
            IOutrunDeployer(OUTRUN_DEPLOYER).getDeployed(owner, cycleIncentivizerSalt);

        console.log("MemecoinImplementation deployed on %s", deployedMemecoinImplementation);
        console.log("MemecoinPOLImplementation deployed on %s", deployedMemecoinPOLImplementation);
        console.log("MemecoinYieldVaultImplementation deployed on %s", deployedMemecoinYieldVaultImplementation);
        console.log("MemecoinDaoGovernorImplementation deployed on %s", deployedMemecoinDaoGovernorImplementation);
        console.log("GovernanceCycleIncentivizerImplementation deployed on %s", deployedCycleIncentivizerImplementation);
    }

    function _getDeployedRegistrationCenter(uint256 nonce) internal view {
        bytes32 salt = keccak256(abi.encodePacked("MemeverseRegistrationCenter", nonce));
        address deployed = IOutrunDeployer(OUTRUN_DEPLOYER).getDeployed(owner, salt);

        console.log("MemeverseRegistrationCenter deployed on %s", deployed);
    }

    function _getDeployedLzEndpointRegistry(uint256 nonce) internal view {
        bytes32 salt = keccak256(abi.encodePacked("LzEndpointRegistry", nonce));
        address deployed = IOutrunDeployer(OUTRUN_DEPLOYER).getDeployed(owner, salt);

        console.log("LzEndpointRegistry deployed on %s", deployed);
    }

    function _getDeployedMemeverseRegistrar(uint256 nonce) internal view {
        bytes32 salt = keccak256(abi.encodePacked("MemeverseRegistrar", nonce));
        address deployed = IOutrunDeployer(OUTRUN_DEPLOYER).getDeployed(owner, salt);

        console.log("MemeverseRegistrar deployed on %s", deployed);
    }

    function _getDeployedMemeverseProxyDeployer(uint256 nonce) internal view {
        bytes32 salt = keccak256(abi.encodePacked("MemeverseProxyDeployer", nonce));
        address deployed = IOutrunDeployer(OUTRUN_DEPLOYER).getDeployed(owner, salt);

        console.log("MemeverseProxyDeployer deployed on %s", deployed);
    }

    function _getDeployedMemeverseLauncher(uint256 nonce) internal view {
        bytes32 salt = keccak256(abi.encodePacked("MemeverseLauncher", nonce));
        address deployed = IOutrunDeployer(OUTRUN_DEPLOYER).getDeployed(owner, salt);

        console.log("MemeverseLauncher deployed on %s", deployed);
    }

    function _getDeployedYieldDispatcher(uint256 nonce) internal view {
        bytes32 salt = keccak256(abi.encodePacked("YieldDispatcher", nonce));
        address deployed = IOutrunDeployer(OUTRUN_DEPLOYER).getDeployed(owner, salt);

        console.log("YieldDispatcher deployed on %s", deployed);
    }

    function _getDeployedMemeverseOmnichainInteroperation(uint256 nonce) internal view {
        bytes32 salt = keccak256(abi.encodePacked("MemeverseOmnichainInteroperation", nonce));
        address deployed = IOutrunDeployer(OUTRUN_DEPLOYER).getDeployed(owner, salt);

        console.log("MemeverseOmnichainInteroperation deployed on %s", deployed);
    }

    function _getDeployedOmnichainMemecoinStaker(uint256 nonce) internal view {
        bytes32 salt = keccak256(abi.encodePacked("OmnichainMemecoinStaker", nonce));
        address deployed = IOutrunDeployer(OUTRUN_DEPLOYER).getDeployed(owner, salt);

        console.log("OmnichainMemecoinStaker deployed on %s", deployed);
    }

    /**
     *
     */

    function _deployImplementation(uint256 nonce) internal {
        bytes32 memecoinSalt = keccak256(abi.encodePacked("MemecoinImplementation", nonce));
        bytes32 memecoinYieldVaultSalt = keccak256(abi.encodePacked("MemecoinYieldVaultImplementation", nonce));
        bytes32 incentivizerSalt = keccak256(abi.encodePacked("GovernanceCycleIncentivizerImplementation", nonce));

        bytes memory memecoinCreationCode =
            abi.encodePacked(type(Memecoin).creationCode, abi.encode(endpoints[uint32(block.chainid)]));

        address memecoinImplementation = IOutrunDeployer(OUTRUN_DEPLOYER).deploy(memecoinSalt, memecoinCreationCode);
        address memecoinYieldVaultImplementation =
            IOutrunDeployer(OUTRUN_DEPLOYER).deploy(memecoinYieldVaultSalt, type(MemecoinYieldVault).creationCode);
        address cycleIncentivizerImplementation = IOutrunDeployer(OUTRUN_DEPLOYER)
            .deploy(incentivizerSalt, type(GovernanceCycleIncentivizerUpgradeable).creationCode);

        console.log("MemecoinImplementation deployed on %s", memecoinImplementation);
        console.log("MemecoinYieldVaultImplementation deployed on %s", memecoinYieldVaultImplementation);
        console.log("GovernanceCycleIncentivizerImplementation deployed on %s", cycleIncentivizerImplementation);
    }

    function _deployMemecoinPOLImplementation(uint256 nonce) internal {
        bytes32 memecoinPOLSalt = keccak256(abi.encodePacked("MemecoinPOLImplementation", nonce));
        bytes memory memecoinPOLCreationCode =
            abi.encodePacked(type(MemePol).creationCode, abi.encode(endpoints[uint32(block.chainid)]));
        address memecoinPOLImplementation =
            IOutrunDeployer(OUTRUN_DEPLOYER).deploy(memecoinPOLSalt, memecoinPOLCreationCode);

        console.log("MemecoinPOLImplementation deployed on %s", memecoinPOLImplementation);
    }

    function _deployMemecoinGovernorImplementation(uint256 nonce) internal {
        bytes32 governorSalt = keccak256(abi.encodePacked("MemecoinDaoGovernorImplementation", nonce));
        address memecoinDaoGovernorImplementation =
            IOutrunDeployer(OUTRUN_DEPLOYER).deploy(governorSalt, type(MemecoinDaoGovernorUpgradeable).creationCode);

        console.log("MemecoinDaoGovernorImplementation deployed on %s", memecoinDaoGovernorImplementation);
    }

    function _deployRegistrationCenter(uint256 nonce) internal {
        bytes32 salt = keccak256(abi.encodePacked("MemeverseRegistrationCenter", nonce));
        address localEndpoint = endpoints[uint32(block.chainid)];
        bytes memory creationCode = abi.encodePacked(
            type(MemeverseRegistrationCenter).creationCode,
            abi.encode(owner, localEndpoint, MEMEVERSE_REGISTRAR, MEMEVERSE_COMMON_INFO)
        );
        address centerAddr = IOutrunDeployer(OUTRUN_DEPLOYER).deploy(salt, creationCode);

        uint256 chainCount = omnichainIds.length;
        for (uint32 i = 0; i < chainCount; i++) {
            uint32 chainId = omnichainIds[i];
            uint32 endpointId = endpointIds[chainId];
            if (block.chainid == chainId) continue;

            IOAppCore(centerAddr).setPeer(endpointId, bytes32(abi.encode(MEMEVERSE_REGISTRAR)));

            UlnConfig memory config = UlnConfig({
                confirmations: 1,
                requiredDVNCount: 0,
                optionalDVNCount: 0,
                optionalDVNThreshold: 0,
                requiredDVNs: new address[](0),
                optionalDVNs: new address[](0)
            });
            SetConfigParam[] memory params = new SetConfigParam[](1);
            params[0] = SetConfigParam({eid: endpointId, configType: 2, config: abi.encode(config)});

            address sendLib = IMessageLibManager(localEndpoint).getSendLibrary(centerAddr, endpointId);
            (address receiveLib,) = IMessageLibManager(localEndpoint).getReceiveLibrary(centerAddr, endpointId);
            IMessageLibManager(localEndpoint).setConfig(centerAddr, sendLib, params);
            IMessageLibManager(localEndpoint).setConfig(centerAddr, receiveLib, params);
        }

        IMemeverseRegistrationCenter(centerAddr).setRegisterGasLimit(1000000);
        IMemeverseRegistrationCenter(centerAddr).setDurationDaysRange(1, 3);

        console.log("MemeverseRegistrationCenter deployed on %s", centerAddr);
    }

    function _deployLzEndpointRegistry(uint256 nonce) internal {
        bytes memory creationCode = abi.encodePacked(type(LzEndpointRegistry).creationCode, abi.encode(owner));
        bytes32 salt = keccak256(abi.encodePacked("LzEndpointRegistry", nonce));
        address lzEndpointRegistryAddr = IOutrunDeployer(OUTRUN_DEPLOYER).deploy(salt, creationCode);

        uint256 length = omnichainIds.length;
        ILzEndpointRegistry.LzEndpointIdPair[] memory lzEndpointPairs =
            new ILzEndpointRegistry.LzEndpointIdPair[](length);
        for (uint32 i = 0; i < length; i++) {
            uint32 chainId = omnichainIds[i];
            uint32 endpointId = endpointIds[chainId];
            lzEndpointPairs[i] = ILzEndpointRegistry.LzEndpointIdPair({chainId: chainId, endpointId: endpointId});
        }
        ILzEndpointRegistry(lzEndpointRegistryAddr).setLzEndpointIds(lzEndpointPairs);

        console.log("LzEndpointRegistry deployed on %s", lzEndpointRegistryAddr);
    }

    function _deployMemeverseRegistrar(uint256 nonce) internal {
        bytes memory encodedArgs;
        bytes memory creationBytecode;
        address localEndpoint = endpoints[uint32(block.chainid)];
        if (block.chainid == vm.envUint("BSC_TESTNET_CHAINID")) {
            encodedArgs = abi.encode(owner, MEMEVERSE_REGISTRATION_CENTER, MEMEVERSE_LAUNCHER, MEMEVERSE_COMMON_INFO);
            creationBytecode = type(MemeverseRegistrarAtLocal).creationCode;
        } else {
            encodedArgs = abi.encode(
                owner,
                localEndpoint,
                MEMEVERSE_LAUNCHER,
                MEMEVERSE_COMMON_INFO,
                uint32(vm.envUint("BSC_TESTNET_EID")),
                uint32(vm.envUint("BSC_TESTNET_CHAINID")),
                150000,
                750000,
                250000
            );
            creationBytecode = type(MemeverseRegistrarOmnichain).creationCode;
        }

        bytes32 salt = keccak256(abi.encodePacked("MemeverseRegistrar", nonce));
        bytes memory creationCode = abi.encodePacked(creationBytecode, encodedArgs);
        address memeverseRegistrarAddr = IOutrunDeployer(OUTRUN_DEPLOYER).deploy(salt, creationCode);
        console.log("MemeverseRegistrar deployed on %s", memeverseRegistrarAddr);

        if (block.chainid != vm.envUint("BSC_TESTNET_CHAINID")) {
            uint32 centerEndpointId = uint32(vm.envUint("BSC_TESTNET_EID"));
            IOAppCore(memeverseRegistrarAddr)
                .setPeer(centerEndpointId, bytes32(abi.encode(MEMEVERSE_REGISTRATION_CENTER)));

            UlnConfig memory config = UlnConfig({
                confirmations: 1,
                requiredDVNCount: 0,
                optionalDVNCount: 0,
                optionalDVNThreshold: 0,
                requiredDVNs: new address[](0),
                optionalDVNs: new address[](0)
            });
            SetConfigParam[] memory params = new SetConfigParam[](1);
            params[0] = SetConfigParam({eid: centerEndpointId, configType: 2, config: abi.encode(config)});

            address sendLib = IMessageLibManager(localEndpoint).getSendLibrary(memeverseRegistrarAddr, centerEndpointId);
            (address receiveLib,) =
                IMessageLibManager(localEndpoint).getReceiveLibrary(memeverseRegistrarAddr, centerEndpointId);
            IMessageLibManager(localEndpoint).setConfig(memeverseRegistrarAddr, sendLib, params);
            IMessageLibManager(localEndpoint).setConfig(memeverseRegistrarAddr, receiveLib, params);
        }
    }

    function _deployMemeverseProxyDeployer(uint256 nonce) internal {
        bytes memory creationCode = abi.encodePacked(
            type(MemeverseProxyDeployer).creationCode,
            abi.encode(
                owner,
                MEMEVERSE_LAUNCHER,
                MEMECOIN_IMPLEMENTATION,
                POL_IMPLEMENTATION,
                MEMECOIN_VAULT_IMPLEMENTATION,
                MEMECOIN_GOVERNOR_IMPLEMENTATION,
                CYCLE_INCENTIVIZER_IMPLEMENTATION,
                50,
                10,
                7 days,
                1000,
                6000
            )
        );

        bytes32 salt = keccak256(abi.encodePacked("MemeverseProxyDeployer", nonce));
        address memeverseProxyDeployer = IOutrunDeployer(OUTRUN_DEPLOYER).deploy(salt, creationCode);

        console.log("MemeverseProxyDeployer deployed on %s", memeverseProxyDeployer);
    }

    function _deployMemeverseLauncher(uint256 nonce) internal {
        address localEndpoint = endpoints[uint32(block.chainid)];
        bytes memory creationCode = _buildMemeverseLauncherCreationCode(localEndpoint);
        bytes32 salt = keccak256(abi.encodePacked("MemeverseLauncher", nonce));
        address memeverseLauncherAddr = IOutrunDeployer(OUTRUN_DEPLOYER).deploy(salt, creationCode);
        IMemeverseLauncher(memeverseLauncherAddr).setFundMetaData(UETH, 1e19, 1000000);
        IMemeverseLauncher(memeverseLauncherAddr).setFundMetaData(UUSD, 50000 * 1e18, 200);

        console.log("MemeverseLauncher deployed on %s", memeverseLauncherAddr);
    }

    function _buildMemeverseLauncherCreationCode(address localEndpoint) internal view returns (bytes memory) {
        require(localEndpoint != address(0), "ZERO_LOCAL_ENDPOINT");
        require(MEMEVERSE_REGISTRAR != address(0), "ZERO_MEMEVERSE_REGISTRAR");
        require(MEMEVERSE_PROXY_DEPLOYER != address(0), "ZERO_MEMEVERSE_PROXY_DEPLOYER");
        require(MEMEVERSE_YIELD_DISPATCHER != address(0), "ZERO_MEMEVERSE_YIELD_DISPATCHER");
        require(MEMEVERSE_COMMON_INFO != address(0), "ZERO_LZ_ENDPOINT_REGISTRY");
        require(POLEND != address(0), "ZERO_POLEND");
        require(POLSPLITTER != address(0), "ZERO_POLSPLITTER");
        require(UETH != address(0), "ZERO_UETH");
        require(UUSD != address(0), "ZERO_UUSD");

        bytes memory encodedArgs = abi.encode(
            owner,
            localEndpoint,
            MEMEVERSE_REGISTRAR,
            MEMEVERSE_PROXY_DEPLOYER,
            MEMEVERSE_YIELD_DISPATCHER,
            MEMEVERSE_COMMON_INFO,
            POLEND,
            POLSPLITTER,
            25,
            115000,
            135000,
            2500,
            7 days
        );
        return abi.encodePacked(type(MemeverseLauncher).creationCode, encodedArgs);
    }

    function _envAddressWithFallback(string memory primary, string memory fallbackName)
        internal
        view
        returns (address)
    {
        if (vm.envExists(primary)) return vm.envAddress(primary);
        return vm.envAddress(fallbackName);
    }

    function _optionalEnvAddress(string memory name) internal view returns (address) {
        if (!vm.envExists(name)) return address(0);
        return vm.envAddress(name);
    }

    function _openSupportedUAssetsAfterReadiness(address registrationCenter, address swapRouter, address hook)
        internal
    {
        _requireContractCode(registrationCenter, "REGISTRATION_CENTER_CODE_NOT_READY");
        _requireDeploymentReady();
        _requireSwapReady(swapRouter, hook);

        IMemeverseRegistrationCenter(registrationCenter).setSupportedUAsset(UETH, true);
        IMemeverseRegistrationCenter(registrationCenter).setSupportedUAsset(UUSD, true);
    }

    function openSupportedUAssetsAfterReadiness(address registrationCenter, address swapRouter, address hook)
        public
        broadcaster
    {
        _loadReadinessEnv();
        _openSupportedUAssetsAfterReadiness(registrationCenter, swapRouter, hook);
    }

    function _requireDeploymentReady() internal view {
        _requireContractCode(MEMEVERSE_LAUNCHER, "LAUNCHER_CODE_NOT_READY");
        _requireContractCode(POLEND, "POLEND_CODE_NOT_READY");
        _requireContractCode(POLSPLITTER, "POLSPLITTER_CODE_NOT_READY");

        require(_readAddress(MEMEVERSE_LAUNCHER, "polend()") == POLEND, "LAUNCHER_POLEND_NOT_READY");
        require(_readAddress(MEMEVERSE_LAUNCHER, "polSplitter()") == POLSPLITTER, "LAUNCHER_POLSPLITTER_NOT_READY");
        require(_readAddress(POLEND, "launcher()") == MEMEVERSE_LAUNCHER, "POLEND_LAUNCHER_NOT_READY");
        require(_readAddress(POLEND, "splitter()") == POLSPLITTER, "POLEND_SPLITTER_NOT_READY");
        require(_readAddress(POLSPLITTER, "launcher()") == MEMEVERSE_LAUNCHER, "POLSPLITTER_LAUNCHER_NOT_READY");
        require(_readPolSplitterPolend() == POLEND, "POLSPLITTER_POLEND_NOT_READY");

        _requireReserveReady(UETH, "UETH_RESERVE_NOT_READY");
        _requireReserveReady(UUSD, "UUSD_RESERVE_NOT_READY");
        _requireFundMetaDataReady(UETH, "UETH_FUND_METADATA_NOT_READY");
        _requireFundMetaDataReady(UUSD, "UUSD_FUND_METADATA_NOT_READY");
    }

    function _requireSwapReady(address swapRouter, address hook) internal view {
        _requireContractCode(swapRouter, "ROUTER_CODE_NOT_READY");
        _requireContractCode(hook, "HOOK_CODE_NOT_READY");
        require(_hookFlags(hook) == MEMEVERSE_HOOK_FLAGS, "HOOK_FLAGS_NOT_READY");

        require(_readAddress(MEMEVERSE_LAUNCHER, "memeverseSwapRouter()") == swapRouter, "LAUNCHER_ROUTER_NOT_READY");
        require(_readAddress(MEMEVERSE_LAUNCHER, "memeverseUniswapHook()") == hook, "LAUNCHER_HOOK_NOT_READY");
        require(_readAddress(swapRouter, "hook()") == hook, "ROUTER_HOOK_NOT_READY");
        require(_readAddress(hook, "launcher()") == MEMEVERSE_LAUNCHER, "HOOK_LAUNCHER_NOT_READY");
        require(_readAddress(hook, "poolInitializer()") == swapRouter, "HOOK_POOL_INITIALIZER_NOT_READY");
    }

    function _hookFlags(address hook) internal pure returns (uint160) {
        return uint160(hook) & UNISWAP_V4_HOOK_FLAG_MASK;
    }

    function _requireReserveReady(address uAsset, string memory errorMessage) internal view {
        (, uint128 maxReserve) = _readSettlementDustState(uAsset);
        // POLend refuses market registration until this cap is configured.
        require(maxReserve > 0, errorMessage);
    }

    function _requireFundMetaDataReady(address uAsset, string memory errorMessage) internal view {
        (uint256 minTotalFund, uint256 fundBasedAmount) = _readFundMetaData(uAsset);
        // Registration must stay closed until launcher funding thresholds are usable.
        require(minTotalFund > 0 && fundBasedAmount > 0, errorMessage);
    }

    function _requireContractCode(address target, string memory errorMessage) internal view {
        require(target.code.length > 0, errorMessage);
    }

    function _readAddress(address target, string memory signature) internal view returns (address value) {
        (bool success, bytes memory data) = target.staticcall(abi.encodeWithSignature(signature));
        require(success && data.length >= 32, "STATICCALL_ADDRESS_FAILED");
        value = abi.decode(data, (address));
    }

    function _readPolSplitterPolend() internal view returns (address value) {
        (bool success, bytes memory data) = POLSPLITTER.staticcall(abi.encodeWithSignature("polend()"));
        if (success && data.length >= 32) return abi.decode(data, (address));

        // POLSplitter stores `polend` in its ERC-7201 namespace at base + 3.
        bytes32 rawValue = vm.load(POLSPLITTER, bytes32(uint256(POLSPLITTER_STORAGE_LOCATION) + 3));
        return address(uint160(uint256(rawValue)));
    }

    function _readSettlementDustState(address uAsset) internal view returns (uint128 reserve, uint128 maxReserve) {
        (bool success, bytes memory data) =
            POLEND.staticcall(abi.encodeWithSignature("settlementDustStates(address)", uAsset));
        require(success && data.length >= 64, "SETTLEMENT_DUST_STATE_NOT_READY");
        return abi.decode(data, (uint128, uint128));
    }

    function _readFundMetaData(address uAsset) internal view returns (uint256 minTotalFund, uint256 fundBasedAmount) {
        (bool success, bytes memory data) =
            MEMEVERSE_LAUNCHER.staticcall(abi.encodeWithSignature("fundMetaDatas(address)", uAsset));
        require(success && data.length >= 64, "FUND_METADATA_NOT_READY");
        return abi.decode(data, (uint256, uint256));
    }

    function _deployYieldDispatcher(uint256 nonce) internal {
        address localEndpoint = endpoints[uint32(block.chainid)];

        bytes memory creationCode =
            abi.encodePacked(type(YieldDispatcher).creationCode, abi.encode(owner, localEndpoint, MEMEVERSE_LAUNCHER));

        bytes32 salt = keccak256(abi.encodePacked("YieldDispatcher", nonce));
        address memeverseOFTDispatcher = IOutrunDeployer(OUTRUN_DEPLOYER).deploy(salt, creationCode);

        console.log("YieldDispatcher deployed on %s", memeverseOFTDispatcher);
    }

    function _deployMemeverseOmnichainInteroperation(uint256 nonce) internal {
        bytes memory creationCode = abi.encodePacked(
            type(MemeverseOmnichainInteroperation).creationCode,
            abi.encode(owner, MEMEVERSE_COMMON_INFO, MEMEVERSE_LAUNCHER, OMNICHAIN_MEMECOIN_STAKER, 115000, 135000)
        );

        bytes32 salt = keccak256(abi.encodePacked("MemeverseOmnichainInteroperation", nonce));
        address staker = IOutrunDeployer(OUTRUN_DEPLOYER).deploy(salt, creationCode);

        console.log("MemeverseOmnichainInteroperation deployed on %s", staker);
    }

    function _deployOmnichainMemecoinStaker(uint256 nonce) internal {
        address localEndpoint = endpoints[uint32(block.chainid)];

        bytes memory creationCode =
            abi.encodePacked(type(OmnichainMemecoinStaker).creationCode, abi.encode(localEndpoint));

        bytes32 salt = keccak256(abi.encodePacked("OmnichainMemecoinStaker", nonce));
        address staker = IOutrunDeployer(OUTRUN_DEPLOYER).deploy(salt, creationCode);

        console.log("OmnichainMemecoinStaker deployed on %s", staker);
    }
}
