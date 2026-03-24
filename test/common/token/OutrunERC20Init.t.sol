// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import {OutrunERC20Init} from "../../../src/common/token/OutrunERC20Init.sol";

contract ERC20Harness is OutrunERC20Init {
    /// @notice Initialize.
    /// @param name_ See implementation.
    /// @param symbol_ See implementation.
    function initialize(string memory name_, string memory symbol_) external initializer {
        __OutrunERC20_init(name_, symbol_);
    }

    /// @notice Mint test.
    /// @param to See implementation.
    /// @param amount See implementation.
    function mintTest(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /// @notice Burn test.
    /// @param from See implementation.
    /// @param amount See implementation.
    function burnTest(address from, uint256 amount) external {
        _burn(from, amount);
    }
}

contract OutrunERC20InitTest is Test {
    using Clones for address;

    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);

    ERC20Harness internal implementation;
    ERC20Harness internal token;

    /// @notice Set up.
    function setUp() external {
        implementation = new ERC20Harness();
        token = ERC20Harness(address(implementation).clone());
        token.initialize("Base Token", "BASE");
    }

    /// @notice Test initialize sets metadata.
    function testInitializeSetsMetadata() external view {
        assertEq(token.name(), "Base Token");
        assertEq(token.symbol(), "BASE");
        assertEq(token.decimals(), 18);
    }

    /// @notice Test transfer approve and transfer from update balances and allowance.
    function testTransferApproveAndTransferFromUpdateBalancesAndAllowance() external {
        token.mintTest(ALICE, 10 ether);

        vm.prank(ALICE);
        _assertTransfer(token, BOB, 3 ether);
        assertEq(token.balanceOf(ALICE), 7 ether);
        assertEq(token.balanceOf(BOB), 3 ether);

        vm.prank(ALICE);
        token.approve(BOB, 2 ether);
        assertEq(token.allowance(ALICE, BOB), 2 ether);

        vm.prank(BOB);
        _assertTransferFrom(token, ALICE, BOB, 2 ether);
        assertEq(token.balanceOf(ALICE), 5 ether);
        assertEq(token.balanceOf(BOB), 5 ether);
        assertEq(token.allowance(ALICE, BOB), 0);
    }

    /// @notice Test transfer and approval reject invalid addresses or insufficient balances.
    function testTransferAndApprovalRejectInvalidAddressesOrInsufficientBalances() external {
        token.mintTest(ALICE, 1 ether);

        _assertTransferCallFails(token, BOB, 1 ether);

        vm.prank(ALICE);
        _assertTransferCallFails(token, address(0), 1 ether);

        vm.prank(ALICE);
        vm.expectRevert();
        token.approve(address(0), 1 ether);

        vm.prank(BOB);
        _assertTransferFromCallFails(token, ALICE, BOB, 1 ether);
    }

    /// @notice Test burn reduces supply.
    function testBurnReducesSupply() external {
        token.mintTest(ALICE, 4 ether);
        token.burnTest(ALICE, 1 ether);

        assertEq(token.totalSupply(), 3 ether);
        assertEq(token.balanceOf(ALICE), 3 ether);
    }

    /// @notice Assert transfer.
    /// @param erc20 See implementation.
    /// @param to See implementation.
    /// @param amount See implementation.
    function _assertTransfer(ERC20Harness erc20, address to, uint256 amount) internal {
        assertTrue(erc20.transfer(to, amount));
    }

    /// @notice Assert transfer from.
    /// @param erc20 See implementation.
    /// @param from See implementation.
    /// @param to See implementation.
    /// @param amount See implementation.
    function _assertTransferFrom(ERC20Harness erc20, address from, address to, uint256 amount) internal {
        assertTrue(erc20.transferFrom(from, to, amount));
    }

    /// @notice Assert transfer call fails.
    /// @param erc20 See implementation.
    /// @param to See implementation.
    /// @param amount See implementation.
    function _assertTransferCallFails(ERC20Harness erc20, address to, uint256 amount) internal {
        (bool success,) = address(erc20).call(abi.encodeCall(erc20.transfer, (to, amount)));
        assertFalse(success);
    }

    /// @notice Assert transfer from call fails.
    /// @param erc20 See implementation.
    /// @param from See implementation.
    /// @param to See implementation.
    /// @param amount See implementation.
    function _assertTransferFromCallFails(ERC20Harness erc20, address from, address to, uint256 amount) internal {
        (bool success,) = address(erc20).call(abi.encodeCall(erc20.transferFrom, (from, to, amount)));
        assertFalse(success);
    }
}
