// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IOAppCore} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppCore.sol";
import {Origin} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppReceiver.sol";

import {OutrunOAppCoreInit} from "../../../../src/common/omnichain/oapp/OutrunOAppCoreInit.sol";
import {OutrunOAppReceiverInit} from "../../../../src/common/omnichain/oapp/OutrunOAppReceiverInit.sol";

contract MockOAppReceiverEndpoint {
    address public delegate;

    /// @notice Set delegate.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @param delegate_ See implementation.
    function setDelegate(address delegate_) external {
        delegate = delegate_;
    }
}

contract OAppReceiverHarness is OutrunOAppReceiverInit {
    uint32 public lastSrcEid;
    bytes32 public lastSender;
    bytes32 public lastGuid;
    bytes public lastMessage;
    address public lastExecutor;

    constructor(address endpoint_) OutrunOAppCoreInit(endpoint_) {}

    /// @notice Initialize.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @param owner_ See implementation.
    /// @param delegate_ See implementation.
    function initialize(address owner_, address delegate_) external initializer {
        __OutrunOwnable_init(owner_);
        __OutrunOAppReceiver_init(delegate_);
    }

    function _lzReceive(Origin calldata origin, bytes32 guid, bytes calldata message, address executor, bytes calldata)
        internal
        override
    {
        lastSrcEid = origin.srcEid;
        lastSender = origin.sender;
        lastGuid = guid;
        lastMessage = message;
        lastExecutor = executor;
    }
}

contract OutrunOAppReceiverInitTest is Test {
    using Clones for address;

    address internal constant OWNER = address(0xABCD);
    address internal constant DELEGATE = address(0xCAFE);
    uint32 internal constant SRC_EID = 101;
    bytes32 internal constant PEER = bytes32(uint256(uint160(address(0xBEEF))));

    MockOAppReceiverEndpoint internal endpoint;
    OAppReceiverHarness internal implementation;
    OAppReceiverHarness internal harness;

    /// @notice Set up.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function setUp() external {
        endpoint = new MockOAppReceiverEndpoint();
        implementation = new OAppReceiverHarness(address(endpoint));
        harness = OAppReceiverHarness(address(implementation).clone());
        harness.initialize(OWNER, DELEGATE);
    }

    /// @notice Test allow initialize path and compose sender checks.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function testAllowInitializePathAndComposeSenderChecks() external view {
        Origin memory origin = Origin({srcEid: SRC_EID, sender: PEER, nonce: 1});

        assertFalse(harness.allowInitializePath(origin));
        assertFalse(harness.isComposeMsgSender(origin, "", address(0x1234)));
        assertTrue(harness.isComposeMsgSender(origin, "", address(harness)));
        assertEq(harness.nextNonce(SRC_EID, PEER), 0);
    }

    /// @notice Test lz receive requires endpoint and matching peer.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function testLzReceiveRequiresEndpointAndMatchingPeer() external {
        Origin memory origin = Origin({srcEid: SRC_EID, sender: PEER, nonce: 1});

        vm.expectRevert(abi.encodeWithSelector(OutrunOAppReceiverInit.OnlyEndpoint.selector, address(this)));
        harness.lzReceive(origin, bytes32("guid"), bytes("msg"), address(0x1), "");

        vm.prank(address(endpoint));
        vm.expectRevert(abi.encodeWithSelector(IOAppCore.NoPeer.selector, SRC_EID));
        harness.lzReceive(origin, bytes32("guid"), bytes("msg"), address(0x1), "");

        vm.prank(OWNER);
        harness.setPeer(SRC_EID, bytes32(uint256(uint160(address(0xCAFE)))));

        vm.prank(address(endpoint));
        vm.expectRevert(abi.encodeWithSelector(IOAppCore.OnlyPeer.selector, SRC_EID, PEER));
        harness.lzReceive(origin, bytes32("guid"), bytes("msg"), address(0x1), "");
    }

    /// @notice Test lz receive dispatches message when endpoint and peer match.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function testLzReceiveDispatchesMessageWhenEndpointAndPeerMatch() external {
        Origin memory origin = Origin({srcEid: SRC_EID, sender: PEER, nonce: 1});

        vm.prank(OWNER);
        harness.setPeer(SRC_EID, PEER);

        vm.prank(address(endpoint));
        harness.lzReceive(origin, bytes32("guid"), bytes("payload"), address(0x1234), "");

        assertEq(harness.lastSrcEid(), SRC_EID);
        assertEq(harness.lastSender(), PEER);
        assertEq(harness.lastGuid(), bytes32("guid"));
        assertEq(harness.lastMessage(), bytes("payload"));
        assertEq(harness.lastExecutor(), address(0x1234));
    }
}
