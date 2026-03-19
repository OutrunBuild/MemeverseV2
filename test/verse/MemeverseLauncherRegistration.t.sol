// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {MemeverseLauncher} from "../../src/verse/MemeverseLauncher.sol";
import {IMemeverseLauncher} from "../../src/verse/interfaces/IMemeverseLauncher.sol";

contract MockLauncherRegistrationToken {
    string public name;
    string public symbol;
    address public memeverseLauncher;
    address public memecoin;
    address public delegate;
    mapping(uint32 eid => bytes32 peer) public peers;

    /// @notice Initialize.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @param name_ See implementation.
    /// @param symbol_ See implementation.
    /// @param launcher_ See implementation.
    /// @param delegate_ See implementation.
    function initialize(string memory name_, string memory symbol_, address launcher_, address delegate_) external {
        name = name_;
        symbol = symbol_;
        memeverseLauncher = launcher_;
        delegate = delegate_;
    }

    /// @notice Initialize.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @param name_ See implementation.
    /// @param symbol_ See implementation.
    /// @param memecoin_ See implementation.
    /// @param launcher_ See implementation.
    /// @param delegate_ See implementation.
    function initialize(
        string memory name_,
        string memory symbol_,
        address memecoin_,
        address launcher_,
        address delegate_
    ) external {
        name = name_;
        symbol = symbol_;
        memecoin = memecoin_;
        memeverseLauncher = launcher_;
        delegate = delegate_;
    }

    /// @notice Set peer.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @param eid See implementation.
    /// @param peer See implementation.
    function setPeer(uint32 eid, bytes32 peer) external {
        peers[eid] = peer;
    }
}

contract MockGovernorForExternalInfo {}

contract TestableMemeverseLauncherRegistration is MemeverseLauncher {
    constructor(
        address _owner,
        address _localLzEndpoint,
        address _memeverseRegistrar,
        address _memeverseProxyDeployer,
        address _oftDispatcher,
        address _lzEndpointRegistry,
        uint256 _executorRewardRate,
        uint128 _oftReceiveGasLimit,
        uint128 _oftDispatcherGasLimit
    )
        MemeverseLauncher(
            _owner,
            _localLzEndpoint,
            _memeverseRegistrar,
            _memeverseProxyDeployer,
            _oftDispatcher,
            _lzEndpointRegistry,
            _executorRewardRate,
            _oftReceiveGasLimit,
            _oftDispatcherGasLimit
        )
    {}

    /// @notice Set memeverse for test.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @param verseId See implementation.
    /// @param verse See implementation.
    function setMemeverseForTest(uint256 verseId, Memeverse memory verse) external {
        memeverses[verseId] = verse;
    }
}

contract MockLauncherRegistrationProxyDeployer {
    address public nextMemecoin;
    address public nextPol;

    /// @notice Set next deployments.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @param memecoin_ See implementation.
    /// @param pol_ See implementation.
    function setNextDeployments(address memecoin_, address pol_) external {
        nextMemecoin = memecoin_;
        nextPol = pol_;
    }

    /// @notice Deploy memecoin.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @param uniqueId See implementation.
    /// @return memecoin See implementation.
    function deployMemecoin(uint256 uniqueId) external view returns (address memecoin) {
        uniqueId;
        return nextMemecoin;
    }

    /// @notice Deploy pol.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @param uniqueId See implementation.
    /// @return pol See implementation.
    function deployPOL(uint256 uniqueId) external view returns (address pol) {
        uniqueId;
        return nextPol;
    }
}

contract MockLauncherRegistrationRegistry {
    mapping(uint32 chainId => uint32 endpointId) public lzEndpointIdOfChain;

    /// @notice Set endpoint.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @param chainId See implementation.
    /// @param endpointId See implementation.
    function setEndpoint(uint32 chainId, uint32 endpointId) external {
        lzEndpointIdOfChain[chainId] = endpointId;
    }
}

