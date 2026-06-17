// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {POLend} from "../../src/polend/POLend.sol";
import {IPOLend} from "../../src/polend/interfaces/IPOLend.sol";
import {IMemeverseLauncher} from "../../src/verse/interfaces/IMemeverseLauncher.sol";

contract MockLauncherForPOLend {
    mapping(uint256 verseId => uint256 totalNormalFunds) internal normalFunds;
    mapping(uint256 verseId => uint256 polSettlementAmount) internal polSettlementAmounts;
    mapping(uint256 verseId => uint256 ptSettlementAmount) internal ptSettlementAmounts;
    mapping(uint256 verseId => uint256 uAssetSettlementAmount) internal uAssetSettlementAmounts;
    mapping(uint256 verseId => IMemeverseLauncher.Memeverse) internal verses;
    mapping(address uAsset => IMemeverseLauncher.FundMetaData) internal fundMetaDatas_;
    bool internal legacyDebtCapReadsRevert;

    function setGenesisFunds(uint256 verseId, uint256 totalNormalFunds_) external {
        normalFunds[verseId] = totalNormalFunds_;
    }

    function setSettlementResult(uint256 verseId, uint256 polAmount, uint256 ptAmount, uint256 uAssetAmount) external {
        polSettlementAmounts[verseId] = polAmount;
        ptSettlementAmounts[verseId] = ptAmount;
        uAssetSettlementAmounts[verseId] = uAssetAmount;
    }

    function setVerseUAsset(uint256 verseId, address uAsset) external {
        verses[verseId].uAsset = uAsset;
    }

    function setVerseStage(uint256 verseId, IMemeverseLauncher.Stage stage) external {
        verses[verseId].currentStage = stage;
    }

    function setFundMetaData(address uAsset, uint256 minTotalFund, uint256 fundBasedAmount) external {
        fundMetaDatas_[uAsset] =
            IMemeverseLauncher.FundMetaData({minTotalFund: minTotalFund, fundBasedAmount: fundBasedAmount});
    }

    function setLegacyDebtCapReadsRevert(bool revertReads) external {
        legacyDebtCapReadsRevert = revertReads;
    }

    function totalNormalFunds(uint256 verseId) external view returns (uint256) {
        if (legacyDebtCapReadsRevert) revert("legacy debt cap read");
        return normalFunds[verseId];
    }

    function getMemeverseByVerseId(uint256 verseId) external view returns (IMemeverseLauncher.Memeverse memory verse) {
        return verses[verseId];
    }

    function getUAssetByVerseId(uint256 verseId) external view returns (address) {
        return verses[verseId].uAsset;
    }

    function getStageByVerseId(uint256 verseId) external view returns (IMemeverseLauncher.Stage stage) {
        return verses[verseId].currentStage;
    }

    function fundMetaDatas(address uAsset) external view returns (uint256 minTotalFund, uint256 fundBasedAmount) {
        if (legacyDebtCapReadsRevert) revert("legacy debt cap read");
        IMemeverseLauncher.FundMetaData memory metadata = fundMetaDatas_[uAsset];
        return (metadata.minTotalFund, metadata.fundBasedAmount);
    }

    function getDebtCapBaseByVerseId(uint256 verseId) external view returns (uint256 debtCapBase) {
        address uAsset = verses[verseId].uAsset;
        uint256 minTotalFund = fundMetaDatas_[uAsset].minTotalFund;
        uint256 totalNormalFunds_ = normalFunds[verseId];
        return totalNormalFunds_ > minTotalFund ? totalNormalFunds_ : minTotalFund;
    }

    function remainingGenesisCapacity(uint256 verseId) external view returns (uint256 remaining) {
        uint256 totalFunds = normalFunds[verseId];
        if (totalFunds >= type(uint128).max) return 0;
        return type(uint128).max - totalFunds;
    }

    function settleLeveragedAuxiliaryLiquidity(uint256 verseId)
        external
        view
        returns (uint256 polAmount, uint256 ptAmount, uint256 uAssetAmount)
    {
        return (polSettlementAmounts[verseId], ptSettlementAmounts[verseId], uAssetSettlementAmounts[verseId]);
    }

    function redeemMemecoinLiquidity(uint256, uint256, bool) external pure returns (uint256) {
        revert("unused");
    }
}

contract MockSplitterForPOLend {
    address internal pt;
    address internal yt;
    address internal pol;
    address internal memecoin;
    address internal uAsset;
    uint256 internal redeemPTAmount;
    uint256 public deployTokensCallCount;
    uint256 public initializeVerseCallCount;
    uint256 public preRedeemCallCount;
    uint256 public lastPreRedeemVerseId;
    uint256 public lastPreRedeemPTAmount;
    uint256 public preRedeemBacking = 25 ether;

    function setTokens(address pt_, address yt_) external {
        pt = pt_;
        yt = yt_;
    }

    function setSplitInfo(address pol_, address memecoin_, address uAsset_) external {
        pol = pol_;
        memecoin = memecoin_;
        uAsset = uAsset_;
    }

    function setRedeemPTAmount(uint256 amount) external {
        redeemPTAmount = amount;
    }

    function deployTokens(uint256, address, string calldata, string calldata) external returns (address, address) {
        deployTokensCallCount++;
        return (pt, yt);
    }

    function initializeVerse(uint256, address, address, address, string calldata, string calldata)
        external
        returns (address, address)
    {
        initializeVerseCallCount++;
        return (pt, yt);
    }

    function redeemPT(uint256, uint256, address) external view returns (uint256) {
        return redeemPTAmount;
    }

    function setPreRedeemBacking(uint256 backing) external {
        preRedeemBacking = backing;
    }

    function preRedeemPTFee(uint256 verseId, uint256 ptAmount) external returns (uint256 uAssetBacking) {
        preRedeemCallCount++;
        lastPreRedeemVerseId = verseId;
        lastPreRedeemPTAmount = ptAmount;
        return preRedeemBacking;
    }

    function splitInfos(uint256)
        external
        view
        returns (address, address, address, address, address, uint256, uint256, uint256, uint256, uint256, bool)
    {
        return (pt, yt, pol, memecoin, uAsset, 0, 0, 0, 0, 0, false);
    }

    function getPT(uint256) external view returns (address) {
        return pt;
    }

    function getYT(uint256) external view returns (address) {
        return yt;
    }

    function getMemecoin(uint256) external view returns (address) {
        return memecoin;
    }

    function getPTAndYT(uint256) external view returns (address, address) {
        return (pt, yt);
    }

    function getPTSettlementState(uint256) external view returns (address, bool) {
        return (pt, false);
    }

    function getPOLAndMemecoin(uint256) external view returns (address, address) {
        return (pol, memecoin);
    }
}

import {
    MockPOLForPOLend,
    MintableToken,
    BurnableMockERC20,
    HookedBurnableMockERC20,
    ReentrantClaimMockERC20
} from "../mocks/polend/POLendMocks.sol";
import {POLendStorageHelper} from "../mocks/polend/POLendStorageHelper.sol";

