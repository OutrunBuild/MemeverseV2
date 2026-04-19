// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";

import {UniswapLP} from "../../src/swap/tokens/UniswapLP.sol";

contract UniswapLPTest is Test {
    bytes32 internal constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    uint256 internal constant OWNER_PK = 0xA11CE;
    uint256 internal constant OTHER_PK = 0xB0B;

    address internal immutable OWNER = vm.addr(OWNER_PK);
    address internal immutable OTHER = vm.addr(OTHER_PK);
    address internal constant SPENDER = address(0xBEEF);

    UniswapLP internal token;

    function setUp() external {
        token = new UniswapLP("Memeverse LP", "MLP", 18, PoolId.wrap(bytes32(uint256(1))), address(this));
    }

    function testConstructorRevertsWithZeroAddressHook() external {
        vm.expectRevert(UniswapLP.ZeroAddressHook.selector);
        new UniswapLP("Memeverse LP", "MLP", 18, PoolId.wrap(bytes32(uint256(1))), address(0));
    }

    function testPermitRevertsWithPermitDeadlineExpired() external {
        uint256 deadline = block.timestamp + 1 days;
        bytes32 digest = _permitDigest(OWNER, SPENDER, 7 ether, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(OWNER_PK, digest);
        uint256 expiredDeadline = block.timestamp - 1;

        vm.expectRevert(abi.encodeWithSelector(UniswapLP.PermitDeadlineExpired.selector, expiredDeadline));
        token.permit(OWNER, SPENDER, 7 ether, expiredDeadline, v, r, s);
    }

    function testPermitRevertsWithInvalidSigner() external {
        uint256 deadline = block.timestamp + 1 days;
        bytes32 digest = _permitDigest(OWNER, SPENDER, 7 ether, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(OTHER_PK, digest);

        vm.expectRevert(abi.encodeWithSelector(UniswapLP.InvalidSigner.selector, OTHER, OWNER));
        token.permit(OWNER, SPENDER, 7 ether, deadline, v, r, s);
    }

    function _permitDigest(address owner, address spender, uint256 value, uint256 deadline)
        internal
        view
        returns (bytes32)
    {
        bytes32 structHash =
            keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, token.nonces(owner), deadline));
        return keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));
    }
}
