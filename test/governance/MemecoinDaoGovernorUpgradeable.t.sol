// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

import {MemecoinDaoGovernorUpgradeable} from "../../src/governance/MemecoinDaoGovernorUpgradeable.sol";
import {IMemecoinDaoGovernor} from "../../src/governance/interfaces/IMemecoinDaoGovernor.sol";

contract MockGovernorVotesToken is IVotes {
    mapping(address => uint256) internal votes;
    uint256 internal totalSupplyVotes = 1_000 ether;

    /// @notice Set votes.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @param account See implementation.
    /// @param amount See implementation.
    function setVotes(address account, uint256 amount) external {
        votes[account] = amount;
    }

    /// @notice Get votes.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @param account See implementation.
    /// @return See implementation.
    function getVotes(address account) external view returns (uint256) {
        return votes[account];
    }

    /// @notice Get past votes.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @param account See implementation.
    /// @param timepoint See implementation.
    /// @return See implementation.
    function getPastVotes(address account, uint256 timepoint) external view returns (uint256) {
        timepoint;
        return votes[account];
    }

    /// @notice Get past total supply.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @param timepoint See implementation.
    /// @return See implementation.
    function getPastTotalSupply(uint256 timepoint) external view returns (uint256) {
        timepoint;
        return totalSupplyVotes;
    }

    /// @notice Delegates.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @param account See implementation.
    /// @return See implementation.
    function delegates(address account) external pure returns (address) {
        return account;
    }

    /// @notice Delegate.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @param delegatee See implementation.
    function delegate(address delegatee) external pure {
        delegatee;
    }

    /// @notice Delegate by sig.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @param delegatee See implementation.
    /// @param nonce See implementation.
    /// @param expiry See implementation.
    /// @param v See implementation.
    /// @param r See implementation.
    /// @param s See implementation.
    function delegateBySig(address delegatee, uint256 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s)
        external
        pure
    {
        delegatee;
        nonce;
        expiry;
        v;
        r;
        s;
    }

    /// @notice Clock.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @return See implementation.
    function clock() external view returns (uint48) {
        return uint48(block.number);
    }

    /// @notice Clock mode.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @return See implementation.
    function CLOCK_MODE() external pure returns (string memory) {
        return "mode=blocknumber&from=default";
    }
}

contract MockGovernorIncentivizer {
    address public lastReceiveToken;
    uint256 public lastReceiveAmount;
    address public lastSentToken;
    address public lastSentTo;
    uint256 public lastSentAmount;
    address public lastVoteAccount;
    uint256 public lastVoteAmount;

    /// @notice Receive treasury income.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @param token See implementation.
    /// @param amount See implementation.
    function receiveTreasuryIncome(address token, uint256 amount) external {
        lastReceiveToken = token;
        lastReceiveAmount = amount;
    }

    /// @notice Send treasury assets.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @param token See implementation.
    /// @param to See implementation.
    /// @param amount See implementation.
    function sendTreasuryAssets(address token, address to, uint256 amount) external {
        lastSentToken = token;
        lastSentTo = to;
        lastSentAmount = amount;
    }

    /// @notice Accum cycle votes.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @param account See implementation.
    /// @param votes See implementation.
    function accumCycleVotes(address account, uint256 votes) external {
        lastVoteAccount = account;
        lastVoteAmount = votes;
    }
}