contract POLendTest is Test, POLendStorageHelper {
    uint256 internal constant VERSE_ID = 1;
    uint256 internal constant OTHER_VERSE_ID = 2;
    uint256 internal constant MAX_SETTLEMENT_DUST = 1e9;
    uint256 internal constant MAX_LEVERAGED_DEBT_FACTOR = uint256(type(uint128).max) * 1e18;
    bytes4 internal constant INVALID_INITIALIZATION_SELECTOR = bytes4(keccak256("InvalidInitialization()"));
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant CAROL = address(0xCAFE);

    event ProtocolTreasuryChanged(address indexed oldTreasury, address indexed newTreasury);
    event DefaultInterestRateChanged(uint256 oldRate, uint256 newRate);
    event LeveragedDebtFactorChanged(uint256 oldFactor, uint256 newFactor);
    event LeveragedGenesis(uint256 indexed verseId, address indexed user, uint256 interestAmount);
    event PreRedeemPTFee(
        uint256 indexed verseId, address indexed uAsset, uint256 ptAmount, uint256 uAssetBacking, address mintTo
    );
    event SettlementDustReserveConfigured(address indexed uAsset, uint128 oldMaxReserve, uint128 newMaxReserve);
    event SettlementDustReservedFromInterest(
        uint256 indexed verseId,
        address indexed uAsset,
        uint256 totalLeveragedInterest,
        uint256 credited,
        uint256 treasuryInterest,
        uint256 reserveAfter
    );
    event SettlementDustReserveFunded(
        address indexed uAsset, address indexed funder, uint256 amount, uint256 credited, uint256 excess
    );
    event SettlementDustReserveConsumed(
        uint256 indexed verseId, address indexed uAsset, uint256 consumed, uint256 reserveAfter
    );
    event GlobalSettlementExecuted(
        uint256 indexed verseId,
        address indexed uAsset,
        uint256 verseDebt,
        uint256 recoveredUAsset,
        uint256 consumedSettlementDustReserve,
        uint256 settlementDustReserveAfter,
        uint256 residualUAsset,
        uint256 residualMemecoin
    );

    BurnableMockERC20 internal uAsset;
    BurnableMockERC20 internal otherUAsset;
    MintableToken internal yt;
    MintableToken internal pt;
    MockERC20 internal memecoin;
    MockPOLForPOLend internal pol;
    MockLauncherForPOLend internal launcher;
    MockSplitterForPOLend internal splitter;
    POLend internal polend;

    function setUp() external {
        uAsset = new BurnableMockERC20("UASSET", "UASSET");
        otherUAsset = new BurnableMockERC20("OTHER", "OTHER");
        yt = new MintableToken("YT", "YT");
        pt = new MintableToken("PT", "PT");
        memecoin = new MockERC20("MEME", "MEME", 18);
        pol = new MockPOLForPOLend(address(memecoin));
        launcher = new MockLauncherForPOLend();
        splitter = new MockSplitterForPOLend();
        splitter.setTokens(address(pt), address(yt));
        splitter.setSplitInfo(address(pol), address(memecoin), address(uAsset));

        polend = _deployPOLend(1e17, 10e18, address(this), address(launcher), address(splitter));
        uAsset.mint(address(this), 10_000 ether);
        otherUAsset.mint(address(this), 10_000 ether);
        uAsset.approve(address(polend), type(uint256).max);
        otherUAsset.approve(address(polend), type(uint256).max);

        launcher.setGenesisFunds(VERSE_ID, 1_000 ether);
        launcher.setGenesisFunds(OTHER_VERSE_ID, 1_000 ether);
        launcher.setVerseUAsset(VERSE_ID, address(uAsset));
        launcher.setVerseUAsset(OTHER_VERSE_ID, address(otherUAsset));
        launcher.setFundMetaData(address(uAsset), 1_000 ether, 1);
        launcher.setFundMetaData(address(otherUAsset), 1_000 ether, 1);
        polend.setMaxSettlementDustReserve(address(uAsset), uint128(MAX_SETTLEMENT_DUST));
        polend.setMaxSettlementDustReserve(address(otherUAsset), uint128(MAX_SETTLEMENT_DUST));
        vm.prank(address(launcher));
        polend.registerLendMarket(VERSE_ID);
        vm.prank(address(launcher));
        polend.registerLendMarket(OTHER_VERSE_ID);
    }

    function _deployPOLend(
        uint256 interestRate,
        uint256 leveragedDebtFactor,
        address treasury,
        address launcher_,
        address splitter_
    ) internal returns (POLend deployed) {
        POLend implementation = new POLend();
        return _deployPOLendWithImplementation(
            implementation, interestRate, leveragedDebtFactor, treasury, launcher_, splitter_
        );
    }

    function _deployPOLendWithImplementation(
        POLend implementation,
        uint256 interestRate,
        uint256 leveragedDebtFactor,
        address treasury,
        address launcher_,
        address splitter_
    ) internal returns (POLend deployed) {
        bytes memory data = abi.encodeCall(
            POLend.initialize, (address(this), interestRate, leveragedDebtFactor, treasury, launcher_, splitter_)
        );
        return POLend(address(new ERC1967Proxy(address(implementation), data)));
    }

    function _fundDustReserveFromAlice(uint256 amount) internal {
        uAsset.mint(ALICE, amount);
        vm.prank(ALICE);
        uAsset.approve(address(polend), amount);
        vm.prank(ALICE);
        polend.fundSettlementDustReserve(address(uAsset), amount);
    }

    function testInitialize_RevertsWhenInterestRateZeroOrAboveOne() external {
        POLend implementation = new POLend();

        vm.expectRevert(IPOLend.ZeroInput.selector);
        _deployPOLendWithImplementation(implementation, 0, 10e18, address(this), address(launcher), address(splitter));

        implementation = new POLend();

        vm.expectRevert(IPOLend.InvalidConfig.selector);
        _deployPOLendWithImplementation(
            implementation, 1e18 + 1, 10e18, address(this), address(launcher), address(splitter)
        );

        implementation = new POLend();

        vm.expectRevert(IPOLend.ZeroInput.selector);
        _deployPOLendWithImplementation(implementation, 1e18, 0, address(this), address(launcher), address(splitter));

        implementation = new POLend();

        POLend deployed = _deployPOLendWithImplementation(
            implementation, 1e18, MAX_LEVERAGED_DEBT_FACTOR, address(this), address(launcher), address(splitter)
        );
        assertEq(deployed.leveragedDebtFactor(), MAX_LEVERAGED_DEBT_FACTOR, "max factor stored");
    }

    function testInitialize_RevertsWhenLeveragedDebtFactorExceedsMax() external {
        POLend implementation = new POLend();

        vm.expectRevert(IPOLend.InvalidConfig.selector);
        _deployPOLendWithImplementation(
            implementation, 1e18, MAX_LEVERAGED_DEBT_FACTOR + 1, address(this), address(launcher), address(splitter)
        );
    }

    function testInitialize_RevertsWhenRequiredAddressesAreZero() external {
        POLend implementation = new POLend();

        vm.expectRevert(IPOLend.ZeroInput.selector);
        _deployPOLendWithImplementation(implementation, 1e17, 10e18, address(0), address(launcher), address(splitter));

        implementation = new POLend();

        vm.expectRevert(IPOLend.ZeroInput.selector);
        _deployPOLendWithImplementation(implementation, 1e17, 10e18, address(this), address(0), address(splitter));

        implementation = new POLend();

        vm.expectRevert(IPOLend.ZeroInput.selector);
        _deployPOLendWithImplementation(implementation, 1e17, 10e18, address(this), address(launcher), address(0));
    }

    function testImplementationInitializerIsDisabled() external {
        POLend implementation = new POLend();

        vm.expectRevert(INVALID_INITIALIZATION_SELECTOR);
        implementation.initialize(address(this), 1e17, 10e18, address(this), address(launcher), address(splitter));
    }

    function testSetMaxSettlementDustReserve_ConfiguresGlobalState() external {
        BurnableMockERC20 extraUAsset = new BurnableMockERC20("EXTRA", "EXTRA");

        vm.expectEmit(true, false, false, true);
        emit SettlementDustReserveConfigured(address(extraUAsset), 0, uint128(MAX_SETTLEMENT_DUST));
        polend.setMaxSettlementDustReserve(address(extraUAsset), uint128(MAX_SETTLEMENT_DUST));

        (uint128 reserve, uint128 maxReserve) = polend.settlementDustStates(address(extraUAsset));
        assertEq(reserve, 0, "reserve");
        assertEq(maxReserve, uint128(MAX_SETTLEMENT_DUST), "max reserve");
    }

    function testSetMaxSettlementDustReserve_RevertsWhenLoweringBelowReserve() external {
        _fundDustReserveFromAlice(MAX_SETTLEMENT_DUST);

        vm.expectRevert(IPOLend.InvalidConfig.selector);
        polend.setMaxSettlementDustReserve(address(uAsset), uint128(MAX_SETTLEMENT_DUST - 1));
    }

    function testRegisterLendMarket_RevertsWhenSettlementDustReserveUnconfigured() external {
        POLend localPolend = _deployPOLend(1e17, 10e18, address(this), address(launcher), address(splitter));
        uint256 verseId = 98;
        launcher.setVerseUAsset(verseId, address(uAsset));

        vm.expectRevert(IPOLend.InvalidConfig.selector);
        vm.prank(address(launcher));
        localPolend.registerLendMarket(verseId);
    }

    function testLeveragedGenesis_AccumulatesInterestAndDebt() external {
        uAsset.mint(ALICE, 10 ether);
        vm.prank(ALICE);
        uAsset.approve(address(polend), 10 ether);

        vm.prank(ALICE);
        uint256 borrowed = polend.leveragedGenesis(VERSE_ID, 10 ether);
        assertEq(borrowed, 100 ether, "borrowed");

        uint256 interestPaid = polend.leveragedInterestPaid(VERSE_ID, ALICE);
        assertEq(interestPaid, 10 ether, "interest");
        assertEq(polend.getUserLeveragedDebt(VERSE_ID, ALICE), 100 ether, "debt");
        assertEq(polend.getTotalLeveragedDebt(VERSE_ID), 100 ether, "total debt");
    }

    function testLeveragedGenesis_EmitsLeveragedGenesis() external {
        polend.setMaxSettlementDustReserve(address(uAsset), uint128(MAX_SETTLEMENT_DUST));
        uAsset.mint(ALICE, 10 ether);
        vm.prank(ALICE);
        uAsset.approve(address(polend), 10 ether);

        vm.expectEmit(true, true, false, true);
        emit LeveragedGenesis(VERSE_ID, ALICE, 10 ether);
        vm.prank(ALICE);
        polend.leveragedGenesis(VERSE_ID, 10 ether);
    }

    function testLeveragedGenesis_ReentrantTransferKeepsAccumulatedInterest() external {
        HookedBurnableMockERC20 hookedUAsset = new HookedBurnableMockERC20("HOOK", "HOOK");
        polend.setMaxSettlementDustReserve(address(hookedUAsset), uint128(MAX_SETTLEMENT_DUST));
        hookedUAsset.mint(ALICE, 10 ether);
        vm.prank(ALICE);
        hookedUAsset.approve(address(polend), 10 ether);

        launcher.setVerseUAsset(VERSE_ID, address(hookedUAsset));
        launcher.setFundMetaData(address(hookedUAsset), 1_000 ether, 1);
        seedMarketUAssetForTest(address(polend), VERSE_ID, address(hookedUAsset));
        hookedUAsset.enableLeveragedGenesisReentry(address(polend), VERSE_ID, 5 ether);

        vm.prank(ALICE);
        uint256 borrowed = polend.leveragedGenesis(VERSE_ID, 10 ether);

        assertEq(borrowed, 100 ether, "borrowed");
        assertEq(hookedUAsset.balanceOf(address(polend)), 15 ether, "transferred");
        assertEq(polend.leveragedInterestPaid(VERSE_ID, ALICE), 10 ether, "interest");
        assertEq(polend.leveragedInterestPaid(VERSE_ID, address(hookedUAsset)), 5 ether, "reentry interest");
        assertEq(polend.getTotalLeveragedInterest(VERSE_ID), 15 ether, "total interest");
        assertEq(polend.getTotalLeveragedDebt(VERSE_ID), 150 ether, "total debt");
    }

    function testLeveragedGenesis_UsesFullPrecisionDebtMathForLargeInterest() external {
        uint256 largeInterest = uint256(type(uint128).max) / 2;
        uint256 verseId = 101;
        POLend localPolend = _deployPOLend(1e18, 1e18, address(this), address(launcher), address(splitter));
        launcher.setVerseUAsset(verseId, address(uAsset));
        launcher.setGenesisFunds(verseId, 0);
        launcher.setFundMetaData(address(uAsset), largeInterest, 1);
        localPolend.setMaxSettlementDustReserve(address(uAsset), uint128(MAX_SETTLEMENT_DUST));
        vm.prank(address(launcher));
        localPolend.registerLendMarket(verseId);

        uAsset.mint(ALICE, largeInterest);
        vm.prank(ALICE);
        uAsset.approve(address(localPolend), largeInterest);

        vm.prank(ALICE);
        uint256 borrowed = localPolend.leveragedGenesis(verseId, largeInterest);

        assertEq(borrowed, largeInterest, "borrowed");
        assertEq(localPolend.getUserLeveragedDebt(verseId, ALICE), largeInterest, "user debt");
        assertEq(localPolend.getTotalLeveragedDebt(verseId), largeInterest, "total debt");
    }

    function testLeveragedGenesis_RevertsOutsideLauncherGenesisWithoutStateOrTransfer() external {
        polend.setMaxSettlementDustReserve(address(uAsset), uint128(MAX_SETTLEMENT_DUST));
        launcher.setVerseStage(VERSE_ID, IMemeverseLauncher.Stage.Locked);
        uAsset.mint(ALICE, 10 ether);
        vm.prank(ALICE);
        uAsset.approve(address(polend), 10 ether);

        vm.prank(ALICE);
        vm.expectRevert(IPOLend.InvalidState.selector);
        polend.leveragedGenesis(VERSE_ID, 10 ether);

        IPOLend.LendMarket memory market = polend.getLendMarket(VERSE_ID);
        assertEq(uAsset.balanceOf(address(polend)), 0, "no transfer");
        assertEq(market.totalLeveragedInterest, 0, "interest unchanged");
        assertEq(uint256(market.state), uint256(IPOLend.MarketState.None), "state unchanged");
        assertEq(polend.leveragedInterestPaid(VERSE_ID, ALICE), 0, "position unchanged");
    }

    function testLeveragedGenesis_UsesMinTotalFundForDebtCapWhenNormalFundsAreZero() external {
        polend.setMaxSettlementDustReserve(address(uAsset), uint128(MAX_SETTLEMENT_DUST));
        launcher.setGenesisFunds(VERSE_ID, 0);
        launcher.setFundMetaData(address(uAsset), 1_000 ether, 1);
        uAsset.mint(ALICE, 1_001 ether);
        vm.prank(ALICE);
        uAsset.approve(address(polend), 1_001 ether);

        vm.prank(ALICE);
        assertEq(polend.leveragedGenesis(VERSE_ID, 1_000 ether), 10_000 ether, "within cap");

        vm.prank(ALICE);
        vm.expectRevert(IPOLend.DebtCapExceeded.selector);
        polend.leveragedGenesis(VERSE_ID, 1 ether);
    }

    function testRegisterLendMarket_TargetABIReadsUAssetAndDoesNotInitializeTokens() external {
        MockSplitterForPOLend localSplitter = new MockSplitterForPOLend();
        POLend localPolend = _deployPOLend(1e17, 10e18, address(this), address(launcher), address(localSplitter));
        uint256 verseId = 99;
        launcher.setVerseUAsset(verseId, address(uAsset));
        localPolend.setMaxSettlementDustReserve(address(uAsset), uint128(MAX_SETTLEMENT_DUST));

        vm.prank(address(launcher));
        (bool success,) = address(localPolend).call(abi.encodeWithSignature("registerLendMarket(uint256)", verseId));

        assertTrue(success, "one-arg register");
        IPOLend.LendMarket memory market = localPolend.getLendMarket(verseId);
        assertEq(market.uAsset, address(uAsset), "uAsset from launcher");
        assertEq(localSplitter.deployTokensCallCount(), 0, "no deployTokens during register");
        assertEq(localSplitter.initializeVerseCallCount(), 0, "no initializeVerse during register");
    }

    function testRegisterLendMarket_RevertsOnDuplicateVerse() external {
        MockSplitterForPOLend localSplitter = new MockSplitterForPOLend();
        POLend localPolend = _deployPOLend(1e17, 10e18, address(this), address(launcher), address(localSplitter));
        uint256 verseId = 100;
        launcher.setVerseUAsset(verseId, address(uAsset));
        localPolend.setMaxSettlementDustReserve(address(uAsset), uint128(MAX_SETTLEMENT_DUST));

        vm.startPrank(address(launcher));
        (bool first,) = address(localPolend).call(abi.encodeWithSignature("registerLendMarket(uint256)", verseId));
        (bool second,) = address(localPolend).call(abi.encodeWithSignature("registerLendMarket(uint256)", verseId));
        vm.stopPrank();

        assertTrue(first, "first register");
        assertFalse(second, "duplicate register");
    }

    function testRegisterLendMarket_TreatsExistingUAssetAsRegisteredWhenRateIsZero() external {
        MockSplitterForPOLend localSplitter = new MockSplitterForPOLend();
        POLend localPolend = _deployPOLend(1e17, 10e18, address(this), address(launcher), address(localSplitter));
        uint256 verseId = 101;
        launcher.setVerseUAsset(verseId, address(uAsset));
        localPolend.setMaxSettlementDustReserve(address(uAsset), uint128(MAX_SETTLEMENT_DUST));
        seedMarketUAssetForTest(address(localPolend), verseId, address(uAsset));

        vm.prank(address(launcher));
        vm.expectRevert(IPOLend.InvalidState.selector);
        localPolend.registerLendMarket(verseId);
    }

    function testRegisterLendMarket_RevertsWhenLauncherReturnsZeroUAsset() external {
        MockSplitterForPOLend localSplitter = new MockSplitterForPOLend();
        POLend localPolend = _deployPOLend(1e17, 10e18, address(this), address(launcher), address(localSplitter));
        uint256 verseId = 102;

        vm.prank(address(launcher));
        vm.expectRevert(IPOLend.ZeroInput.selector);
        localPolend.registerLendMarket(verseId);
    }

    function testSetDefaultInterestRate_RevertsWhenDebtFactorAndRateCannotReachThreshold() external {
        MockSplitterForPOLend localSplitter = new MockSplitterForPOLend();
        POLend localPolend = _deployPOLend(1e18, 1e18, address(this), address(launcher), address(localSplitter));

        vm.expectRevert(IPOLend.InvalidConfig.selector);
        localPolend.setDefaultInterestRate(1);

        assertEq(localPolend.defaultInterestRate(), 1e18, "rate unchanged");
    }

    function testDebtCapacityAndLeveragedGenesis_DoNotPanicAtLargeFactorAndLargeFundBase() external {
        uint256 largeFactor = 2e18;
        MockSplitterForPOLend localSplitter = new MockSplitterForPOLend();
        POLend localPolend = _deployPOLend(1e18, largeFactor, address(this), address(launcher), address(localSplitter));
        uint256 verseId = 103;
        launcher.setVerseUAsset(verseId, address(uAsset));
        launcher.setGenesisFunds(verseId, 0);
        launcher.setFundMetaData(address(uAsset), type(uint128).max, 1);
        localPolend.setMaxSettlementDustReserve(address(uAsset), uint128(MAX_SETTLEMENT_DUST));
        vm.prank(address(launcher));
        localPolend.registerLendMarket(verseId);

        IPOLend.LeveragedDebtInfo memory info = localPolend.getLeveragedDebtInfo(verseId);

        assertEq(info.totalLeveragedInterest, 0, "interest");
        assertEq(info.debtCap, type(uint128).max, "debt cap clamped by aggregate cap");
        assertGt(info.remainingAdditionalInterest, 0, "remaining");
    }

    function testDebtCapacity_SaturatedDebtCapDoesNotReportUnreachableRemainingInterest() external {
        uint256 verseId = 107;
        uint256 rate = 5e17;
        uint256 largeFactor = MAX_LEVERAGED_DEBT_FACTOR;
        MockSplitterForPOLend localSplitter = new MockSplitterForPOLend();
        POLend localPolend = _deployPOLend(rate, largeFactor, address(this), address(launcher), address(localSplitter));
        launcher.setVerseUAsset(verseId, address(uAsset));
        launcher.setGenesisFunds(verseId, 0);
        launcher.setFundMetaData(address(uAsset), type(uint128).max, 1);
        localPolend.setMaxSettlementDustReserve(address(uAsset), uint128(MAX_SETTLEMENT_DUST));
        vm.prank(address(launcher));
        localPolend.registerLendMarket(verseId);

        IPOLend.LeveragedDebtInfo memory info = localPolend.getLeveragedDebtInfo(verseId);
        uint256 clampedDebtCap = type(uint128).max;
        uint256 expectedMaxTotalInterest = Math.mulDiv(clampedDebtCap + 1, rate, 1e18, Math.Rounding.Ceil) - 1;

        assertEq(info.debtCap, type(uint128).max, "debt cap clamped by aggregate cap");
        assertEq(info.remainingAdditionalInterest, expectedMaxTotalInterest, "bounded remaining interest");
    }

    function testLeveragedGenesis_RevertsWhenAggregateTotalGenesisFundsWouldExceedSupportedMaximum() external {
        uint256 verseId = 108;
        uint256 rate = 1e18;
        MockSplitterForPOLend localSplitter = new MockSplitterForPOLend();
        POLend localPolend = _deployPOLend(rate, 2e18, address(this), address(launcher), address(localSplitter));
        launcher.setVerseUAsset(verseId, address(uAsset));
        launcher.setGenesisFunds(verseId, type(uint128).max);
        launcher.setFundMetaData(address(uAsset), 1, 1);
        localPolend.setMaxSettlementDustReserve(address(uAsset), uint128(MAX_SETTLEMENT_DUST));
        vm.prank(address(launcher));
        localPolend.registerLendMarket(verseId);

        uAsset.mint(ALICE, 1);
        vm.prank(ALICE);
        uAsset.approve(address(localPolend), 1);
        vm.prank(ALICE);
        vm.expectRevert(IPOLend.InvalidConfig.selector);
        localPolend.leveragedGenesis(verseId, 1);
    }

    function testLeveragedGenesis_RevertsWhenCumulativeAggregateTotalGenesisFundsWouldExceedSupportedMaximum()
        external
    {
        uint256 verseId = 109;
        MockSplitterForPOLend localSplitter = new MockSplitterForPOLend();
        POLend localPolend = _deployPOLend(1e18, 2e18, address(this), address(launcher), address(localSplitter));
        launcher.setVerseUAsset(verseId, address(uAsset));
        launcher.setGenesisFunds(verseId, uint256(type(uint128).max) - 10);
        launcher.setFundMetaData(address(uAsset), 1, 1);
        localPolend.setMaxSettlementDustReserve(address(uAsset), uint128(MAX_SETTLEMENT_DUST));
        vm.prank(address(launcher));
        localPolend.registerLendMarket(verseId);

        uAsset.mint(ALICE, 11);
        vm.prank(ALICE);
        uAsset.approve(address(localPolend), 11);

        vm.prank(ALICE);
        assertEq(localPolend.leveragedGenesis(verseId, 10), 10, "first debt");
        assertEq(localPolend.getTotalLeveragedDebt(verseId), 10, "total debt");

        vm.prank(ALICE);
        vm.expectRevert(IPOLend.InvalidConfig.selector);
        localPolend.leveragedGenesis(verseId, 1);
    }

    /// @notice Verifies leveragedGenesis reverts with DebtCapExceeded when interest pushes debt exactly 1 unit over the debt cap.
    function testLeveragedGenesis_RevertsWhenDebtExceedsCapByOne() external {
        // Setup: interestRate = 1e18 (1:1 mapping), debtFactor = 2e18, minTotalFund = 100
        // debtCap = debtFactor * capBase / 1e18 = 2e18 * 100 / 1e18 = 200
        // With interestRate = 1e18: previewTotalDebt = interest * 1e18 / 1e18 = interest
        // So: borrow 200 interest => debt = 200 = debtCap => succeeds
        // Then: borrow 1 more interest => debt would be 201 > 200 => reverts
        uint256 verseId = 150;
        MockSplitterForPOLend localSplitter = new MockSplitterForPOLend();
        POLend localPolend = _deployPOLend(1e18, 2e18, address(this), address(launcher), address(localSplitter));
        launcher.setVerseUAsset(verseId, address(uAsset));
        launcher.setGenesisFunds(verseId, 0);
        launcher.setFundMetaData(address(uAsset), 100, 1);
        localPolend.setMaxSettlementDustReserve(address(uAsset), uint128(MAX_SETTLEMENT_DUST));
        vm.prank(address(launcher));
        localPolend.registerLendMarket(verseId);

        // Verify debt cap = 200
        IPOLend.LeveragedDebtInfo memory info = localPolend.getLeveragedDebtInfo(verseId);
        assertEq(info.debtCap, 200, "debt cap");

        // Borrow exactly up to the cap: 200 interest => previewTotalDebt = 200 = debtCap
        uAsset.mint(ALICE, 200);
        vm.prank(ALICE);
        uAsset.approve(address(localPolend), 200);
        vm.prank(ALICE);
        localPolend.leveragedGenesis(verseId, 200);

        // Borrow 1 more => previewTotalDebt = 201 > 200 => revert
        vm.prank(ALICE);
        vm.expectRevert(IPOLend.DebtCapExceeded.selector);
        localPolend.leveragedGenesis(verseId, 1);
    }

    function testGetLeveragedDebtInfo_UsesCeilDerivedRemainingInterestCapacity() external {
        uint256 verseId = 106;
        POLend localPolend = _deployPOLend(0.7 ether, 2 ether, address(this), address(launcher), address(splitter));
        launcher.setVerseUAsset(verseId, address(uAsset));
        launcher.setGenesisFunds(verseId, 0);
        launcher.setFundMetaData(address(uAsset), 1, 1);
        localPolend.setMaxSettlementDustReserve(address(uAsset), uint128(MAX_SETTLEMENT_DUST));
        vm.prank(address(launcher));
        localPolend.registerLendMarket(verseId);

        IPOLend.LeveragedDebtInfo memory info = localPolend.getLeveragedDebtInfo(verseId);

        assertEq(info.debtCap, 2, "debt cap");
        assertEq(info.remainingAdditionalInterest, 2, "ceil-derived capacity");
    }

    function testGetLeveragedDebtInfo_ReturnsZeroCapacityWhenDustCapUnset() external {
        seedSettlementDustStateForTest(address(polend), address(uAsset), 0, 0);
        (uint256 totalInterest, uint256 totalDebt, uint256 rate, uint256 debtCap, uint256 remaining) =
            _getLeveragedDebtInfo(VERSE_ID);

        assertEq(totalInterest, 0, "interest");
        assertEq(totalDebt, 0, "debt");
        assertEq(rate, 1e17, "rate");
        assertEq(debtCap, 0, "debt cap");
        assertEq(remaining, 0, "remaining");
    }

    function testFinalizeLeveragedGenesis_LocksMarketMintsDebtAndSweepsInterest() external {
        polend.setMaxSettlementDustReserve(address(uAsset), uint128(MAX_SETTLEMENT_DUST));
        uAsset.mint(ALICE, 10 ether);
        vm.prank(ALICE);
        uAsset.approve(address(polend), 10 ether);

        vm.prank(ALICE);
        polend.leveragedGenesis(VERSE_ID, 10 ether);

        uint256 treasuryBefore = uAsset.balanceOf(address(this));
        vm.prank(address(launcher));
        (bool success,) = address(polend).call(abi.encodeWithSignature("finalizeLeveragedGenesis(uint256)", VERSE_ID));

        assertTrue(success, "finalize");
        IPOLend.LendMarket memory market = polend.getLendMarket(VERSE_ID);
        assertEq(uint256(market.state), 2, "state locked");
        assertEq(uAsset.balanceOf(address(launcher)), 100 ether, "minted debt to launcher");
        assertEq(
            uAsset.balanceOf(address(this)) - treasuryBefore,
            10 ether - MAX_SETTLEMENT_DUST,
            "interest swept to treasury"
        );
    }

    function testFinalizeLeveragedGenesis_CreditsGlobalReserveAndTransfersTreasuryInterest() external {
        uAsset.mint(ALICE, 10 ether);
        vm.prank(ALICE);
        uAsset.approve(address(polend), 10 ether);
        vm.prank(ALICE);
        polend.leveragedGenesis(VERSE_ID, 10 ether);
        uint256 treasuryBefore = uAsset.balanceOf(address(this));

        vm.expectEmit(true, true, false, true);
        emit SettlementDustReservedFromInterest(
            VERSE_ID,
            address(uAsset),
            10 ether,
            MAX_SETTLEMENT_DUST,
            10 ether - MAX_SETTLEMENT_DUST,
            MAX_SETTLEMENT_DUST
        );
        vm.prank(address(launcher));
        polend.finalizeLeveragedGenesis(VERSE_ID);

        (uint128 reserve,) = polend.settlementDustStates(address(uAsset));
        assertEq(reserve, uint128(MAX_SETTLEMENT_DUST), "reserve");
        assertEq(uAsset.balanceOf(address(this)), treasuryBefore + 10 ether - MAX_SETTLEMENT_DUST, "treasury");
        assertEq(uAsset.balanceOf(address(polend)), MAX_SETTLEMENT_DUST, "polend reserve");
    }

    function testFinalizeLeveragedGenesis_ReserveIsCappedByInterest() external {
        BurnableMockERC20 extraUAsset = new BurnableMockERC20("EXTRA", "EXTRA");
        uint256 verseId = 399;
        launcher.setVerseUAsset(verseId, address(extraUAsset));
        launcher.setGenesisFunds(verseId, 1_000 ether);
        launcher.setFundMetaData(address(extraUAsset), 1_000 ether, 1);
        polend.setMaxSettlementDustReserve(address(extraUAsset), uint128(10 ether));
        vm.prank(address(launcher));
        polend.registerLendMarket(verseId);

        extraUAsset.mint(ALICE, 1 ether);
        vm.prank(ALICE);
        extraUAsset.approve(address(polend), 1 ether);
        vm.prank(ALICE);
        polend.leveragedGenesis(verseId, 1 ether);

        vm.prank(address(launcher));
        polend.finalizeLeveragedGenesis(verseId);

        (uint128 reserve,) = polend.settlementDustStates(address(extraUAsset));
        assertEq(reserve, uint128(1 ether), "reserve capped by interest");
        assertEq(extraUAsset.balanceOf(address(polend)), 1 ether, "all interest reserved");
    }

    function testFinalizeLeveragedGenesis_RevertsWhenDustCapUnset() external {
        seedSettlementDustStateForTest(address(polend), address(uAsset), 0, 0);
        setGenesisStateForTest(address(polend), VERSE_ID, 10 ether);
        uAsset.mint(address(polend), 10 ether);

        vm.prank(address(launcher));
        vm.expectRevert(IPOLend.InvalidConfig.selector);
        polend.finalizeLeveragedGenesis(VERSE_ID);
    }

    function testClaimRefund_ReturnsInterestOnlyInRefund() external {
        seedLeveragedPositionForTest(address(polend), VERSE_ID, ALICE, 10 ether);
        setRefundStateForTest(address(polend), VERSE_ID);
        uAsset.mint(address(polend), 10 ether);

        vm.prank(ALICE);
        uint256 refunded = _claimRefund(VERSE_ID, CAROL);
        assertEq(refunded, 10 ether, "refund interest only");
        assertEq(uAsset.balanceOf(CAROL), 10 ether, "recipient refunded");
        assertEq(uAsset.balanceOf(ALICE), 0, "caller not recipient");
    }

    function testClaimRefund_MarksCallerAndRejectsZeroRecipient() external {
        seedLeveragedPositionForTest(address(polend), VERSE_ID, ALICE, 10 ether);
        seedLeveragedPositionForTest(address(polend), VERSE_ID, BOB, 5 ether);
        setRefundStateForTest(address(polend), VERSE_ID);
        uAsset.mint(address(polend), 15 ether);

        vm.prank(ALICE);
        _expectLowLevelRevert(
            abi.encodeWithSignature("claimRefund(uint256,address)", VERSE_ID, address(0)), IPOLend.ZeroInput.selector
        );

        vm.prank(ALICE);
        assertEq(_claimRefund(VERSE_ID, CAROL), 10 ether, "alice refund");

        vm.prank(ALICE);
        _expectLowLevelRevert(
            abi.encodeWithSignature("claimRefund(uint256,address)", VERSE_ID, BOB), IPOLend.InvalidClaim.selector
        );

        vm.prank(BOB);
        assertEq(_claimRefund(VERSE_ID, ALICE), 5 ether, "bob refund");
        assertEq(uAsset.balanceOf(ALICE), 5 ether, "bob recipient");
    }

    function testClaimRefund_BlocksReentrantClaim() external {
        ReentrantClaimMockERC20 hookedUAsset = new ReentrantClaimMockERC20("HOOK", "HOOK");
        POLend localPolend = _deployPOLend(1e17, 10e18, address(this), address(launcher), address(splitter));
        uint256 verseId = 201;
        launcher.setVerseUAsset(verseId, address(hookedUAsset));
        localPolend.setMaxSettlementDustReserve(address(hookedUAsset), uint128(MAX_SETTLEMENT_DUST));

        vm.prank(address(launcher));
        localPolend.registerLendMarket(verseId);
        seedLeveragedPositionForTest(address(localPolend), verseId, ALICE, 10 ether);
        seedLeveragedPositionForTest(address(localPolend), verseId, BOB, 5 ether);
        setRefundStateForTest(address(localPolend), verseId);
        hookedUAsset.mint(address(localPolend), 15 ether);
        hookedUAsset.armReentry(
            address(localPolend),
            abi.encodeWithSignature("claimRefund(uint256,address)", verseId, BOB),
            bytes4(keccak256("ReentrancyGuardReentrantCall()"))
        );

        vm.prank(ALICE);
        localPolend.claimRefund(verseId, CAROL);

        assertTrue(hookedUAsset.sawExpectedRevert(), "reentrant refund blocked");
    }

    function testClaimLeveragedYT_MarksCallerAndTransfersToRecipient() external {
        seedLeveragedPositionForTest(address(polend), VERSE_ID, ALICE, 10 ether);
        seedLeveragedPositionForTest(address(polend), VERSE_ID, BOB, 30 ether);
        seedMarketForTest(address(polend), VERSE_ID, address(yt), 40 ether);
        setLockedStateForTest(address(polend), VERSE_ID, 400 ether);
        yt.mint(address(polend), 400 ether);

        vm.prank(ALICE);
        assertEq(_claimLeveragedYT(VERSE_ID, CAROL), 100 ether, "alice yt");
        assertEq(yt.balanceOf(CAROL), 100 ether, "recipient yt");
        assertEq(yt.balanceOf(ALICE), 0, "caller not recipient");

        vm.prank(BOB);
        assertEq(_claimLeveragedYT(VERSE_ID, ALICE), 300 ether, "bob yt");
        assertEq(yt.balanceOf(ALICE), 300 ether, "bob can still claim");

        vm.prank(ALICE);
        _expectLowLevelRevert(
            abi.encodeWithSignature("claimLeveragedYT(uint256,address)", VERSE_ID, BOB), IPOLend.InvalidClaim.selector
        );
    }

    function testClaimLeveragedYT_RevertsWhenRecipientIsZero() external {
        seedLeveragedPositionForTest(address(polend), VERSE_ID, ALICE, 10 ether);
        seedMarketForTest(address(polend), VERSE_ID, address(yt), 10 ether);
        setLockedStateForTest(address(polend), VERSE_ID, 100 ether);
        yt.mint(address(polend), 100 ether);

        vm.prank(ALICE);
        _expectLowLevelRevert(
            abi.encodeWithSignature("claimLeveragedYT(uint256,address)", VERSE_ID, address(0)),
            IPOLend.ZeroInput.selector
        );
    }

    function testClaimLeveragedYT_UsesInterestShareInsteadOfRoundedDebtShare() external {
        uint256 verseId = 104;
        POLend localPolend = _deployPOLend(3, 1e36, address(this), address(launcher), address(splitter));
        launcher.setVerseUAsset(verseId, address(uAsset));
        localPolend.setMaxSettlementDustReserve(address(uAsset), uint128(MAX_SETTLEMENT_DUST));
        vm.prank(address(launcher));
        localPolend.registerLendMarket(verseId);
        seedLeveragedPositionForTest(address(localPolend), verseId, ALICE, 1);
        seedLeveragedPositionForTest(address(localPolend), verseId, BOB, 2);
        seedMarketForTest(address(localPolend), verseId, address(yt), 3);
        setLockedStateForTest(address(localPolend), verseId, 300 ether);
        yt.mint(address(localPolend), 300 ether);

        vm.prank(ALICE);
        (bool success, bytes memory data) =
            address(localPolend).call(abi.encodeWithSignature("claimLeveragedYT(uint256,address)", verseId, CAROL));

        assertTrue(success, "claim");
        assertEq(abi.decode(data, (uint256)), 100 ether, "interest-proportional yt");
        assertEq(yt.balanceOf(CAROL), 100 ether, "recipient yt");
    }

    function testClaimLeveragedYT_BlocksReentrantClaim() external {
        ReentrantClaimMockERC20 hookedYT = new ReentrantClaimMockERC20("HOOKYT", "HOOKYT");
        seedLeveragedPositionForTest(address(polend), VERSE_ID, ALICE, 10 ether);
        seedLeveragedPositionForTest(address(polend), VERSE_ID, BOB, 5 ether);
        seedMarketForTest(address(polend), VERSE_ID, address(hookedYT), 15 ether);
        setLockedStateForTest(address(polend), VERSE_ID, 150 ether);
        hookedYT.mint(address(polend), 150 ether);
        hookedYT.armReentry(
            address(polend),
            abi.encodeWithSignature("claimLeveragedYT(uint256,address)", VERSE_ID, BOB),
            bytes4(keccak256("ReentrancyGuardReentrantCall()"))
        );

        vm.prank(ALICE);
        polend.claimLeveragedYT(VERSE_ID, CAROL);

        assertTrue(hookedYT.sawExpectedRevert(), "reentrant yt claim blocked");
    }

    function testClaimResidual_MarksCallerAndTransfersToRecipient() external {
        seedLeveragedPositionForTest(address(polend), VERSE_ID, ALICE, 10 ether);
        seedLeveragedPositionForTest(address(polend), VERSE_ID, BOB, 30 ether);
        seedResidualForTest(address(polend), VERSE_ID, 200 ether, 100 ether, 40 ether);
        uAsset.mint(address(polend), 200 ether);
        memecoin.mint(address(polend), 100 ether);

        vm.prank(ALICE);
        (uint256 uAssetAmount, uint256 memecoinAmount) = _claimResidual(VERSE_ID, CAROL);
        assertEq(uAssetAmount, 50 ether, "uAsset");
        assertEq(memecoinAmount, 25 ether, "memecoin");
        assertEq(uAsset.balanceOf(CAROL), 50 ether, "recipient uAsset");
        assertEq(memecoin.balanceOf(CAROL), 25 ether, "recipient memecoin");
        assertEq(uAsset.balanceOf(ALICE), 0, "caller not recipient uAsset");
        assertEq(memecoin.balanceOf(ALICE), 0, "caller not recipient memecoin");

        vm.prank(BOB);
        (uAssetAmount, memecoinAmount) = _claimResidual(VERSE_ID, ALICE);
        assertEq(uAssetAmount, 150 ether, "bob uAsset");
        assertEq(memecoinAmount, 75 ether, "bob memecoin");
        assertEq(uAsset.balanceOf(ALICE), 150 ether, "bob can still claim");

        vm.prank(ALICE);
        _expectLowLevelRevert(
            abi.encodeWithSignature("claimResidual(uint256,address)", VERSE_ID, BOB), IPOLend.InvalidClaim.selector
        );
    }

    function testClaimResidual_RevertsWhenRecipientIsZero() external {
        seedLeveragedPositionForTest(address(polend), VERSE_ID, ALICE, 10 ether);
        seedResidualForTest(address(polend), VERSE_ID, 50 ether, 25 ether, 10 ether);
        uAsset.mint(address(polend), 50 ether);
        memecoin.mint(address(polend), 25 ether);

        vm.prank(ALICE);
        _expectLowLevelRevert(
            abi.encodeWithSignature("claimResidual(uint256,address)", VERSE_ID, address(0)), IPOLend.ZeroInput.selector
        );
    }

    function testClaimResidual_UsesInterestShareInsteadOfRoundedDebtShare() external {
        uint256 verseId = 105;
        POLend localPolend = _deployPOLend(3, 1e36, address(this), address(launcher), address(splitter));
        launcher.setVerseUAsset(verseId, address(uAsset));
        localPolend.setMaxSettlementDustReserve(address(uAsset), uint128(MAX_SETTLEMENT_DUST));
        vm.prank(address(launcher));
        localPolend.registerLendMarket(verseId);
        seedLeveragedPositionForTest(address(localPolend), verseId, ALICE, 1);
        seedLeveragedPositionForTest(address(localPolend), verseId, BOB, 2);
        seedResidualForTest(address(localPolend), verseId, 300 ether, 600 ether, 3);
        uAsset.mint(address(localPolend), 300 ether);
        memecoin.mint(address(localPolend), 600 ether);

        vm.prank(ALICE);
        (bool success, bytes memory data) =
            address(localPolend).call(abi.encodeWithSignature("claimResidual(uint256,address)", verseId, CAROL));

        assertTrue(success, "claim");
        (uint256 uAssetAmount, uint256 memecoinAmount) = abi.decode(data, (uint256, uint256));
        assertEq(uAssetAmount, 100 ether, "interest-proportional uAsset");
        assertEq(memecoinAmount, 200 ether, "interest-proportional memecoin");
        assertEq(uAsset.balanceOf(CAROL), 100 ether, "recipient uAsset");
        assertEq(memecoin.balanceOf(CAROL), 200 ether, "recipient memecoin");
    }

    function testClaimResidual_BlocksReentrantClaim() external {
        ReentrantClaimMockERC20 hookedUAsset = new ReentrantClaimMockERC20("HOOK", "HOOK");
        seedMarketUAssetForTest(address(polend), VERSE_ID, address(hookedUAsset));
        seedLeveragedPositionForTest(address(polend), VERSE_ID, ALICE, 10 ether);
        seedLeveragedPositionForTest(address(polend), VERSE_ID, BOB, 5 ether);
        seedResidualForTest(address(polend), VERSE_ID, 150 ether, 0, 15 ether);
        hookedUAsset.mint(address(polend), 150 ether);
        hookedUAsset.armReentry(
            address(polend),
            abi.encodeWithSignature("claimResidual(uint256,address)", VERSE_ID, BOB),
            bytes4(keccak256("ReentrancyGuardReentrantCall()"))
        );

        vm.prank(ALICE);
        polend.claimResidual(VERSE_ID, CAROL);

        assertTrue(hookedUAsset.sawExpectedRevert(), "reentrant residual claim blocked");
    }

    function testOwnerSetters_ValidateOwnerBoundsAndEmitEvents() external {
        vm.prank(ALICE);
        _expectLowLevelRevert(abi.encodeWithSignature("setProtocolTreasury(address)", CAROL), bytes4(0));

        _expectLowLevelRevert(
            abi.encodeWithSignature("setProtocolTreasury(address)", address(0)), IPOLend.ZeroInput.selector
        );

        vm.expectEmit(true, true, false, true);
        emit ProtocolTreasuryChanged(address(this), CAROL);
        (bool treasurySuccess,) = address(polend).call(abi.encodeWithSignature("setProtocolTreasury(address)", CAROL));
        assertTrue(treasurySuccess, "set treasury");
        assertEq(polend.treasury(), CAROL, "treasury");

        vm.prank(ALICE);
        _expectLowLevelRevert(abi.encodeWithSignature("setDefaultInterestRate(uint256)", 2e17), bytes4(0));

        _expectLowLevelRevert(abi.encodeWithSignature("setDefaultInterestRate(uint256)", 0), IPOLend.ZeroInput.selector);
        _expectLowLevelRevert(
            abi.encodeWithSignature("setDefaultInterestRate(uint256)", 1e18 + 1), IPOLend.InvalidConfig.selector
        );

        vm.expectEmit(false, false, false, true);
        emit DefaultInterestRateChanged(1e17, 2e17);
        (bool rateSuccess,) = address(polend).call(abi.encodeWithSignature("setDefaultInterestRate(uint256)", 2e17));
        assertTrue(rateSuccess, "set rate");
        assertEq(polend.defaultInterestRate(), 2e17, "default rate");

        assertEq(polend.getLendMarket(VERSE_ID).interestRate, 1e17, "existing market rate");

        uint256 newVerseId = 3;
        launcher.setVerseUAsset(newVerseId, address(uAsset));
        launcher.setGenesisFunds(newVerseId, 1_000 ether);
        launcher.setFundMetaData(address(uAsset), 1_000 ether, 1);
        polend.setMaxSettlementDustReserve(address(uAsset), uint128(MAX_SETTLEMENT_DUST));
        vm.prank(address(launcher));
        polend.registerLendMarket(newVerseId);

        assertEq(polend.getLendMarket(newVerseId).interestRate, 2e17, "new market rate");
    }

    function testSetDefaultInterestRate_RevertsWhenCurrentDebtFactorDoesNotSupportRate() external {
        vm.expectRevert(IPOLend.InvalidConfig.selector);
        polend.setDefaultInterestRate(1);

        assertEq(polend.defaultInterestRate(), 1e17, "rate unchanged");
    }

    function testSetLeveragedDebtFactor_OnlyOwnerAndValidatesBounds() external {
        bytes4 ownableUnauthorizedAccount = bytes4(keccak256("OwnableUnauthorizedAccount(address)"));

        vm.prank(ALICE);
        (bool ownerSuccess, bytes memory ownerRevertData) =
            address(polend).call(abi.encodeWithSignature("setLeveragedDebtFactor(uint256)", 20e18));
        assertFalse(ownerSuccess, "owner-only");
        assertGe(ownerRevertData.length, 4, "owner revert selector length");
        assertEq(bytes4(ownerRevertData), ownableUnauthorizedAccount, "owner revert selector");

        _expectLowLevelRevert(abi.encodeWithSignature("setLeveragedDebtFactor(uint256)", 0), IPOLend.ZeroInput.selector);
        _expectLowLevelRevert(
            abi.encodeWithSignature("setLeveragedDebtFactor(uint256)", 1e18), IPOLend.InvalidConfig.selector
        );
        _expectLowLevelRevert(
            abi.encodeWithSignature("setLeveragedDebtFactor(uint256)", MAX_LEVERAGED_DEBT_FACTOR + 1),
            IPOLend.InvalidConfig.selector
        );

        vm.expectEmit(false, false, false, true);
        emit LeveragedDebtFactorChanged(10e18, 20e18);
        (bool success,) = address(polend).call(abi.encodeWithSignature("setLeveragedDebtFactor(uint256)", 20e18));
        assertTrue(success, "set factor");
        assertEq(polend.leveragedDebtFactor(), 20e18, "factor");
    }

    function testSetLeveragedDebtFactor_UpdatesGenesisCapacityWithoutChangingRegisteredRates() external {
        polend.setMaxSettlementDustReserve(address(uAsset), uint128(MAX_SETTLEMENT_DUST));

        IPOLend.LendMarket memory existingMarket = polend.getLendMarket(VERSE_ID);
        IPOLend.LeveragedDebtInfo memory beforeInfo = polend.getLeveragedDebtInfo(VERSE_ID);
        assertEq(existingMarket.interestRate, 1e17, "existing rate before");
        assertEq(beforeInfo.debtCap, 10_000 ether, "debt cap before");

        (bool success,) = address(polend).call(abi.encodeWithSignature("setLeveragedDebtFactor(uint256)", 20e18));
        assertTrue(success, "set factor");

        existingMarket = polend.getLendMarket(VERSE_ID);
        IPOLend.LeveragedDebtInfo memory afterInfo = polend.getLeveragedDebtInfo(VERSE_ID);
        assertEq(existingMarket.interestRate, 1e17, "existing rate after");
        assertEq(afterInfo.debtCap, 20_000 ether, "debt cap after");

        uint256 newVerseId = 3;
        launcher.setVerseUAsset(newVerseId, address(uAsset));
        launcher.setGenesisFunds(newVerseId, 1_000 ether);
        launcher.setFundMetaData(address(uAsset), 1_000 ether, 1);
        vm.prank(address(launcher));
        polend.registerLendMarket(newVerseId);

        IPOLend.LendMarket memory newMarket = polend.getLendMarket(newVerseId);
        IPOLend.LeveragedDebtInfo memory newInfo = polend.getLeveragedDebtInfo(newVerseId);
        assertEq(newMarket.interestRate, 1e17, "new market rate");
        assertEq(newInfo.debtCap, 20_000 ether, "new debt cap");
    }

    function testGetLeveragedDebtInfo_DebtCapTracksLauncherCurrentCapBase() external {
        uint256 verseId = 190;
        launcher.setVerseUAsset(verseId, address(uAsset));
        launcher.setGenesisFunds(verseId, 100 ether);
        launcher.setFundMetaData(address(uAsset), 1_000 ether, 1);
        polend.setMaxSettlementDustReserve(address(uAsset), uint128(MAX_SETTLEMENT_DUST));
        vm.prank(address(launcher));
        polend.registerLendMarket(verseId);

        assertEq(polend.getLeveragedDebtInfo(verseId).debtCap, 10_000 ether, "initial min fund cap");

        launcher.setGenesisFunds(verseId, 2_000 ether);
        assertEq(polend.getLeveragedDebtInfo(verseId).debtCap, 20_000 ether, "normal funds cap");

        launcher.setFundMetaData(address(uAsset), 3_000 ether, 1);
        assertEq(polend.getLeveragedDebtInfo(verseId).debtCap, 30_000 ether, "updated min fund cap");
    }

    /// @notice Verifies that lowering leveragedDebtFactor blocks new leveragedGenesis that was
    /// within the old debt cap but exceeds the new one, while existing interest is unaffected.
    function testSetLeveragedDebtFactor_ReducingFactorBlocksNewLeverageForGenesisMarket() external {
        // interestRate = 1e18 (1:1), debtFactor = 2e18
        // minDebtFactor = 1e36 / 1e18 = 1e18,  debtFactor=2e18 >= 1e18 ✔
        // normalFunds = 1_000 ether, minTotalFund = 1_000 ether
        // debtCap = 2e18 * 1_000 ether / 1e18 = 2_000 ether
        MockSplitterForPOLend localSplitter = new MockSplitterForPOLend();
        localSplitter.setTokens(address(pt), address(yt));
        localSplitter.setSplitInfo(address(pol), address(memecoin), address(uAsset));
        POLend localPolend = _deployPOLend(1e18, 2e18, address(this), address(launcher), address(localSplitter));

        uint256 verseId = 200;
        launcher.setVerseUAsset(verseId, address(uAsset));
        launcher.setGenesisFunds(verseId, 1_000 ether);
        launcher.setFundMetaData(address(uAsset), 1_000 ether, 1);
        localPolend.setMaxSettlementDustReserve(address(uAsset), uint128(MAX_SETTLEMENT_DUST));
        vm.prank(address(launcher));
        localPolend.registerLendMarket(verseId);

        assertEq(localPolend.getLeveragedDebtInfo(verseId).debtCap, 2_000 ether, "initial cap");

        // Deposit 1_500 ether interest → debt = 1_500 ether, below initial cap of 2_000
        uAsset.mint(ALICE, 1_500 ether);
        vm.prank(ALICE);
        uAsset.approve(address(localPolend), 1_500 ether);
        vm.prank(ALICE);
        localPolend.leveragedGenesis(verseId, 1_500 ether);

        // Lower debtFactor from 2e18 to 1e18 → new debtCap = 1_000 ether
        // minDebtFactor = 1e36 / 1e18 = 1e18,  1e18 >= 1e18 ✔
        localPolend.setLeveragedDebtFactor(1e18);
        assertEq(localPolend.getLeveragedDebtInfo(verseId).debtCap, 1_000 ether, "lowered cap");

        // New leveragedGenesis of 1 ether interest → previewDebt = 1_501 > 1_000 → DebtCapExceeded
        uAsset.mint(ALICE, 1 ether);
        vm.prank(ALICE);
        vm.expectRevert(IPOLend.DebtCapExceeded.selector);
        localPolend.leveragedGenesis(verseId, 1 ether);

        // New market registered after lowering uses the new factor
        uint256 newVerseId = 201;
        launcher.setVerseUAsset(newVerseId, address(uAsset));
        launcher.setGenesisFunds(newVerseId, 1_000 ether);
        localPolend.setMaxSettlementDustReserve(address(uAsset), uint128(MAX_SETTLEMENT_DUST));
        vm.prank(address(launcher));
        localPolend.registerLendMarket(newVerseId);
        assertEq(localPolend.getLeveragedDebtInfo(newVerseId).debtCap, 1_000 ether, "new market uses lowered factor");
    }

    function testSetMaxSettlementDustReserve_OnlyOwnerAndEmits() external {
        BurnableMockERC20 extraUAsset = new BurnableMockERC20("EXTRA", "EXTRA");

        vm.expectEmit(true, false, false, true);
        emit SettlementDustReserveConfigured(address(extraUAsset), 0, uint128(MAX_SETTLEMENT_DUST));
        polend.setMaxSettlementDustReserve(address(extraUAsset), uint128(MAX_SETTLEMENT_DUST));

        (, uint128 maxReserve) = polend.settlementDustStates(address(extraUAsset));
        assertEq(maxReserve, uint128(MAX_SETTLEMENT_DUST), "max reserve");

        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("OwnableUnauthorizedAccount(address)")), ALICE));
        polend.setMaxSettlementDustReserve(address(extraUAsset), 1);
    }

    function testSetMaxSettlementDustReserve_RevertsForZeroUAsset() external {
        vm.expectRevert(IPOLend.ZeroInput.selector);
        polend.setMaxSettlementDustReserve(address(0), uint128(MAX_SETTLEMENT_DUST));
    }

    function testSetMaxSettlementDustReserve_RevertsForZeroDust() external {
        vm.expectRevert(IPOLend.ZeroInput.selector);
        polend.setMaxSettlementDustReserve(address(uAsset), 0);
    }

    function testPauseUnpause_CallableThroughIPOLendInterface() external {
        IPOLend polendInterface = IPOLend(address(polend));

        polendInterface.pause();
        assertTrue(polend.paused(), "paused");

        polendInterface.unpause();
        assertFalse(polend.paused(), "unpaused");
    }

    /// @notice Test leveragedGenesis reverts when paused.
    function testLeveragedGenesis_RevertsWhenPaused() external {
        polend.setMaxSettlementDustReserve(address(uAsset), uint128(MAX_SETTLEMENT_DUST));
        uAsset.mint(ALICE, 10 ether);
        vm.prank(ALICE);
        uAsset.approve(address(polend), 10 ether);

        polend.pause();

        vm.prank(ALICE);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        polend.leveragedGenesis(VERSE_ID, 10 ether);
    }

    function testDebtByUAssetTracksFinalizePreRedeemBackingAndSettlement() external {
        polend.setMaxSettlementDustReserve(address(uAsset), uint128(MAX_SETTLEMENT_DUST));
        uAsset.mint(ALICE, 10 ether);
        vm.prank(ALICE);
        uAsset.approve(address(polend), 10 ether);

        vm.prank(ALICE);
        polend.leveragedGenesis(VERSE_ID, 10 ether);

        vm.prank(address(launcher));
        polend.finalizeLeveragedGenesis(VERSE_ID);
        assertEq(_getTotalDebtByUAsset(address(uAsset)), 100 ether, "finalized debt");
        assertEq(_getTotalDebtByUAsset(address(otherUAsset)), 0, "other asset debt");

        setLockedStateForTest(address(polend), VERSE_ID, 0);
        vm.prank(address(launcher));
        polend.preRedeemPTFee(VERSE_ID, 25 ether, BOB);
        assertEq(_getTotalDebtByUAsset(address(uAsset)), 125 ether, "preRedeem debt");

        uAsset.mint(address(splitter), 25 ether);
        vm.prank(address(splitter));
        polend.burnPreRedeemedBacking(VERSE_ID, 25 ether);
        assertEq(_getTotalDebtByUAsset(address(uAsset)), 100 ether, "backing repaid");

        launcher.setSettlementResult(VERSE_ID, 0, 0, 100 ether);
        uAsset.mint(address(polend), 100 ether);
        vm.prank(address(launcher));
        polend.executeGlobalSettlement(VERSE_ID);
        assertEq(_getTotalDebtByUAsset(address(uAsset)), 0, "settlement repaid");

        _expectLowLevelRevert(
            abi.encodeWithSignature("getTotalDebtByUAsset(address)", address(0)), IPOLend.ZeroInput.selector
        );
    }

    function testGetLeveragedDebtInfo_CoversGenesisCapAndClosedStates() external {
        polend.setMaxSettlementDustReserve(address(uAsset), uint128(MAX_SETTLEMENT_DUST));
        (uint256 totalInterest, uint256 totalDebt, uint256 rate, uint256 debtCap, uint256 remaining) =
            _getLeveragedDebtInfo(VERSE_ID);
        assertEq(totalInterest, 0, "none interest");
        assertEq(totalDebt, 0, "none debt");
        assertEq(rate, 1e17, "rate");
        assertEq(debtCap, 10_000 ether, "none cap");
        assertEq(remaining, 1_000 ether, "none remaining");

        uAsset.mint(ALICE, 10 ether);
        vm.prank(ALICE);
        uAsset.approve(address(polend), 10 ether);
        vm.prank(ALICE);
        polend.leveragedGenesis(VERSE_ID, 10 ether);

        (totalInterest, totalDebt, rate, debtCap, remaining) = _getLeveragedDebtInfo(VERSE_ID);
        assertEq(totalInterest, 10 ether, "genesis interest");
        assertEq(totalDebt, 100 ether, "genesis debt");
        assertEq(rate, 1e17, "genesis rate");
        assertEq(debtCap, 10_000 ether, "genesis cap");
        assertEq(remaining, 990 ether, "genesis remaining");

        setLockedStateForTest(address(polend), VERSE_ID, 0);
        (,,, debtCap, remaining) = _getLeveragedDebtInfo(VERSE_ID);
        assertEq(debtCap, 0, "locked cap");
        assertEq(remaining, 0, "locked remaining");

        setRefundStateForTest(address(polend), VERSE_ID);
        (,,, debtCap, remaining) = _getLeveragedDebtInfo(VERSE_ID);
        assertEq(debtCap, 0, "refund cap");
        assertEq(remaining, 0, "refund remaining");

        _expectLowLevelRevert(
            abi.encodeWithSignature("getLeveragedDebtInfo(uint256)", 999), IPOLend.InvalidState.selector
        );
    }

    function testGetUserLeveragedDebt_RevertsForUnregisteredOrZeroUser() external {
        vm.expectRevert(IPOLend.InvalidState.selector);
        polend.getUserLeveragedDebt(999, ALICE);

        vm.expectRevert(IPOLend.ZeroInput.selector);
        polend.getUserLeveragedDebt(VERSE_ID, address(0));
    }

    function testFundSettlementDustReserve_ManualFundingCreditsReserveAndEmitsZeroExcess() external {
        polend.pause();

        uAsset.mint(ALICE, MAX_SETTLEMENT_DUST);
        vm.prank(ALICE);
        uAsset.approve(address(polend), MAX_SETTLEMENT_DUST);

        vm.expectEmit(true, true, false, true);
        emit SettlementDustReserveFunded(address(uAsset), ALICE, MAX_SETTLEMENT_DUST, MAX_SETTLEMENT_DUST, 0);
        vm.prank(ALICE);
        polend.fundSettlementDustReserve(address(uAsset), MAX_SETTLEMENT_DUST);

        (uint128 reserve,) = polend.settlementDustStates(address(uAsset));
        assertEq(reserve, uint128(MAX_SETTLEMENT_DUST), "reserve");
        assertEq(uAsset.balanceOf(address(polend)), MAX_SETTLEMENT_DUST, "balance");
        assertEq(polend.leveragedInterestPaid(VERSE_ID, ALICE), 0, "no interest claim");
        (uint256 residualUAsset, uint256 residualMemecoin) = polend.residualStates(VERSE_ID);
        assertEq(residualUAsset, 0, "no residual uasset claim");
        assertEq(residualMemecoin, 0, "no residual memecoin claim");
    }

    function testFundSettlementDustReserve_ManualFundingOverCapacityRevertsBeforeTransfer() external {
        uint256 amount = MAX_SETTLEMENT_DUST + 1;
        uAsset.mint(ALICE, amount);
        vm.prank(ALICE);
        uAsset.approve(address(polend), amount);

        vm.expectRevert(
            abi.encodeWithSelector(IPOLend.SettlementDustReserveExceeded.selector, amount, MAX_SETTLEMENT_DUST)
        );
        vm.prank(ALICE);
        polend.fundSettlementDustReserve(address(uAsset), amount);

        assertEq(uAsset.balanceOf(ALICE), amount, "no transfer");
        assertEq(uAsset.balanceOf(address(polend)), 0, "polend unchanged");
    }

    function testFundSettlementDustReserve_LauncherExcessGoesToTreasury() external {
        uint256 amount = MAX_SETTLEMENT_DUST + 7;
        uAsset.mint(address(launcher), amount);
        vm.prank(address(launcher));
        uAsset.approve(address(polend), amount);
        uint256 treasuryBefore = uAsset.balanceOf(address(this));

        vm.expectEmit(true, true, false, true);
        emit SettlementDustReserveFunded(address(uAsset), address(launcher), amount, MAX_SETTLEMENT_DUST, 7);
        vm.prank(address(launcher));
        polend.fundSettlementDustReserve(address(uAsset), amount);

        (uint128 reserve,) = polend.settlementDustStates(address(uAsset));
        assertEq(reserve, uint128(MAX_SETTLEMENT_DUST), "reserve");
        assertEq(uAsset.balanceOf(address(this)), treasuryBefore + 7, "treasury excess");
    }

    function testFundSettlementDustReserve_RevertsForUnconfiguredOrZeroAmount() external {
        vm.expectRevert(IPOLend.ZeroInput.selector);
        polend.fundSettlementDustReserve(address(uAsset), 0);

        BurnableMockERC20 extraUAsset = new BurnableMockERC20("EXTRA", "EXTRA");
        extraUAsset.mint(ALICE, 1);
        vm.prank(ALICE);
        extraUAsset.approve(address(polend), 1);
        vm.prank(ALICE);
        vm.expectRevert(IPOLend.InvalidConfig.selector);
        polend.fundSettlementDustReserve(address(extraUAsset), 1);
    }

    function testExecuteGlobalSettlement_RepaysDebtAndLeavesOnlyRecoveredResidual() external {
        seedMarketForTest(address(polend), VERSE_ID, address(yt), 10 ether);
        setLockedStateForTest(address(polend), VERSE_ID, 0);
        seedGlobalDebtForTest(address(polend), address(uAsset), 100 ether);
        launcher.setSettlementResult(VERSE_ID, 0, 0, 150 ether);

        uAsset.mint(address(polend), 150 ether);

        vm.expectEmit(true, true, false, true);
        emit GlobalSettlementExecuted(VERSE_ID, address(uAsset), 100 ether, 150 ether, 0, 0, 50 ether, 0);
        vm.prank(address(launcher));
        polend.executeGlobalSettlement(VERSE_ID);

        IPOLend.LendMarket memory market = polend.getLendMarket(VERSE_ID);
        (uint256 residualUAsset, uint256 residualMemecoin) = polend.residualStates(VERSE_ID);
        assertEq(uAsset.repaidAmount(), 100 ether, "debt repaid");
        assertEq(uAsset.lastRepayAccount(), address(polend), "repay account");
        assertEq(uAsset.burnedAmount(), 0, "burn not used");
        assertEq(polend.globalDebtByUAsset(address(uAsset)), 0, "global debt cleared");
        assertEq(residualUAsset, 50 ether, "residual uasset");
        assertEq(residualMemecoin, 0, "residual memecoin");
        assertEq(uAsset.balanceOf(address(polend)), 50 ether, "only recovered residual kept");
        assertEq(uint256(market.state), uint256(IPOLend.MarketState.Settled), "state settled");
    }

    function testExecuteGlobalSettlement_RevertsWithoutDebtStateChangeWhenRepayFails() external {
        seedMarketForTest(address(polend), VERSE_ID, address(yt), 10 ether);
        setLockedStateForTest(address(polend), VERSE_ID, 0);
        seedGlobalDebtForTest(address(polend), address(uAsset), 100 ether);
        launcher.setSettlementResult(VERSE_ID, 0, 0, 150 ether);
        uAsset.mint(address(polend), 150 ether);
        uAsset.setRevertRepay(true);

        vm.prank(address(launcher));
        vm.expectRevert(bytes("repay failed"));
        polend.executeGlobalSettlement(VERSE_ID);

        assertEq(polend.globalDebtByUAsset(address(uAsset)), 100 ether, "global debt unchanged");
        assertEq(uAsset.repaidAmount(), 0, "repay reverted");
        assertEq(uAsset.burnedAmount(), 0, "burn not used");
        assertEq(uint256(polend.getLendMarket(VERSE_ID).state), uint256(IPOLend.MarketState.Locked), "state unchanged");
    }

    function testExecuteGlobalSettlement_ConsumesReserveForBoundedDustDeficit() external {
        setLockedStateForTest(address(polend), VERSE_ID, 0);
        seedMarketForTest(address(polend), VERSE_ID, address(yt), 10 ether);
        seedGlobalDebtForTest(address(polend), address(uAsset), 100 ether);
        launcher.setSettlementResult(VERSE_ID, 0, 0, 100 ether - 1);
        uAsset.mint(address(polend), 100 ether - 1 + MAX_SETTLEMENT_DUST);
        seedSettlementDustStateForTest(
            address(polend), address(uAsset), uint128(MAX_SETTLEMENT_DUST), uint128(MAX_SETTLEMENT_DUST)
        );
        uint256 treasuryBefore = uAsset.balanceOf(address(this));

        uint256 consumedSettlementDustReserve = 1;
        uint256 settlementDustReserveBeforeSettlement = MAX_SETTLEMENT_DUST;
        assertLe(consumedSettlementDustReserve, MAX_SETTLEMENT_DUST, "dust cap");
        assertLe(consumedSettlementDustReserve, settlementDustReserveBeforeSettlement, "reserve cap");

        vm.expectEmit(true, true, false, true);
        emit SettlementDustReserveConsumed(VERSE_ID, address(uAsset), 1, MAX_SETTLEMENT_DUST - 1);
        vm.expectEmit(true, true, false, true);
        emit GlobalSettlementExecuted(
            VERSE_ID, address(uAsset), 100 ether, 100 ether - 1, 1, MAX_SETTLEMENT_DUST - 1, 0, 0
        );
        vm.prank(address(launcher));
        polend.executeGlobalSettlement(VERSE_ID);

        (uint256 residualUAsset, uint256 residualMemecoin) = polend.residualStates(VERSE_ID);
        (uint128 reserve,) = polend.settlementDustStates(address(uAsset));
        assertEq(polend.globalDebtByUAsset(address(uAsset)), 0, "global debt");
        assertEq(reserve, uint128(MAX_SETTLEMENT_DUST - 1), "remaining reserve");
        assertEq(uAsset.repaidAmount(), 100 ether, "full debt repaid");
        assertEq(residualUAsset, 0, "no uasset residual");
        assertEq(residualMemecoin, 0, "memecoin residual");
        assertEq(uAsset.balanceOf(address(this)), treasuryBefore, "unused reserve not swept");
    }

    function testExecuteGlobalSettlement_ConsumesPubliclyFundedDustReserve() external {
        setLockedStateForTest(address(polend), VERSE_ID, 0);
        seedMarketForTest(address(polend), VERSE_ID, address(yt), 10 ether);
        seedGlobalDebtForTest(address(polend), address(uAsset), 100 ether);
        launcher.setSettlementResult(VERSE_ID, 0, 0, 100 ether - 2);
        uAsset.mint(address(polend), 100 ether - 2);

        uAsset.mint(ALICE, 2);
        vm.prank(ALICE);
        uAsset.approve(address(polend), 2);
        vm.prank(ALICE);
        polend.fundSettlementDustReserve(address(uAsset), 2);

        vm.expectEmit(true, true, false, true);
        emit GlobalSettlementExecuted(VERSE_ID, address(uAsset), 100 ether, 100 ether - 2, 2, 0, 0, 0);
        vm.prank(address(launcher));
        polend.executeGlobalSettlement(VERSE_ID);

        (uint256 residualUAsset, uint256 residualMemecoin) = polend.residualStates(VERSE_ID);
        (uint128 reserve,) = polend.settlementDustStates(address(uAsset));
        assertEq(polend.globalDebtByUAsset(address(uAsset)), 0, "global debt");
        assertEq(reserve, 0, "reserve consumed");
        assertEq(uAsset.repaidAmount(), 100 ether, "full debt repaid");
        assertEq(residualUAsset, 0, "no uasset residual");
        assertEq(residualMemecoin, 0, "memecoin residual");
        assertEq(uAsset.balanceOf(address(polend)), 0, "no polend uasset residual");
    }

    function testExecuteGlobalSettlement_RevertsWhenDeficitExceedsGlobalReserve() external {
        setLockedStateForTest(address(polend), VERSE_ID, 0);
        seedMarketForTest(address(polend), VERSE_ID, address(yt), 10 ether);
        seedGlobalDebtForTest(address(polend), address(uAsset), 100 ether);
        launcher.setSettlementResult(VERSE_ID, 0, 0, 100 ether - MAX_SETTLEMENT_DUST - 1);
        uAsset.mint(address(polend), 100 ether);
        seedSettlementDustStateForTest(
            address(polend), address(uAsset), uint128(MAX_SETTLEMENT_DUST), uint128(MAX_SETTLEMENT_DUST)
        );

        vm.prank(address(launcher));
        vm.expectRevert(
            abi.encodeWithSelector(
                IPOLend.SettlementDustInsufficient.selector, MAX_SETTLEMENT_DUST + 1, MAX_SETTLEMENT_DUST
            )
        );
        polend.executeGlobalSettlement(VERSE_ID);
    }

    function testExecuteGlobalSettlement_RevertsWhenReserveIsUnderfunded() external {
        setLockedStateForTest(address(polend), VERSE_ID, 0);
        seedMarketForTest(address(polend), VERSE_ID, address(yt), 10 ether);
        seedGlobalDebtForTest(address(polend), address(uAsset), 100 ether);
        launcher.setSettlementResult(VERSE_ID, 0, 0, 100 ether - 2);
        uAsset.mint(address(polend), 100 ether);
        seedSettlementDustStateForTest(address(polend), address(uAsset), 1, uint128(MAX_SETTLEMENT_DUST));

        vm.prank(address(launcher));
        vm.expectRevert(abi.encodeWithSelector(IPOLend.SettlementDustInsufficient.selector, 2, 1));
        polend.executeGlobalSettlement(VERSE_ID);
    }

    function testExecuteGlobalSettlement_RevertsWhenReserveUnfunded() external {
        setLockedStateForTest(address(polend), VERSE_ID, 0);
        seedMarketForTest(address(polend), VERSE_ID, address(yt), 10 ether);
        seedGlobalDebtForTest(address(polend), address(uAsset), 100 ether);
        launcher.setSettlementResult(VERSE_ID, 0, 0, 100 ether - 1);
        uAsset.mint(address(polend), 100 ether);
        seedSettlementDustStateForTest(address(polend), address(uAsset), 0, uint128(MAX_SETTLEMENT_DUST));

        vm.prank(address(launcher));
        vm.expectRevert(abi.encodeWithSelector(IPOLend.SettlementDustInsufficient.selector, 1, 0));
        polend.executeGlobalSettlement(VERSE_ID);
    }

    function testPreRedeemPTFee_MintsToTargetAndIncreasesGlobalDebt() external {
        setLockedStateForTest(address(polend), VERSE_ID, 0);
        splitter.setPreRedeemBacking(10 ether);

        vm.prank(address(launcher));
        (bool success,) = address(polend)
            .call(abi.encodeWithSignature("preRedeemPTFee(uint256,uint256,address)", VERSE_ID, 25 ether, BOB));

        assertTrue(success, "preRedeemPTFee");
        assertEq(splitter.preRedeemCallCount(), 1, "splitter preRedeem called");
        assertEq(splitter.lastPreRedeemVerseId(), VERSE_ID, "verse id");
        assertEq(splitter.lastPreRedeemPTAmount(), 25 ether, "pt amount");
        assertEq(uAsset.balanceOf(BOB), 10 ether, "minted uAsset");
        assertEq(polend.globalDebtByUAsset(address(uAsset)), 10 ether, "global debt increased");
    }

    function testPreRedeemPTFee_EmitsPreRedeemPTFee() external {
        setLockedStateForTest(address(polend), VERSE_ID, 0);
        splitter.setPreRedeemBacking(10 ether);

        vm.expectEmit(true, true, false, true);
        emit PreRedeemPTFee(VERSE_ID, address(uAsset), 25 ether, 10 ether, BOB);
        vm.prank(address(launcher));
        polend.preRedeemPTFee(VERSE_ID, 25 ether, BOB);
    }

    function testPreRedeemPTFee_MintHookObservesDebtAlreadyIncreased() external {
        HookedBurnableMockERC20 hookedUAsset = new HookedBurnableMockERC20("HOOK", "HOOK");
        setLockedStateForTest(address(polend), VERSE_ID, 0);
        seedMarketUAssetForTest(address(polend), VERSE_ID, address(hookedUAsset));
        splitter.setPreRedeemBacking(10 ether);
        hookedUAsset.expectMintDebt(address(polend), 10 ether);

        vm.prank(address(launcher));
        polend.preRedeemPTFee(VERSE_ID, 25 ether, BOB);

        assertEq(hookedUAsset.balanceOf(BOB), 10 ether, "minted uAsset");
        assertEq(polend.getTotalDebtByUAsset(address(hookedUAsset)), 10 ether, "global debt");
    }

    function testBurnPreRedeemedBacking_RepaysSplitterBackingAndReducesGlobalDebt() external {
        seedGlobalDebtForTest(address(polend), address(uAsset), 40 ether);
        uAsset.mint(address(splitter), 40 ether);

        vm.prank(address(splitter));
        (bool success,) =
            address(polend).call(abi.encodeWithSignature("burnPreRedeemedBacking(uint256,uint256)", VERSE_ID, 40 ether));

        assertTrue(success, "burnPreRedeemedBacking");
        assertEq(uAsset.repaidAmount(), 40 ether, "backing repaid");
        assertEq(uAsset.lastRepayAccount(), address(splitter), "repay account");
        assertEq(polend.globalDebtByUAsset(address(uAsset)), 0, "global debt reduced");
    }

    function testBurnPreRedeemedBacking_RepayHookObservesDebtAlreadyDecreased() external {
        HookedBurnableMockERC20 hookedUAsset = new HookedBurnableMockERC20("HOOK", "HOOK");
        seedMarketUAssetForTest(address(polend), VERSE_ID, address(hookedUAsset));
        seedGlobalDebtForTest(address(polend), address(hookedUAsset), 40 ether);
        hookedUAsset.mint(address(splitter), 40 ether);
        hookedUAsset.expectRepayDebt(address(polend), 0);

        vm.prank(address(splitter));
        polend.burnPreRedeemedBacking(VERSE_ID, 40 ether);

        assertEq(hookedUAsset.repaidAmount(), 40 ether, "backing repaid");
        assertEq(polend.getTotalDebtByUAsset(address(hookedUAsset)), 0, "global debt");
    }

    function testExecuteGlobalSettlement_DoesNotCountInterestTowardDebtCoverage() external {
        seedMarketForTest(address(polend), VERSE_ID, address(yt), 10 ether);
        setLockedStateForTest(address(polend), VERSE_ID, 0);
        launcher.setSettlementResult(VERSE_ID, 0, 0, 90 ether);

        uAsset.mint(address(polend), 100 ether);

        vm.prank(address(launcher));
        vm.expectRevert(abi.encodeWithSelector(IPOLend.SettlementDustInsufficient.selector, 10 ether, 0));
        polend.executeGlobalSettlement(VERSE_ID);
    }

    function testLeveragedGenesis_DifferentVersesUseTheirOwnUAsset() external {
        polend.setMaxSettlementDustReserve(address(otherUAsset), uint128(MAX_SETTLEMENT_DUST));
        otherUAsset.mint(ALICE, 10 ether);
        vm.prank(ALICE);
        otherUAsset.approve(address(polend), 10 ether);

        vm.prank(ALICE);
        polend.leveragedGenesis(OTHER_VERSE_ID, 10 ether);

        assertEq(otherUAsset.balanceOf(address(polend)), 10 ether, "other verse interest escrowed in its own asset");
        assertEq(uAsset.balanceOf(address(polend)), 0, "default uAsset untouched");
    }

    function testMarkRefundable_OnlyMovesGenesisMarketToRefund() external {
        polend.setMaxSettlementDustReserve(address(uAsset), uint128(MAX_SETTLEMENT_DUST));
        uAsset.mint(ALICE, 10 ether);
        vm.prank(ALICE);
        uAsset.approve(address(polend), 10 ether);

        vm.prank(ALICE);
        polend.leveragedGenesis(VERSE_ID, 10 ether);

        vm.prank(address(launcher));
        polend.markRefundable(VERSE_ID);

        IPOLend.LendMarket memory market = polend.getLendMarket(VERSE_ID);
        assertEq(uint256(market.state), uint256(IPOLend.MarketState.Refund), "refund state");
        assertEq(uAsset.balanceOf(address(polend)), 10 ether, "interest remains refundable");
    }

    function testRecordLeveragedYT_RecordsOnceAfterFinalize() external {
        polend.setMaxSettlementDustReserve(address(uAsset), uint128(MAX_SETTLEMENT_DUST));
        uAsset.mint(ALICE, 10 ether);
        vm.prank(ALICE);
        uAsset.approve(address(polend), 10 ether);

        vm.prank(ALICE);
        polend.leveragedGenesis(VERSE_ID, 10 ether);
        vm.prank(address(launcher));
        polend.finalizeLeveragedGenesis(VERSE_ID);

        vm.prank(address(launcher));
        polend.recordLeveragedYT(VERSE_ID, address(yt), 100 ether);

        IPOLend.LendMarket memory market = polend.getLendMarket(VERSE_ID);
        assertEq(market.yt, address(yt), "yt");
        assertEq(market.totalLeveragedYT, 100 ether, "total yt");

        vm.prank(address(launcher));
        vm.expectRevert(IPOLend.InvalidState.selector);
        polend.recordLeveragedYT(VERSE_ID, address(yt), 100 ether);
    }

    function testClaimLeveragedYT_SucceedsInSettledStateAfterGlobalSettlement() external {
        polend.setMaxSettlementDustReserve(address(uAsset), uint128(MAX_SETTLEMENT_DUST));
        uAsset.mint(ALICE, 10 ether);
        vm.prank(ALICE);
        uAsset.approve(address(polend), 10 ether);
        vm.prank(ALICE);
        polend.leveragedGenesis(VERSE_ID, 10 ether);

        vm.prank(address(launcher));
        polend.finalizeLeveragedGenesis(VERSE_ID);
        vm.prank(address(launcher));
        polend.recordLeveragedYT(VERSE_ID, address(yt), 100 ether);

        launcher.setSettlementResult(VERSE_ID, 0, 0, 150 ether);
        uAsset.mint(address(polend), 150 ether);
        vm.prank(address(launcher));
        polend.executeGlobalSettlement(VERSE_ID);

        IPOLend.LendMarket memory market = polend.getLendMarket(VERSE_ID);
        assertEq(uint256(market.state), uint256(IPOLend.MarketState.Settled), "settled");

        yt.mint(address(polend), 100 ether);
        vm.prank(ALICE);
        assertEq(_claimLeveragedYT(VERSE_ID, CAROL), 100 ether, "settled yt claim");
        assertEq(yt.balanceOf(CAROL), 100 ether, "recipient");

        vm.prank(ALICE);
        _expectLowLevelRevert(
            abi.encodeWithSignature("claimLeveragedYT(uint256,address)", VERSE_ID, BOB), IPOLend.InvalidClaim.selector
        );
    }

    function testClaimResidual_SucceedsWithZeroPayoutAndMarksClaim() external {
        seedLeveragedPositionForTest(address(polend), VERSE_ID, ALICE, 1);
        seedResidualForTest(address(polend), VERSE_ID, 1, 0, 2);
        uAsset.mint(address(polend), 1);

        vm.prank(ALICE);
        (uint256 uAssetAmount, uint256 memecoinAmount) = _claimResidual(VERSE_ID, CAROL);
        assertEq(uAssetAmount, 0, "zero uAsset payout");
        assertEq(memecoinAmount, 0, "zero memecoin payout");

        vm.prank(ALICE);
        _expectLowLevelRevert(
            abi.encodeWithSignature("claimResidual(uint256,address)", VERSE_ID, BOB), IPOLend.InvalidClaim.selector
        );
    }

    function testClaimLeveragedYTAndClaimResidual_AreIndependentForSameUser() external {
        seedLeveragedPositionForTest(address(polend), VERSE_ID, ALICE, 10 ether);
        seedMarketForTest(address(polend), VERSE_ID, address(yt), 10 ether);
        setLockedStateForTest(address(polend), VERSE_ID, 100 ether);
        seedResidualForTest(address(polend), VERSE_ID, 200 ether, 100 ether, 10 ether);
        uAsset.mint(address(polend), 200 ether);
        memecoin.mint(address(polend), 100 ether);
        yt.mint(address(polend), 100 ether);

        vm.prank(ALICE);
        assertEq(_claimLeveragedYT(VERSE_ID, CAROL), 100 ether, "yt");
        assertEq(yt.balanceOf(CAROL), 100 ether, "yt recipient");

        vm.prank(ALICE);
        (uint256 uAssetAmount, uint256 memecoinAmount) = _claimResidual(VERSE_ID, CAROL);
        assertEq(uAssetAmount, 200 ether, "residual uAsset");
        assertEq(memecoinAmount, 100 ether, "residual memecoin");
        assertEq(uAsset.balanceOf(CAROL), 200 ether, "uAsset recipient");
        assertEq(memecoin.balanceOf(CAROL), 100 ether, "memecoin recipient");

        vm.prank(ALICE);
        _expectLowLevelRevert(
            abi.encodeWithSignature("claimLeveragedYT(uint256,address)", VERSE_ID, BOB), IPOLend.InvalidClaim.selector
        );
        vm.prank(ALICE);
        _expectLowLevelRevert(
            abi.encodeWithSignature("claimResidual(uint256,address)", VERSE_ID, BOB), IPOLend.InvalidClaim.selector
        );
    }

    function _claimLeveragedYT(uint256 verseId, address to) internal returns (uint256 amount) {
        (bool success, bytes memory data) =
            address(polend).call(abi.encodeWithSignature("claimLeveragedYT(uint256,address)", verseId, to));
        assertTrue(success, "claimLeveragedYT call");
        amount = abi.decode(data, (uint256));
    }

    function _claimRefund(uint256 verseId, address to) internal returns (uint256 amount) {
        (bool success, bytes memory data) =
            address(polend).call(abi.encodeWithSignature("claimRefund(uint256,address)", verseId, to));
        assertTrue(success, "claimRefund call");
        amount = abi.decode(data, (uint256));
    }

    function _claimResidual(uint256 verseId, address to)
        internal
        returns (uint256 uAssetAmount, uint256 memecoinAmount)
    {
        (bool success, bytes memory data) = address(polend)
            .call(abi.encodeWithSignature("claimResidual(uint256,address)", verseId, to));
        assertTrue(success, "claimResidual call");
        (uAssetAmount, memecoinAmount) = abi.decode(data, (uint256, uint256));
    }

    function _getTotalDebtByUAsset(address uAsset_) internal returns (uint256 amount) {
        (bool success, bytes memory data) =
            address(polend).call(abi.encodeWithSignature("getTotalDebtByUAsset(address)", uAsset_));
        assertTrue(success, "getTotalDebtByUAsset call");
        amount = abi.decode(data, (uint256));
    }

    function _getLeveragedDebtInfo(uint256 verseId)
        internal
        returns (
            uint256 totalLeveragedInterest,
            uint256 totalLeveragedDebt,
            uint256 interestRate,
            uint256 debtCap,
            uint256 remainingAdditionalInterest
        )
    {
        (bool success, bytes memory data) =
            address(polend).call(abi.encodeWithSignature("getLeveragedDebtInfo(uint256)", verseId));
        assertTrue(success, "getLeveragedDebtInfo call");
        (totalLeveragedInterest, totalLeveragedDebt, interestRate, debtCap, remainingAdditionalInterest) =
            abi.decode(data, (uint256, uint256, uint256, uint256, uint256));
    }

    function _expectLowLevelRevert(bytes memory callData, bytes4 selector) internal {
        (bool success, bytes memory revertData) = address(polend).call(callData);
        assertFalse(success, "call reverted");
        if (selector != bytes4(0)) {
            assertGe(revertData.length, 4, "revert selector length");
            assertEq(bytes4(revertData), selector, "revert selector");
        }
    }
}
