// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IOAppCore} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppCore.sol";

import {OutrunOAppCoreInit} from "../../../../src/common/omnichain/oapp/OutrunOAppCoreInit.sol";

contract MockOAppCoreEndpoint {
    address public delegate;

    /// @notice Set delegate.
    /// @param delegate_ See implementation.
    function setDelegate(address delegate_) external {
        delegate = delegate_;
    }
}

contract OAppCoreHarness is OutrunOAppCoreInit {
    constructor(address endpoint_) OutrunOAppCoreInit(endpoint_) {}

    /// @notice Initialize.
    /// @param owner_ See implementation.
    /// @param delegate_ See implementation.
    function initialize(address owner_, address delegate_) external initializer {
        __OutrunOwnable_init(owner_);
        __OutrunOAppCore_init(delegate_);
    }

    /// @notice O app version.
    /// @return senderVersion See implementation.
    /// @return receiverVersion See implementation.
    function oAppVersion() public pure override returns (uint64 senderVersion, uint64 receiverVersion) {
        return (1, 1);
    }

    /// @notice Exposed get peer.
    /// @param eid See implementation.
    /// @return See implementation.
    function exposedGetPeer(uint32 eid) external view returns (bytes32) {
        return _getPeerOrRevert(eid);
    }
}

contract OutrunOAppCoreInitTest is Test {
    using Clones for address;

    address internal constant OWNER = address(0xABCD);
    address internal constant OTHER = address(0xBEEF);
    address internal constant DELEGATE = address(0xCAFE);

    MockOAppCoreEndpoint internal endpoint;
    OAppCoreHarness internal implementation;
    OAppCoreHarness internal harness;

    /// @notice Set up.
    function setUp() external {
        endpoint = new MockOAppCoreEndpoint();
        implementation = new OAppCoreHarness(address(endpoint));
        harness = OAppCoreHarness(address(implementation).clone());
    }

    /// @notice Test initialize rejects zero delegate and sets owner state.
    function testInitializeRejectsZeroDelegateAndSetsOwnerState() external {
        vm.expectRevert(IOAppCore.InvalidDelegate.selector);
        harness.initialize(OWNER, address(0));

        harness.initialize(OWNER, DELEGATE);
        assertEq(harness.owner(), OWNER);
        assertEq(endpoint.delegate(), DELEGATE);
        assertEq(address(harness.endpoint()), address(endpoint));
    }

    /// @notice Test set peer and get peer are owner gated.
    function testSetPeerAndGetPeerAreOwnerGated() external {
        harness.initialize(OWNER, DELEGATE);

        vm.expectRevert(abi.encodeWithSelector(IOAppCore.NoPeer.selector, uint32(101)));
        harness.exposedGetPeer(101);

        vm.prank(OTHER);
        vm.expectRevert();
        harness.setPeer(101, bytes32(uint256(1)));

        vm.prank(OWNER);
        harness.setPeer(101, bytes32(uint256(1)));
        assertEq(harness.peers(101), bytes32(uint256(1)));
        assertEq(harness.exposedGetPeer(101), bytes32(uint256(1)));
    }

    /// @notice Test set delegate requires owner.
    function testSetDelegateRequiresOwner() external {
        harness.initialize(OWNER, DELEGATE);

        vm.prank(OTHER);
        vm.expectRevert();
        harness.setDelegate(address(0x1234));

        vm.prank(OWNER);
        harness.setDelegate(address(0x1234));
        assertEq(endpoint.delegate(), address(0x1234));
    }
}
