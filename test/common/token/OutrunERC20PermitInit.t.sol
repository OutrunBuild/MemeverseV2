// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import {OutrunERC20PermitInit} from "../../../src/common/token/OutrunERC20PermitInit.sol";

contract PermitHarness is OutrunERC20PermitInit {
    bytes32 internal constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    /// @notice Initialize.
    /// @param name_ See implementation.
    /// @param symbol_ See implementation.
    function initialize(string memory name_, string memory symbol_) external initializer {
        __OutrunERC20_init(name_, symbol_);
        __OutrunERC20Permit_init(name_);
    }

    /// @notice Mint test.
    /// @param to See implementation.
    /// @param amount See implementation.
    function mintTest(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /// @notice Permit digest.
    /// @param owner See implementation.
    /// @param spender See implementation.
    /// @param value See implementation.
    /// @param deadline See implementation.
    /// @return See implementation.
    function permitDigest(address owner, address spender, uint256 value, uint256 deadline)
        external
        view
        returns (bytes32)
    {
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces(owner), deadline));
        return _hashTypedDataV4(structHash);
    }
}

contract OutrunERC20PermitInitTest is Test {
    using Clones for address;

    uint256 internal constant OWNER_PK = 0xA11CE;
    address internal immutable OWNER = vm.addr(OWNER_PK);
    address internal constant SPENDER = address(0xBEEF);

    PermitHarness internal implementation;
    PermitHarness internal token;

    /// @notice Set up.
    function setUp() external {
        implementation = new PermitHarness();
        token = PermitHarness(address(implementation).clone());
        token.initialize("Permit Token", "PRM");
    }

    /// @notice Test initialize sets metadata and domain separator.
    function testInitializeSetsMetadataAndDomainSeparator() external view {
        assertEq(token.name(), "Permit Token");
        assertEq(token.symbol(), "PRM");
        assertTrue(token.DOMAIN_SEPARATOR() != bytes32(0));
        (, string memory name, string memory version, uint256 chainId, address verifyingContract,,) =
            token.eip712Domain();
        assertEq(name, "Permit Token");
        assertEq(version, "1");
        assertEq(chainId, block.chainid);
        assertEq(verifyingContract, address(token));
    }

    /// @notice Test permit sets allowance and consumes nonce.
    function testPermitSetsAllowanceAndConsumesNonce() external {
        uint256 deadline = block.timestamp + 1 days;
        bytes32 digest = token.permitDigest(OWNER, SPENDER, 7 ether, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(OWNER_PK, digest);

        token.permit(OWNER, SPENDER, 7 ether, deadline, v, r, s);

        assertEq(token.allowance(OWNER, SPENDER), 7 ether);
        assertEq(token.nonces(OWNER), 1);
    }

    /// @notice Test permit rejects expired or invalid signer.
    function testPermitRejectsExpiredOrInvalidSigner() external {
        bytes32 digest = token.permitDigest(OWNER, SPENDER, 7 ether, block.timestamp + 1 days);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(OWNER_PK, digest);

        vm.expectRevert(abi.encodeWithSelector(OutrunERC20PermitInit.ERC2612ExpiredSignature.selector, block.timestamp));
        token.permit(OWNER, SPENDER, 7 ether, block.timestamp, v, r, s);

        bytes32 wrongDigest = token.permitDigest(OWNER, SPENDER, 8 ether, block.timestamp + 1 days);
        (v, r, s) = vm.sign(OWNER_PK, wrongDigest);
        vm.expectRevert();
        token.permit(OWNER, SPENDER, 7 ether, block.timestamp + 1 days, v, r, s);
    }
}
