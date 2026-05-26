// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {POLSplitter} from "../../src/polend/POLSplitter.sol";
import {IPOLSplitter} from "../../src/polend/interfaces/IPOLSplitter.sol";
import {PrincipalToken} from "../../src/polend/tokens/PrincipalToken.sol";
import {YieldToken} from "../../src/polend/tokens/YieldToken.sol";
import {IMemeverseLauncher} from "../../src/verse/interfaces/IMemeverseLauncher.sol";

contract MockPOL is MockERC20 {
    address public memecoin;

    constructor(address memecoin_) MockERC20("POL", "POL", 18) {
        memecoin = memecoin_;
    }
}

contract NoOpBurnMockERC20 is MockERC20 {
    constructor(string memory name_, string memory symbol_) MockERC20(name_, symbol_, 18) {}

    function burn(uint256 amount) external pure {
        amount;
    }
}

contract DualNoOpBurnMockERC20 is MockERC20 {
    constructor(string memory name_, string memory symbol_) MockERC20(name_, symbol_, 18) {}

    function burn(uint256 amount) external pure {
        amount;
    }

    function burn(address account, uint256 amount) public pure override {
        account;
        amount;
    }
}

contract TransferOnlyBurnMockERC20 is MockERC20 {
    address internal immutable sink;

    constructor(string memory name_, string memory symbol_, address sink_) MockERC20(name_, symbol_, 18) {
        sink = sink_;
    }

    function burn(uint256 amount) external {
        balanceOf[msg.sender] -= amount;
        unchecked {
            balanceOf[sink] += amount;
        }

        emit Transfer(msg.sender, sink, amount);
    }
}

interface IPOLSplitterReentryTarget {
    function onTokenTransferReenter(uint8 mode) external;
}

contract ReentrantMockERC20 is MockERC20 {
    uint8 internal reentryMode;
    address internal reentryTarget;

    constructor(string memory name_, string memory symbol_) MockERC20(name_, symbol_, 18) {}

    function armReentry(address target, uint8 mode) external {
        reentryTarget = target;
        reentryMode = mode;
    }

    function transfer(address to, uint256 amount) public override returns (bool success) {
        success = super.transfer(to, amount);
        _reenter();
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool success) {
        success = super.transferFrom(from, to, amount);
        _reenter();
    }

    function _reenter() internal {
        uint8 mode = reentryMode;
        if (mode == 0) return;

        reentryMode = 0;
        IPOLSplitterReentryTarget(reentryTarget).onTokenTransferReenter(mode);
    }
}

contract POLSplitterReentryProbe is IPOLSplitterReentryTarget {
    uint8 internal constant MODE_SPLIT = 1;
    uint8 internal constant MODE_MERGE = 2;
    uint8 internal constant MODE_REDEEM_PT = 3;

    POLSplitterHarness internal immutable splitter;
    ReentrantMockERC20 internal immutable pol;
    uint256 internal immutable verseId;

    constructor(POLSplitterHarness splitter_, ReentrantMockERC20 pol_, uint256 verseId_) {
        splitter = splitter_;
        pol = pol_;
        verseId = verseId_;
    }

    function attackSplit(uint256 amount) external {
        pol.approve(address(splitter), type(uint256).max);
        pol.armReentry(address(this), MODE_SPLIT);
        splitter.split(verseId, amount);
    }

    function seedSplit(uint256 amount) external {
        pol.approve(address(splitter), type(uint256).max);
        splitter.split(verseId, amount);
    }

    function attackMerge(uint256 amount) external {
        pol.armReentry(address(this), MODE_MERGE);
        splitter.merge(verseId, amount);
    }

    function attackRedeemPT(uint256 amount) external {
        pol.armReentry(address(this), MODE_REDEEM_PT);
        splitter.redeemPT(verseId, amount, address(this));
    }

    function onTokenTransferReenter(uint8 mode) external {
        if (mode == MODE_SPLIT) {
            splitter.split(verseId, 1 ether);
        } else if (mode == MODE_MERGE) {
            splitter.merge(verseId, 1 ether);
        } else if (mode == MODE_REDEEM_PT) {
            splitter.redeemPT(verseId, 1 ether, address(this));
        }
    }
}

contract MockLauncher {
    // Boundary note:
    // This mock only drives launcher stage and unwrap selector wiring for POLSplitter unit tests.
    // It does not prove real launcher/router asset-flow semantics.
    struct RedemptionSeed {
        uint256 uAssetAmount;
        uint256 memecoinAmount;
    }

    mapping(uint256 verseId => IMemeverseLauncher.Stage) internal stages;
    mapping(uint256 verseId => address) internal polTokens;
    mapping(uint256 verseId => RedemptionSeed) internal redemptionSeeds;
    mapping(uint256 verseId => IMemeverseLauncher.Memeverse) internal verses;
    address internal polendAddress;

    MockERC20 internal immutable uAsset;
    MockERC20 internal immutable memecoin;

    constructor(MockERC20 uAsset_, MockERC20 memecoin_) {
        uAsset = uAsset_;
        memecoin = memecoin_;
    }

    function setStage(uint256 verseId, IMemeverseLauncher.Stage stage) external {
        stages[verseId] = stage;
    }

    function registerPol(uint256 verseId, address pol) external {
        polTokens[verseId] = pol;
    }

    function setVerseUAsset(uint256 verseId, address uAsset_) external {
        verses[verseId].uAsset = uAsset_;
    }

    function seedRedemption(uint256 verseId, uint256 uAssetAmount, uint256 memecoinAmount) external {
        redemptionSeeds[verseId] = RedemptionSeed({uAssetAmount: uAssetAmount, memecoinAmount: memecoinAmount});
    }

    function setPolend(address polend_) external {
        polendAddress = polend_;
    }

    function getStageByVerseId(uint256 verseId) external view returns (IMemeverseLauncher.Stage) {
        return stages[verseId];
    }

    function getMemeverseByVerseId(uint256 verseId) external view returns (IMemeverseLauncher.Memeverse memory verse) {
        return verses[verseId];
    }

    function getUAssetByVerseId(uint256 verseId) external view returns (address) {
        return verses[verseId].uAsset;
    }

    function polend() external view returns (address) {
        return polendAddress;
    }

    function redeemMemecoinLiquidity(uint256 verseId, uint256 amountInPOL, bool) external returns (uint256 amountInLP) {
        require(MockPOL(polTokens[verseId]).transferFrom(msg.sender, address(this), amountInPOL), "transfer failed");

        RedemptionSeed memory seed = redemptionSeeds[verseId];
        if (seed.uAssetAmount != 0) uAsset.mint(msg.sender, seed.uAssetAmount);
        if (seed.memecoinAmount != 0) memecoin.mint(msg.sender, seed.memecoinAmount);
        return amountInPOL;
    }
}

