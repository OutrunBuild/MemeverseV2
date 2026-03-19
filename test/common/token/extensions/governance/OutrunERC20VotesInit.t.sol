// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";

import {OutrunERC20VotesInit} from "../../../../../src/common/token/extensions/governance/OutrunERC20VotesInit.sol";

contract VotesHarness is OutrunERC20VotesInit {
    bytes32 internal constant DELEGATION_TYPEHASH =
        keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");

    /// @notice Initialize.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @param name_ See implementation.
    /// @param symbol_ See implementation.
    function initialize(string memory name_, string memory symbol_) external initializer {
        __OutrunERC20_init(name_, symbol_);
        __OutrunEIP712_init(name_, "1");
        __OutrunVotes_init();
        __OutrunERC20Votes_init();
    }

    /// @notice Mint test.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @param to See implementation.
    /// @param amount See implementation.
    function mintTest(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /// @notice Delegation digest.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @param delegatee See implementation.
    /// @param nonce See implementation.
    /// @param expiry See implementation.
    /// @return See implementation.
    function delegationDigest(address delegatee, uint256 nonce, uint256 expiry) external view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(DELEGATION_TYPEHASH, delegatee, nonce, expiry)));
    }
}

contract CappedVotesHarness is VotesHarness {
    function _maxSupply() internal pure override returns (uint256) {
        return 10 ether;
    }
}

contract OutrunERC20VotesInitTest is Test {
    using Clones for address;

    uint256 internal constant ALICE_PK = 0xA11CE;
    address internal immutable ALICE = vm.addr(ALICE_PK);
    address internal constant BOB = address(0xB0B);

    VotesHarness internal implementation;
    VotesHarness internal token;

    /// @notice Set up.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function setUp() external {
        implementation = new VotesHarness();
        token = VotesHarness(address(implementation).clone());
        token.initialize("Vote Token", "VOTE");
    }

    /// @notice Test delegate moves voting power and creates checkpoints.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function testDelegateMovesVotingPowerAndCreatesCheckpoints() external {
        token.mintTest(ALICE, 10 ether);

        vm.prank(ALICE);
        token.delegate(ALICE);

        assertEq(token.getVotes(ALICE), 10 ether);
        assertEq(token.numCheckpoints(ALICE), 1);

        Checkpoints.Checkpoint208 memory checkpoint = token.checkpoints(ALICE, 0);
        assertEq(checkpoint._value, 10 ether);
    }

    /// @notice Test transfer after delegation updates past votes.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function testTransferAfterDelegationUpdatesPastVotes() external {
        vm.roll(10);
        token.mintTest(ALICE, 10 ether);

        vm.roll(11);
        vm.prank(ALICE);
        token.delegate(ALICE);

        uint256 snapshotBlock = 11;
        vm.roll(12);

        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 4 ether));

        vm.roll(13);
        assertEq(token.getVotes(ALICE), 6 ether);
        assertEq(token.getPastVotes(ALICE, snapshotBlock), 10 ether);
        assertEq(token.getPastTotalSupply(snapshotBlock), 10 ether);
    }

    /// @notice Test delegate by sig consumes nonce and assigns votes.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function testDelegateBySigConsumesNonceAndAssignsVotes() external {
        token.mintTest(ALICE, 5 ether);

        uint256 expiry = block.timestamp + 1 days;
        bytes32 digest = token.delegationDigest(ALICE, token.nonces(ALICE), expiry);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ALICE_PK, digest);

        token.delegateBySig(ALICE, token.nonces(ALICE), expiry, v, r, s);

        assertEq(token.delegates(ALICE), ALICE);
        assertEq(token.getVotes(ALICE), 5 ether);
        assertEq(token.nonces(ALICE), 1);
    }

    /// @notice Test get past votes rejects future lookup.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function testGetPastVotesRejectsFutureLookup() external {
        vm.expectRevert();
        token.getPastVotes(ALICE, block.number);
    }

    /// @notice Test mint respects safe supply cap override.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function testMintRespectsSafeSupplyCapOverride() external {
        CappedVotesHarness cappedImplementation = new CappedVotesHarness();
        CappedVotesHarness capped = CappedVotesHarness(address(cappedImplementation).clone());
        capped.initialize("Cap Token", "CAP");

        capped.mintTest(ALICE, 10 ether);
        vm.expectRevert(
            abi.encodeWithSelector(OutrunERC20VotesInit.ERC20ExceededSafeSupply.selector, 11 ether, 10 ether)
        );
        capped.mintTest(ALICE, 1 ether);
    }
}
