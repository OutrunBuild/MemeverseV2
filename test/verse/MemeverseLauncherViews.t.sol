// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {MemeverseLauncher} from "../../src/verse/MemeverseLauncher.sol";
import {IMemeverseLauncher} from "../../src/verse/interfaces/IMemeverseLauncher.sol";

contract TestableMemeverseLauncherViews is MemeverseLauncher {
    constructor(
        address _owner,
        address _localLzEndpoint,
        address _memeverseRegistrar,
        address _memeverseProxyDeployer,
        address _oftDispatcher,
        address _lzEndpointRegistry,
        uint256 _executorRewardRate,
        uint128 _oftReceiveGasLimit,
        uint128 _oftDispatcherGasLimit,
        uint256 _preorderCapRatio,
        uint256 _preorderVestingDuration
    )
        MemeverseLauncher(
            _owner,
            _localLzEndpoint,
            _memeverseRegistrar,
            _memeverseProxyDeployer,
            _oftDispatcher,
            _lzEndpointRegistry,
            _executorRewardRate,
            _oftReceiveGasLimit,
            _oftDispatcherGasLimit,
            _preorderCapRatio,
            _preorderVestingDuration
        )
    {}

    /// @notice Set memeverse for test.
    /// @dev Writes directly to `memeverses` so the view tests can observe specific state.
    /// @param verseId See implementation.
    /// @param verse See implementation.
    function setMemeverseForTest(uint256 verseId, Memeverse memory verse) external {
        memeverses[verseId] = verse;
    }

    /// @notice Set verse id by memecoin for test.
    /// @dev Writes the inverse mapping used by the accessors under test.
    /// @param memecoin See implementation.
    /// @param verseId See implementation.
    function setVerseIdByMemecoinForTest(address memecoin, uint256 verseId) external {
        memecoinToIds[memecoin] = verseId;
    }

    /// @notice Set genesis fund for test.
    /// @dev Populates `genesisFunds` so view helpers can report specific totals.
    /// @param verseId See implementation.
    /// @param totalMemecoinFunds See implementation.
    /// @param totalLiquidProofFunds See implementation.
    function setGenesisFundForTest(uint256 verseId, uint128 totalMemecoinFunds, uint128 totalLiquidProofFunds)
        external
    {
        genesisFunds[verseId] =
            GenesisFund({totalMemecoinFunds: totalMemecoinFunds, totalLiquidProofFunds: totalLiquidProofFunds});
    }

    /// @notice Set user genesis data for test.
    /// @dev Adjusts the genesis data fields so view helpers return the expected flags.
    /// @param verseId See implementation.
    /// @param account See implementation.
    /// @param genesisFund See implementation.
    /// @param isRefunded See implementation.
    /// @param isClaimed See implementation.
    /// @param isRedeemed See implementation.
    function setUserGenesisDataForTest(
        uint256 verseId,
        address account,
        uint256 genesisFund,
        bool isRefunded,
        bool isClaimed,
        bool isRedeemed
    ) external {
        userGenesisData[verseId][account] = GenesisData({
            genesisFund: genesisFund, isRefunded: isRefunded, isClaimed: isClaimed, isRedeemed: isRedeemed
        });
    }

    /// @notice Set total claimable polfor test.
    /// @dev Controls the claimable POL total observed by views.
    /// @param verseId See implementation.
    /// @param amount See implementation.
    function setTotalClaimablePOLForTest(uint256 verseId, uint256 amount) external {
        totalClaimablePOL[verseId] = amount;
    }

    /// @notice Set user preorder data for test.
    /// @dev Tunes the preorder ledger so clams/vesting views can read specific values.
    /// @param verseId See implementation.
    /// @param account See implementation.
    /// @param funds See implementation.
    /// @param claimedMemecoin See implementation.
    /// @param isRefunded See implementation.
    function setUserPreorderDataForTest(
        uint256 verseId,
        address account,
        uint256 funds,
        uint256 claimedMemecoin,
        bool isRefunded
    ) external {
        userPreorderData[verseId][account] = PreorderData({
            funds: funds, claimedMemecoin: claimedMemecoin, isRefunded: isRefunded
        });
    }

    /// @notice Set preorder settlement state for test.
    /// @dev Drives the state observed by preorder claim previews.
    /// @param verseId See implementation.
    /// @param totalFunds See implementation.
    /// @param settledMemecoin See implementation.
    /// @param timestamp See implementation.
    function setPreorderStateForTest(uint256 verseId, uint256 totalFunds, uint256 settledMemecoin, uint40 timestamp)
        external
    {
        preorderStates[verseId] =
            PreorderState({totalFunds: totalFunds, settledMemecoin: settledMemecoin, settlementTimestamp: timestamp});
    }
}

