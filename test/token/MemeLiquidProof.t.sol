// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

import {MemeLiquidProof} from "../../src/token/MemeLiquidProof.sol";
import {IPol} from "../../src/token/interfaces/IPol.sol";
import {IOFTCompose} from "../../src/common/omnichain/oft/IOFTCompose.sol";

contract MockMemeLiquidProofEndpoint {
    address public delegate;

    /// @notice Set delegate.
    /// @param delegate_ See implementation.
    function setDelegate(address delegate_) external {
        delegate = delegate_;
    }
}

contract MemeLiquidProofTest is Test {
    using Clones for address;

    address internal constant MEMECOIN = address(0xABCD);
    address internal constant LAUNCHER = address(0xBEEF);
    address internal constant DELEGATE = address(0xCAFE);
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);

    MockMemeLiquidProofEndpoint internal endpoint;
    MemeLiquidProof internal implementation;
    MemeLiquidProof internal liquidProof;

    /// @notice Set up.
    function setUp() external {
        endpoint = new MockMemeLiquidProofEndpoint();
        implementation = new MemeLiquidProof(address(endpoint));
        liquidProof = MemeLiquidProof(address(implementation).clone());
    }

    /// @notice Test initialize sets config and owner.
    function testInitializeSetsConfigAndOwner() external {
        liquidProof.initialize("POL-MEME", "POLM", MEMECOIN, LAUNCHER, DELEGATE);

        assertEq(liquidProof.name(), "POL-MEME");
        assertEq(liquidProof.symbol(), "POLM");
        assertEq(liquidProof.memecoin(), MEMECOIN);
        assertEq(liquidProof.memeverseLauncher(), LAUNCHER);
        assertEq(liquidProof.owner(), DELEGATE);
        assertEq(endpoint.delegate(), DELEGATE);
    }

    /// @notice Test only launcher can set pool id and mint.
    function testOnlyLauncherCanSetPoolIdAndMint() external {
        liquidProof.initialize("POL-MEME", "POLM", MEMECOIN, LAUNCHER, DELEGATE);
        PoolId poolId = PoolId.wrap(bytes32(uint256(1234)));

        vm.expectRevert(IOFTCompose.PermissionDenied.selector);
        liquidProof.setPoolId(poolId);

        vm.expectRevert(IOFTCompose.PermissionDenied.selector);
        liquidProof.mint(ALICE, 1 ether);

        vm.prank(LAUNCHER);
        liquidProof.setPoolId(poolId);
        assertEq(PoolId.unwrap(liquidProof.poolId()), PoolId.unwrap(poolId));

        vm.prank(LAUNCHER);
        liquidProof.mint(ALICE, 2 ether);
        assertEq(liquidProof.balanceOf(ALICE), 2 ether);
    }

    /// @notice Test burn supports direct holder and approved spender.
    function testBurnSupportsDirectHolderAndApprovedSpender() external {
        liquidProof.initialize("POL-MEME", "POLM", MEMECOIN, LAUNCHER, DELEGATE);

        vm.prank(LAUNCHER);
        liquidProof.mint(ALICE, 3 ether);

        vm.prank(ALICE);
        liquidProof.burn(1 ether);
        assertEq(liquidProof.balanceOf(ALICE), 2 ether);

        vm.prank(ALICE);
        liquidProof.approve(BOB, 1 ether);

        vm.prank(BOB);
        liquidProof.burn(ALICE, 1 ether);
        assertEq(liquidProof.balanceOf(ALICE), 1 ether);
        assertEq(liquidProof.allowance(ALICE, BOB), 0);
    }

    /// @notice Test mint and burn reject zero amount.
    function testMintAndBurnRejectZeroAmount() external {
        liquidProof.initialize("POL-MEME", "POLM", MEMECOIN, LAUNCHER, DELEGATE);

        vm.prank(LAUNCHER);
        vm.expectRevert(IPol.ZeroInput.selector);
        liquidProof.mint(ALICE, 0);

        vm.prank(ALICE);
        vm.expectRevert(IPol.ZeroInput.selector);
        liquidProof.burn(0);

        vm.prank(ALICE);
        vm.expectRevert(IPol.ZeroInput.selector);
        liquidProof.burn(ALICE, 0);
    }
}