contract MemecoinDaoGovernorUpgradeableTest is Test {
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);

    MemecoinDaoGovernorUpgradeable internal implementation;
    MemecoinDaoGovernorUpgradeable internal governor;
    MockGovernorVotesToken internal votesToken;
    MockGovernorIncentivizer internal incentivizer;
    MockERC20 internal treasuryToken;

    /// @notice Set up.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function setUp() external {
        implementation = new MemecoinDaoGovernorUpgradeable();
        votesToken = new MockGovernorVotesToken();
        incentivizer = new MockGovernorIncentivizer();
        treasuryToken = new MockERC20("Treasury", "TRY", 18);

        votesToken.setVotes(ALICE, 100 ether);
        votesToken.setVotes(BOB, 80 ether);

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(
                MemecoinDaoGovernorUpgradeable.initialize,
                ("Memecoin DAO", IVotes(address(votesToken)), 0, 5, 1 ether, 10, address(incentivizer))
            )
        );
        governor = MemecoinDaoGovernorUpgradeable(payable(address(proxy)));
    }

    /// @notice Test initialize exposes incentivizer and governor metadata.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function testInitializeExposesIncentivizerAndGovernorMetadata() external view {
        assertEq(governor.governanceCycleIncentivizer(), address(incentivizer));
        assertEq(governor.name(), "Memecoin DAO");
        assertEq(governor.votingDelay(), 0);
        assertEq(governor.votingPeriod(), 5);
        assertEq(governor.proposalThreshold(), 1 ether);
    }

    /// @notice Test receive treasury income notifies incentivizer and pulls tokens.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function testReceiveTreasuryIncomeNotifiesIncentivizerAndPullsTokens() external {
        treasuryToken.mint(address(this), 10 ether);
        treasuryToken.approve(address(governor), type(uint256).max);

        governor.receiveTreasuryIncome(address(treasuryToken), 10 ether);

        assertEq(incentivizer.lastReceiveToken(), address(treasuryToken));
        assertEq(incentivizer.lastReceiveAmount(), 10 ether);
        assertEq(treasuryToken.balanceOf(address(governor)), 10 ether);
    }

    /// @notice Test propose blocks second unfinalized proposal and allows after defeat.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function testProposeBlocksSecondUnfinalizedProposalAndAllowsAfterDefeat() external {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = _proposalPayload();

        vm.prank(ALICE);
        uint256 firstProposalId = governor.propose(targets, values, calldatas, "proposal-1");

        vm.prank(ALICE);
        vm.expectRevert(IMemecoinDaoGovernor.UserHasUnfinalizedProposal.selector);
        governor.propose(targets, values, calldatas, "proposal-2");

        vm.roll(block.number + governor.votingPeriod() + 1);
        assertEq(uint8(governor.state(firstProposalId)), uint8(IGovernor.ProposalState.Defeated));

        vm.prank(ALICE);
        uint256 secondProposalId = governor.propose(targets, values, calldatas, "proposal-3");
        assertTrue(secondProposalId != 0);
    }

    /// @notice Test cast vote accumulates cycle votes on incentivizer.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function testCastVoteAccumulatesCycleVotesOnIncentivizer() external {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) = _proposalPayload();

        vm.prank(ALICE);
        uint256 proposalId = governor.propose(targets, values, calldatas, "vote-proposal");

        vm.roll(block.number + 1);
        vm.prank(BOB);
        governor.castVote(proposalId, 1);

        assertEq(incentivizer.lastVoteAccount(), BOB);
        assertEq(incentivizer.lastVoteAmount(), 80 ether);
    }

    /// @notice Test send treasury assets requires governance executor and transfers tokens.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function testSendTreasuryAssetsRequiresGovernanceExecutorAndTransfersTokens() external {
        treasuryToken.mint(address(governor), 10 ether);

        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorOnlyExecutor.selector, address(this)));
        governor.sendTreasuryAssets(address(treasuryToken), BOB, 3 ether);

        vm.prank(address(governor));
        governor.sendTreasuryAssets(address(treasuryToken), BOB, 3 ether);

        assertEq(incentivizer.lastSentToken(), address(treasuryToken));
        assertEq(incentivizer.lastSentTo(), BOB);
        assertEq(incentivizer.lastSentAmount(), 3 ether);
        assertEq(treasuryToken.balanceOf(BOB), 3 ether);
    }

    function _proposalPayload()
        internal
        pure
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas)
    {
        targets = new address[](1);
        values = new uint256[](1);
        calldatas = new bytes[](1);
        targets[0] = address(0x1234);
        values[0] = 0;
        calldatas[0] = bytes("");
    }
}
