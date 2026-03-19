// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {LzEndpointRegistry} from "../../../src/common/omnichain/LzEndpointRegistry.sol";
import {ILzEndpointRegistry} from "../../../src/common/omnichain/interfaces/ILzEndpointRegistry.sol";

contract LzEndpointRegistryTest is Test {
    address internal constant OWNER = address(0xABCD);
    address internal constant OTHER = address(0xBEEF);

    LzEndpointRegistry internal registry;

    /// @notice Set up.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function setUp() external {
        registry = new LzEndpointRegistry(OWNER);
    }

    /// @notice Test set lz endpoint ids stores valid pairs and ignores zero values.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function testSetLzEndpointIdsStoresValidPairsAndIgnoresZeroValues() external {
        ILzEndpointRegistry.LzEndpointIdPair[] memory pairs = new ILzEndpointRegistry.LzEndpointIdPair[](4);
        pairs[0] = ILzEndpointRegistry.LzEndpointIdPair({chainId: 1, endpointId: 101});
        pairs[1] = ILzEndpointRegistry.LzEndpointIdPair({chainId: 2, endpointId: 0});
        pairs[2] = ILzEndpointRegistry.LzEndpointIdPair({chainId: 0, endpointId: 202});
        pairs[3] = ILzEndpointRegistry.LzEndpointIdPair({chainId: 3, endpointId: 303});

        vm.prank(OWNER);
        registry.setLzEndpointIds(pairs);

        assertEq(registry.lzEndpointIdOfChain(1), 101);
        assertEq(registry.lzEndpointIdOfChain(2), 0);
        assertEq(registry.lzEndpointIdOfChain(3), 303);
    }

    /// @notice Test set lz endpoint ids only owner.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function testSetLzEndpointIdsOnlyOwner() external {
        ILzEndpointRegistry.LzEndpointIdPair[] memory pairs = new ILzEndpointRegistry.LzEndpointIdPair[](1);
        pairs[0] = ILzEndpointRegistry.LzEndpointIdPair({chainId: 1, endpointId: 101});

        vm.prank(OTHER);
        vm.expectRevert();
        registry.setLzEndpointIds(pairs);
    }
}
