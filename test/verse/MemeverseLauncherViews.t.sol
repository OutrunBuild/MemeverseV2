// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";

import {MemeverseLauncher} from "../../src/verse/MemeverseLauncher.sol";
import {IMemeverseLauncher} from "../../src/verse/interfaces/IMemeverseLauncher.sol";
import {IPOLend} from "../../src/polend/interfaces/IPOLend.sol";

contract MockPOLendForViews {
    uint256 internal totalLeveragedDebt_;
    IPOLend.LendMarket internal market;

    function setTotalLeveragedDebt(uint256 amount) external {
        totalLeveragedDebt_ = amount;
    }

    function getTotalLeveragedDebt(uint256) external view returns (uint256) {
        return totalLeveragedDebt_;
    }

    function getLendMarket(uint256) external view returns (IPOLend.LendMarket memory) {
        return market;
    }

    function registerLendMarket(uint256) external {}
}

contract MockPOLSplitterForViews {
    address internal immutable yt;

    constructor(address yt_) {
        yt = yt_;
    }

    function splitInfos(uint256)
        external
        view
        returns (address, address, address, address, address, uint256, uint256, uint256, uint256, uint256, bool)
    {
        return (address(0), yt, address(0), address(0), address(0), 0, 0, 0, 0, 0, false);
    }

    function getPT(uint256) external pure returns (address) {
        return address(0);
    }

    function getYT(uint256) external view returns (address) {
        return yt;
    }

    function getMemecoin(uint256) external pure returns (address) {
        return address(0);
    }

    function getPTAndYT(uint256) external view returns (address, address) {
        return (address(0), yt);
    }

    function getPTSettlementState(uint256) external pure returns (address, bool) {
        return (address(0), false);
    }
}