contract MockPOLendForSplitter {
    uint256 public burnPreRedeemedBackingCallCount;
    uint256 public lastBurnPreRedeemedBackingVerseId;
    uint256 public lastBurnPreRedeemedBackingAmount;

    function burnPreRedeemedBacking(uint256 verseId, uint256 amount) external {
        burnPreRedeemedBackingCallCount++;
        lastBurnPreRedeemedBackingVerseId = verseId;
        lastBurnPreRedeemedBackingAmount = amount;
    }
}

contract POLSplitterHarness is POLSplitter {
    function mockSettled(uint256 verseId, uint256 settlementUAsset, uint256 settlementMemecoin) external {
        POLSplitterStorage storage $ = _getPOLSplitterStorageHarness();
        $.splitInfos[verseId].settlementUAsset = settlementUAsset;
        $.splitInfos[verseId].settlementMemecoin = settlementMemecoin;
        $.splitInfos[verseId].settled = true;
    }

    function mintPT(uint256 verseId, address to, uint256 amount) external {
        PrincipalToken(_getPOLSplitterStorageHarness().splitInfos[verseId].pt).mint(to, amount);
    }

    function mintYT(uint256 verseId, address to, uint256 amount) external {
        YieldToken(_getPOLSplitterStorageHarness().splitInfos[verseId].yt).mint(to, amount);
    }

    function _getPOLSplitterStorageHarness() internal pure returns (POLSplitterStorage storage $) {
        bytes32 slot = 0xab504a6dee30096d32ccac13a30a002829c5eeb4c38a0196ed16a6c4e9faca00;
        assembly {
            $.slot := slot
        }
    }
}

