// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
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

contract TestableMemecoinYieldVault is MemecoinYieldVault {
    function setTotalAssetsForTest(uint256 totalAssets_) external {
        totalAssets = totalAssets_;
    }

    function mintSharesForTest(address receiver, uint256 amount) external {
        _mint(receiver, amount);
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
    /// @dev Seeds a large exchange rate state via a test harness so the request path reaches the narrowing conversion.
    function testRequestRedeemRevertsWhenQueuedAssetsOverflowUint192() external {
        TestableMemecoinYieldVault implementation = new TestableMemecoinYieldVault();
        TestableMemecoinYieldVault overflowVault = TestableMemecoinYieldVault(Clones.clone(address(implementation)));
        overflowVault.initialize("Overflow Vault", "ovMEME", address(0xD15A7), address(asset), 99);

        uint256 oversizedAssets = uint256(type(uint192).max) + uint256(type(uint128).max) + 1;
        overflowVault.setTotalAssetsForTest(oversizedAssets);
        overflowVault.mintSharesForTest(ATTACKER, type(uint128).max);

        uint256 previewAssets = overflowVault.previewRedeem(type(uint128).max);
        assertGt(previewAssets, uint256(type(uint192).max), "preview must exceed uint192");

        vm.prank(ATTACKER);
        vm.expectRevert(abi.encodeWithSelector(IMemecoinYieldVault.RedeemAmountOverflowed.selector, previewAssets));
        overflowVault.requestRedeem(type(uint128).max, ATTACKER);
    }
}