contract TestableMemeverseLauncherViews is MemeverseLauncher {
    constructor(
        address _owner,
        address _localLzEndpoint,
        address _memeverseRegistrar,
        address _memeverseProxyDeployer,
        address _yieldDispatcher,
        address _lzEndpointRegistry,
        address _polend,
        address _polSplitter,
        uint256 _executorRewardRate,
        uint128 _oftReceiveGasLimit,
        uint128 _yieldDispatcherGasLimit,
        uint256 _preorderCapRatio,
        uint256 _preorderVestingDuration
    )
        MemeverseLauncher(
            _owner,
            _localLzEndpoint,
            _memeverseRegistrar,
            _memeverseProxyDeployer,
            _yieldDispatcher,
            _lzEndpointRegistry,
            _polend,
            _polSplitter,
            _executorRewardRate,
            _oftReceiveGasLimit,
            _yieldDispatcherGasLimit,
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
    function setGenesisFundForTest(uint256 verseId, uint256 _totalNormalFunds) external {
        totalNormalFunds[verseId] = _totalNormalFunds;
    }

    /// @notice Set user genesis data for test.
    /// @dev Adjusts the genesis data fields so view helpers return the expected flags.
    /// @param verseId See implementation.
    /// @param account See implementation.
    /// @param genesisFund See implementation.
    /// @param isRefunded See implementation.
    /// @param isRedeemed See implementation.
    function setUserGenesisDataForTest(
        uint256 verseId,
        address account,
        uint256 genesisFund,
        bool isRefunded,
        bool isRedeemed
    ) external {
        userGenesisData[verseId][account] =
            GenesisData({genesisFund: genesisFund, isRefunded: isRefunded, isRedeemed: isRedeemed});
    }

    function setTotalNormalClaimableYTForTest(uint256 verseId, uint256 amount) external {
        totalNormalClaimableYT[verseId] = amount;
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
    uint256 internal constant MAX_SUPPORTED_FUND_BASED_AMOUNT = (1 << 64) - 1;

    TestableMemeverseLauncherViews internal launcher;
    MockERC20 internal uAssetToken;
    MockERC20 internal ytToken;
    MockPOLendForViews internal polend;
    MockPOLSplitterForViews internal splitter;

    /// @notice Set up.
    /// @dev Deploys the views-only launcher and a helper token to exercise getters.
    function setUp() external {
        uAssetToken = new MockERC20("UASSET", "UASSET", 18);
        ytToken = new MockERC20("YT", "YT", 18);
        polend = new MockPOLendForViews();
        splitter = new MockPOLSplitterForViews(address(ytToken));
        launcher = new TestableMemeverseLauncherViews(
            address(this),
            address(0x1),
            REGISTRAR,
            address(0x3),
            address(0x4),
            address(0x5),
            address(polend),
            address(splitter),
            25,
            115_000,
            135_000,
            2_500,
            7 days
        );
    }

    /// @notice Builds a base verse for the requested stage.
    /// @dev Supplies consistent memecoin and uAsset addresses for view tests.
    function _baseVerse(IMemeverseLauncher.Stage stage)
        internal
        view
        returns (IMemeverseLauncher.Memeverse memory verse)
    {
        verse.memecoin = MEMECOIN;
        verse.uAsset = address(uAssetToken);
        verse.currentStage = stage;
    }

    function _expectedDefaultPreorderCapacity(uint256 baseFunds) internal pure returns (uint256) {
        uint256 quotient = baseFunds / 40;
        uint256 remainder = baseFunds % 40;
        return quotient * 7 + remainder * 7 / 40;
    }

    /// @notice Test getter views revert on zero input and return stored state.
    /// @dev Exercises all public view helpers for zero-input guarding and correct state returns.
    function testGetterViewsRevertOnZeroInputAndReturnStoredState() external {
        IMemeverseLauncher.Memeverse memory verse = _baseVerse(IMemeverseLauncher.Stage.Locked);
        verse.governor = GOVERNOR;
        verse.yieldVault = YIELD_VAULT;
        launcher.setMemeverseForTest(1, verse);
        launcher.setVerseIdByMemecoinForTest(MEMECOIN, 1);
        launcher.setGenesisFundForTest(1, 120 ether);
        launcher.setUserGenesisDataForTest(1, ALICE, 24 ether, false, false);

        vm.expectRevert(IMemeverseLauncher.ZeroInput.selector);
        launcher.getVerseIdByMemecoin(address(0));
        vm.expectRevert(IMemeverseLauncher.InvalidVerseId.selector);
        launcher.getMemeverseByVerseId(0);
        vm.expectRevert(IMemeverseLauncher.InvalidVerseId.selector);
        launcher.getUAssetByVerseId(0);
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
        assertEq(launcher.getUAssetByVerseId(1), address(uAssetToken));
        assertEq(uint256(launcher.getStageByVerseId(1)), uint256(IMemeverseLauncher.Stage.Locked));
        assertEq(launcher.getYieldVaultByVerseId(1), YIELD_VAULT);
        assertEq(launcher.getGovernorByVerseId(1), GOVERNOR);
        vm.stopPrank();
    }

    function testPreviewPreorderCapacity_UsesAllNormalFundsAndLeveragedDebtBase() external {
        launcher.setMemeverseForTest(1, _baseVerse(IMemeverseLauncher.Stage.Genesis));
        launcher.setGenesisFundForTest(1, 1000 ether);
        polend.setTotalLeveragedDebt(500 ether);
        assertEq(launcher.previewPreorderCapacity(1), 262.5 ether, "70 percent base times ratio");
    }

    function testPreviewPreorderCapacity_HandlesLargeBaseWithoutIntermediateOverflow() external {
        launcher.setMemeverseForTest(1, _baseVerse(IMemeverseLauncher.Stage.Genesis));
        uint256 baseFunds = type(uint128).max;
        launcher.setGenesisFundForTest(1, baseFunds);

        assertEq(launcher.previewPreorderCapacity(1), _expectedDefaultPreorderCapacity(baseFunds), "capacity");
    }

    function testPreviewPreorderCapacity_RevertsWhenTotalGenesisFundsExceedSupportedMaximum() external {
        launcher.setMemeverseForTest(1, _baseVerse(IMemeverseLauncher.Stage.Genesis));
        launcher.setGenesisFundForTest(1, type(uint128).max);
        polend.setTotalLeveragedDebt(1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMemeverseLauncher.TotalGenesisFundsTooHigh.selector,
                uint256(type(uint128).max) + 1,
                uint256(type(uint128).max)
            )
        );
        launcher.previewPreorderCapacity(1);
    }

    function testPreviewPreorderCapacity_RevertsWhenVerseIdInvalid() external {
        vm.expectRevert(IMemeverseLauncher.InvalidVerseId.selector);
        launcher.previewPreorderCapacity(0);

        vm.expectRevert(IMemeverseLauncher.InvalidVerseId.selector);
        launcher.previewPreorderCapacity(999);
    }

    function testClaimablePreorderMemecoin_UsesFullPrecisionForLargePreorderAndVesting() external {
        launcher.setMemeverseForTest(1, _baseVerse(IMemeverseLauncher.Stage.Locked));

        uint256 settledMemecoin = 1 << 240;
        uint256 userFunds = 1 << 80;
        uint256 totalFunds = 1 << 80;
        uint40 settlementTimestamp = 1_000;
        uint256 elapsed = 2 days;

        launcher.setPreorderStateForTest(1, totalFunds, settledMemecoin, settlementTimestamp);
        launcher.setUserPreorderDataForTest(1, ALICE, userFunds, 0, false);
        vm.warp(uint256(settlementTimestamp) + elapsed);

        uint256 purchasedMemecoin = FullMath.mulDiv(settledMemecoin, userFunds, totalFunds);
        uint256 expected = FullMath.mulDiv(purchasedMemecoin, elapsed, 7 days);

        vm.prank(ALICE);
        assertEq(launcher.claimablePreorderMemecoin(1), expected, "claimable preorder");
    }

    function testGetDebtCapBaseByVerseId_ReturnsMinTotalFundWhenNormalFundsAreLower() external {
        launcher.setMemeverseForTest(1, _baseVerse(IMemeverseLauncher.Stage.Genesis));
        launcher.setGenesisFundForTest(1, 5 ether);
        launcher.setFundMetaData(address(uAssetToken), 10 ether, 1);

        (bool success, bytes memory data) =
            address(launcher).staticcall(abi.encodeWithSignature("getDebtCapBaseByVerseId(uint256)", 1));

        assertTrue(success, "debt cap base getter");
        assertEq(abi.decode(data, (uint256)), 10 ether, "min fund");
    }

    function testGetDebtCapBaseByVerseId_ReturnsNormalFundsWhenHigher() external {
        launcher.setMemeverseForTest(1, _baseVerse(IMemeverseLauncher.Stage.Genesis));
        launcher.setGenesisFundForTest(1, 15 ether);
        launcher.setFundMetaData(address(uAssetToken), 10 ether, 1);

        (bool success, bytes memory data) =
            address(launcher).staticcall(abi.encodeWithSignature("getDebtCapBaseByVerseId(uint256)", 1));

        assertTrue(success, "debt cap base getter");
        assertEq(abi.decode(data, (uint256)), 15 ether, "normal funds");
    }

    function testGetDebtCapBaseByVerseId_AllowsLargeMinTotalFund() external {
        uint256 verseId = 2;
        uint256 largeMinTotalFund = uint256(type(uint128).max) + 1;
        launcher.setMemeverseForTest(verseId, _baseVerse(IMemeverseLauncher.Stage.Genesis));
        launcher.setGenesisFundForTest(verseId, 0);
        launcher.setFundMetaData(address(uAssetToken), largeMinTotalFund, 1);

        assertEq(launcher.getDebtCapBaseByVerseId(verseId), largeMinTotalFund, "large min fund");
    }

    function testGetDebtCapBaseByVerseId_RevertsForInvalidVerseId() external view {
        (bool success, bytes memory data) =
            address(launcher).staticcall(abi.encodeWithSignature("getDebtCapBaseByVerseId(uint256)", 999));

        assertFalse(success, "invalid verse");
        assertEq(bytes4(data), IMemeverseLauncher.InvalidVerseId.selector, "selector");
    }

    function testClaimNormalYT_RevertsBeforeLocked() external {
        IMemeverseLauncher.Memeverse memory verse = _baseVerse(IMemeverseLauncher.Stage.Genesis);
        launcher.setMemeverseForTest(1, verse);

        vm.prank(ALICE);
        vm.expectRevert(IMemeverseLauncher.NotReachedLockedStage.selector);
        launcher.claimNormalYT(1);
    }

    /// @notice Verifies launcher no longer exposes a configurable unlock-protection getter/setter surface.
    /// @dev The protection window is now a fixed product constant rather than owner-configurable state.
    function testUnlockProtectionWindow_ConfigSurfaceRemoved() external view {
        (bool getterOk,) = address(launcher).staticcall(abi.encodeWithSignature("unlockProtectionWindow()"));
        (bool setterOk,) =
            address(launcher).staticcall(abi.encodeWithSignature("setUnlockProtectionWindow(uint256)", 1));

        assertFalse(getterOk, "getter should be removed");
        assertFalse(setterOk, "setter should be removed");
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

        uAssetToken.mint(address(this), 1 ether);
        uAssetToken.approve(address(launcher), type(uint256).max);
        launcher.genesis(1, 1 ether, ALICE);

        uint256 _totalNormalFunds = launcher.totalNormalFunds(1);
        (uint256 genesisFund,,) = launcher.userGenesisData(1, ALICE);
        assertEq(_totalNormalFunds, 1 ether);
        assertEq(genesisFund, 1 ether);
    }

    /// @notice Verifies genesis can accumulate past the old fundBasedAmount cap.
    function testGenesis_AllowsAccumulationPastFormerFundBasedAmountCap() external {
        IMemeverseLauncher.Memeverse memory verse = _baseVerse(IMemeverseLauncher.Stage.Genesis);
        launcher.setMemeverseForTest(1, verse);
        launcher.setGenesisFundForTest(1, uint128(MAX_SUPPORTED_FUND_BASED_AMOUNT));

        uAssetToken.mint(address(this), 1 ether);
        uAssetToken.approve(address(launcher), type(uint256).max);

        launcher.genesis(1, 1 ether, ALICE);

        assertEq(launcher.totalNormalFunds(1), MAX_SUPPORTED_FUND_BASED_AMOUNT + 1 ether, "funds increased");
        (uint256 genesisFund,,) = launcher.userGenesisData(1, ALICE);
        assertEq(genesisFund, 1 ether, "genesis fund tracked");
    }

    /// @notice Verifies genesis can cross the former 2^64-1 totalNormalFunds ceiling.
    function testGenesis_AllowsTotalNormalFundsAboveFormerSupportedCapBase() external {
        IMemeverseLauncher.Memeverse memory verse = _baseVerse(IMemeverseLauncher.Stage.Genesis);
        launcher.setMemeverseForTest(1, verse);
        launcher.setGenesisFundForTest(1, uint128(MAX_SUPPORTED_FUND_BASED_AMOUNT - 5));

        uAssetToken.mint(address(this), 10);
        uAssetToken.approve(address(launcher), type(uint256).max);

        launcher.genesis(1, 10, ALICE);

        assertEq(launcher.totalNormalFunds(1), MAX_SUPPORTED_FUND_BASED_AMOUNT + 5, "funds crossed old cap");
        (uint256 genesisFund,,) = launcher.userGenesisData(1, ALICE);
        assertEq(genesisFund, 10, "genesis fund recorded");
    }

    function testGenesis_RevertsWhenAggregateTotalGenesisFundsWouldExceedSupportedMaximum() external {
        IMemeverseLauncher.Memeverse memory verse = _baseVerse(IMemeverseLauncher.Stage.Genesis);
        launcher.setMemeverseForTest(1, verse);
        launcher.setGenesisFundForTest(1, type(uint128).max);
        polend.setTotalLeveragedDebt(1);

        uAssetToken.mint(address(this), 1);
        uAssetToken.approve(address(launcher), type(uint256).max);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMemeverseLauncher.TotalGenesisFundsTooHigh.selector,
                uint256(type(uint128).max) + 2,
                uint256(type(uint128).max)
            )
        );
        launcher.genesis(1, 1, ALICE);
    }

    /// @notice Test refund success marks user and transfers native fund.
    /// @dev Checks that refunds set the flag and return ETH when the verse is in Refund stage.
    function testRefundSuccessMarksUserAndTransfersNativeFund() external {
        IMemeverseLauncher.Memeverse memory verse = _baseVerse(IMemeverseLauncher.Stage.Refund);
        launcher.setMemeverseForTest(1, verse);
        launcher.setUserGenesisDataForTest(1, ALICE, 1 ether, false, false);
        uAssetToken.mint(address(launcher), 1 ether);

        vm.prank(ALICE);
        uint256 refunded = launcher.refund(1);

        (uint256 genesisFund, bool isRefunded,) = launcher.userGenesisData(1, ALICE);
        assertEq(refunded, 1 ether);
        assertEq(genesisFund, 1 ether);
        assertTrue(isRefunded);
        assertEq(uAssetToken.balanceOf(ALICE), 1 ether);
    }

    /// @notice Test claim normal YT pause guard while pause allows refund safety exit.
    /// @dev Ensures pause blocks non-exit claims but does not block refunds.
    function testClaimNormalYTPauseGuardAllowsRefundSafetyExit() external {
        IMemeverseLauncher.Memeverse memory verse = _baseVerse(IMemeverseLauncher.Stage.Locked);
        verse.pol = POL;
        launcher.setMemeverseForTest(1, verse);
        launcher.setGenesisFundForTest(1, 120 ether);
        launcher.setUserGenesisDataForTest(1, ALICE, 0, false, false);
        launcher.setTotalNormalClaimableYTForTest(1, 60 ether);

        vm.prank(ALICE);
        vm.expectRevert(IMemeverseLauncher.InvalidClaim.selector);
        launcher.claimNormalYT(1);

        launcher.pause();
        vm.prank(ALICE);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        launcher.claimNormalYT(1);

        verse.currentStage = IMemeverseLauncher.Stage.Refund;
        launcher.setMemeverseForTest(1, verse);
        launcher.setUserGenesisDataForTest(1, ALICE, 1 ether, false, false);
        uAssetToken.mint(address(launcher), 1 ether);
        vm.prank(ALICE);
        assertEq(launcher.refund(1), 1 ether);
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
        launcher.setGenesisFundForTest(1, 4 ether);

        vm.expectRevert(IMemeverseLauncher.ZeroInput.selector);
        launcher.preorder(1, 0, ALICE);

        uAssetToken.mint(address(this), 2 ether);
        uAssetToken.approve(address(launcher), type(uint256).max);

        vm.expectRevert();
        launcher.preorder(1, 2 ether, ALICE);
    }

    function testPreorderCapacity_IncludesPolFundsInNormalFundBase() external {
        IMemeverseLauncher.Memeverse memory verse = _baseVerse(IMemeverseLauncher.Stage.Genesis);
        launcher.setMemeverseForTest(1, verse);
        launcher.setGenesisFundForTest(1, 10 ether);

        uAssetToken.mint(address(this), 1 ether);
        uAssetToken.approve(address(launcher), type(uint256).max);

        launcher.preorder(1, 1 ether, ALICE);

        (uint256 preorderFunds,, bool isRefunded) = launcher.userPreorderData(1, ALICE);
        assertEq(preorderFunds, 1 ether, "preorder accepted");
        assertFalse(isRefunded, "not refunded");
    }

    function testPreorderCapacityCheck_HandlesLargeBaseWithoutIntermediateOverflow() external {
        uint256 baseFunds = type(uint128).max;
        uint256 expectedCapacity = _expectedDefaultPreorderCapacity(baseFunds);
        IMemeverseLauncher.Memeverse memory verse = _baseVerse(IMemeverseLauncher.Stage.Genesis);
        launcher.setMemeverseForTest(1, verse);
        launcher.setGenesisFundForTest(1, baseFunds);
        launcher.setPreorderStateForTest(1, expectedCapacity - 1, 0, 0);

        uAssetToken.mint(address(this), 1);
        uAssetToken.approve(address(launcher), type(uint256).max);

        launcher.preorder(1, 1, ALICE);

        (uint256 preorderFunds,, bool isRefunded) = launcher.userPreorderData(1, ALICE);
        assertEq(preorderFunds, 1, "preorder accepted");
        assertFalse(isRefunded, "not refunded");
    }

    /// @notice Test claimable preorder memecoin linearly vests over seven days.
    /// @dev Checks that linear vesting unfolds over 7 days by warping time.
    function testClaimablePreorderMemecoin_LinearVestingOverSevenDays() external {
        IMemeverseLauncher.Memeverse memory verse = _baseVerse(IMemeverseLauncher.Stage.Locked);
        launcher.setMemeverseForTest(1, verse);
        launcher.setUserPreorderDataForTest(1, ALICE, 1 ether, 10 ether, false);
        launcher.setPreorderStateForTest(1, 1 ether, 70 ether, uint40(block.timestamp));
        uAssetToken.mint(address(launcher), 70 ether);

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
