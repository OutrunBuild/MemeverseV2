// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {MemecoinYieldVault} from "../../src/yield/MemecoinYieldVault.sol";
import {IMemecoinYieldVault} from "../../src/yield/interfaces/IMemecoinYieldVault.sol";

contract MockComposeAsset is MockERC20 {
    mapping(bytes32 guid => uint256 amount) internal queuedAmounts;

    constructor() MockERC20("Compose Memecoin", "cMEME", 18) {}

    /// @notice Stores the queued compose amount keyed by LayerZero guid.
    /// @dev Test helper for simulating `withdrawIfNotExecuted` availability.
    /// @param guid The LayerZero message guid.
    /// @param amount The amount that should be withdrawn for this guid.
    function setQueuedAmount(bytes32 guid, uint256 amount) external {
        queuedAmounts[guid] = amount;
    }

    /// @notice Mints the queued amount to `receiver` and clears the guid entry.
    /// @dev Test helper mirroring the production `IOFTCompose.withdrawIfNotExecuted` shape.
    /// @param guid The LayerZero message guid.
    /// @param receiver The address receiving the withdrawn tokens.
    /// @return amount The amount withdrawn for the guid.
    function withdrawIfNotExecuted(bytes32 guid, address receiver) external returns (uint256 amount) {
        amount = queuedAmounts[guid];
        queuedAmounts[guid] = 0;
        mint(receiver, amount);
    }

    /// @notice Burns test tokens from the caller.
    /// @dev Used to satisfy the vault path that burns yield when no shares exist.
    /// @param amount The token amount to burn.
    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}



