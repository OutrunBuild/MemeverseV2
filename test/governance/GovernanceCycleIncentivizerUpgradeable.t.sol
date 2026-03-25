// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {IGovernanceCycleIncentivizer} from "../../src/governance/interfaces/IGovernanceCycleIncentivizer.sol";
import {GovernanceCycleIncentivizerUpgradeable} from "../../src/governance/GovernanceCycleIncentivizerUpgradeable.sol";

contract GovernanceCycleIncentivizerUpgradeableTest is Test {
    address internal constant OTHER = address(0xBEEF);

    GovernanceCycleIncentivizerUpgradeable internal implementation;
    GovernanceCycleIncentivizerUpgradeable internal incentivizer;
    MockERC20 internal tokenA;
    MockERC20 internal tokenB;

    /// @notice Set up.
    function setUp() external {
        implementation = new GovernanceCycleIncentivizerUpgradeable();
        tokenA = new MockERC20("TokenA", "TKA", 18);
        tokenB = new MockERC20("TokenB", "TKB", 18);

        incentivizer = _deployIncentivizer(address(this), address(tokenA));
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

    function _deployIncentivizer(address governor, address initialToken)
        internal
        returns (GovernanceCycleIncentivizerUpgradeable deployed)
    {
        address[] memory initTokens = new address[](1);
        initTokens[0] = initialToken;
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeCall(GovernanceCycleIncentivizerUpgradeable.initialize, (governor, initTokens))
        );
        deployed = GovernanceCycleIncentivizerUpgradeable(address(proxy));
    }

    /// @notice Test initialize seeds cycle and treasury metadata.
    function testInitializeSeedsCycleAndTreasuryMetadata() external view {
        (
            uint128 currentCycleId,
            uint128 rewardRatio,
            address governor,
            address[] memory treasuryTokenList,
            address[] memory rewardTokenList
        ) = incentivizer.metaData();

        assertEq(currentCycleId, 1);
        assertEq(rewardRatio, 5000);
        assertEq(governor, address(this));
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
        tokenA.mint(address(incentivizer), 100 ether);
        tokenB.mint(address(incentivizer), 40 ether);
        incentivizer.registerTreasuryToken(address(tokenB));
        incentivizer.registerRewardToken(address(tokenA));
        incentivizer.receiveTreasuryIncome(address(tokenA), 100 ether);
        incentivizer.receiveTreasuryIncome(address(tokenB), 40 ether);
        incentivizer.accumCycleVotes(address(this), 100);

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

        vm.expectRevert(IGovernanceCycleIncentivizer.ZeroInput.selector);
        incentivizer.registerTreasuryToken(address(0));

        vm.expectRevert(IGovernanceCycleIncentivizer.RegisteredToken.selector);
        incentivizer.registerTreasuryToken(address(tokenA));

        vm.expectRevert(IGovernanceCycleIncentivizer.NonTreasuryToken.selector);
        incentivizer.registerRewardToken(address(tokenB));

        incentivizer.registerTreasuryToken(address(tokenB));
        assertTrue(incentivizer.isTreasuryToken(1, address(tokenB)));

        incentivizer.registerRewardToken(address(tokenB));
        assertTrue(incentivizer.isRewardToken(1, address(tokenB)));

        incentivizer.unregisterRewardToken(address(tokenB));
        assertFalse(incentivizer.isRewardToken(1, address(tokenB)));

        incentivizer.unregisterTreasuryToken(address(tokenB));
        assertFalse(incentivizer.isTreasuryToken(1, address(tokenB)));
    }

    /// @notice Test register treasury token respects max list size.
    function testRegisterTreasuryTokenRespectsMaxListSize() external {
        for (uint256 i = 0; i < incentivizer.MAX_TOKENS_LIMIT() - 1; i++) {
            MockERC20 extra = new MockERC20("Extra", "EXT", 18);
            incentivizer.registerTreasuryToken(address(extra));
        }

        MockERC20 overflowToken = new MockERC20("Overflow", "OVR", 18);
        vm.expectRevert(IGovernanceCycleIncentivizer.OutOfMaxTokensLimit.selector);
        incentivizer.registerTreasuryToken(address(overflowToken));
    }

    /// @notice Test register reward token rejects zero input and duplicate token.
    function testRegisterRewardTokenRejectsZeroInputAndDuplicateToken() external {
        vm.expectRevert(IGovernanceCycleIncentivizer.ZeroInput.selector);
        incentivizer.registerRewardToken(address(0));

        incentivizer.registerRewardToken(address(tokenA));

        vm.expectRevert(IGovernanceCycleIncentivizer.RegisteredToken.selector);
        incentivizer.registerRewardToken(address(tokenA));
    }

    /// @notice Test unregister functions reject non registered tokens.
    function testUnregisterFunctionsRejectNonRegisteredTokens() external {
        vm.expectRevert(IGovernanceCycleIncentivizer.NonRegisteredToken.selector);
        incentivizer.unregisterRewardToken(address(tokenB));

        vm.expectRevert(IGovernanceCycleIncentivizer.NonRegisteredToken.selector);
        incentivizer.unregisterTreasuryToken(address(tokenB));
    }

    /// @notice Test unregister treasury token also removes reward registration.
    function testUnregisterTreasuryTokenAlsoRemovesRewardRegistration() external {
        incentivizer.registerTreasuryToken(address(tokenB));
        incentivizer.registerRewardToken(address(tokenB));

        incentivizer.unregisterTreasuryToken(address(tokenB));

        assertFalse(incentivizer.isTreasuryToken(1, address(tokenB)));
        assertFalse(incentivizer.isRewardToken(1, address(tokenB)));
    }

    /// @notice Test unregister treasury token without reward registration keeps other reward list untouched.
    function testUnregisterTreasuryTokenWithoutRewardRegistrationKeepsOtherRewardListUntouched() external {
        incentivizer.registerTreasuryToken(address(tokenB));

        incentivizer.unregisterTreasuryToken(address(tokenB));

        assertFalse(incentivizer.isTreasuryToken(1, address(tokenB)));
        assertFalse(incentivizer.isRewardToken(1, address(tokenB)));
    }

    /// @notice Test receive and send treasury assets track balances.
    function testReceiveAndSendTreasuryAssetsTrackBalances() external {
        tokenA.mint(address(this), 100 ether);

        vm.expectRevert(IGovernanceCycleIncentivizer.ZeroInput.selector);
        incentivizer.receiveTreasuryIncome(address(0), 1 ether);

        vm.expectRevert(IGovernanceCycleIncentivizer.NonTreasuryToken.selector);
        incentivizer.receiveTreasuryIncome(address(tokenB), 1 ether);

        incentivizer.receiveTreasuryIncome(address(tokenA), 100 ether);
        assertEq(incentivizer.getTreasuryBalance(1, address(tokenA)), 100 ether);

        vm.prank(OTHER);
        vm.expectRevert(IGovernanceCycleIncentivizer.PermissionDenied.selector);
        incentivizer.sendTreasuryAssets(address(tokenA), OTHER, 1 ether);

        vm.expectRevert(IGovernanceCycleIncentivizer.InsufficientTreasuryBalance.selector);
        incentivizer.sendTreasuryAssets(address(tokenA), OTHER, 101 ether);

        incentivizer.sendTreasuryAssets(address(tokenA), OTHER, 40 ether);
        assertEq(incentivizer.getTreasuryBalance(1, address(tokenA)), 60 ether);
    }

    /// @notice Test send treasury assets rejects zero input and non treasury token.
    function testSendTreasuryAssetsRejectsZeroInputAndNonTreasuryToken() external {
        vm.expectRevert(IGovernanceCycleIncentivizer.ZeroInput.selector);
        incentivizer.sendTreasuryAssets(address(0), OTHER, 1 ether);

        vm.expectRevert(IGovernanceCycleIncentivizer.NonTreasuryToken.selector);
        incentivizer.sendTreasuryAssets(address(tokenB), OTHER, 1 ether);
    }

    /// @notice Test send treasury assets reverts when recorded balance exceeds actual holdings.
    function testSendTreasuryAssetsRevertsWhenRecordedBalanceExceedsActualHoldings() external {
        incentivizer.receiveTreasuryIncome(address(tokenA), 10 ether);

        vm.expectRevert(IGovernanceCycleIncentivizer.InsufficientTreasuryBalance.selector);
        incentivizer.sendTreasuryAssets(address(tokenA), OTHER, 1 ether);
    }

    /// @notice Test finalize current cycle distributes rewards and starts next cycle.
    function testFinalizeCurrentCycleDistributesRewardsAndStartsNextCycle() external {
        tokenA.mint(address(incentivizer), 100 ether);

        incentivizer.registerRewardToken(address(tokenA));
        incentivizer.receiveTreasuryIncome(address(tokenA), 100 ether);
        incentivizer.accumCycleVotes(address(0x1), 40);
        incentivizer.accumCycleVotes(address(0x2), 60);

        vm.warp(block.timestamp + 90 days);
        incentivizer.finalizeCurrentCycle();

        assertEq(incentivizer.currentCycleId(), 2);
        assertEq(incentivizer.getClaimableReward(address(0x1), address(tokenA)), 20 ether);
        assertEq(incentivizer.getClaimableReward(address(0x2), address(tokenA)), 30 ether);
        assertEq(incentivizer.getTreasuryBalance(2, address(tokenA)), 50 ether);
    }

    /// @notice Test finalize current cycle reverts before end and carries undistributed rewards forward.
    function testFinalizeCurrentCycleRevertsBeforeEndAndCarriesUndistributedRewardsForward() external {
        tokenA.mint(address(incentivizer), 100 ether);
        incentivizer.registerRewardToken(address(tokenA));
        incentivizer.receiveTreasuryIncome(address(tokenA), 100 ether);

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
        tokenA.mint(address(incentivizer), 100 ether);
        incentivizer.registerRewardToken(address(tokenA));
        incentivizer.receiveTreasuryIncome(address(tokenA), 100 ether);
        incentivizer.accumCycleVotes(address(this), 100);

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
        tokenA.mint(address(incentivizer), 100 ether);
        incentivizer.registerRewardToken(address(tokenA));
        incentivizer.receiveTreasuryIncome(address(tokenA), 100 ether);

        vm.warp(block.timestamp + 90 days);
        incentivizer.finalizeCurrentCycle();

        assertEq(incentivizer.currentCycleId(), 2);
        assertEq(incentivizer.getTreasuryBalance(2, address(tokenA)), 100 ether);
        assertEq(incentivizer.getClaimableReward(address(this), address(tokenA)), 0);
    }

    /// @notice Test claim reward transfers previous cycle rewards.
    function testClaimRewardTransfersPreviousCycleRewards() external {
        tokenA.mint(address(incentivizer), 100 ether);

        incentivizer.registerRewardToken(address(tokenA));
        incentivizer.receiveTreasuryIncome(address(tokenA), 100 ether);
        incentivizer.accumCycleVotes(address(this), 100);

        vm.warp(block.timestamp + 90 days);
        incentivizer.finalizeCurrentCycle();

        uint256 beforeBalance = tokenA.balanceOf(address(this));
        incentivizer.claimReward();
        uint256 afterBalance = tokenA.balanceOf(address(this));

        assertEq(afterBalance - beforeBalance, 50 ether);
        assertEq(incentivizer.getRemainingClaimableRewards(address(tokenA)), 0);
    }

    /// @notice Test claim reward reverts without votes and supports partial rewards across users.
    function testClaimRewardRevertsWithoutVotesAndSupportsPartialRewardsAcrossUsers() external {
        vm.prank(OTHER);
        vm.expectRevert(IGovernanceCycleIncentivizer.PermissionDenied.selector);
        incentivizer.claimReward();

        vm.expectRevert(IGovernanceCycleIncentivizer.NoRewardsToClaim.selector);
        incentivizer.claimReward();

        tokenA.mint(address(incentivizer), 100 ether);
        incentivizer.registerRewardToken(address(tokenA));
        incentivizer.receiveTreasuryIncome(address(tokenA), 100 ether);
        incentivizer.accumCycleVotes(address(this), 40);
        incentivizer.accumCycleVotes(OTHER, 60);

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
        tokenA.mint(address(incentivizer), 1 ether);
        incentivizer.registerRewardToken(address(tokenA));
        incentivizer.receiveTreasuryIncome(address(tokenA), 1 ether);
        incentivizer.accumCycleVotes(address(this), 1);
        incentivizer.accumCycleVotes(OTHER, 10_000);

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

        vm.expectRevert(IGovernanceCycleIncentivizer.InvalidRewardRatio.selector);
        incentivizer.updateRewardRatio(10001);

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
