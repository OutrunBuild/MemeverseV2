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
        uint128 _oftDispatcherGasLimit
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
            _oftDispatcherGasLimit
        )
    {}

    /// @notice Set memeverse for test.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @param verseId See implementation.
    /// @param verse See implementation.
    function setMemeverseForTest(uint256 verseId, Memeverse memory verse) external {
        memeverses[verseId] = verse;
    }

    /// @notice Set verse id by memecoin for test.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @param memecoin See implementation.
    /// @param verseId See implementation.
    function setVerseIdByMemecoinForTest(address memecoin, uint256 verseId) external {
        memecoinToIds[memecoin] = verseId;
    }

    /// @notice Set genesis fund for test.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
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
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
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
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @param verseId See implementation.
    /// @param amount See implementation.
    function setTotalClaimablePOLForTest(uint256 verseId, uint256 amount) external {
        totalClaimablePOL[verseId] = amount;
    }
}

contract MemeverseLauncherViewsTest is Test {
    address internal constant REGISTRAR = address(0xBEEF);
    address internal constant ALICE = address(0xA11CE);
    address internal constant MEMECOIN = address(0x1111);
    address internal constant GOVERNOR = address(0x3333);
    address internal constant YIELD_VAULT = address(0x4444);
    address internal constant POL = address(0x5555);

    TestableMemeverseLauncherViews internal launcher;
    MockERC20 internal uptToken;

    /// @notice Set up.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function setUp() external {
        launcher = new TestableMemeverseLauncherViews(
            address(this), address(0x1), REGISTRAR, address(0x3), address(0x4), address(0x5), 25, 115_000, 135_000
        );
        uptToken = new MockERC20("UPT", "UPT", 18);
    }

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
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
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
        vm.expectRevert(IMemeverseLauncher.ZeroInput.selector);
        launcher.getMemeverseByVerseId(0);
        vm.expectRevert(IMemeverseLauncher.ZeroInput.selector);
        launcher.getMemeverseByMemecoin(address(0));
        vm.expectRevert(IMemeverseLauncher.ZeroInput.selector);
        launcher.getStageByVerseId(0);
        vm.expectRevert(IMemeverseLauncher.ZeroInput.selector);
        launcher.getStageByMemecoin(address(0));
        vm.expectRevert(IMemeverseLauncher.ZeroInput.selector);
        launcher.getYieldVaultByVerseId(0);
        vm.expectRevert(IMemeverseLauncher.ZeroInput.selector);
        launcher.getGovernorByVerseId(0);
        vm.expectRevert(IMemeverseLauncher.ZeroInput.selector);
        launcher.claimablePOLToken(0);
        vm.expectRevert(IMemeverseLauncher.ZeroInput.selector);
        launcher.previewGenesisMakerFees(0);
        vm.expectRevert(IMemeverseLauncher.ZeroInput.selector);
        launcher.quoteDistributionLzFee(0);

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
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
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
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
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
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
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

    /// @notice Test get memeverse by memecoin and stage by memecoin return stored state.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
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