contract MemecoinYieldVaultTest is Test {
    address internal constant ATTACKER = address(0xA11CE);
    address internal constant VICTIM = address(0xB0B);
    address internal constant RECEIVER = address(0xCAFE);

    MockERC20 internal asset;
    MemecoinYieldVault internal vault;

    /// @notice Deploys a fresh vault clone and seeds attacker/victim balances.
    /// @dev Reuses the production initializer path so tests exercise clone semantics.
    function setUp() external {
        asset = new MockERC20("Memecoin", "MEME", 18);
        MemecoinYieldVault implementation = new MemecoinYieldVault();
        vault = MemecoinYieldVault(Clones.clone(address(implementation)));
        vault.initialize("Staked Memecoin", "sMEME", address(0xD15A7), address(asset), 1);

        asset.mint(ATTACKER, 1_001 ether);
        asset.mint(VICTIM, 2_000 ether);

        vm.prank(ATTACKER);
        asset.approve(address(vault), type(uint256).max);

        vm.prank(VICTIM);
        asset.approve(address(vault), type(uint256).max);
    }

    /// @notice Verifies public yield injection cannot make the first depositor profitable.
    /// @dev Models the donation-style inflation path through `accumulateYields`.
    function testInflationAttackIsNotProfitableAfterPublicYieldInjection() external {
        uint256 attackerInitialBalance = asset.balanceOf(ATTACKER);

        vm.startPrank(ATTACKER);
        uint256 attackerShares = vault.deposit(1, ATTACKER);
        vault.accumulateYields(1_000 ether);
        vm.stopPrank();

        vm.prank(VICTIM);
        vault.deposit(2_000 ether, VICTIM);

        vm.prank(ATTACKER);
        vault.requestRedeem(attackerShares, ATTACKER);

        vm.warp(block.timestamp + 1 days);

        vm.prank(ATTACKER);
        vault.executeRedeem();

        assertLe(asset.balanceOf(ATTACKER), attackerInitialBalance, "attacker profit");
    }

    /// @notice Verifies raw ERC20 transfers into the vault do not affect share pricing.
    /// @dev Confirms pricing relies on managed assets rather than `balanceOf(address(this))`.
    function testDirectAssetDonationDoesNotChangeSharePricing() external {
        vm.prank(ATTACKER);
        vault.deposit(10 ether, ATTACKER);

        // Direct ERC20 donations should not move the preview path because pricing tracks managed assets only.
        uint256 previewBefore = vault.previewDeposit(20 ether);

        vm.prank(ATTACKER);
        assertTrue(asset.transfer(address(vault), 500 ether));

        uint256 previewAfter = vault.previewDeposit(20 ether);

        vm.prank(VICTIM);
        uint256 actualShares = vault.deposit(20 ether, VICTIM);

        assertEq(previewAfter, previewBefore, "preview changed by raw donation");
        assertEq(actualShares, previewBefore, "deposit changed by raw donation");
    }

    /// @notice Verifies repeated victim deposits still do not make public yield injection profitable.
    /// @dev Extends the inflation test to multiple downstream deposits.
    function testPublicYieldInjectionRemainsUnprofitableAcrossMultipleDeposits() external {
        uint256 attackerInitialBalance = asset.balanceOf(ATTACKER);
        address victimTwo = address(0xB0B2);

        asset.mint(victimTwo, 2_000 ether);
        vm.prank(victimTwo);
        asset.approve(address(vault), type(uint256).max);

        vm.startPrank(ATTACKER);
        uint256 attackerShares = vault.deposit(1 ether, ATTACKER);
        vault.accumulateYields(1_000 ether);
        vm.stopPrank();

        vm.prank(VICTIM);
        vault.deposit(1_000 ether, VICTIM);

        vm.prank(victimTwo);
        vault.deposit(1_000 ether, victimTwo);

        vm.prank(ATTACKER);
        vault.requestRedeem(attackerShares, ATTACKER);

        vm.warp(block.timestamp + 1 days);

        vm.prank(ATTACKER);
        vault.executeRedeem();

        assertLe(asset.balanceOf(ATTACKER), attackerInitialBalance, "attacker profit across deposits");
    }

    /// @notice Verifies the nominated redeem receiver can execute the delayed withdrawal.
    /// @dev Confirms queue ownership tracks `receiver` rather than the original share holder.
    function testReceiverCanExecuteRedeemAfterDelay() external {
        vm.prank(ATTACKER);
        uint256 shares = vault.deposit(10 ether, ATTACKER);

        vm.prank(ATTACKER);
        uint256 assetsOut = vault.requestRedeem(shares / 2, RECEIVER);

        vm.warp(block.timestamp + 1 days);

        uint256 receiverBalanceBefore = asset.balanceOf(RECEIVER);

        vm.prank(RECEIVER);
        uint256 redeemedAmount = vault.executeRedeem();

        assertEq(redeemedAmount, assetsOut, "redeemed amount");
        assertEq(asset.balanceOf(RECEIVER) - receiverBalanceBefore, assetsOut, "receiver assets");
    }

    /// @notice Verifies previewed shares match actual shares after yield accumulation.
    /// @dev Guards the pricing path shared by `previewDeposit` and `deposit`.
    function testPreviewDepositMatchesActualDepositAfterYieldAccumulation() external {
        vm.prank(ATTACKER);
        vault.deposit(10 ether, ATTACKER);

        vm.prank(ATTACKER);
        vault.accumulateYields(5 ether);

        uint256 previewedShares = vault.previewDeposit(20 ether);

        vm.prank(VICTIM);
        uint256 actualShares = vault.deposit(20 ether, VICTIM);

        assertEq(actualShares, previewedShares, "preview deposit");
    }

    /// @notice Verifies requestRedeem locks the asset amount at request time regardless of later deposits.
    /// @dev Yield accumulation or new deposits after requestRedeem must not change the queued redemption amount.
    function testRequestRedeem_LocksAssetAmountAgainstSubsequentDeposits() external {
        // A deposits 10 ether, gets 10 shares (1:1 at initial state)
        vm.prank(ATTACKER);
        uint256 sharesA = vault.deposit(10 ether, ATTACKER);
        assertEq(sharesA, 10 ether, "initial shares");

        // Yield accumulates: totalAssets goes from 10 to 15, share price = 1.5
        vm.prank(ATTACKER);
        vault.accumulateYields(5 ether);

        vm.prank(ATTACKER);
        uint256 lockedAssets = vault.requestRedeem(sharesA, ATTACKER);
        assertGt(lockedAssets, 10 ether, "locked reflects yield");

        vm.prank(VICTIM);
        vault.deposit(30 ether, VICTIM);

        vm.warp(block.timestamp + 1 days);

        uint256 attackerBalanceBefore = asset.balanceOf(ATTACKER);
        vm.prank(ATTACKER);
        uint256 redeemed = vault.executeRedeem();

        assertEq(redeemed, lockedAssets, "redeemed amount matches locked");
        assertEq(asset.balanceOf(ATTACKER), attackerBalanceBefore + lockedAssets, "attacker received locked amount");
    }

    /// @notice Verifies `reAccumulateYields` rebooks the withdrawn compose amount into managed assets.
    /// @dev Models the retry path used when a LayerZero compose call to `accumulateYields` previously failed.
    function testReAccumulateYieldsAddsWithdrawnAmountToManagedAssets() external {
        MockComposeAsset composeAsset = new MockComposeAsset();
        MemecoinYieldVault implementation = new MemecoinYieldVault();
        MemecoinYieldVault composeVault = MemecoinYieldVault(Clones.clone(address(implementation)));
        bytes32 guid = keccak256("compose-guid");

        composeVault.initialize("Compose Vault", "cvMEME", address(0xD15A7), address(composeAsset), 2);

        composeAsset.mint(ATTACKER, 10 ether);
        vm.prank(ATTACKER);
        composeAsset.approve(address(composeVault), type(uint256).max);

        vm.prank(ATTACKER);
        composeVault.deposit(10 ether, ATTACKER);

        composeAsset.setQueuedAmount(guid, 5 ether);

        composeVault.reAccumulateYields(guid);

        assertEq(composeVault.totalAssets(), 15 ether, "total assets after re-accumulate");
    }

    /// @notice Verifies the vault reports timestamp-based clock metadata.
    /// @dev Confirms governance snapshotting semantics stay timestamp-based.
    function testClockMetadataUsesTimestampMode() external view {
        assertEq(vault.clock(), uint48(block.timestamp), "clock");
        assertEq(vault.CLOCK_MODE(), "mode=timestamp", "clock mode");
    }

    /// @notice Verifies redeem requests reject zero receivers and zero-asset burns.
    /// @dev Covers both guard branches in `requestRedeem`.
    function testRequestRedeemRevertsOnZeroAddressAndZeroRedeemRequest() external {
        vm.prank(ATTACKER);
        vault.deposit(10 ether, ATTACKER);

        vm.prank(ATTACKER);
        vm.expectRevert(IMemecoinYieldVault.ZeroAddress.selector);
        vault.requestRedeem(1 ether, address(0));

        vm.prank(ATTACKER);
        vm.expectRevert(IMemecoinYieldVault.ZeroRedeemRequest.selector);
        vault.requestRedeem(0, ATTACKER);
    }

    /// @notice Verifies redeem execution before the delay elapses returns zero and leaves the queue intact.
    /// @dev Covers the branch where no queued request is yet claimable.
    function testExecuteRedeemReturnsZeroBeforeDelay() external {
        vm.prank(ATTACKER);
        uint256 shares = vault.deposit(10 ether, ATTACKER);

        vm.prank(ATTACKER);
        vault.requestRedeem(shares / 2, ATTACKER);

        vm.prank(ATTACKER);
        uint256 redeemedAmount = vault.executeRedeem();

        assertEq(redeemedAmount, 0, "redeemed amount");
        (uint192 queuedAmount,) = vault.redeemRequestQueues(ATTACKER, 0);
        assertGt(uint256(queuedAmount), 0, "queue retained");
    }

    /// @notice Verifies redeem execution removes matured entries even when they are not at the queue tail.
    /// @dev Covers the swap-pop branch in `executeRedeem`.
    function testExecuteRedeemRemovesMiddleEntryViaSwapPop() external {
        vm.prank(ATTACKER);
        uint256 shares = vault.deposit(20 ether, ATTACKER);

        vm.prank(ATTACKER);
        vault.requestRedeem(shares / 2, ATTACKER);
        vm.warp(block.timestamp + 1 days);

        vm.prank(ATTACKER);
        vault.requestRedeem(shares / 4, ATTACKER);

        vm.prank(ATTACKER);
        uint256 redeemedAmount = vault.executeRedeem();

        assertGt(redeemedAmount, 0, "redeemed amount");
        (uint192 remainingAmount, uint64 remainingRequestTime) = vault.redeemRequestQueues(ATTACKER, 0);
        assertGt(uint256(remainingAmount), 0, "remaining queue amount");
        assertGt(uint256(remainingRequestTime), 0, "remaining queue request time");
    }

    /// @notice Verifies the queue caps outstanding redeem requests.
    /// @dev Covers the `MaxRedeemRequestsReached` branch.
    function testRequestRedeemRevertsWhenQueueIsFull() external {
        vm.prank(ATTACKER);
        uint256 shares = vault.deposit(10 ether, ATTACKER);

        for (uint256 i = 0; i < vault.MAX_REDEEM_REQUESTS(); i++) {
            vm.prank(ATTACKER);
            vault.requestRedeem(shares / 10, ATTACKER);
        }

        vm.prank(ATTACKER);
        vm.expectRevert(IMemecoinYieldVault.MaxRedeemRequestsReached.selector);
        vault.requestRedeem(1, ATTACKER);
    }

    /// @notice Verifies redeem requests reject asset amounts that cannot fit in the packed uint192 queue entry.
    /// @dev Seeds a large exchange rate via vm.store (direct storage writes) so the request path
    ///      reaches the narrowing conversion without relying on a test-harness subclass.
    function testRequestRedeemRevertsWhenQueuedAssetsOverflowUint192() external {
        // Deploy a standard production vault (no test-harness subclass).
        MemecoinYieldVault implementation = new MemecoinYieldVault();
        MemecoinYieldVault overflowVault = MemecoinYieldVault(Clones.clone(address(implementation)));
        overflowVault.initialize("Overflow Vault", "ovMEME", address(0xD15A7), address(asset), 99);

        // Give the attacker 1 wei of shares via a real deposit so _burn has a valid balance to debit.
        vm.startPrank(ATTACKER);
        asset.approve(address(overflowVault), type(uint256).max);
        overflowVault.deposit(1, ATTACKER);
        vm.stopPrank();

        // Inflate totalAssets to push _convertToAssets above type(uint192).max.
        // With 1 share and totalAssets ≈ 2^200, _convertToAssets(1, totalAssets) ≈ totalAssets / 2 >> uint192.
        uint256 oversizedAssets = uint256(type(uint192).max) + uint256(type(uint128).max) + 1;
        // Slot 2 = totalAssets (regular storage, after yieldDispatcher and asset).
        vm.store(address(overflowVault), bytes32(uint256(2)), bytes32(oversizedAssets));

        // Also inflate ERC20 totalSupply so _burn doesn't underflow.
        // ERC20_STORAGE_LOCATION + 2 = totalSupply (after two mapping fields).
        vm.store(address(overflowVault),
            bytes32(0xae36c519e2a406a79e4c05a9c40dc957f3757904fff7f6a4d18b68c3b12f9302),
            bytes32(uint256(type(uint128).max)));
        // Inflate the attacker's balance so requestRedeem can request a large share amount.
        // keccak256(abi.encode(ATTACKER, ERC20_STORAGE_LOCATION + 0)).
        vm.store(address(overflowVault),
            bytes32(0x819c7a1121989277ca5e22639b1d6fcf99589b7b3581ea632d4a29d6f73e87e4),
            bytes32(uint256(type(uint128).max)));

        uint256 previewAssets = overflowVault.previewRedeem(type(uint128).max);
        assertGt(previewAssets, uint256(type(uint192).max), "preview must exceed uint192");

        vm.prank(ATTACKER);
        vm.expectRevert(abi.encodeWithSelector(IMemecoinYieldVault.RedeemAmountOverflowed.selector, previewAssets));
        overflowVault.requestRedeem(type(uint128).max, ATTACKER);
    }

    // ──────────────────────────────────────────────────────────────────────────────
    // Asset-denominated votes tests
    // ──────────────────────────────────────────────────────────────────────────────

    /// @notice Yield accumulation makes account votes grow by asset value, not stay at raw shares.
    function testYieldAccumulationIncreasesAccountVotesByAssetValue() external {
        vm.prank(ATTACKER);
        uint256 shares = vault.deposit(10 ether, ATTACKER);
        assertEq(shares, 10 ether, "initial shares");

        vm.prank(ATTACKER);
        vault.delegate(ATTACKER);

        uint256 votesBefore = vault.getVotes(ATTACKER);
        assertEq(votesBefore, 10 ether, "votes before yield = shares");

        vm.prank(ATTACKER);
        vault.accumulateYields(10 ether);

        uint256 votesAfter = vault.getVotes(ATTACKER);
        assertGt(votesAfter, votesBefore, "votes must increase after yield");
        assertEq(votesAfter, Math.mulDiv(shares, 20 ether + 1, 10 ether + 1), "votes formula");
    }

    /// @notice Quorum reads asset-denominated total supply, not raw share supply.
    function testQuorumUsesAssetDenominatedTotalSupply() external {
        // Deposit at t=100
        vm.warp(100);
        vm.prank(ATTACKER);
        vault.deposit(10 ether, ATTACKER);

        // Yield at t=200
        vm.warp(200);
        vm.prank(ATTACKER);
        vault.accumulateYields(10 ether);

        // Query at t=300 (past all events)
        vm.warp(300);
        assertEq(vault.getPastTotalSupply(100), 10 ether, "initial total supply = assets");

        uint256 pastTotalAfterYield = vault.getPastTotalSupply(200);
        assertGt(pastTotalAfterYield, 10 ether, "total supply grows with yield");
        assertEq(pastTotalAfterYield, Math.mulDiv(10 ether, 20 ether + 1, 10 ether + 1), "formula");
    }

    /// @notice Asset denomination lets a sub-threshold staker cross proposalThreshold after yield.
    /// @dev Deposits 60 raw shares (below an abstract 100-ether threshold), then yields so the
    ///      asset-denominated votes (≈119) clear it. Pre-fix `getVotes` returned raw shares (60),
    ///      failing the threshold assertion — the denomination lift, not the share count, crosses it.
    function testProposalThresholdAndAccountVotesUseSameUnit() external {
        vm.prank(ATTACKER);
        vault.deposit(60 ether, ATTACKER);
        vm.prank(ATTACKER);
        vault.delegate(ATTACKER);

        // Yield moves totalAssets 60 -> 120, so 60 shares price to ≈119 asset-votes (over the 100 threshold).
        vm.prank(ATTACKER);
        vault.accumulateYields(60 ether);

        uint256 accountVotes = vault.getVotes(ATTACKER);
        // Load-bearing: pre-fix getVotes == 60 (raw shares) would fail; only asset denomination clears 100.
        assertGt(accountVotes, 100 ether, "asset-denominated votes cross threshold after yield");
        assertGt(accountVotes, 60 ether, "votes exceed raw shares");
    }

    /// @notice Post-snapshot donation does not change getPastVotes or getPastTotalSupply.
    function testSnapshotImmutabilityAfterPostSnapshotDonation() external {
        vm.warp(100);
        vm.prank(ATTACKER);
        vault.deposit(10 ether, ATTACKER);
        vm.prank(ATTACKER);
        vault.delegate(ATTACKER);

        vm.warp(200);
        vm.prank(ATTACKER);
        vault.accumulateYields(10 ether);

        vm.warp(300);
        assertEq(vault.getPastVotes(ATTACKER, 100), 10 ether, "votes unchanged at snapshot");
        assertEq(vault.getPastTotalSupply(100), 10 ether, "total supply unchanged at snapshot");
        assertGt(vault.getVotes(ATTACKER), 10 ether, "current votes reflect yield");
    }

    /// @notice requestRedeem immediately removes user votes and queued assets from total supply.
    function testRequestRedeemImmediatelyRemovesVotes() external {
        vm.warp(100);
        vm.prank(ATTACKER);
        uint256 shares = vault.deposit(10 ether, ATTACKER);
        vm.prank(ATTACKER);
        vault.delegate(ATTACKER);

        assertEq(vault.getVotes(ATTACKER), 10 ether, "votes before redeem");

        vm.prank(ATTACKER);
        vault.requestRedeem(shares / 2, ATTACKER);

        assertEq(vault.getVotes(ATTACKER), 5 ether, "votes halved after redeem request");

        vm.warp(200);
        assertEq(vault.getPastTotalSupply(100), 5 ether, "total supply reduced");
    }

    /// @notice After delegation, delegatee votes equal delegated shares converted to asset value.
    function testDelegateeVotesUseAssetDenominatedValue() external {
        vm.prank(ATTACKER);
        vault.deposit(10 ether, ATTACKER);

        vm.prank(ATTACKER);
        vault.delegate(VICTIM);

        uint256 victimVotes = vault.getVotes(VICTIM);
        assertEq(victimVotes, 10 ether, "delegatee votes = depositor shares at 1:1");

        vm.prank(ATTACKER);
        vault.accumulateYields(10 ether);

        uint256 victimVotesAfterYield = vault.getVotes(VICTIM);
        assertGt(victimVotesAfterYield, 10 ether, "delegatee votes grow with yield");
        assertEq(victimVotesAfterYield, Math.mulDiv(10 ether, 20 ether + 1, 10 ether + 1), "formula");
    }

    /// @notice After delegate rebalancing, the moved votes stay consistent with the total.
    /// @dev Re-delegating from a shared delegatee back to self must not change the asset-denominated
    ///      vote total (within rounding). This exercises the `delegate()` path, not share `transfer()`.
    function testDelegateRebalancingKeepsVotesConsistent() external {
        vm.prank(ATTACKER);
        vault.deposit(10 ether, ATTACKER);
        vm.prank(VICTIM);
        vault.deposit(10 ether, VICTIM);

        address delegatee = address(0xBEEF);
        vm.prank(ATTACKER);
        vault.delegate(delegatee);
        vm.prank(VICTIM);
        vault.delegate(delegatee);

        assertEq(vault.getVotes(delegatee), 20 ether, "combined delegation");

        vm.prank(ATTACKER);
        vault.accumulateYields(10 ether);

        uint256 totalDelegatedAfterYield = vault.getVotes(delegatee);
        assertGt(totalDelegatedAfterYield, 20 ether, "combined votes grow with yield");

        vm.prank(ATTACKER);
        vault.delegate(ATTACKER);
        uint256 sum = vault.getVotes(delegatee) + vault.getVotes(ATTACKER);
        // Allow 1 wei rounding tolerance from integer division.
        assertLe(sum, totalDelegatedAfterYield, "sum <= total");
        assertLe(totalDelegatedAfterYield - sum, 1, "sum within 1 wei");
    }

    /// @notice A real share `transfer()` conserves asset-denominated votes between sender and receiver.
    /// @dev Transferring shares moves raw units via `_update` without touching totalAssets/totalSupply,
    ///      so both holders' asset-denominated votes must sum to the pre-transfer total within 1 wei.
    function testShareTransferKeepsAssetDenominatedVotesConserved() external {
        vm.prank(ATTACKER);
        vault.deposit(10 ether, ATTACKER);
        vm.prank(VICTIM);
        vault.deposit(10 ether, VICTIM);
        vm.prank(ATTACKER);
        vault.delegate(ATTACKER);
        vm.prank(VICTIM);
        vault.delegate(VICTIM);

        // Yield first so the exchange rate is not 1:1; conservation must hold post-yield too.
        vm.prank(ATTACKER);
        vault.accumulateYields(10 ether);

        uint256 totalBefore = vault.getVotes(ATTACKER) + vault.getVotes(VICTIM);
        uint256 victimBefore = vault.getVotes(VICTIM);

        // Real ERC20 share transfer: ATTACKER sends 3 shares to VICTIM.
        vm.prank(ATTACKER);
        vault.transfer(VICTIM, 3 ether);

        uint256 totalAfter = vault.getVotes(ATTACKER) + vault.getVotes(VICTIM);
        uint256 victimAfter = vault.getVotes(VICTIM);

        // Transfer does not change totalAssets or totalSupply, so the asset-vote total is conserved.
        // Integer division can shift the per-holder sum by ±1 wei in either direction, so use a
        // symmetric tolerance. A one-sided uint subtraction would underflow if rounding pushed
        // totalAfter above totalBefore.
        assertApproxEqAbs(totalAfter, totalBefore, 1, "asset votes conserved within 1 wei");
        assertGt(victimAfter, victimBefore, "receiver gained votes");
    }

    /// @notice Empty vault, first depositor, and managed donation edge cases are safe.
    function testEmptyVaultAndFirstDepositorEdgeCases() external {
        assertEq(vault.getVotes(ATTACKER), 0, "empty vault votes = 0");

        vm.warp(100);
        vm.prank(ATTACKER);
        vault.deposit(1 ether, ATTACKER);
        vm.prank(ATTACKER);
        vault.delegate(ATTACKER);

        assertEq(vault.getVotes(ATTACKER), 1 ether, "first depositor votes = deposit");

        vm.warp(200);
        vm.prank(ATTACKER);
        vault.accumulateYields(100 ether);

        vm.warp(300);
        assertEq(vault.getPastVotes(ATTACKER, 100), 1 ether, "snapshot votes unaffected by later donation");
        assertGt(vault.getVotes(ATTACKER), 1 ether, "current votes reflect donation");
    }

    /// @notice Direct ERC20 transfer to vault address does not change votes or total supply.
    function testDirectERC20TransferDoesNotAffectVotes() external {
        vm.warp(100);
        vm.prank(ATTACKER);
        vault.deposit(10 ether, ATTACKER);
        vm.prank(ATTACKER);
        vault.delegate(ATTACKER);

        uint256 votesBefore = vault.getVotes(ATTACKER);

        vm.prank(ATTACKER);
        asset.transfer(address(vault), 100 ether);

        assertEq(vault.getVotes(ATTACKER), votesBefore, "votes unchanged by raw transfer");

        vm.warp(200);
        assertEq(vault.getPastTotalSupply(100), 10 ether, "total supply unchanged by raw transfer");
    }

    /// @notice totalAssets checkpoints and IVotes checkpoints share the same ERC-6372 timepoint domain.
    function testTotalAssetsCheckpointsUseSameTimestampTimepoint() external {
        // Use the standard vault deployed in setUp (no test-harness subclass needed).
        vm.warp(100);
        vm.prank(ATTACKER);
        vault.deposit(10 ether, ATTACKER);

        // getTotalAssetsCheckpointLen() is inherited from OutrunVotesInit — no helper needed.
        assertEq(vault.getTotalAssetsCheckpointLen(), 1, "one checkpoint after deposit");

        vm.warp(200);
        // Verify the checkpoint value indirectly: at 1:1 rate, pastTotalSupply == deposit amount.
        assertEq(vault.getPastTotalSupply(100), 10 ether, "checkpoint records totalAssets at deposit time");
        assertEq(vault.CLOCK_MODE(), "mode=timestamp", "clock mode");
    }

    /// @notice getPastTotalSupply equals real shares at historical rate, not total managed assets.
    function testSmallDepositorLargeDonation_TotalSupplyNotEqualToTotalAssets() external {
        vm.warp(100);
        vm.prank(ATTACKER);
        vault.deposit(1 ether, ATTACKER);

        vm.warp(200);
        vm.prank(ATTACKER);
        vault.accumulateYields(1000 ether);

        vm.warp(300);
        assertEq(vault.getPastTotalSupply(100), 1 ether, "snapshot total = deposit amount");

        uint256 currentTotal = vault.getPastTotalSupply(200);
        uint256 expected = Math.mulDiv(1 ether, 1001 ether + 1, 1 ether + 1);
        assertEq(currentTotal, expected, "total supply = shares * rate");
        assertLt(currentTotal, 1001 ether, "total supply < totalAssets when virtual share captures value");
    }

    /// @notice Multiple yield rounds keep each historical snapshot at its own exchange rate.
    /// @dev Exercises a checkpoint chain longer than two entries through the binary lookup path.
    function testMultipleYieldRoundsProduceCorrectHistoricalVotes() external {
        vm.warp(100);
        vm.prank(ATTACKER);
        vault.deposit(10 ether, ATTACKER);
        vm.prank(ATTACKER);
        vault.delegate(ATTACKER);

        // Round 1: +10 yield, rate moves to 2.0
        vm.warp(200);
        vm.prank(ATTACKER);
        vault.accumulateYields(10 ether);

        // Round 2: +20 yield, rate moves to 4.0
        vm.warp(300);
        vm.prank(ATTACKER);
        vault.accumulateYields(20 ether);

        // Query from a later block so every snapshot is strictly in the past.
        vm.warp(400);

        // Snapshot at t=100 (rate 1.0): 10 shares * (10+1)/(10+1) = 10 assets.
        assertEq(vault.getPastVotes(ATTACKER, 100), 10 ether, "votes@100 = raw shares");
        // Snapshot at t=200 (rate 2.0): past total assets = 20.
        assertEq(
            vault.getPastVotes(ATTACKER, 200),
            Math.mulDiv(10 ether, 20 ether + 1, 10 ether + 1),
            "votes@200 reflect round-1 rate"
        );
        // Snapshot at t=300 (rate 4.0): past total assets = 40.
        assertEq(
            vault.getPastVotes(ATTACKER, 300),
            Math.mulDiv(10 ether, 40 ether + 1, 10 ether + 1),
            "votes@300 reflect round-2 rate"
        );
    }

    /// @notice Same-block deposit then yield records the post-yield asset value at that timepoint.
    /// @dev The total-assets checkpoint is overwritten in-block while share supply reflects the deposit.
    function testSameBlockDepositAndYieldCheckpointAlignment() external {
        // Seed a first depositor so the later yield is not burned.
        vm.warp(100);
        vm.prank(VICTIM);
        vault.deposit(10 ether, VICTIM);

        // Same block: ATTACKER deposits 10, then 5 yield lands.
        vm.prank(ATTACKER);
        vault.deposit(10 ether, ATTACKER);
        vm.prank(ATTACKER);
        vault.accumulateYields(5 ether);

        // Block end state: shares = 20, managed assets = 25.
        vm.warp(200);
        uint256 pastTotal = vault.getPastTotalSupply(100);
        assertEq(
            pastTotal, Math.mulDiv(20 ether, 25 ether + 1, 20 ether + 1), "same-block total = shares * post-yield rate"
        );
    }

    /// @notice Redeeming the entire supply to zero then re-depositing keeps votes consistent.
    /// @dev Guards checkpoint chain continuity across the empty-vault boundary.
    function testRedeemToZeroThenRedepositRestoresVotes() external {
        vm.warp(100);
        vm.prank(ATTACKER);
        uint256 shares = vault.deposit(10 ether, ATTACKER);
        vm.prank(ATTACKER);
        vault.delegate(ATTACKER);
        assertEq(vault.getVotes(ATTACKER), 10 ether, "votes before redeem");

        // Burn every share: supply and managed assets both return to zero.
        vm.prank(ATTACKER);
        vault.requestRedeem(shares, ATTACKER);
        assertEq(vault.getVotes(ATTACKER), 0, "votes zero after full redeem");

        vm.warp(block.timestamp + 1 days);
        vm.prank(ATTACKER);
        vault.executeRedeem();

        // Fresh deposit in a new block: rate resets to 1:1, votes equal assets.
        vm.warp(300);
        vm.prank(ATTACKER);
        vault.deposit(20 ether, ATTACKER);
        assertEq(vault.getVotes(ATTACKER), 20 ether, "votes restored after redeposit");
    }

    /// @notice A 1000x yield rate does not overflow and keeps sole-holder votes within convention slack.
    /// @dev The +1 convention leaves slack = (totalAssets - totalSupply) / (totalSupply + 1), bounded here under 1001 wei.
    function testExtremeYieldRateStaysWithinConventionSlack() external {
        vm.warp(100);
        vm.prank(ATTACKER);
        vault.deposit(1 ether, ATTACKER);
        vm.prank(ATTACKER);
        vault.delegate(ATTACKER);

        // Donate 999x the deposit to push the rate to 1000x.
        vm.warp(200);
        vm.prank(ATTACKER);
        vault.accumulateYields(999 ether);

        vm.warp(300);
        uint256 votes = vault.getPastVotes(ATTACKER, 200);
        assertEq(votes, Math.mulDiv(1 ether, 1000 ether + 1, 1 ether + 1), "votes match +1 formula");
        // Sole holder owns all shares, so votes track total assets within the virtual-share slack.
        assertLt(1000 ether - votes, 1001, "slack bounded under 1001 wei at 1000x rate");
    }

    /// @notice Verifies deposit(0) returns 0 without minting, transferring, or writing checkpoints.
    /// @dev Guards the round-trip-preserving early return in `deposit`.
    function testDepositZeroReturnsEarlyWithoutSideEffects() external {
        vm.prank(VICTIM);
        vault.deposit(10 ether, VICTIM);
        uint256 baselineLen = vault.getTotalAssetsCheckpointLen();
        uint256 baselineAssets = vault.totalAssets();

        vm.prank(ATTACKER);
        uint256 shares = vault.deposit(0, RECEIVER);

        assertEq(shares, 0, "deposit(0) shares");
        assertEq(vault.balanceOf(RECEIVER), 0, "no mint to receiver");
        assertEq(vault.totalAssets(), baselineAssets, "totalAssets unchanged");
        assertEq(vault.getTotalAssetsCheckpointLen(), baselineLen, "no new checkpoint");
    }

    /// @notice Verifies accumulateYields(0) leaves totalAssets and checkpoints unchanged.
    /// @dev Guards the zero-yield early return in `_accumulateYield`.
    function testAccumulateZeroYieldReturnsEarlyWithoutSideEffects() external {
        vm.prank(VICTIM);
        vault.deposit(10 ether, VICTIM);
        uint256 baselineLen = vault.getTotalAssetsCheckpointLen();
        uint256 baselineAssets = vault.totalAssets();

        vm.prank(ATTACKER);
        vault.accumulateYields(0);

        assertEq(vault.totalAssets(), baselineAssets, "totalAssets unchanged");
        assertEq(vault.getTotalAssetsCheckpointLen(), baselineLen, "no new checkpoint");
    }

    /// @notice A yield landing between two snapshot timepoints is reflected only at the later
    ///         snapshot, and scales every voter by the same factor so it cannot flip a proposal's
    ///         pass/fail outcome (griefing neutral).
    /// @dev OZ Governor sets `proposalSnapshot = clock() + votingDelay`, a future timepoint, so a
    ///      permissionless `accumulateYields` during the delay window writes a checkpoint the
    ///      snapshot reads. This documents that the window is harmless: the earlier snapshot stays
    ///      immutable, and the donation preserves each voter's share of total votes.
    function testYieldDuringSnapshotWindowPreservesVoterShare() external {
        // Split supply 6:4 between two stakers.
        vm.warp(100);
        vm.prank(ATTACKER);
        vault.deposit(6 ether, ATTACKER);
        vm.prank(VICTIM);
        vault.deposit(4 ether, VICTIM);
        vm.prank(ATTACKER);
        vault.delegate(ATTACKER);
        vm.prank(VICTIM);
        vault.delegate(VICTIM);

        // Yield lands at T=200 — between the baseline snapshot (T=100) and a later one.
        vm.warp(200);
        vm.prank(ATTACKER);
        vault.accumulateYields(10 ether); // totalAssets 10 -> 20, rate 2.0

        // Query from T=300 so both 100 and 200 are strictly past.
        vm.warp(300);

        // Immutability: the pre-yield snapshot keeps rate-1.0 votes.
        assertEq(vault.getPastVotes(ATTACKER, 100), 6 ether, "pre-yield snapshot immutable");
        assertEq(vault.getPastVotes(VICTIM, 100), 4 ether, "pre-yield snapshot immutable");

        // The post-yield snapshot reflects the doubled rate.
        uint256 attackerAt200 = vault.getPastVotes(ATTACKER, 200);
        uint256 victimAt200 = vault.getPastVotes(VICTIM, 200);
        assertEq(attackerAt200, Math.mulDiv(6 ether, 20 ether + 1, 10 ether + 1), "attacker votes reflect yield");
        assertEq(victimAt200, Math.mulDiv(4 ether, 20 ether + 1, 10 ether + 1), "victim votes reflect yield");

        // Griefing neutrality: the donation scaled both voters by the same factor, so the
        // attacker:victim ratio (3:2) is preserved within rounding. A donation moves every vote
        // and the quorum denominator by one multiplier, so it cannot change a proposal's outcome.
        assertApproxEqAbs(attackerAt200 * 2, victimAt200 * 3, 4, "voter ratio preserved (griefing neutral)");
    }

    /// @notice Yield landing exactly at the proposal snapshot timepoint is reflected in getPastVotes.
    /// @dev Governor sets `proposalSnapshot = clock() + votingDelay`. When yield arrives at that
    ///      exact timestamp, the snapshot reads post-yield values. This documents that yield during
    ///      the voting-delay window is harmless: each voter's share of total votes is preserved,
    ///      and the snapshot correctly captures the yield-inclusive exchange rate.
    function testYieldAtSnapshotTimepointReflectedInGetPastVotes() external {
        // Deposit at T=100, split 6:4.
        vm.warp(100);
        vm.prank(ATTACKER);
        vault.deposit(6 ether, ATTACKER);
        vm.prank(VICTIM);
        vault.deposit(4 ether, VICTIM);
        vm.prank(ATTACKER);
        vault.delegate(ATTACKER);
        vm.prank(VICTIM);
        vault.delegate(VICTIM);

        // Yield lands at T=200 — the exact timepoint a Governor with votingDelay=100 would snapshot.
        vm.warp(200);
        vm.prank(ATTACKER);
        vault.accumulateYields(10 ether); // totalAssets 10 -> 20, rate 2.0

        // Query from T=300 so T=200 is strictly past.
        vm.warp(300);

        // The snapshot at T=200 reflects the post-yield exchange rate.
        uint256 attackerVotes = vault.getPastVotes(ATTACKER, 200);
        uint256 victimVotes = vault.getPastVotes(VICTIM, 200);
        assertEq(attackerVotes, Math.mulDiv(6 ether, 20 ether + 1, 10 ether + 1), "attacker votes at snapshot");
        assertEq(victimVotes, Math.mulDiv(4 ether, 20 ether + 1, 10 ether + 1), "victim votes at snapshot");

        // Total supply at snapshot reflects post-yield rate.
        uint256 totalSupplyAtSnapshot = vault.getPastTotalSupply(200);
        assertEq(totalSupplyAtSnapshot, Math.mulDiv(10 ether, 20 ether + 1, 10 ether + 1), "total supply at snapshot");

        // Voter ratio preserved: 6:4 = 3:2 scaling is uniform.
        assertApproxEqAbs(attackerVotes * 2, victimVotes * 3, 4, "voter ratio preserved at snapshot");
    }
}