contract MemeverseLauncherViewsTest is Test {
    address internal constant REGISTRAR = address(0xBEEF);
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant MEMECOIN = address(0x1111);
    address internal constant GOVERNOR = address(0x3333);
    address internal constant YIELD_VAULT = address(0x4444);
    address internal constant POL = address(0x5555);

    TestableMemeverseLauncherViews internal launcher;
    MockERC20 internal uptToken;

    /// @notice Set up.
    /// @dev Deploys the views-only launcher and a helper token to exercise getters.
    function setUp() external {
        launcher = new TestableMemeverseLauncherViews(
            address(this),
            address(0x1),
            REGISTRAR,
            address(0x3),
            address(0x4),
            address(0x5),
            25,
            115_000,
            135_000,
            2_500,
            7 days
        );
        uptToken = new MockERC20("UPT", "UPT", 18);
    }

    /// @notice Builds a base verse for the requested stage.
    /// @dev Supplies consistent memecoin and UPT addresses for view tests.
    function _baseVerse(IMemeverseLauncher.Stage stage)
        internal
        view
        returns (IMemeverseLauncher.Memeverse memory verse)
    {
        verse.memecoin = MEMECOIN;
        verse.UPT = address(uptToken);
        verse.currentStage = stage;
    }

    /// @notice Test getter views revert on zero input and return stored state.
    /// @dev Exercises all public view helpers for zero-input guarding and correct state returns.
    function testGetterViewsRevertOnZeroInputAndReturnStoredState() external {
        IMemeverseLauncher.Memeverse memory verse = _baseVerse(IMemeverseLauncher.Stage.Locked);
        verse.governor = GOVERNOR;
        verse.yieldVault = YIELD_VAULT;
        launcher.setMemeverseForTest(1, verse);
        launcher.setVerseIdByMemecoinForTest(MEMECOIN, 1);
        launcher.setTotalClaimablePOLForTest(1, 60 ether);
        launcher.setGenesisFundForTest(1, 90 ether, 30 ether);
        launcher.setUserGenesisDataForTest(1, ALICE, 24 ether, false, false, false);

        vm.expectRevert(IMemeverseLauncher.ZeroInput.selector);
        launcher.getVerseIdByMemecoin(address(0));
        vm.expectRevert(IMemeverseLauncher.InvalidVerseId.selector);
        launcher.getMemeverseByVerseId(0);
        vm.expectRevert(IMemeverseLauncher.ZeroInput.selector);
        launcher.getMemeverseByMemecoin(address(0));
        vm.expectRevert(IMemeverseLauncher.InvalidVerseId.selector);
        launcher.getStageByVerseId(0);
        vm.expectRevert(IMemeverseLauncher.ZeroInput.selector);
        launcher.getStageByMemecoin(address(0));
        vm.expectRevert(IMemeverseLauncher.InvalidVerseId.selector);
        launcher.getYieldVaultByVerseId(0);
        vm.expectRevert(IMemeverseLauncher.InvalidVerseId.selector);
        launcher.getGovernorByVerseId(0);
        vm.expectRevert(IMemeverseLauncher.InvalidVerseId.selector);
        launcher.claimablePOLToken(0);
        vm.expectRevert(IMemeverseLauncher.InvalidVerseId.selector);
        launcher.previewGenesisMakerFees(0);
        vm.expectRevert(IMemeverseLauncher.InvalidVerseId.selector);
        launcher.quoteDistributionLzFee(0);

        vm.expectRevert(IMemeverseLauncher.InvalidVerseId.selector);
        launcher.getMemeverseByVerseId(999);
        vm.expectRevert(IMemeverseLauncher.InvalidVerseId.selector);
        launcher.getMemeverseByMemecoin(address(0x9999));
        vm.expectRevert(IMemeverseLauncher.InvalidVerseId.selector);
        launcher.quoteDistributionLzFee(999);

        vm.startPrank(ALICE);
        assertEq(launcher.getVerseIdByMemecoin(MEMECOIN), 1);
        assertEq(launcher.getMemeverseByVerseId(1).memecoin, MEMECOIN);
        assertEq(uint256(launcher.getStageByVerseId(1)), uint256(IMemeverseLauncher.Stage.Locked));
        assertEq(launcher.getYieldVaultByVerseId(1), YIELD_VAULT);
        assertEq(launcher.getGovernorByVerseId(1), GOVERNOR);
        assertEq(launcher.claimablePOLToken(1), 12 ether);
        vm.stopPrank();
    }

    /// @notice Test genesis reverts when verse missing or paused or wrong stage and accumulates funds.
    /// @dev Confirms genesis enforces id, stage, zero-input, and pause guards while still accounting for funds.
    function testGenesisRevertsWhenVerseMissingOrPausedOrWrongStageAndAccumulatesFunds() external {
        vm.expectRevert(IMemeverseLauncher.InvalidVerseId.selector);
        launcher.genesis(1, 1 ether, ALICE);

        IMemeverseLauncher.Memeverse memory verse = _baseVerse(IMemeverseLauncher.Stage.Locked);
        launcher.setMemeverseForTest(1, verse);

        vm.expectRevert(IMemeverseLauncher.NotGenesisStage.selector);
        launcher.genesis(1, 1 ether, ALICE);

        verse.currentStage = IMemeverseLauncher.Stage.Genesis;
        launcher.setMemeverseForTest(1, verse);

        vm.expectRevert(IMemeverseLauncher.ZeroInput.selector);
        launcher.genesis(1, 0, ALICE);

        launcher.pause();
        vm.expectRevert(Pausable.EnforcedPause.selector);
        launcher.genesis(1, 1 ether, ALICE);
        launcher.unpause();

        uptToken.mint(address(this), 1 ether);
        uptToken.approve(address(launcher), type(uint256).max);
        launcher.genesis(1, 1 ether, ALICE);

        (uint128 totalMemecoinFunds, uint128 totalLiquidProofFunds) = launcher.genesisFunds(1);
        (uint256 genesisFund,,,) = launcher.userGenesisData(1, ALICE);
        assertEq(totalMemecoinFunds, 0.75 ether);
        assertEq(totalLiquidProofFunds, 0.25 ether);
        assertEq(genesisFund, 1 ether);
    }

    /// @notice Test refund success marks user and transfers native fund.
    /// @dev Checks that refunds set the flag and return ETH when the verse is in Refund stage.
    function testRefundSuccessMarksUserAndTransfersNativeFund() external {
        IMemeverseLauncher.Memeverse memory verse = _baseVerse(IMemeverseLauncher.Stage.Refund);
        launcher.setMemeverseForTest(1, verse);
        launcher.setUserGenesisDataForTest(1, ALICE, 1 ether, false, false, false);
        uptToken.mint(address(launcher), 1 ether);

        vm.prank(ALICE);
        uint256 refunded = launcher.refund(1);

        (uint256 genesisFund, bool isRefunded,,) = launcher.userGenesisData(1, ALICE);
        assertEq(refunded, 1 ether);
        assertEq(genesisFund, 1 ether);
        assertTrue(isRefunded);
        assertEq(uptToken.balanceOf(ALICE), 1 ether);
    }

    /// @notice Test claim poltoken reverts when no claimable and pause blocks lifecycle actions.
    /// @dev Ensures claimPOLToken enforces pause and zero-output guards, relying on Pausable semantics.
    function testClaimPOLTokenRevertsWhenNoClaimableAndPauseBlocksLifecycleActions() external {
        IMemeverseLauncher.Memeverse memory verse = _baseVerse(IMemeverseLauncher.Stage.Locked);
        verse.liquidProof = POL;
        launcher.setMemeverseForTest(1, verse);
        launcher.setGenesisFundForTest(1, 90 ether, 30 ether);
        launcher.setUserGenesisDataForTest(1, ALICE, 0, false, false, false);

        vm.prank(ALICE);
        vm.expectRevert(IMemeverseLauncher.NoPOLAvailable.selector);
        launcher.claimPOLToken(1);

        launcher.pause();
        vm.prank(ALICE);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        launcher.claimPOLToken(1);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        launcher.refund(1);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        launcher.changeStage(1);
    }

    /// @notice Test preorder reverts when stage or capacity invalid.
    /// @dev Verifies preorder enforces stage, non-zero input, and cap constraints.
    function testPreorderRevertsWhenNotGenesisOrCapacityExceeded() external {
        IMemeverseLauncher.Memeverse memory verse = _baseVerse(IMemeverseLauncher.Stage.Locked);
        launcher.setMemeverseForTest(1, verse);

        vm.expectRevert(IMemeverseLauncher.NotGenesisStage.selector);
        launcher.preorder(1, 1 ether, ALICE);

        verse.currentStage = IMemeverseLauncher.Stage.Genesis;
        launcher.setMemeverseForTest(1, verse);
        launcher.setGenesisFundForTest(1, 4 ether, 0);

        vm.expectRevert(IMemeverseLauncher.ZeroInput.selector);
        launcher.preorder(1, 0, ALICE);

        uptToken.mint(address(this), 2 ether);
        uptToken.approve(address(launcher), type(uint256).max);

        vm.expectRevert();
        launcher.preorder(1, 2 ether, ALICE);
    }

    /// @notice Test claimable preorder memecoin linearly vests over seven days.
    /// @dev Checks that linear vesting unfolds over 7 days by warping time.
    function testClaimablePreorderMemecoin_LinearVestingOverSevenDays() external {
        IMemeverseLauncher.Memeverse memory verse = _baseVerse(IMemeverseLauncher.Stage.Locked);
        launcher.setMemeverseForTest(1, verse);
        launcher.setUserPreorderDataForTest(1, ALICE, 1 ether, 10 ether, false);
        launcher.setPreorderStateForTest(1, 1 ether, 70 ether, uint40(block.timestamp));
        uptToken.mint(address(launcher), 70 ether);

        vm.prank(ALICE);
        assertEq(launcher.claimablePreorderMemecoin(1), 0, "initial claimable");

        vm.warp(block.timestamp + 3 days + 12 hours);
        vm.prank(ALICE);
        assertEq(launcher.claimablePreorderMemecoin(1), 25 ether, "midway claimable");

        vm.warp(block.timestamp + 3 days + 12 hours + 1);
        vm.prank(ALICE);
        assertEq(launcher.claimablePreorderMemecoin(1), 60 ether, "final claimable");
    }

    /// @notice Test claimable preorder memecoin remains pro-rata and bounded for multiple users under fuzzed inputs.
    /// @dev Exercises the pro-rata and total vesting bounds with bounded fuzzed inputs.
    /// @param fundsA See implementation.
    /// @param fundsB See implementation.
    /// @param settledMemecoin See implementation.
    /// @param elapsed See implementation.
    function testFuzzClaimablePreorderMemecoin_MultiUserProRataAndBounded(
        uint96 fundsA,
        uint96 fundsB,
        uint96 settledMemecoin,
        uint32 elapsed
    ) external {
        fundsA = uint96(bound(uint256(fundsA), 1, 1_000_000 ether));
        fundsB = uint96(bound(uint256(fundsB), 1, 1_000_000 ether));
        settledMemecoin = uint96(bound(uint256(settledMemecoin), 1, 1_000_000 ether));
        elapsed = uint32(bound(uint256(elapsed), 0, 7 days));

        IMemeverseLauncher.Memeverse memory verse = _baseVerse(IMemeverseLauncher.Stage.Locked);
        launcher.setMemeverseForTest(1, verse);
        launcher.setUserPreorderDataForTest(1, ALICE, fundsA, 0, false);
        launcher.setUserPreorderDataForTest(1, BOB, fundsB, 0, false);
        launcher.setPreorderStateForTest(1, uint256(fundsA) + uint256(fundsB), settledMemecoin, uint40(block.timestamp));

        vm.warp(block.timestamp + elapsed);

        vm.prank(ALICE);
        uint256 claimableA = launcher.claimablePreorderMemecoin(1);

        vm.prank(BOB);
        uint256 claimableB = launcher.claimablePreorderMemecoin(1);

        uint256 entitledA = uint256(settledMemecoin) * uint256(fundsA) / (uint256(fundsA) + uint256(fundsB));
        uint256 entitledB = uint256(settledMemecoin) * uint256(fundsB) / (uint256(fundsA) + uint256(fundsB));
        uint256 vestedTotal = uint256(settledMemecoin) * elapsed / 7 days;

        assertLe(claimableA, entitledA, "alice bounded by entitlement");
        assertLe(claimableB, entitledB, "bob bounded by entitlement");
        assertLe(claimableA + claimableB, vestedTotal, "total bounded by vested");
    }

    /// @notice Verifies preorder claim previews reject non-existent non-zero verse ids.
    /// @dev Prevents unknown verse ids from falling through to stage-based errors.
    function testClaimablePreorderMemecoin_RevertsWhenVerseIdNotRegistered() external {
        vm.prank(ALICE);
        vm.expectRevert(IMemeverseLauncher.InvalidVerseId.selector);
        launcher.claimablePreorderMemecoin(999);
    }

    /// @notice Test get memeverse by memecoin and stage by memecoin return stored state.
    /// @dev Ensures the memecoin-indexed getters match the pre-seeded verse metadata.
    function testGetMemeverseByMemecoinAndStageByMemecoinReturnStoredState() external {
        IMemeverseLauncher.Memeverse memory verse = _baseVerse(IMemeverseLauncher.Stage.Unlocked);
        verse.governor = GOVERNOR;
        launcher.setMemeverseForTest(7, verse);
        launcher.setVerseIdByMemecoinForTest(MEMECOIN, 7);

        IMemeverseLauncher.Memeverse memory stored = launcher.getMemeverseByMemecoin(MEMECOIN);
        assertEq(stored.memecoin, MEMECOIN);
        assertEq(stored.governor, GOVERNOR);
        assertEq(uint256(launcher.getStageByMemecoin(MEMECOIN)), uint256(IMemeverseLauncher.Stage.Unlocked));
    }
}
