// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {IGovernanceCycleIncentivizer} from "../../src/governance/interfaces/IGovernanceCycleIncentivizer.sol";
import {GovernanceCycleIncentivizerUpgradeable} from "../../src/governance/GovernanceCycleIncentivizerUpgradeable.sol";

contract MockIncentivizerGovernor {
    address public incentivizer;
    address public lastRewardToken;
    address public lastRewardTo;
    uint256 public lastRewardAmount;

    function setIncentivizer(address _incentivizer) external {
        incentivizer = _incentivizer;
    }

    function disburseReward(address token, address to, uint256 amount) external {
        require(msg.sender == incentivizer, "not incentivizer");
        lastRewardToken = token;
        lastRewardTo = to;
        lastRewardAmount = amount;
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        MockERC20(token).transfer(to, amount);
    }
}

contract GovernanceCycleIncentivizerUpgradeableTest is Test {
    address internal constant OTHER = address(0xBEEF);

    GovernanceCycleIncentivizerUpgradeable internal implementation;
    GovernanceCycleIncentivizerUpgradeable internal incentivizer;
    MockIncentivizerGovernor internal governor;
    MockERC20 internal tokenA;
    MockERC20 internal tokenB;

    /// @notice Set up.
    function setUp() external {
        implementation = new GovernanceCycleIncentivizerUpgradeable();
        governor = new MockIncentivizerGovernor();
        tokenA = new MockERC20("TokenA", "TKA", 18);
        tokenB = new MockERC20("TokenB", "TKB", 18);

        incentivizer = _deployIncentivizer(address(governor), address(tokenA));
        governor.setIncentivizer(address(incentivizer));
    }

    function testUpgradeToAndCallRequiresGovernorAndUpgradesProxy() external {
        GovernanceCycleIncentivizerUpgradeable governedIncentivizer = _deployIncentivizer(OTHER, address(tokenA));
        GovernanceCycleIncentivizerUpgradeableV2 newImplementation = new GovernanceCycleIncentivizerUpgradeableV2();

        vm.expectRevert(IGovernanceCycleIncentivizer.PermissionDenied.selector);
        governedIncentivizer.upgradeToAndCall(address(newImplementation), bytes(""));

        vm.prank(OTHER);
        governedIncentivizer.upgradeToAndCall(address(newImplementation), bytes(""));

        assertEq(GovernanceCycleIncentivizerUpgradeableV2(address(governedIncentivizer)).upgradeVersion(), 2);
        assertEq(governedIncentivizer.currentCycleId(), 1);
    }

    function _deployIncentivizer(address governorAddress, address initialToken)
        internal
        returns (GovernanceCycleIncentivizerUpgradeable deployed)
    {
        address[] memory initTokens = new address[](1);
        initTokens[0] = initialToken;
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(GovernanceCycleIncentivizerUpgradeable.initialize, (governorAddress, initTokens))
        );
        deployed = GovernanceCycleIncentivizerUpgradeable(address(proxy));
    }

    /// @notice Test initialize seeds cycle and treasury metadata.
    function testInitializeSeedsCycleAndTreasuryMetadata() external view {
        (
            uint128 currentCycleId,
            uint128 rewardRatio,
            address governorAddress,
            address[] memory treasuryTokenList,
            address[] memory rewardTokenList
        ) = incentivizer.metaData();

        assertEq(currentCycleId, 1);
        assertEq(rewardRatio, 5000);
        assertEq(governorAddress, address(governor));
        assertEq(treasuryTokenList.length, 1);
        assertEq(treasuryTokenList[0], address(tokenA));
        assertEq(rewardTokenList.length, 0);
    }

    /// @notice Test view helpers return false or zero when cycle has no matching data.
    function testViewHelpersReturnFalseOrZeroWhenCycleHasNoMatchingData() external view {
        assertFalse(incentivizer.isTreasuryToken(1, address(tokenB)));
        assertFalse(incentivizer.isRewardToken(1, address(tokenB)));
        assertEq(incentivizer.getClaimableReward(address(0x1), address(tokenA)), 0);
        assertEq(incentivizer.getRemainingClaimableRewards(address(tokenA)), 0);

        (address[] memory rewardTokens, uint256[] memory rewards) = incentivizer.getClaimableReward(address(0x1));
        assertEq(rewardTokens.length, 0);
        assertEq(rewards.length, 0);

        (address[] memory remainingTokens, uint256[] memory remainingRewards) =
            incentivizer.getRemainingClaimableRewards();
        assertEq(remainingTokens.length, 0);
        assertEq(remainingRewards.length, 0);
    }

    /// @notice Test historical view helpers read frozen lists after finalize.
    function testHistoricalViewHelpersReadFrozenListsAfterFinalize() external {
        tokenA.mint(address(governor), 100 ether);
        tokenB.mint(address(governor), 40 ether);
        vm.startPrank(address(governor));
        incentivizer.registerTreasuryToken(address(tokenB));
        incentivizer.registerRewardToken(address(tokenA));
        incentivizer.recordTreasuryIncome(address(tokenA), 100 ether);
        incentivizer.recordTreasuryIncome(address(tokenB), 40 ether);
        incentivizer.accumCycleVotes(address(this), 100);
        vm.stopPrank();

        vm.warp(block.timestamp + 90 days);
        incentivizer.finalizeCurrentCycle();

        assertTrue(incentivizer.isTreasuryToken(1, address(tokenA)));
        assertTrue(incentivizer.isTreasuryToken(1, address(tokenB)));
        assertTrue(incentivizer.isRewardToken(1, address(tokenA)));
        assertFalse(incentivizer.isRewardToken(1, address(tokenB)));

        (address[] memory tokens, uint256[] memory balances) = incentivizer.getTreasuryBalances(1);
        assertEq(tokens.length, 2);
        assertEq(balances.length, 2);

        (address[] memory rewardTokens, uint256[] memory rewards) = incentivizer.getClaimableReward(address(this));
        assertEq(rewardTokens.length, 1);
        assertEq(rewards.length, 1);
        assertEq(rewardTokens[0], address(tokenA));
        assertEq(rewards[0], 50 ether);

        (address[] memory remainingTokens, uint256[] memory remainingRewards) =
            incentivizer.getRemainingClaimableRewards();
        assertEq(remainingTokens.length, 1);
        assertEq(remainingRewards.length, 1);
        assertEq(remainingTokens[0], address(tokenA));
        assertEq(remainingRewards[0], 50 ether);
    }

    /// @notice Test governance registration guards and token lists.
    function testGovernanceRegistrationGuardsAndTokenLists() external {
        vm.prank(OTHER);
        vm.expectRevert(IGovernanceCycleIncentivizer.PermissionDenied.selector);
        incentivizer.registerTreasuryToken(address(tokenB));

        vm.prank(address(governor));
        vm.expectRevert(IGovernanceCycleIncentivizer.ZeroInput.selector);
        incentivizer.registerTreasuryToken(address(0));

        vm.prank(address(governor));
        vm.expectRevert(IGovernanceCycleIncentivizer.RegisteredToken.selector);
        incentivizer.registerTreasuryToken(address(tokenA));

        vm.prank(address(governor));
        vm.expectRevert(IGovernanceCycleIncentivizer.NonTreasuryToken.selector);
        incentivizer.registerRewardToken(address(tokenB));

        vm.prank(address(governor));
        incentivizer.registerTreasuryToken(address(tokenB));
        assertTrue(incentivizer.isTreasuryToken(1, address(tokenB)));

        vm.prank(address(governor));
        incentivizer.registerRewardToken(address(tokenB));
        assertTrue(incentivizer.isRewardToken(1, address(tokenB)));

        vm.prank(address(governor));
        incentivizer.unregisterRewardToken(address(tokenB));
        assertFalse(incentivizer.isRewardToken(1, address(tokenB)));

        vm.prank(address(governor));
        incentivizer.unregisterTreasuryToken(address(tokenB));
        assertFalse(incentivizer.isTreasuryToken(1, address(tokenB)));
    }

    /// @notice Test register treasury token respects max list size.
    function testRegisterTreasuryTokenRespectsMaxListSize() external {
        for (uint256 i = 0; i < incentivizer.MAX_TOKENS_LIMIT() - 1; i++) {
            MockERC20 extra = new MockERC20("Extra", "EXT", 18);
            vm.prank(address(governor));
            incentivizer.registerTreasuryToken(address(extra));
        }

        MockERC20 overflowToken = new MockERC20("Overflow", "OVR", 18);
        vm.prank(address(governor));
        vm.expectRevert(IGovernanceCycleIncentivizer.OutOfMaxTokensLimit.selector);
        incentivizer.registerTreasuryToken(address(overflowToken));
    }

    /// @notice Test register reward token rejects zero input and duplicate token.
    function testRegisterRewardTokenRejectsZeroInputAndDuplicateToken() external {
        vm.prank(address(governor));
        vm.expectRevert(IGovernanceCycleIncentivizer.ZeroInput.selector);
        incentivizer.registerRewardToken(address(0));

        vm.prank(address(governor));
        incentivizer.registerRewardToken(address(tokenA));

        vm.prank(address(governor));
        vm.expectRevert(IGovernanceCycleIncentivizer.RegisteredToken.selector);
        incentivizer.registerRewardToken(address(tokenA));
    }

    /// @notice Test unregister functions reject non registered tokens.
    function testUnregisterFunctionsRejectNonRegisteredTokens() external {
        vm.prank(address(governor));
        vm.expectRevert(IGovernanceCycleIncentivizer.NonRegisteredToken.selector);
        incentivizer.unregisterRewardToken(address(tokenB));

        vm.prank(address(governor));
        vm.expectRevert(IGovernanceCycleIncentivizer.NonRegisteredToken.selector);
        incentivizer.unregisterTreasuryToken(address(tokenB));
    }

    /// @notice Test unregister treasury token also removes reward registration.
    function testUnregisterTreasuryTokenAlsoRemovesRewardRegistration() external {
        vm.startPrank(address(governor));
        incentivizer.registerTreasuryToken(address(tokenB));
        incentivizer.registerRewardToken(address(tokenB));
        vm.stopPrank();

        vm.prank(address(governor));
        incentivizer.unregisterTreasuryToken(address(tokenB));

        assertFalse(incentivizer.isTreasuryToken(1, address(tokenB)));
        assertFalse(incentivizer.isRewardToken(1, address(tokenB)));
    }

    /// @notice Test unregister treasury token without reward registration keeps other reward list untouched.
    function testUnregisterTreasuryTokenWithoutRewardRegistrationKeepsOtherRewardListUntouched() external {
        vm.prank(address(governor));
        incentivizer.registerTreasuryToken(address(tokenB));

        vm.prank(address(governor));
        incentivizer.unregisterTreasuryToken(address(tokenB));

        assertFalse(incentivizer.isTreasuryToken(1, address(tokenB)));
        assertFalse(incentivizer.isRewardToken(1, address(tokenB)));
    }

    /// @notice Test receive and send treasury assets track balances.
    function testRecordTreasuryIncomeAndSpendTrackBalances() external {
        tokenA.mint(address(governor), 100 ether);

        vm.expectRevert(IGovernanceCycleIncentivizer.ZeroInput.selector);
        vm.prank(address(governor));
        incentivizer.recordTreasuryIncome(address(0), 1 ether);

        vm.expectRevert(IGovernanceCycleIncentivizer.NonTreasuryToken.selector);
        vm.prank(address(governor));
        incentivizer.recordTreasuryIncome(address(tokenB), 1 ether);

        vm.prank(address(governor));
        incentivizer.recordTreasuryIncome(address(tokenA), 100 ether);
        assertEq(incentivizer.getTreasuryBalance(1, address(tokenA)), 100 ether);

        vm.prank(OTHER);
        vm.expectRevert(IGovernanceCycleIncentivizer.PermissionDenied.selector);
        incentivizer.recordTreasuryAssetSpend(address(tokenA), OTHER, 1 ether);

        vm.prank(address(governor));
        vm.expectRevert(IGovernanceCycleIncentivizer.InsufficientTreasuryBalance.selector);
        incentivizer.recordTreasuryAssetSpend(address(tokenA), OTHER, 101 ether);

        vm.prank(address(governor));
        incentivizer.recordTreasuryAssetSpend(address(tokenA), OTHER, 40 ether);
        assertEq(incentivizer.getTreasuryBalance(1, address(tokenA)), 60 ether);
    }

    /// @notice Test record treasury asset spend rejects zero input and non treasury token.
    function testRecordTreasuryAssetSpendRejectsZeroInputAndNonTreasuryToken() external {
        vm.prank(address(governor));
        vm.expectRevert(IGovernanceCycleIncentivizer.ZeroInput.selector);
        incentivizer.recordTreasuryAssetSpend(address(0), OTHER, 1 ether);

        vm.prank(address(governor));
        vm.expectRevert(IGovernanceCycleIncentivizer.NonTreasuryToken.selector);
        incentivizer.recordTreasuryAssetSpend(address(tokenB), OTHER, 1 ether);
    }

    /// @notice Test record treasury asset spend reverts when recorded balance exceeds actual holdings.
    function testRecordTreasuryAssetSpendRevertsWhenRecordedBalanceExceedsActualHoldings() external {
        vm.prank(address(governor));
        incentivizer.recordTreasuryIncome(address(tokenA), 10 ether);

        vm.prank(address(governor));
        vm.expectRevert(IGovernanceCycleIncentivizer.InsufficientTreasuryBalance.selector);
        incentivizer.recordTreasuryAssetSpend(address(tokenA), OTHER, 1 ether);
    }

    /// @notice Test finalize current cycle distributes rewards and starts next cycle.
    function testFinalizeCurrentCycleDistributesRewardsAndStartsNextCycle() external {
        tokenA.mint(address(governor), 100 ether);

        vm.startPrank(address(governor));
        incentivizer.registerRewardToken(address(tokenA));
        incentivizer.recordTreasuryIncome(address(tokenA), 100 ether);
        incentivizer.accumCycleVotes(address(0x1), 40);
        incentivizer.accumCycleVotes(address(0x2), 60);
        vm.stopPrank();

        vm.warp(block.timestamp + 90 days);
        incentivizer.finalizeCurrentCycle();

        assertEq(incentivizer.currentCycleId(), 2);
        assertEq(incentivizer.getClaimableReward(address(0x1), address(tokenA)), 20 ether);
        assertEq(incentivizer.getClaimableReward(address(0x2), address(tokenA)), 30 ether);
        assertEq(incentivizer.getTreasuryBalance(2, address(tokenA)), 50 ether);
    }

    /// @notice Test finalize current cycle reverts before end and carries undistributed rewards forward.
    function testFinalizeCurrentCycleRevertsBeforeEndAndCarriesUndistributedRewardsForward() external {
        tokenA.mint(address(governor), 100 ether);
        vm.startPrank(address(governor));
        incentivizer.registerRewardToken(address(tokenA));
        incentivizer.recordTreasuryIncome(address(tokenA), 100 ether);
        vm.stopPrank();

        vm.expectRevert(IGovernanceCycleIncentivizer.CycleNotEnded.selector);
        incentivizer.finalizeCurrentCycle();

        vm.warp(block.timestamp + 90 days);
        incentivizer.finalizeCurrentCycle();

        assertEq(incentivizer.currentCycleId(), 2);
        assertEq(incentivizer.getTreasuryBalance(2, address(tokenA)), 100 ether);
        assertEq(incentivizer.getRemainingClaimableRewards(address(tokenA)), 0);
    }

    /// @notice Test finalize next cycle carries forward unclaimed rewards into treasury.
    function testFinalizeNextCycleCarriesForwardUnclaimedRewardsIntoTreasury() external {
        tokenA.mint(address(governor), 100 ether);
        vm.startPrank(address(governor));
        incentivizer.registerRewardToken(address(tokenA));
        incentivizer.recordTreasuryIncome(address(tokenA), 100 ether);
        incentivizer.accumCycleVotes(address(this), 100);
        vm.stopPrank();

        vm.warp(block.timestamp + 90 days);
        incentivizer.finalizeCurrentCycle();

        // Do not claim cycle 1 rewards, then finalize cycle 2 to force carry-over of prev reward balance.
        vm.warp(block.timestamp + 90 days + 1);
        incentivizer.finalizeCurrentCycle();

        assertEq(incentivizer.currentCycleId(), 3);
        assertEq(incentivizer.getTreasuryBalance(3, address(tokenA)), 100 ether);
        assertEq(incentivizer.getRemainingClaimableRewards(address(tokenA)), 0);
    }

    /// @notice Test finalize with reward token but no votes keeps treasury balance undistributed.
    function testFinalizeWithRewardTokenButNoVotesKeepsTreasuryBalanceUndistributed() external {
        tokenA.mint(address(governor), 100 ether);
        vm.startPrank(address(governor));
        incentivizer.registerRewardToken(address(tokenA));
        incentivizer.recordTreasuryIncome(address(tokenA), 100 ether);
        vm.stopPrank();

        vm.warp(block.timestamp + 90 days);
        incentivizer.finalizeCurrentCycle();

        assertEq(incentivizer.currentCycleId(), 2);
        assertEq(incentivizer.getTreasuryBalance(2, address(tokenA)), 100 ether);
        assertEq(incentivizer.getClaimableReward(address(this), address(tokenA)), 0);
    }

    /// @notice Test claim reward transfers previous cycle rewards.
    function testClaimRewardTransfersPreviousCycleRewards() external {
        tokenA.mint(address(governor), 100 ether);

        vm.startPrank(address(governor));
        incentivizer.registerRewardToken(address(tokenA));
        incentivizer.recordTreasuryIncome(address(tokenA), 100 ether);
        incentivizer.accumCycleVotes(address(this), 100);
        vm.stopPrank();

        vm.warp(block.timestamp + 90 days);
        incentivizer.finalizeCurrentCycle();

        uint256 beforeBalance = tokenA.balanceOf(address(this));
        incentivizer.claimReward();
        uint256 afterBalance = tokenA.balanceOf(address(this));

        assertEq(afterBalance - beforeBalance, 50 ether);
        assertEq(incentivizer.getRemainingClaimableRewards(address(tokenA)), 0);
        assertEq(governor.lastRewardToken(), address(tokenA));
        assertEq(governor.lastRewardTo(), address(this));
        assertEq(governor.lastRewardAmount(), 50 ether);
    }

    /// @notice Test claim reward reverts without votes and supports partial rewards across users.
    function testClaimRewardRevertsWithoutVotesAndSupportsPartialRewardsAcrossUsers() external {
        vm.prank(OTHER);
        vm.expectRevert(IGovernanceCycleIncentivizer.NoRewardsToClaim.selector);
        incentivizer.claimReward();

        vm.expectRevert(IGovernanceCycleIncentivizer.NoRewardsToClaim.selector);
        incentivizer.claimReward();

        tokenA.mint(address(governor), 100 ether);
        vm.startPrank(address(governor));
        incentivizer.registerRewardToken(address(tokenA));
        incentivizer.recordTreasuryIncome(address(tokenA), 100 ether);
        incentivizer.accumCycleVotes(address(this), 40);
        incentivizer.accumCycleVotes(OTHER, 60);
        vm.stopPrank();

        vm.warp(block.timestamp + 90 days);
        incentivizer.finalizeCurrentCycle();

        uint256 before = tokenA.balanceOf(address(this));
        incentivizer.claimReward();
        uint256 claimed = tokenA.balanceOf(address(this)) - before;

        assertEq(claimed, 20 ether);
        assertEq(incentivizer.getRemainingClaimableRewards(address(tokenA)), 30 ether);
    }

    /// @notice Test claim reward clears votes even when rounded reward is zero.
    function testClaimRewardClearsVotesEvenWhenRoundedRewardIsZero() external {
        tokenA.mint(address(governor), 1 ether);
        vm.startPrank(address(governor));
        incentivizer.registerRewardToken(address(tokenA));
        incentivizer.recordTreasuryIncome(address(tokenA), 1 ether);
        incentivizer.accumCycleVotes(address(this), 1);
        incentivizer.accumCycleVotes(OTHER, 10_000);
        vm.stopPrank();

        vm.warp(block.timestamp + 90 days);
        incentivizer.finalizeCurrentCycle();

        incentivizer.claimReward();

        assertEq(incentivizer.getClaimableReward(address(this), address(tokenA)), 0);
    }

    /// @notice Test accum cycle votes requires governance.
    function testAccumCycleVotesRequiresGovernance() external {
        vm.prank(OTHER);
        vm.expectRevert(IGovernanceCycleIncentivizer.PermissionDenied.selector);
        incentivizer.accumCycleVotes(OTHER, 1 ether);
    }

    /// @notice Test update reward ratio checks bounds.
    function testUpdateRewardRatioChecksBounds() external {
        vm.prank(OTHER);
        vm.expectRevert(IGovernanceCycleIncentivizer.PermissionDenied.selector);
        incentivizer.updateRewardRatio(1);

        vm.prank(address(governor));
        vm.expectRevert(IGovernanceCycleIncentivizer.InvalidRewardRatio.selector);
        incentivizer.updateRewardRatio(10001);

        vm.prank(address(governor));
        incentivizer.updateRewardRatio(2500);
        (, uint128 rewardRatio,,,) = incentivizer.metaData();
        assertEq(rewardRatio, 2500);
    }
}

contract GovernanceCycleIncentivizerUpgradeableV2 is GovernanceCycleIncentivizerUpgradeable {
    function upgradeVersion() external pure returns (uint256) {
        return 2;
    }
}
