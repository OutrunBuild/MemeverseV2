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
    /// @param account See implementation.
    /// @param amount See implementation.
    function setVotes(address account, uint256 amount) external {
        votes[account] = amount;
    }

    /// @notice Get votes.
    /// @param account See implementation.
    /// @return See implementation.
    function getVotes(address account) external view returns (uint256) {
        return votes[account];
    }

    /// @notice Get past votes.
    /// @param account See implementation.
    /// @param timepoint See implementation.
    /// @return See implementation.
    function getPastVotes(address account, uint256 timepoint) external view returns (uint256) {
        timepoint;
        return votes[account];
    }

    /// @notice Get past total supply.
    /// @param timepoint See implementation.
    /// @return See implementation.
    function getPastTotalSupply(uint256 timepoint) external view returns (uint256) {
        timepoint;
        return totalSupplyVotes;
    }

    /// @notice Delegates.
    /// @param account See implementation.
    /// @return See implementation.
    function delegates(address account) external pure returns (address) {
        return account;
    }

    /// @notice Delegate.
    /// @param delegatee See implementation.
    function delegate(address delegatee) external pure {
        delegatee;
    }

    /// @notice Delegate by sig.
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
    /// @return See implementation.
    function clock() external view returns (uint48) {
        return uint48(block.number);
    }

    /// @notice Clock mode.
    /// @return See implementation.
    function CLOCK_MODE() external pure returns (string memory) {
        return "mode=blocknumber&from=default";
    }
}

contract MockGovernorIncentivizer {
    address public lastReceiveToken;
    uint256 public lastReceiveAmount;
    uint256 public lastReceiveGovernorBalance;
    address public lastSentToken;
    address public lastSentTo;
    uint256 public lastSentAmount;
    uint256 public lastSentGovernorBalance;
    address public lastVoteAccount;
    uint256 public lastVoteAmount;

    /// @notice Record treasury income.
    /// @param token See implementation.
    /// @param amount See implementation.
    function recordTreasuryIncome(address token, uint256 amount) external {
        lastReceiveToken = token;
        lastReceiveAmount = amount;
        lastReceiveGovernorBalance = MockERC20(token).balanceOf(msg.sender);
    }

    /// @notice Record treasury asset spend.
    /// @param token See implementation.
    /// @param to See implementation.
    /// @param amount See implementation.
    function recordTreasuryAssetSpend(address token, address to, uint256 amount) external {
        lastSentToken = token;
        lastSentTo = to;
        lastSentAmount = amount;
        lastSentGovernorBalance = MockERC20(token).balanceOf(msg.sender);
    }

    /// @notice Accum cycle votes.
    /// @param account See implementation.
    /// @param votes See implementation.
    function accumCycleVotes(address account, uint256 votes) external {
        lastVoteAccount = account;
        lastVoteAmount = votes;
    }
}

contract MemecoinDaoGovernorUpgradeableV2 is MemecoinDaoGovernorUpgradeable {
    function upgradeVersion() external pure returns (uint256) {
        return 2;
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
                ("Memecoin DAO", IVotes(address(votesToken)), 0, 5, 1 ether, 10, address(incentivizer), 0, 0)
            )
        );
        governor = MemecoinDaoGovernorUpgradeable(payable(address(proxy)));
    }

    /// @notice Test initialize exposes incentivizer and governor metadata.
    function testInitializeExposesIncentivizerAndGovernorMetadata() external view {
        assertEq(governor.governanceCycleIncentivizer(), address(incentivizer));
        assertEq(governor.name(), "Memecoin DAO");
        assertEq(governor.votingDelay(), 0);
        assertEq(governor.votingPeriod(), 5);
        assertEq(governor.proposalThreshold(), 1 ether);
    }

    /// @notice Test receive treasury income notifies incentivizer and pulls tokens.
    function testReceiveTreasuryIncomeNotifiesIncentivizerAndPullsTokens() external {
        treasuryToken.mint(address(this), 10 ether);
        treasuryToken.approve(address(governor), type(uint256).max);

        governor.receiveTreasuryIncome(address(treasuryToken), 10 ether);

        assertEq(incentivizer.lastReceiveToken(), address(treasuryToken));
        assertEq(incentivizer.lastReceiveAmount(), 10 ether);
        assertEq(incentivizer.lastReceiveGovernorBalance(), 10 ether);
        assertEq(treasuryToken.balanceOf(address(governor)), 10 ether);
    }

    /// @notice Test propose blocks second unfinalized proposal and allows after defeat.
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
    function testSendTreasuryAssetsRequiresGovernanceExecutorAndTransfersTokens() external {
        treasuryToken.mint(address(governor), 10 ether);

        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorOnlyExecutor.selector, address(this)));
        governor.sendTreasuryAssets(address(treasuryToken), BOB, 3 ether);

        vm.prank(address(governor));
        governor.sendTreasuryAssets(address(treasuryToken), BOB, 3 ether);

        assertEq(incentivizer.lastSentToken(), address(treasuryToken));
        assertEq(incentivizer.lastSentTo(), BOB);
        assertEq(incentivizer.lastSentAmount(), 3 ether);
        assertEq(incentivizer.lastSentGovernorBalance(), 10 ether);
        assertEq(treasuryToken.balanceOf(BOB), 3 ether);
    }

    /// @notice Test disburse reward is restricted to incentivizer and pays from governor custody.
    function testDisburseRewardOnlyIncentivizerAndTransfersTokens() external {
        treasuryToken.mint(address(governor), 10 ether);

        vm.expectRevert(IMemecoinDaoGovernor.UnauthorizedRewardPayout.selector);
        governor.disburseReward(address(treasuryToken), BOB, 4 ether);

        vm.prank(address(incentivizer));
        governor.disburseReward(address(treasuryToken), BOB, 4 ether);

        assertEq(treasuryToken.balanceOf(BOB), 4 ether);
        assertEq(treasuryToken.balanceOf(address(governor)), 6 ether);
    }

    /// @notice Test UUPS upgrade requires governance executor and upgrades the proxy implementation.
    function testUpgradeToAndCallRequiresGovernanceExecutorAndUpgradesProxy() external {
        MemecoinDaoGovernorUpgradeableV2 newImplementation = new MemecoinDaoGovernorUpgradeableV2();

        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorOnlyExecutor.selector, address(this)));
        governor.upgradeToAndCall(address(newImplementation), bytes(""));

        vm.prank(address(governor));
        governor.upgradeToAndCall(address(newImplementation), bytes(""));

        assertEq(MemecoinDaoGovernorUpgradeableV2(payable(address(governor))).upgradeVersion(), 2);
        assertEq(governor.governanceCycleIncentivizer(), address(incentivizer));
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