contract MemeverseLauncherRegistrationTest is Test {
    address internal constant OWNER = address(0xABCD);
    address internal constant REGISTRAR = address(0xBEEF);
    uint32 internal constant REMOTE_CHAIN_ID = 202;
    uint32 internal constant REMOTE_EID = 302;

    TestableMemeverseLauncherRegistration internal launcher;
    MockLauncherRegistrationProxyDeployer internal proxyDeployer;
    MockLauncherRegistrationRegistry internal registry;
    MockLauncherRegistrationToken internal memecoin;
    MockLauncherRegistrationToken internal pol;

    /// @notice Set up.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function setUp() external {
        launcher = new TestableMemeverseLauncherRegistration(
            OWNER, address(0x1), REGISTRAR, address(0), address(0x4), address(0), 25, 115_000, 135_000
        );
        proxyDeployer = new MockLauncherRegistrationProxyDeployer();
        registry = new MockLauncherRegistrationRegistry();
        memecoin = new MockLauncherRegistrationToken();
        pol = new MockLauncherRegistrationToken();

        proxyDeployer.setNextDeployments(address(memecoin), address(pol));

        vm.startPrank(OWNER);
        launcher.setMemeverseProxyDeployer(address(proxyDeployer));
        launcher.setLzEndpointRegistry(address(registry));
        vm.stopPrank();
    }

    /// @notice Test register memeverse only registrar.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function testRegisterMemeverseOnlyRegistrar() external {
        vm.expectRevert(IMemeverseLauncher.PermissionDenied.selector);
        launcher.registerMemeverse(
            "Memeverse",
            "MEME",
            1,
            uint128(block.timestamp + 1 days),
            uint128(block.timestamp + 2 days),
            _omnichainIds(),
            address(0x7777),
            true
        );
    }

    /// @notice Test register memeverse reverts on invalid remote omnichain id.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function testRegisterMemeverseRevertsOnInvalidRemoteOmnichainId() external {
        uint32[] memory omnichainIds = _omnichainIds();

        vm.prank(REGISTRAR);
        vm.expectRevert(abi.encodeWithSelector(IMemeverseLauncher.InvalidOmnichainId.selector, REMOTE_CHAIN_ID));
        launcher.registerMemeverse(
            "Memeverse",
            "MEME",
            1,
            uint128(block.timestamp + 1 days),
            uint128(block.timestamp + 2 days),
            omnichainIds,
            address(0x7777),
            true
        );
    }

    /// @notice Test register memeverse stores verse and configures remote peers.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function testRegisterMemeverseStoresVerseAndConfiguresRemotePeers() external {
        registry.setEndpoint(REMOTE_CHAIN_ID, REMOTE_EID);
        uint256 uniqueId = 7;
        uint32[] memory omnichainIds = _omnichainIds();

        vm.prank(REGISTRAR);
        launcher.registerMemeverse(
            "Memeverse",
            "MEME",
            uniqueId,
            uint128(block.timestamp + 1 days),
            uint128(block.timestamp + 2 days),
            omnichainIds,
            address(0x7777),
            true
        );

        IMemeverseLauncher.Memeverse memory verse = launcher.getMemeverseByVerseId(uniqueId);
        assertEq(verse.name, "Memeverse");
        assertEq(verse.symbol, "MEME");
        assertEq(verse.UPT, address(0x7777));
        assertEq(verse.memecoin, address(memecoin));
        assertEq(verse.liquidProof, address(pol));
        assertEq(launcher.getVerseIdByMemecoin(address(memecoin)), uniqueId);

        assertEq(memecoin.memeverseLauncher(), address(launcher));
        assertEq(pol.memecoin(), address(memecoin));
        assertEq(memecoin.peers(REMOTE_EID), bytes32(uint256(uint160(address(memecoin)))));
        assertEq(pol.peers(REMOTE_EID), bytes32(uint256(uint160(address(pol)))));
        assertEq(memecoin.peers(uint32(block.chainid)), bytes32(0));
    }

    /// @notice Test register memeverse local only omnichain ids skip peer configuration.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function testRegisterMemeverse_LocalOnlyOmnichainIdsSkipPeerConfiguration() external {
        uint256 uniqueId = 8;
        uint32[] memory omnichainIds = new uint32[](1);
        omnichainIds[0] = uint32(block.chainid);

        vm.prank(REGISTRAR);
        launcher.registerMemeverse(
            "Memeverse",
            "MEME",
            uniqueId,
            uint128(block.timestamp + 1 days),
            uint128(block.timestamp + 2 days),
            omnichainIds,
            address(0x7777),
            true
        );

        assertEq(memecoin.peers(uint32(block.chainid)), bytes32(0));
        assertEq(pol.peers(uint32(block.chainid)), bytes32(0));
    }

    /// @notice Test set external info requires registrar or governor and rejects oversized description.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function testSetExternalInfoRequiresRegistrarOrGovernorAndRejectsOversizedDescription() external {
        registry.setEndpoint(REMOTE_CHAIN_ID, REMOTE_EID);
        uint256 uniqueId = 9;

        vm.prank(REGISTRAR);
        launcher.registerMemeverse(
            "Memeverse",
            "MEME",
            uniqueId,
            uint128(block.timestamp + 1 days),
            uint128(block.timestamp + 2 days),
            _omnichainIds(),
            address(0x7777),
            true
        );

        vm.expectRevert(IMemeverseLauncher.PermissionDenied.selector);
        launcher.setExternalInfo(uniqueId, "ipfs://meme", "desc", _communities("https://site"));

        vm.prank(REGISTRAR);
        launcher.setExternalInfo(uniqueId, "ipfs://meme", "desc", _communities("https://site"));

        IMemeverseLauncher.Memeverse memory verse = launcher.getMemeverseByVerseId(uniqueId);
        assertEq(verse.uri, "ipfs://meme");
        assertEq(verse.desc, "desc");

        string memory oversized = string(new bytes(256));
        vm.prank(REGISTRAR);
        vm.expectRevert(IMemeverseLauncher.InvalidLength.selector);
        launcher.setExternalInfo(uniqueId, "", oversized, new string[](0));
    }

    /// @notice Test set external info governor path supports selective updates.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function testSetExternalInfoGovernorPathSupportsSelectiveUpdates() external {
        registry.setEndpoint(REMOTE_CHAIN_ID, REMOTE_EID);
        uint256 uniqueId = 10;

        vm.prank(REGISTRAR);
        launcher.registerMemeverse(
            "Memeverse",
            "MEME",
            uniqueId,
            uint128(block.timestamp + 1 days),
            uint128(block.timestamp + 2 days),
            _omnichainIds(),
            address(0x7777),
            true
        );

        IMemeverseLauncher.Memeverse memory verse = launcher.getMemeverseByVerseId(uniqueId);
        verse.governor = address(new MockGovernorForExternalInfo());
        launcher.setMemeverseForTest(uniqueId, verse);

        vm.prank(verse.governor);
        launcher.setExternalInfo(uniqueId, "ipfs://first", "first", _communities("https://site-1"));

        vm.prank(verse.governor);
        launcher.setExternalInfo(uniqueId, "", "", new string[](0));

        IMemeverseLauncher.Memeverse memory stored = launcher.getMemeverseByVerseId(uniqueId);
        assertEq(stored.uri, "ipfs://first");
        assertEq(stored.desc, "first");
        assertEq(launcher.communitiesMap(uniqueId, 0), "https://site-1");
    }

    function _omnichainIds() internal view returns (uint32[] memory ids) {
        ids = new uint32[](2);
        ids[0] = uint32(block.chainid);
        ids[1] = REMOTE_CHAIN_ID;
    }

    function _communities(string memory website) internal pure returns (string[] memory communities) {
        communities = new string[](1);
        communities[0] = website;
    }
}