contract POLSplitterTest is Test {
    uint256 internal constant VERSE_ID = 1;
    uint256 internal constant OTHER_VERSE_ID = 2;
    bytes4 internal constant ZERO_INPUT_SELECTOR = bytes4(keccak256("ZeroInput()"));
    bytes4 internal constant INVALID_CLAIM_SELECTOR = bytes4(keccak256("InvalidClaim()"));
    bytes4 internal constant INVALID_INITIALIZATION_SELECTOR = bytes4(keccak256("InvalidInitialization()"));
    bytes4 internal constant PANIC_SELECTOR = bytes4(keccak256("Panic(uint256)"));
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);

    MockERC20 internal memecoin;
    MockERC20 internal uAsset;
    MockERC20 internal otherUAsset;
    MockPOL internal pol;
    MockPOL internal otherPol;
    MockLauncher internal launcher;
    MockPOLendForSplitter internal polend;
    POLSplitterHarness internal splitter;
    PrincipalToken internal pt;
    YieldToken internal yt;

    function setUp() external {
        memecoin = new MockERC20("MEME", "MEME", 18);
        uAsset = new MockERC20("UASSET", "UASSET", 18);
        otherUAsset = new MockERC20("OTHER", "OTHER", 18);
        pol = new MockPOL(address(memecoin));
        otherPol = new MockPOL(address(memecoin));
        launcher = new MockLauncher(uAsset, memecoin);
        polend = new MockPOLendForSplitter();
        launcher.setPolend(address(polend));
        splitter = _deploySplitterHarness(address(launcher));

        launcher.setVerseUAsset(VERSE_ID, address(uAsset));
        launcher.setVerseUAsset(OTHER_VERSE_ID, address(otherUAsset));
        vm.prank(address(launcher));
        splitter.initializeVerse(VERSE_ID, address(pol), address(memecoin), address(uAsset), "Verse", "VRS");
        vm.prank(address(launcher));
        splitter.initializeVerse(
            OTHER_VERSE_ID, address(otherPol), address(memecoin), address(otherUAsset), "Other", "OTH"
        );
        launcher.registerPol(VERSE_ID, address(pol));
        launcher.registerPol(OTHER_VERSE_ID, address(otherPol));
        (address ptAddress, address ytAddress,,,,,,,,,) = splitter.splitInfos(VERSE_ID);
        pt = PrincipalToken(ptAddress);
        yt = YieldToken(ytAddress);
    }

    function _deploySplitterHarness(address launcher_) internal returns (POLSplitterHarness deployed) {
        POLSplitterHarness implementation = new POLSplitterHarness();
        bytes memory data = abi.encodeCall(POLSplitter.initialize, (address(this), launcher_));
        return POLSplitterHarness(address(new ERC1967Proxy(address(implementation), data)));
    }

    function testDeployTokens_RevertForNonLauncherOrRepeatDeployment() external {
        POLSplitterHarness otherSplitter = _deploySplitterHarness(address(launcher));

        vm.prank(ALICE);
        vm.expectRevert(IPOLSplitter.PermissionDenied.selector);
        otherSplitter.initializeVerse(VERSE_ID, address(pol), address(memecoin), address(uAsset), "Verse", "VRS");

        vm.prank(address(launcher));
        vm.expectRevert(IPOLSplitter.AlreadyDeployed.selector);
        splitter.initializeVerse(VERSE_ID, address(pol), address(memecoin), address(uAsset), "Verse", "VRS");
    }

    function testGetPOLAndMemecoin_ReturnsStoredAddresses() external view {
        (address storedPol, address storedMemecoin) = splitter.getPOLAndMemecoin(VERSE_ID);

        assertEq(storedPol, address(pol), "pol");
        assertEq(storedMemecoin, address(memecoin), "memecoin");
    }

    function testNarrowGetters_ReturnStoredAddresses() external view {
        address storedPT = splitter.getPT(VERSE_ID);
        address storedYT = splitter.getYT(VERSE_ID);
        address storedMemecoin = splitter.getMemecoin(VERSE_ID);
        (address pairPT, address pairYT) = splitter.getPTAndYT(VERSE_ID);

        assertEq(storedPT, address(pt), "pt");
        assertEq(storedYT, address(yt), "yt");
        assertEq(storedMemecoin, address(memecoin), "memecoin");
        assertEq(pairPT, address(pt), "pair pt");
        assertEq(pairYT, address(yt), "pair yt");
    }

    function testGetPTSettlementState_ReturnsStoredValues() external {
        (address storedPT, bool settled) = splitter.getPTSettlementState(VERSE_ID);
        assertEq(storedPT, address(pt), "pt before settle");
        assertFalse(settled, "settled before settle");

        vm.prank(address(launcher));
        splitter.recordPTBackingRatio(VERSE_ID, 1 ether, 1 ether);
        pol.mint(address(this), 500 ether);
        pol.approve(address(splitter), 500 ether);
        splitter.split(VERSE_ID, 500 ether);
        launcher.seedRedemption(VERSE_ID, 900 ether, 400 ether);
        launcher.setStage(VERSE_ID, IMemeverseLauncher.Stage.Unlocked);
        vm.prank(address(launcher));
        splitter.settle(VERSE_ID);

        (storedPT, settled) = splitter.getPTSettlementState(VERSE_ID);
        assertEq(storedPT, address(pt), "pt after settle");
        assertTrue(settled, "settled after settle");
    }

    function testRecordPTBackingRatio_StoresRatioAndPreviewConvertsPT() external {
        launcher.setStage(VERSE_ID, IMemeverseLauncher.Stage.Locked);

        vm.prank(address(launcher));
        splitter.recordPTBackingRatio(VERSE_ID, 7 ether, 14 ether);

        (uint256 ptBackingNumerator, uint256 ptBackingDenominator) = splitter.ptBackingRatios(VERSE_ID);
        assertEq(ptBackingNumerator, 7 ether, "numerator");
        assertEq(ptBackingDenominator, 14 ether, "denominator");
        assertEq(splitter.previewPTToUAsset(VERSE_ID, 14 ether), 7 ether, "full base");
        assertEq(splitter.previewPTToUAsset(VERSE_ID, 1 ether), 0.5 ether, "pro rata");
    }

    function testRecordPTBackingRatio_RevertsWhenCalledTwice() external {
        launcher.setStage(VERSE_ID, IMemeverseLauncher.Stage.Locked);

        vm.startPrank(address(launcher));
        splitter.recordPTBackingRatio(VERSE_ID, 7 ether, 14 ether);
        vm.expectRevert(IPOLSplitter.InvalidClaim.selector);
        splitter.recordPTBackingRatio(VERSE_ID, 7 ether, 14 ether);
        vm.stopPrank();
    }

    function testRecordPTBackingRatio_RevertsForNonLauncher() external {
        launcher.setStage(VERSE_ID, IMemeverseLauncher.Stage.Locked);

        vm.prank(ALICE);
        vm.expectRevert(IPOLSplitter.PermissionDenied.selector);
        splitter.recordPTBackingRatio(VERSE_ID, 7 ether, 14 ether);
    }

    function testRecordPTBackingRatio_RevertsAfterSplitStarted() external {
        launcher.setStage(VERSE_ID, IMemeverseLauncher.Stage.Locked);
        vm.prank(address(launcher));
        splitter.recordPTBackingRatio(VERSE_ID, 1 ether, 1 ether);
        pol.mint(address(this), 1 ether);
        pol.approve(address(splitter), 1 ether);
        splitter.split(VERSE_ID, 1 ether);

        vm.prank(address(launcher));
        vm.expectRevert(IPOLSplitter.InvalidClaim.selector);
        splitter.recordPTBackingRatio(VERSE_ID, 7 ether, 14 ether);
    }

    function testPreviewPTToUAsset_RevertsBeforeRatioConfigured() external {
        launcher.setStage(VERSE_ID, IMemeverseLauncher.Stage.Locked);

        vm.expectRevert(IPOLSplitter.InvalidClaim.selector);
        splitter.previewPTToUAsset(VERSE_ID, 1 ether);
    }

    function testInitializeVerse_RejectsConfiguredPOLend() external {
        POLSplitterHarness otherSplitter = _deploySplitterHarness(address(launcher));
        launcher.setPolend(ALICE);

        vm.prank(ALICE);
        vm.expectRevert(IPOLSplitter.PermissionDenied.selector);
        otherSplitter.initializeVerse(VERSE_ID, address(pol), address(memecoin), address(uAsset), "Verse", "VRS");
    }

    function testImplementationInitializerIsDisabled() external {
        POLSplitter implementation = new POLSplitter();

        vm.expectRevert(INVALID_INITIALIZATION_SELECTOR);
        implementation.initialize(address(this), address(launcher));
    }

    function testProxyInitialization_RevertsOnZeroLauncher() external {
        POLSplitter implementation = new POLSplitter();
        bytes memory data = abi.encodeCall(POLSplitter.initialize, (address(this), address(0)));

        vm.expectRevert(ZERO_INPUT_SELECTOR);
        new ERC1967Proxy(address(implementation), data);
    }

    function testSplit_RevertAfterUnlocked() external {
        launcher.setStage(VERSE_ID, IMemeverseLauncher.Stage.Unlocked);

        vm.expectRevert(IPOLSplitter.AlreadyUnlocked.selector);
        splitter.split(VERSE_ID, 100 ether);
    }

    function testSplit_RevertsBeforeRatioConfigured() external {
        pol.mint(address(this), 100 ether);
        pol.approve(address(splitter), 100 ether);

        vm.expectRevert(IPOLSplitter.InvalidClaim.selector);
        splitter.split(VERSE_ID, 100 ether);
    }

    function testRedeemPT_RevertBeforeSettle() external {
        vm.expectRevert(IPOLSplitter.NotSettled.selector);
        splitter.redeemPT(VERSE_ID, 1 ether, address(this));
    }

    function testRedeemPT_RevertsOnZeroRecipientBeforeBurn() external {
        vm.prank(address(launcher));
        splitter.recordPTBackingRatio(VERSE_ID, 1 ether, 1 ether);
        splitter.mockSettled(VERSE_ID, 100 ether, 0);
        uAsset.mint(address(splitter), 100 ether);
        splitter.mintPT(VERSE_ID, ALICE, 100 ether);

        vm.prank(ALICE);
        vm.expectRevert(ZERO_INPUT_SELECTOR);
        splitter.redeemPT(VERSE_ID, 40 ether, address(0));

        assertEq(pt.balanceOf(ALICE), 100 ether, "pt not burned");
        assertEq(uAsset.balanceOf(address(splitter)), 100 ether, "uAsset not transferred");
    }

    function testRedeemPT_RevertsWithInvalidClaimWhenSettlementUAssetIsInsufficient() external {
        vm.prank(address(launcher));
        splitter.recordPTBackingRatio(VERSE_ID, 1 ether, 1 ether);
        splitter.mockSettled(VERSE_ID, 40 ether, 0);
        uAsset.mint(address(splitter), 40 ether);
        splitter.mintPT(VERSE_ID, ALICE, 60 ether);

        vm.prank(ALICE);
        vm.expectRevert(INVALID_CLAIM_SELECTOR);
        splitter.redeemPT(VERSE_ID, 60 ether, ALICE);

        (,,,,,, uint256 settlementUAsset,,,,) = splitter.splitInfos(VERSE_ID);
        assertEq(pt.balanceOf(ALICE), 60 ether, "pt not burned");
        assertEq(uAsset.balanceOf(address(splitter)), 40 ether, "uAsset unchanged");
        assertEq(settlementUAsset, 40 ether, "settlement uAsset unchanged");
    }

    function testSplitMergeRedeemPTAndRedeemYT_RevertOnZeroAmount() external {
        vm.expectRevert(ZERO_INPUT_SELECTOR);
        splitter.split(VERSE_ID, 0);

        vm.expectRevert(ZERO_INPUT_SELECTOR);
        splitter.merge(VERSE_ID, 0);

        vm.prank(address(launcher));
        splitter.recordPTBackingRatio(VERSE_ID, 1 ether, 1 ether);
        splitter.mockSettled(VERSE_ID, 100 ether, 100 ether);

        vm.expectRevert(ZERO_INPUT_SELECTOR);
        splitter.redeemPT(VERSE_ID, 0, ALICE);

        vm.expectRevert(ZERO_INPUT_SELECTOR);
        splitter.redeemYT(VERSE_ID, 0, ALICE);
    }

    function testPreviewRedeemYTUAsset_UsesSettlementUAssetMinusReservedPT() external {
        vm.prank(address(launcher));
        splitter.recordPTBackingRatio(VERSE_ID, 1 ether, 1 ether);
        splitter.mockSettled(VERSE_ID, 600 ether, 300 ether);
        splitter.mintPT(VERSE_ID, address(this), 200 ether);
        splitter.mintYT(VERSE_ID, address(this), 300 ether);

        uint256 redeemedUAsset = splitter.previewRedeemYTUAsset(VERSE_ID, 150 ether);
        assertEq(redeemedUAsset, 200 ether, "uAsset pool excludes reserved PT");
    }

    function testPreviewRedeemYTUAsset_ReservesConvertedPTBacking() external {
        vm.prank(address(launcher));
        splitter.recordPTBackingRatio(VERSE_ID, 7 ether, 14 ether);
        splitter.mockSettled(VERSE_ID, 600 ether, 300 ether);
        splitter.mintPT(VERSE_ID, address(this), 200 ether);
        splitter.mintYT(VERSE_ID, address(this), 300 ether);

        uint256 redeemedUAsset = splitter.previewRedeemYTUAsset(VERSE_ID, 150 ether);
        assertEq(redeemedUAsset, 250 ether, "uAsset pool excludes converted PT backing");
    }

    function testRedeemYT_UsesFullPrecisionWhenPoolTimesAmountWouldOverflow() external {
        vm.prank(address(launcher));
        splitter.recordPTBackingRatio(VERSE_ID, 1 ether, 1 ether);
        uint256 pool = type(uint256).max;
        splitter.mockSettled(VERSE_ID, pool, 0);
        uAsset.mint(address(splitter), pool);
        splitter.mintYT(VERSE_ID, BOB, pool);

        assertEq(splitter.previewRedeemYTUAsset(VERSE_ID, 2), 2, "preview");

        vm.prank(BOB);
        (uint256 uAssetAmount, uint256 memecoinAmount) = splitter.redeemYT(VERSE_ID, 2, BOB);

        assertEq(uAssetAmount, 2, "uAsset");
        assertEq(memecoinAmount, 0, "memecoin");
        assertEq(uAsset.balanceOf(BOB), 2, "received uAsset");
    }

    function testRedeemYT_RevertsWithInvalidClaimWhenRedeemOutputsAreZeroBeforeBurn() external {
        vm.prank(address(launcher));
        splitter.recordPTBackingRatio(VERSE_ID, 1 ether, 1 ether);
        splitter.mockSettled(VERSE_ID, 1, 1);
        uAsset.mint(address(splitter), 1);
        memecoin.mint(address(splitter), 1);
        splitter.mintYT(VERSE_ID, BOB, 3);

        vm.prank(BOB);
        vm.expectRevert(INVALID_CLAIM_SELECTOR);
        splitter.redeemYT(VERSE_ID, 1, BOB);

        assertEq(yt.balanceOf(BOB), 3, "yt not burned");
        assertEq(uAsset.balanceOf(address(splitter)), 1, "uAsset not transferred");
        assertEq(memecoin.balanceOf(address(splitter)), 1, "memecoin not transferred");
    }

    function testSplitAndMerge_RoundTripBeforeUnlocked() external {
        vm.prank(address(launcher));
        splitter.recordPTBackingRatio(VERSE_ID, 1 ether, 1 ether);
        pol.mint(address(this), 300 ether);
        pol.approve(address(splitter), 300 ether);

        (uint256 ptAmount, uint256 ytAmount) = splitter.split(VERSE_ID, 300 ether);
        assertEq(ptAmount, 300 ether, "pt minted");
        assertEq(ytAmount, 300 ether, "yt minted");
        assertEq(pt.balanceOf(address(this)), 300 ether, "pt balance");
        assertEq(yt.balanceOf(address(this)), 300 ether, "yt balance");

        pt.approve(address(splitter), 100 ether);
        yt.approve(address(splitter), 100 ether);
        uint256 polAmount = splitter.merge(VERSE_ID, 100 ether);
        assertEq(polAmount, 100 ether, "merged pol");
        assertEq(pol.balanceOf(address(this)), 100 ether, "pol refunded");
        assertEq(pt.balanceOf(address(this)), 200 ether, "pt burned");
        assertEq(yt.balanceOf(address(this)), 200 ether, "yt burned");
    }

    function testMerge_BurnsTokensDecrementsCollateralAndReturnsPOL() external {
        vm.prank(address(launcher));
        splitter.recordPTBackingRatio(VERSE_ID, 1 ether, 1 ether);
        pol.mint(address(this), 300 ether);
        pol.approve(address(splitter), 300 ether);
        splitter.split(VERSE_ID, 300 ether);

        pt.approve(address(splitter), 100 ether);
        yt.approve(address(splitter), 100 ether);

        uint256 polAmount = splitter.merge(VERSE_ID, 100 ether);
        (,,,,, uint256 totalPOLCollateral,,,,,) = splitter.splitInfos(VERSE_ID);

        assertEq(polAmount, 100 ether, "merged pol");
        assertEq(pt.balanceOf(address(this)), 200 ether, "pt burned");
        assertEq(yt.balanceOf(address(this)), 200 ether, "yt burned");
        assertEq(totalPOLCollateral, 200 ether, "collateral decremented");
        assertEq(pol.balanceOf(address(this)), 100 ether, "pol returned");
        assertEq(pol.balanceOf(address(splitter)), 200 ether, "splitter collateral");
    }

    function testSplit_RevertsOnReentrantTransferFrom() external {
        ReentrantMockERC20 reentrantPol = new ReentrantMockERC20("RPOL", "RPOL");
        POLSplitterReentryProbe probe = _deployReentryVerse(reentrantPol);
        reentrantPol.mint(address(probe), 2 ether);

        vm.expectRevert(bytes4(keccak256("ReentrancyGuardReentrantCall()")));
        probe.attackSplit(1 ether);
    }

    function testMerge_RevertsOnReentrantTransfer() external {
        ReentrantMockERC20 reentrantPol = new ReentrantMockERC20("RPOL", "RPOL");
        POLSplitterReentryProbe probe = _deployReentryVerse(reentrantPol);
        reentrantPol.mint(address(probe), 2 ether);
        probe.seedSplit(2 ether);

        vm.expectRevert(bytes4(keccak256("ReentrancyGuardReentrantCall()")));
        probe.attackMerge(1 ether);
    }

    function testRedeemPT_RevertsOnReentrantTransfer() external {
        ReentrantMockERC20 reentrantPol = new ReentrantMockERC20("RUASSET", "RUASSET");
        POLSplitterReentryProbe probe = _deployReentryVerse(reentrantPol);
        splitter.mockSettled(OTHER_VERSE_ID + 1, 3 ether, 0);
        reentrantPol.mint(address(splitter), 3 ether);
        splitter.mintPT(OTHER_VERSE_ID + 1, address(probe), 2 ether);

        vm.expectRevert(bytes4(keccak256("ReentrancyGuardReentrantCall()")));
        probe.attackRedeemPT(1 ether);
    }

    function testSettle_StoresSettlementPoolsAndBlocksSecondCall() external {
        vm.prank(address(launcher));
        splitter.recordPTBackingRatio(VERSE_ID, 1 ether, 1 ether);
        pol.mint(address(this), 500 ether);
        pol.approve(address(splitter), 500 ether);
        splitter.split(VERSE_ID, 500 ether);
        launcher.seedRedemption(VERSE_ID, 900 ether, 400 ether);
        launcher.setStage(VERSE_ID, IMemeverseLauncher.Stage.Unlocked);

        vm.prank(address(launcher));
        splitter.settle(VERSE_ID);
        (,,,,,, uint256 settlementUAsset, uint256 settlementMemecoin,,, bool settled) = splitter.splitInfos(VERSE_ID);
        assertEq(settlementUAsset, 900 ether, "uAsset");
        assertEq(settlementMemecoin, 400 ether, "memecoin");
        assertTrue(settled, "settled");

        vm.prank(address(launcher));
        vm.expectRevert(IPOLSplitter.AlreadySettled.selector);
        splitter.settle(VERSE_ID);
    }

    function testSettle_AllowsLauncherWhenUnlocked() external {
        vm.prank(address(launcher));
        splitter.recordPTBackingRatio(VERSE_ID, 1 ether, 1 ether);
        pol.mint(address(this), 500 ether);
        pol.approve(address(splitter), 500 ether);
        splitter.split(VERSE_ID, 500 ether);
        launcher.seedRedemption(VERSE_ID, 900 ether, 400 ether);
        launcher.setStage(VERSE_ID, IMemeverseLauncher.Stage.Unlocked);

        vm.prank(address(launcher));
        splitter.settle(VERSE_ID);

        (,,,,,, uint256 settlementUAsset, uint256 settlementMemecoin,,, bool settled) = splitter.splitInfos(VERSE_ID);
        assertEq(settlementUAsset, 900 ether, "uAsset");
        assertEq(settlementMemecoin, 400 ether, "memecoin");
        assertTrue(settled, "settled");
    }

    function testSettle_RevertsWhenSettlementUAssetCannotCoverPTSupply() external {
        vm.prank(address(launcher));
        splitter.recordPTBackingRatio(VERSE_ID, 1 ether, 1 ether);
        pol.mint(address(this), 500 ether);
        pol.approve(address(splitter), 500 ether);
        splitter.split(VERSE_ID, 500 ether);
        launcher.seedRedemption(VERSE_ID, 499 ether, 400 ether);
        launcher.setStage(VERSE_ID, IMemeverseLauncher.Stage.Unlocked);

        vm.prank(address(launcher));
        vm.expectRevert(IPOLSplitter.InvalidClaim.selector);
        splitter.settle(VERSE_ID);

        (,,,,,, uint256 settlementUAsset, uint256 settlementMemecoin,,, bool settled) = splitter.splitInfos(VERSE_ID);
        assertEq(settlementUAsset, 0, "settlement uAsset not stored");
        assertEq(settlementMemecoin, 0, "settlement memecoin not stored");
        assertFalse(settled, "not settled");
    }

    function testSettle_RevertsWhenNetSettlementCannotCoverPTSupplyAfterPreRedeem() external {
        vm.prank(address(launcher));
        splitter.recordPTBackingRatio(VERSE_ID, 1 ether, 1 ether);
        pol.mint(address(this), 500 ether);
        pol.approve(address(splitter), 500 ether);
        splitter.split(VERSE_ID, 500 ether);
        splitter.mintPT(VERSE_ID, address(launcher), 120 ether);

        vm.prank(address(polend));
        splitter.preRedeemPTFee(VERSE_ID, 120 ether);

        launcher.seedRedemption(VERSE_ID, 619 ether, 400 ether);
        launcher.setStage(VERSE_ID, IMemeverseLauncher.Stage.Unlocked);
        vm.prank(address(launcher));
        vm.expectRevert(IPOLSplitter.InvalidClaim.selector);
        splitter.settle(VERSE_ID);

        (,,,,,, uint256 settlementUAsset, uint256 settlementMemecoin,,, bool settled) = splitter.splitInfos(VERSE_ID);
        (uint256 ptAmount, uint256 storedBacking) = splitter.preRedeemedStates(VERSE_ID);
        assertEq(settlementUAsset, 0, "settlement uAsset not stored");
        assertEq(settlementMemecoin, 0, "settlement memecoin not stored");
        assertFalse(settled, "not settled");
        assertEq(ptAmount, 120 ether, "preRedeemed pt retained");
        assertEq(storedBacking, 120 ether, "preRedeemed backing retained");
        assertEq(polend.burnPreRedeemedBackingCallCount(), 0, "backing burn not called");
    }

    function testSettle_SucceedsAtExactNetPTBackingLowerBoundAfterPreRedeem() external {
        vm.prank(address(launcher));
        splitter.recordPTBackingRatio(VERSE_ID, 1 ether, 1 ether);
        pol.mint(address(this), 500 ether);
        pol.approve(address(splitter), 500 ether);
        splitter.split(VERSE_ID, 500 ether);
        splitter.mintPT(VERSE_ID, address(launcher), 120 ether);

        vm.prank(address(polend));
        splitter.preRedeemPTFee(VERSE_ID, 120 ether);

        launcher.seedRedemption(VERSE_ID, 620 ether, 400 ether);
        launcher.setStage(VERSE_ID, IMemeverseLauncher.Stage.Unlocked);
        vm.prank(address(launcher));
        splitter.settle(VERSE_ID);

        (,,,,,, uint256 settlementUAsset, uint256 settlementMemecoin,,, bool settled) = splitter.splitInfos(VERSE_ID);
        (uint256 ptAmount, uint256 storedBacking) = splitter.preRedeemedStates(VERSE_ID);
        assertEq(settlementUAsset, 500 ether, "net settlement uAsset");
        assertEq(settlementMemecoin, 400 ether, "settlement memecoin");
        assertTrue(settled, "settled");
        assertEq(ptAmount, 0, "preRedeemed pt cleared");
        assertEq(storedBacking, 0, "preRedeemed backing cleared");
        assertEq(polend.burnPreRedeemedBackingCallCount(), 1, "backing burn called");
        assertEq(polend.lastBurnPreRedeemedBackingAmount(), 120 ether, "backing burn amount");
    }

    function testSettle_RevertBeforeUnlockedOrForNonLauncher() external {
        vm.prank(address(launcher));
        splitter.recordPTBackingRatio(VERSE_ID, 1 ether, 1 ether);
        pol.mint(address(this), 500 ether);
        pol.approve(address(splitter), 500 ether);
        splitter.split(VERSE_ID, 500 ether);
        launcher.seedRedemption(VERSE_ID, 900 ether, 400 ether);

        vm.prank(address(launcher));
        vm.expectRevert(IPOLSplitter.NotUnlocked.selector);
        splitter.settle(VERSE_ID);

        launcher.setStage(VERSE_ID, IMemeverseLauncher.Stage.Unlocked);
        vm.prank(ALICE);
        vm.expectRevert(IPOLSplitter.PermissionDenied.selector);
        splitter.settle(VERSE_ID);
    }

    function testRedeemPTAndRedeemYT_ConsumeCorrectPools() external {
        vm.prank(address(launcher));
        splitter.recordPTBackingRatio(VERSE_ID, 1 ether, 1 ether);
        splitter.mockSettled(VERSE_ID, 600 ether, 300 ether);
        uAsset.mint(address(splitter), 600 ether);
        memecoin.mint(address(splitter), 300 ether);
        splitter.mintPT(VERSE_ID, ALICE, 200 ether);
        splitter.mintYT(VERSE_ID, BOB, 300 ether);

        vm.prank(ALICE);
        assertEq(splitter.redeemPT(VERSE_ID, 50 ether, ALICE), 50 ether, "pt 1:1");
        assertEq(uAsset.balanceOf(ALICE), 50 ether, "pt uAsset");

        vm.prank(BOB);
        (uint256 uAssetAmount, uint256 memecoinAmount) = splitter.redeemYT(VERSE_ID, 150 ether, BOB);
        assertEq(uAssetAmount, 200 ether, "yt uAsset");
        assertEq(memecoinAmount, 150 ether, "yt memecoin");
        assertEq(uAsset.balanceOf(BOB), 200 ether, "yt uAsset balance");
        assertEq(memecoin.balanceOf(BOB), 150 ether, "yt memecoin balance");
    }

    function testRedeemPT_UsesFixedBackingRatio() external {
        vm.prank(address(launcher));
        splitter.recordPTBackingRatio(VERSE_ID, 7 ether, 14 ether);
        splitter.mockSettled(VERSE_ID, 7 ether, 0);
        uAsset.mint(address(splitter), 7 ether);
        splitter.mintPT(VERSE_ID, ALICE, 14 ether);

        vm.prank(ALICE);
        uint256 uAssetAmount = splitter.redeemPT(VERSE_ID, 14 ether, ALICE);

        assertEq(uAssetAmount, 7 ether, "converted uAsset");
        assertEq(pt.balanceOf(ALICE), 0, "pt burned");
        assertEq(uAsset.balanceOf(ALICE), 7 ether, "uAsset received");
        (,,,,,, uint256 settlementUAsset,,,,) = splitter.splitInfos(VERSE_ID);
        assertEq(settlementUAsset, 0, "settlement debited by converted amount");
    }

    function testRedeemPT_RevertsWhenConvertedBackingIsZero() external {
        vm.prank(address(launcher));
        splitter.recordPTBackingRatio(VERSE_ID, 1, 2);
        splitter.mockSettled(VERSE_ID, 1 ether, 0);
        uAsset.mint(address(splitter), 1 ether);
        splitter.mintPT(VERSE_ID, ALICE, 1);

        vm.prank(ALICE);
        vm.expectRevert(IPOLSplitter.InvalidClaim.selector);
        splitter.redeemPT(VERSE_ID, 1, ALICE);

        assertEq(pt.balanceOf(ALICE), 1, "pt not burned");
        assertEq(uAsset.balanceOf(ALICE), 0, "uAsset not transferred");
    }

    function testRedeemYT_ReservesConvertedPTBacking() external {
        vm.prank(address(launcher));
        splitter.recordPTBackingRatio(VERSE_ID, 7 ether, 14 ether);
        splitter.mockSettled(VERSE_ID, 600 ether, 300 ether);
        uAsset.mint(address(splitter), 600 ether);
        memecoin.mint(address(splitter), 300 ether);
        splitter.mintPT(VERSE_ID, ALICE, 200 ether);
        splitter.mintYT(VERSE_ID, BOB, 300 ether);

        vm.prank(BOB);
        (uint256 uAssetAmount, uint256 memecoinAmount) = splitter.redeemYT(VERSE_ID, 150 ether, BOB);

        assertEq(uAssetAmount, 250 ether, "uAsset pool excludes converted PT backing");
        assertEq(memecoinAmount, 150 ether, "memecoin");
        assertEq(uAsset.balanceOf(BOB), 250 ether, "uAsset received");
        assertEq(memecoin.balanceOf(BOB), 150 ether, "memecoin received");
    }

    function testRedeemYT_RevertsOnZeroRecipientBeforeBurn() external {
        vm.prank(address(launcher));
        splitter.recordPTBackingRatio(VERSE_ID, 1 ether, 1 ether);
        splitter.mockSettled(VERSE_ID, 600 ether, 300 ether);
        uAsset.mint(address(splitter), 600 ether);
        memecoin.mint(address(splitter), 300 ether);
        splitter.mintYT(VERSE_ID, BOB, 300 ether);

        vm.prank(BOB);
        vm.expectRevert(ZERO_INPUT_SELECTOR);
        splitter.redeemYT(VERSE_ID, 150 ether, address(0));

        assertEq(yt.balanceOf(BOB), 300 ether, "yt not burned");
        assertEq(uAsset.balanceOf(address(splitter)), 600 ether, "uAsset not transferred");
        assertEq(memecoin.balanceOf(address(splitter)), 300 ether, "memecoin not transferred");
    }

    function testRedeemYT_RevertsWithInvalidClaimWhenNoOutstandingYT() external {
        vm.prank(address(launcher));
        splitter.recordPTBackingRatio(VERSE_ID, 1 ether, 1 ether);
        splitter.mockSettled(VERSE_ID, 600 ether, 300 ether);
        uAsset.mint(address(splitter), 600 ether);
        memecoin.mint(address(splitter), 300 ether);

        vm.expectRevert(INVALID_CLAIM_SELECTOR);
        splitter.redeemYT(VERSE_ID, 1 ether, BOB);
    }

    function testPreviewRedeemYTUAsset_RevertsWhenSettlementUAssetCannotReservePTSupply() external {
        vm.prank(address(launcher));
        splitter.recordPTBackingRatio(VERSE_ID, 1 ether, 1 ether);
        splitter.mockSettled(VERSE_ID, 50 ether, 300 ether);
        splitter.mintPT(VERSE_ID, ALICE, 100 ether);
        splitter.mintYT(VERSE_ID, BOB, 300 ether);

        vm.expectRevert(abi.encodeWithSelector(PANIC_SELECTOR, uint256(0x11)));
        splitter.previewRedeemYTUAsset(VERSE_ID, 150 ether);
    }

    function testRedeemYT_RevertsWhenSettlementUAssetCannotReservePTSupply() external {
        vm.prank(address(launcher));
        splitter.recordPTBackingRatio(VERSE_ID, 1 ether, 1 ether);
        splitter.mockSettled(VERSE_ID, 50 ether, 300 ether);
        uAsset.mint(address(splitter), 50 ether);
        memecoin.mint(address(splitter), 300 ether);
        splitter.mintPT(VERSE_ID, ALICE, 100 ether);
        splitter.mintYT(VERSE_ID, BOB, 300 ether);

        vm.prank(BOB);
        vm.expectRevert(abi.encodeWithSelector(PANIC_SELECTOR, uint256(0x11)));
        splitter.redeemYT(VERSE_ID, 150 ether, BOB);
    }

    function testPreRedeemPTFee_BurnsLauncherPTWithoutApproveAndRecordsPreRedeemedPT() external {
        vm.prank(address(launcher));
        splitter.recordPTBackingRatio(VERSE_ID, 1 ether, 1 ether);
        splitter.mintPT(VERSE_ID, address(launcher), 120 ether);

        vm.prank(address(polend));
        (bool success,) =
            address(splitter).call(abi.encodeWithSignature("preRedeemPTFee(uint256,uint256)", VERSE_ID, 120 ether));

        assertTrue(success, "preRedeemPTFee");
        assertEq(pt.balanceOf(address(launcher)), 0, "launcher pt burned");
        (bool getterSuccess, bytes memory data) =
            address(splitter).staticcall(abi.encodeWithSignature("preRedeemedPT(uint256)", VERSE_ID));
        assertTrue(getterSuccess, "preRedeemedPT getter");
        assertEq(abi.decode(data, (uint256)), 120 ether, "preRedeemedPT");
    }

    function testPreRedeemPTFee_RecordsRawPTAndConvertedBacking() external {
        vm.prank(address(launcher));
        splitter.recordPTBackingRatio(VERSE_ID, 7 ether, 14 ether);
        splitter.mintPT(VERSE_ID, address(launcher), 140 ether);

        vm.prank(address(polend));
        uint256 uAssetBacking = splitter.preRedeemPTFee(VERSE_ID, 140 ether);

        assertEq(uAssetBacking, 70 ether, "returned backing");
        (uint256 ptAmount, uint256 storedBacking) = splitter.preRedeemedStates(VERSE_ID);
        assertEq(ptAmount, 140 ether, "raw pt");
        assertEq(storedBacking, 70 ether, "stored backing");
        assertEq(pt.balanceOf(address(launcher)), 0, "launcher pt burned");
    }

    function testPreRedeemPTFee_RevertsWhenConvertedBackingIsZeroBeforeBurn() external {
        vm.prank(address(launcher));
        splitter.recordPTBackingRatio(VERSE_ID, 1, 2);
        splitter.mintPT(VERSE_ID, address(launcher), 1);

        vm.prank(address(polend));
        vm.expectRevert(IPOLSplitter.InvalidClaim.selector);
        splitter.preRedeemPTFee(VERSE_ID, 1);

        assertEq(pt.balanceOf(address(launcher)), 1, "pt not burned");
        (uint256 ptAmount, uint256 storedBacking) = splitter.preRedeemedStates(VERSE_ID);
        assertEq(ptAmount, 0, "raw pt not recorded");
        assertEq(storedBacking, 0, "backing not recorded");
    }

    function testSettle_BurnsPreRedeemedBackingAndDeductsSettlementUAsset() external {
        vm.prank(address(launcher));
        splitter.recordPTBackingRatio(VERSE_ID, 1 ether, 1 ether);
        pol.mint(address(this), 500 ether);
        pol.approve(address(splitter), 500 ether);
        splitter.split(VERSE_ID, 500 ether);
        splitter.mintPT(VERSE_ID, address(launcher), 120 ether);

        vm.prank(address(polend));
        (bool success,) =
            address(splitter).call(abi.encodeWithSignature("preRedeemPTFee(uint256,uint256)", VERSE_ID, 120 ether));
        assertTrue(success, "preRedeemPTFee");

        launcher.seedRedemption(VERSE_ID, 900 ether, 400 ether);
        launcher.setStage(VERSE_ID, IMemeverseLauncher.Stage.Unlocked);
        vm.prank(address(launcher));
        splitter.settle(VERSE_ID);

        (,,,,,, uint256 settlementUAsset,,,,) = splitter.splitInfos(VERSE_ID);
        assertEq(polend.burnPreRedeemedBackingCallCount(), 1, "backing burn called");
        assertEq(polend.lastBurnPreRedeemedBackingVerseId(), VERSE_ID, "verse id");
        assertEq(polend.lastBurnPreRedeemedBackingAmount(), 120 ether, "backing amount");
        assertEq(settlementUAsset, 780 ether, "net settlement uAsset");
        (bool getterSuccess, bytes memory data) =
            address(splitter).staticcall(abi.encodeWithSignature("preRedeemedPT(uint256)", VERSE_ID));
        assertTrue(getterSuccess, "preRedeemedPT getter");
        assertEq(abi.decode(data, (uint256)), 0, "preRedeemedPT cleared");
    }

    function testSettle_BurnsPreRedeemedBackingAndDeductsConvertedBacking() external {
        vm.prank(address(launcher));
        splitter.recordPTBackingRatio(VERSE_ID, 7 ether, 14 ether);
        pol.mint(address(this), 500 ether);
        pol.approve(address(splitter), 500 ether);
        splitter.split(VERSE_ID, 500 ether);
        splitter.mintPT(VERSE_ID, address(launcher), 140 ether);

        vm.prank(address(polend));
        uint256 uAssetBacking = splitter.preRedeemPTFee(VERSE_ID, 140 ether);
        assertEq(uAssetBacking, 70 ether, "preRedeem backing");

        launcher.seedRedemption(VERSE_ID, 900 ether, 400 ether);
        launcher.setStage(VERSE_ID, IMemeverseLauncher.Stage.Unlocked);
        vm.prank(address(launcher));
        splitter.settle(VERSE_ID);

        (,,,,,, uint256 settlementUAsset,,,,) = splitter.splitInfos(VERSE_ID);
        assertEq(polend.burnPreRedeemedBackingCallCount(), 1, "backing burn called");
        assertEq(polend.lastBurnPreRedeemedBackingVerseId(), VERSE_ID, "verse id");
        assertEq(polend.lastBurnPreRedeemedBackingAmount(), 70 ether, "backing amount");
        assertEq(settlementUAsset, 830 ether, "net settlement uAsset");
        (uint256 ptAmount, uint256 storedBacking) = splitter.preRedeemedStates(VERSE_ID);
        assertEq(ptAmount, 0, "raw pt cleared");
        assertEq(storedBacking, 0, "backing cleared");
    }

    /// @notice Verifies preRedeemPTFee reverts with AlreadySettled after settle completes.
    /// @dev The AlreadySettled guard is a defensive safety line: normal flow routes settled PT fees
    /// through redeemPT, so preRedeemPTFee should never be callable post-settle.
    function testPreRedeemPTFee_RevertsAfterSettle() external {
        vm.prank(address(launcher));
        splitter.recordPTBackingRatio(VERSE_ID, 1 ether, 1 ether);
        pol.mint(address(this), 500 ether);
        pol.approve(address(splitter), 500 ether);
        splitter.split(VERSE_ID, 500 ether);
        splitter.mintPT(VERSE_ID, address(launcher), 100 ether);

        launcher.seedRedemption(VERSE_ID, 900 ether, 400 ether);
        launcher.setStage(VERSE_ID, IMemeverseLauncher.Stage.Unlocked);
        vm.prank(address(launcher));
        splitter.settle(VERSE_ID);

        vm.prank(address(polend));
        vm.expectRevert(IPOLSplitter.AlreadySettled.selector);
        splitter.preRedeemPTFee(VERSE_ID, 100 ether);
    }

    function testDeployTokens_DifferentVersesStoreTheirOwnUAsset() external view {
        (,,,, address verseUAsset,,,,,,) = splitter.splitInfos(VERSE_ID);
        (,,,, address otherVerseUAsset,,,,,,) = splitter.splitInfos(OTHER_VERSE_ID);

        assertEq(verseUAsset, address(uAsset), "verse uAsset");
        assertEq(otherVerseUAsset, address(otherUAsset), "other verse uAsset");
    }

    function testRedeemPT_DifferentVersesDoNotMixUAsset() external {
        vm.prank(address(launcher));
        splitter.recordPTBackingRatio(VERSE_ID, 1 ether, 1 ether);
        vm.prank(address(launcher));
        splitter.recordPTBackingRatio(OTHER_VERSE_ID, 1 ether, 1 ether);
        splitter.mockSettled(VERSE_ID, 100 ether, 0);
        splitter.mockSettled(OTHER_VERSE_ID, 100 ether, 0);
        uAsset.mint(address(splitter), 100 ether);
        otherUAsset.mint(address(splitter), 100 ether);
        splitter.mintPT(VERSE_ID, ALICE, 100 ether);

        vm.prank(ALICE);
        splitter.redeemPT(VERSE_ID, 100 ether, ALICE);

        assertEq(uAsset.balanceOf(ALICE), 100 ether, "correct uAsset paid");
        assertEq(otherUAsset.balanceOf(ALICE), 0, "other uAsset untouched");
    }

    function _deployReentryVerse(ReentrantMockERC20 reentrantToken) internal returns (POLSplitterReentryProbe probe) {
        uint256 reentryVerseId = OTHER_VERSE_ID + 1;
        vm.prank(address(launcher));
        splitter.initializeVerse(
            reentryVerseId, address(reentrantToken), address(memecoin), address(reentrantToken), "Reentrant", "RNT"
        );
        vm.prank(address(launcher));
        splitter.recordPTBackingRatio(reentryVerseId, 1 ether, 1 ether);
        probe = new POLSplitterReentryProbe(splitter, reentrantToken, reentryVerseId);
    }
}
