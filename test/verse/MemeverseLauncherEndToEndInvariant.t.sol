// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";

import {MemeverseLauncher} from "../../src/verse/MemeverseLauncher.sol";
import {IMemeverseLauncher} from "../../src/verse/interfaces/IMemeverseLauncher.sol";
import {IPOLend} from "../../src/polend/interfaces/IPOLend.sol";
import {MemeverseSwapRouter} from "../../src/swap/MemeverseSwapRouter.sol";
import {IMemeverseUniswapHook} from "../../src/swap/interfaces/IMemeverseUniswapHook.sol";
import {MockPoolManagerForRouterTest} from "../swap/MemeverseSwapRouter.t.sol";
import {
    MockIntegrationMemecoin,
    MockLauncherIntegrationLzEndpointRegistry,
    MockLauncherIntegrationProxyDeployer,
    TestableMemeverseUniswapHookForLauncherIntegration
} from "./MemeverseLauncherPreorderIntegration.t.sol";

contract MockPOLendForEndToEndInvariant {
    uint256 internal totalLeveragedDebt_;
    address internal pt_;
    address internal yt_;

    function setLendMarket(address pt, address yt) external {
        pt_ = pt;
        yt_ = yt;
    }

    function registerLendMarket(uint256) external {}

    function getTotalLeveragedDebt(uint256) external view returns (uint256) {
        return totalLeveragedDebt_;
    }

    function getTotalLeveragedInterest(uint256) external pure returns (uint256) {
        return 0;
    }

    function getLendMarket(uint256) external view returns (IPOLend.LendMarket memory market) {
        market.yt = yt_;
    }

    function finalizeLeveragedGenesis(uint256) external {}

    function recordLeveragedYT(uint256, address, uint256) external {}

    function markRefundable(uint256) external {}

    function executeGlobalSettlement(uint256) external {}
}

contract MockPOLSplitterForEndToEndInvariant {
    address internal immutable pt;
    address internal immutable yt;

    constructor(address pt_, address yt_) {
        pt = pt_;
        yt = yt_;
    }

    function initializeVerse(uint256, address, address, address, string calldata, string calldata)
        external
        view
        returns (address, address)
    {
        return (pt, yt);
    }

    function splitInfos(uint256)
        external
        view
        returns (address, address, address, address, address, uint256, uint256, uint256, uint256, uint256, bool)
    {
        return (pt, yt, address(0), address(0), address(0), 0, 0, 0, 0, 0, false);
    }

    function getPT(uint256) external view returns (address) {
        return pt;
    }

    function getYT(uint256) external view returns (address) {
        return yt;
    }

    function getMemecoin(uint256) external pure returns (address) {
        return address(0);
    }

    function getPTAndYT(uint256) external view returns (address, address) {
        return (pt, yt);
    }

    function getPTSettlementState(uint256) external view returns (address, bool) {
        return (pt, false);
    }

    function split(uint256, uint256 polAmount) external returns (uint256 ptAmount, uint256 ytAmount) {
        MockERC20(pt).mint(msg.sender, polAmount);
        MockERC20(yt).mint(msg.sender, polAmount);
        return (polAmount, polAmount);
    }

    function settle(uint256) external pure returns (uint256 settlementUAsset, uint256 settlementMemecoin) {
        return (0, 0);
    }

    function merge(uint256, uint256) external pure returns (uint256) {
        revert("unused");
    }

    function preRedeemPTFee(uint256, uint256) external pure returns (uint256 uAssetBacking) {
        return 0;
    }

    function redeemPT(uint256, uint256, address) external pure returns (uint256) {
        revert("unused");
    }

    function redeemYT(uint256, uint256, address) external pure returns (uint256, uint256) {
        revert("unused");
    }

    function previewRedeemYTUAsset(uint256, uint256) external pure returns (uint256 uAssetAmount) {
        return 0;
    }
}

contract InspectableEndToEndLauncher is MemeverseLauncher {
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

    /// @notice Test helper for getPreorderStateForTest.
    /// @param verseId See implementation.
    /// @return totalFunds See implementation.
    /// @return settledMemecoin See implementation.
    /// @return settlementTimestamp See implementation.
    function getPreorderStateForTest(uint256 verseId)
        external
        view
        returns (uint256 totalFunds, uint256 settledMemecoin, uint40 settlementTimestamp)
    {
        PreorderState storage state = preorderStates[verseId];
        return (state.totalFunds, state.settledMemecoin, state.settlementTimestamp);
    }

    /// @notice Test helper for claimablePreorderMemecoinForTest.
    /// @param verseId See implementation.
    /// @param account See implementation.
    /// @return amount See implementation.
    function claimablePreorderMemecoinForTest(uint256 verseId, address account) external view returns (uint256 amount) {
        PreorderState storage preorderState = preorderStates[verseId];
        uint40 settlementTimestamp = preorderState.settlementTimestamp;
        if (settlementTimestamp == 0) return 0;

        PreorderData storage preorderData = userPreorderData[verseId][account];
        uint256 userFunds = preorderData.funds;
        uint256 totalFunds = preorderState.totalFunds;
        if (userFunds == 0 || totalFunds == 0 || preorderData.isRefunded) return 0;

        uint256 purchasedMemecoin = FullMath.mulDiv(preorderState.settledMemecoin, userFunds, totalFunds);
        if (purchasedMemecoin <= preorderData.claimedMemecoin) return 0;

        uint256 elapsed = block.timestamp - settlementTimestamp;
        if (elapsed >= preorderVestingDuration) {
            return purchasedMemecoin - preorderData.claimedMemecoin;
        }

        uint256 vested = FullMath.mulDiv(purchasedMemecoin, elapsed, preorderVestingDuration);
        if (vested <= preorderData.claimedMemecoin) return 0;
        return vested - preorderData.claimedMemecoin;
    }
}

contract EndToEndSuccessHandler is Test {
    uint256 internal constant VERSE_ID = 1;

    InspectableEndToEndLauncher internal immutable launcher;
    MockERC20 internal immutable uAsset;
    address[] internal actors;

    uint256 public recordedMemecoinDust;
    bool public memecoinDustRecorded;

    constructor(InspectableEndToEndLauncher _launcher, MockERC20 _uAsset, address[] memory _actors) {
        launcher = _launcher;
        uAsset = _uAsset;
        actors = _actors;
    }

    /// @notice Test helper for genesis.
    /// @param actorSeed See implementation.
    /// @param amountSeed See implementation.
    function genesis(uint256 actorSeed, uint256 amountSeed) external {
        if (launcher.getStageByVerseId(VERSE_ID) != IMemeverseLauncher.Stage.Genesis) return;

        address actor = actors[actorSeed % actors.length];
        uint256 balance = uAsset.balanceOf(actor);
        if (balance == 0) return;

        uint256 amount = bound(amountSeed, 1, _min(balance, type(uint128).max));
        vm.prank(actor);
        try launcher.genesis(VERSE_ID, amount, actor) {} catch {}
    }

    /// @notice Test helper for preorder.
    /// @param actorSeed See implementation.
    /// @param amountSeed See implementation.
    function preorder(uint256 actorSeed, uint256 amountSeed) external {
        if (launcher.getStageByVerseId(VERSE_ID) != IMemeverseLauncher.Stage.Genesis) return;

        uint256 capacity = launcher.previewPreorderCapacity(VERSE_ID);
        if (capacity == 0) return;

        address actor = actors[actorSeed % actors.length];
        uint256 balance = uAsset.balanceOf(actor);
        uint256 maxAmount = _min(capacity, _min(balance, type(uint128).max));
        if (maxAmount == 0) return;

        uint256 amount = bound(amountSeed, 1, maxAmount);
        vm.prank(actor);
        try launcher.preorder(VERSE_ID, amount, actor) {} catch {}
    }

    /// @notice Test helper for warp.
    /// @param deltaSeed See implementation.
    function warp(uint256 deltaSeed) external {
        vm.warp(block.timestamp + bound(deltaSeed, 0, 5 days));
    }

    /// @notice Test helper for changeStage.
    function changeStage() external {
        try launcher.changeStage(VERSE_ID) {
            if (!memecoinDustRecorded) {
                (uint256 totalFunds, uint256 settledMemecoin, uint40 settlementTimestamp) =
                    launcher.getPreorderStateForTest(VERSE_ID);
                if (settlementTimestamp != 0 && totalFunds != 0) {
                    IMemeverseLauncher.Memeverse memory verse = launcher.getMemeverseByVerseId(VERSE_ID);
                    uint256 launcherMemecoinBalance =
                        MockIntegrationMemecoin(verse.memecoin).balanceOf(address(launcher));
                    recordedMemecoinDust = launcherMemecoinBalance - settledMemecoin;
                    memecoinDustRecorded = true;
                }
            }
        } catch {}
    }

    /// @notice Test helper for claim.
    /// @param actorSeed See implementation.
    function claim(uint256 actorSeed) external {
        address actor = actors[actorSeed % actors.length];
        vm.prank(actor);
        try launcher.claimUnlockedPreorderMemecoin(VERSE_ID) {} catch {}
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}

contract EndToEndRefundHandler is Test {
    uint256 internal constant VERSE_ID = 1;

    InspectableEndToEndLauncher internal immutable launcher;
    MockERC20 internal immutable uAsset;
    address[] internal actors;

    constructor(InspectableEndToEndLauncher _launcher, MockERC20 _uAsset, address[] memory _actors) {
        launcher = _launcher;
        uAsset = _uAsset;
        actors = _actors;
    }

    /// @notice Test helper for genesis.
    /// @param actorSeed See implementation.
    /// @param amountSeed See implementation.
    function genesis(uint256 actorSeed, uint256 amountSeed) external {
        if (launcher.getStageByVerseId(VERSE_ID) != IMemeverseLauncher.Stage.Genesis) return;

        address actor = actors[actorSeed % actors.length];
        uint256 balance = uAsset.balanceOf(actor);
        if (balance == 0) return;

        uint256 amount = bound(amountSeed, 1, _min(balance, type(uint128).max));
        vm.prank(actor);
        try launcher.genesis(VERSE_ID, amount, actor) {} catch {}
    }

    /// @notice Test helper for preorder.
    /// @param actorSeed See implementation.
    /// @param amountSeed See implementation.
    function preorder(uint256 actorSeed, uint256 amountSeed) external {
        if (launcher.getStageByVerseId(VERSE_ID) != IMemeverseLauncher.Stage.Genesis) return;

        uint256 capacity = launcher.previewPreorderCapacity(VERSE_ID);
        if (capacity == 0) return;

        address actor = actors[actorSeed % actors.length];
        uint256 balance = uAsset.balanceOf(actor);
        uint256 maxAmount = _min(capacity, _min(balance, type(uint128).max));
        if (maxAmount == 0) return;

        uint256 amount = bound(amountSeed, 1, maxAmount);
        vm.prank(actor);
        try launcher.preorder(VERSE_ID, amount, actor) {} catch {}
    }

    /// @notice Test helper for warp.
    /// @param deltaSeed See implementation.
    function warp(uint256 deltaSeed) external {
        vm.warp(block.timestamp + bound(deltaSeed, 0, 5 days));
    }

    /// @notice Test helper for changeStage.
    function changeStage() external {
        try launcher.changeStage(VERSE_ID) {} catch {}
    }

    /// @notice Test helper for refundGenesis.
    /// @param actorSeed See implementation.
    function refundGenesis(uint256 actorSeed) external {
        address actor = actors[actorSeed % actors.length];
        vm.prank(actor);
        try launcher.refund(VERSE_ID) {} catch {}
    }

    /// @notice Test helper for refundPreorder.
    /// @param actorSeed See implementation.
    function refundPreorder(uint256 actorSeed) external {
        address actor = actors[actorSeed % actors.length];
        vm.prank(actor);
        try launcher.refundPreorder(VERSE_ID) {} catch {}
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}

contract MemeverseLauncherEndToEndInvariantTest is StdInvariant, Test {
    address internal constant REGISTRAR = address(0xBEEF);
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant CHARLIE = address(0xCA11E);
    uint32 internal constant REMOTE_GOV_CHAIN_ID = 202;
    uint32 internal constant REMOTE_EID = 302;
    uint256 internal constant VERSE_ID = 1;

    address[] internal actors;

    MockPoolManagerForRouterTest internal manager;
    TestableMemeverseUniswapHookForLauncherIntegration internal hook;
    MemeverseSwapRouter internal router;
    InspectableEndToEndLauncher internal launcher;
    MockLauncherIntegrationProxyDeployer internal proxyDeployer;
    MockLauncherIntegrationLzEndpointRegistry internal registry;
    MockPOLendForEndToEndInvariant internal polend;
    MockPOLSplitterForEndToEndInvariant internal splitter;
    MockERC20 internal uAsset;
    MockERC20 internal pt;
    MockERC20 internal yt;
    address internal treasury;
    EndToEndSuccessHandler internal handler;

    /// @notice Test helper for setUp.
    function setUp() external {
        actors.push(ALICE);
        actors.push(BOB);
        actors.push(CHARLIE);

        treasury = makeAddr("treasury");
        manager = new MockPoolManagerForRouterTest();
        proxyDeployer = new MockLauncherIntegrationProxyDeployer(address(0xD00D), address(0xCAFE), address(0xF00D));
        registry = new MockLauncherIntegrationLzEndpointRegistry();
        uAsset = new MockERC20("UASSET", "UASSET", 18);
        pt = new MockERC20("PT", "PT", 18);
        yt = new MockERC20("YT", "YT", 18);
        polend = new MockPOLendForEndToEndInvariant();
        splitter = new MockPOLSplitterForEndToEndInvariant(address(pt), address(yt));
        launcher = new InspectableEndToEndLauncher(
            address(this),
            address(0x1111),
            REGISTRAR,
            address(0),
            address(0x4444),
            address(0),
            address(polend),
            address(splitter),
            25,
            115_000,
            135_000,
            2_500,
            7 days
        );
        hook = new TestableMemeverseUniswapHookForLauncherIntegration(
            IPoolManager(address(manager)), address(this), treasury
        );
        router = new MemeverseSwapRouter(
            IPoolManager(address(manager)), IMemeverseUniswapHook(address(hook)), IPermit2(address(0xBEEF))
        );
        hook.setLauncher(address(launcher));
        hook.setPoolInitializer(address(router));

        launcher.setMemeverseUniswapHook(address(router.hook()));
        launcher.setMemeverseSwapRouter(address(router));
        launcher.setMemeverseProxyDeployer(address(proxyDeployer));
        launcher.setLzEndpointRegistry(address(registry));
        launcher.setFundMetaData(address(uAsset), 10 ether, 4);
        polend.setLendMarket(address(pt), address(yt));

        registry.setEndpoint(REMOTE_GOV_CHAIN_ID, REMOTE_EID);

        uint32[] memory omnichainIds = new uint32[](1);
        omnichainIds[0] = REMOTE_GOV_CHAIN_ID;
        vm.prank(REGISTRAR);
        launcher.registerMemeverse(
            "Memeverse",
            "MEME",
            VERSE_ID,
            uint128(block.timestamp + 1 days),
            uint128(block.timestamp + 30 days),
            omnichainIds,
            address(uAsset),
            true
        );

        IMemeverseLauncher.Memeverse memory verse = launcher.getMemeverseByVerseId(VERSE_ID);
        hook.setProtocolFeeCurrency(Currency.wrap(address(uAsset)));
        hook.setProtocolFeeCurrency(Currency.wrap(verse.memecoin));

        uAsset.mint(ALICE, 1_000 ether);
        uAsset.mint(BOB, 1_000 ether);
        uAsset.mint(CHARLIE, 1_000 ether);

        vm.prank(ALICE);
        uAsset.approve(address(launcher), type(uint256).max);
        vm.prank(BOB);
        uAsset.approve(address(launcher), type(uint256).max);
        vm.prank(CHARLIE);
        uAsset.approve(address(launcher), type(uint256).max);

        vm.prank(ALICE);
        launcher.genesis(VERSE_ID, 10 ether, ALICE);

        handler = new EndToEndSuccessHandler(launcher, uAsset, actors);
        targetContract(address(handler));
    }

    /// @notice Test helper for invariant_endToEndGenesisAccountingMatchesUserBalances.
    function invariant_endToEndGenesisAccountingMatchesUserBalances() external view {
        uint256 totalNormalFunds = launcher.totalNormalFunds(VERSE_ID);
        uint256 totalUserGenesisFunds;

        for (uint256 i; i < actors.length; ++i) {
            (uint256 genesisFund,,) = launcher.userGenesisData(VERSE_ID, actors[i]);
            totalUserGenesisFunds += genesisFund;
        }

        assertEq(totalUserGenesisFunds, totalNormalFunds, "genesis sum");
    }

    /// @notice Test helper for invariant_endToEndPreorderAccountingMatchesState.
    function invariant_endToEndPreorderAccountingMatchesState() external view {
        (uint256 totalFunds,,) = launcher.getPreorderStateForTest(VERSE_ID);
        uint256 totalNormalFunds_ = launcher.totalNormalFunds(VERSE_ID);
        uint256 leveragedDebt = polend.getTotalLeveragedDebt(VERSE_ID);
        uint256 summedUserFunds;

        for (uint256 i; i < actors.length; ++i) {
            (uint256 funds,,) = launcher.userPreorderData(VERSE_ID, actors[i]);
            summedUserFunds += funds;
        }

        assertEq(summedUserFunds, totalFunds, "preorder sum");
        assertLe(
            totalFunds,
            (totalNormalFunds_ + leveragedDebt) * 7 * launcher.preorderCapRatio() / (10 * launcher.RATIO()),
            "preorder cap"
        );
    }

    /// @notice Test helper for invariant_endToEndLaunchSettlementEitherAbsentOrFullyApplied.
    function invariant_endToEndLaunchSettlementEitherAbsentOrFullyApplied() external view {
        (uint256 totalFunds,, uint40 settlementTimestamp) = launcher.getPreorderStateForTest(VERSE_ID);
        IMemeverseLauncher.Stage stage = launcher.getStageByVerseId(VERSE_ID);

        if (stage == IMemeverseLauncher.Stage.Genesis) {
            assertEq(settlementTimestamp, 0, "genesis settlement timestamp");
            assertEq(uAsset.balanceOf(treasury), 0, "genesis treasury");
            return;
        }

        if (totalFunds == 0) {
            assertEq(settlementTimestamp, 0, "no-preorder settlement timestamp");
            assertEq(uAsset.balanceOf(treasury), 0, "no-preorder treasury");
            return;
        }

        assertTrue(
            stage == IMemeverseLauncher.Stage.Locked || stage == IMemeverseLauncher.Stage.Unlocked, "post-launch stage"
        );
        assertGt(settlementTimestamp, 0, "missing settlement timestamp");
        assertEq(uAsset.balanceOf(treasury), totalFunds * 30 / 10_000, "treasury settlement fee");
    }

    /// @notice Test helper for invariant_endToEndPreorderClaimsRemainBounded.
    function invariant_endToEndPreorderClaimsRemainBounded() external view {
        (uint256 totalFunds, uint256 settledMemecoin, uint40 settlementTimestamp) =
            launcher.getPreorderStateForTest(VERSE_ID);
        uint256 totalClaimed;

        for (uint256 i; i < actors.length; ++i) {
            (uint256 funds, uint256 claimedMemecoin,) = launcher.userPreorderData(VERSE_ID, actors[i]);
            uint256 purchasedMemecoin = totalFunds == 0 ? 0 : FullMath.mulDiv(settledMemecoin, funds, totalFunds);
            uint256 claimable = launcher.claimablePreorderMemecoinForTest(VERSE_ID, actors[i]);

            assertLe(claimedMemecoin, purchasedMemecoin, "claimed exceeds entitlement");
            assertLe(claimedMemecoin + claimable, purchasedMemecoin, "claimable exceeds entitlement");
            totalClaimed += claimedMemecoin;
        }

        if (settlementTimestamp != 0) {
            IMemeverseLauncher.Memeverse memory verse = launcher.getMemeverseByVerseId(VERSE_ID);
            uint256 launcherMemecoinBalance = MockIntegrationMemecoin(verse.memecoin).balanceOf(address(launcher));
            assertGe(launcherMemecoinBalance + totalClaimed, settledMemecoin, "undercollateralized memecoin");
            if (handler.memecoinDustRecorded()) {
                assertEq(
                    launcherMemecoinBalance + totalClaimed,
                    settledMemecoin + handler.recordedMemecoinDust(),
                    "memecoin conservation"
                );
            }
        }
    }
}

contract MemeverseLauncherRefundEndToEndInvariantTest is StdInvariant, Test {
    address internal constant REGISTRAR = address(0xBEEF);
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant CHARLIE = address(0xCA11E);
    uint32 internal constant REMOTE_GOV_CHAIN_ID = 202;
    uint32 internal constant REMOTE_EID = 302;
    uint256 internal constant VERSE_ID = 1;

    address[] internal actors;

    MockPoolManagerForRouterTest internal manager;
    TestableMemeverseUniswapHookForLauncherIntegration internal hook;
    MemeverseSwapRouter internal router;
    InspectableEndToEndLauncher internal launcher;
    MockLauncherIntegrationProxyDeployer internal proxyDeployer;
    MockLauncherIntegrationLzEndpointRegistry internal registry;
    MockPOLendForEndToEndInvariant internal polend;
    MockPOLSplitterForEndToEndInvariant internal splitter;
    MockERC20 internal uAsset;
    MockERC20 internal pt;
    MockERC20 internal yt;
    address internal treasury;
    EndToEndRefundHandler internal handler;

    /// @notice Test helper for setUp.
    function setUp() external {
        actors.push(ALICE);
        actors.push(BOB);
        actors.push(CHARLIE);

        treasury = makeAddr("treasury");
        manager = new MockPoolManagerForRouterTest();
        proxyDeployer = new MockLauncherIntegrationProxyDeployer(address(0xD00D), address(0xCAFE), address(0xF00D));
        registry = new MockLauncherIntegrationLzEndpointRegistry();
        uAsset = new MockERC20("UASSET", "UASSET", 18);
        pt = new MockERC20("PT", "PT", 18);
        yt = new MockERC20("YT", "YT", 18);
        polend = new MockPOLendForEndToEndInvariant();
        splitter = new MockPOLSplitterForEndToEndInvariant(address(pt), address(yt));
        launcher = new InspectableEndToEndLauncher(
            address(this),
            address(0x1111),
            REGISTRAR,
            address(0),
            address(0x4444),
            address(0),
            address(polend),
            address(splitter),
            25,
            115_000,
            135_000,
            2_500,
            7 days
        );
        hook = new TestableMemeverseUniswapHookForLauncherIntegration(
            IPoolManager(address(manager)), address(this), treasury
        );
        router = new MemeverseSwapRouter(
            IPoolManager(address(manager)), IMemeverseUniswapHook(address(hook)), IPermit2(address(0xBEEF))
        );
        hook.setLauncher(address(launcher));
        hook.setPoolInitializer(address(router));

        launcher.setMemeverseUniswapHook(address(router.hook()));
        launcher.setMemeverseSwapRouter(address(router));
        launcher.setMemeverseProxyDeployer(address(proxyDeployer));
        launcher.setLzEndpointRegistry(address(registry));
        launcher.setFundMetaData(address(uAsset), 10 ether, 4);
        polend.setLendMarket(address(pt), address(yt));

        registry.setEndpoint(REMOTE_GOV_CHAIN_ID, REMOTE_EID);

        uint32[] memory omnichainIds = new uint32[](1);
        omnichainIds[0] = REMOTE_GOV_CHAIN_ID;
        vm.prank(REGISTRAR);
        launcher.registerMemeverse(
            "Memeverse",
            "MEME",
            VERSE_ID,
            uint128(block.timestamp + 1 days),
            uint128(block.timestamp + 30 days),
            omnichainIds,
            address(uAsset),
            false
        );

        IMemeverseLauncher.Memeverse memory verse = launcher.getMemeverseByVerseId(VERSE_ID);
        hook.setProtocolFeeCurrency(Currency.wrap(address(uAsset)));
        hook.setProtocolFeeCurrency(Currency.wrap(verse.memecoin));

        uAsset.mint(ALICE, 1_000 ether);
        uAsset.mint(BOB, 1_000 ether);
        uAsset.mint(CHARLIE, 1_000 ether);

        vm.prank(ALICE);
        uAsset.approve(address(launcher), type(uint256).max);
        vm.prank(BOB);
        uAsset.approve(address(launcher), type(uint256).max);
        vm.prank(CHARLIE);
        uAsset.approve(address(launcher), type(uint256).max);

        handler = new EndToEndRefundHandler(launcher, uAsset, actors);
        targetContract(address(handler));
    }

    /// @notice Test helper for invariant_refundPathStageNeverLeavesGenesisOrRefund.
    function invariant_refundPathStageNeverLeavesGenesisOrRefund() external view {
        IMemeverseLauncher.Stage stage = launcher.getStageByVerseId(VERSE_ID);
        assertTrue(
            stage == IMemeverseLauncher.Stage.Genesis || stage == IMemeverseLauncher.Stage.Refund, "refund stage"
        );
    }

    /// @notice Test helper for invariant_refundPathNeverCreatesSettlementOrTreasuryFee.
    function invariant_refundPathNeverCreatesSettlementOrTreasuryFee() external view {
        (, uint256 settledMemecoin, uint40 settlementTimestamp) = launcher.getPreorderStateForTest(VERSE_ID);
        assertEq(settledMemecoin, 0, "refund settled memecoin");
        assertEq(settlementTimestamp, 0, "refund settlement timestamp");
        assertEq(uAsset.balanceOf(treasury), 0, "refund treasury fee");
    }

    /// @notice Test helper for invariant_refundPathUAssetBalanceMatchesOutstandingLiability.
    function invariant_refundPathUAssetBalanceMatchesOutstandingLiability() external view {
        uint256 outstandingGenesis;
        uint256 outstandingPreorder;
        uint256 historicalGenesis;
        uint256 historicalPreorder;

        for (uint256 i; i < actors.length; ++i) {
            (uint256 genesisFund, bool isGenesisRefunded,) = launcher.userGenesisData(VERSE_ID, actors[i]);
            (uint256 preorderFund,, bool isPreorderRefunded) = launcher.userPreorderData(VERSE_ID, actors[i]);

            historicalGenesis += genesisFund;
            historicalPreorder += preorderFund;
            if (!isGenesisRefunded) outstandingGenesis += genesisFund;
            if (!isPreorderRefunded) outstandingPreorder += preorderFund;
        }

        uint256 totalNormalFunds = launcher.totalNormalFunds(VERSE_ID);
        (uint256 totalPreorderFunds,,) = launcher.getPreorderStateForTest(VERSE_ID);

        assertEq(historicalGenesis, totalNormalFunds, "genesis history");
        assertEq(historicalPreorder, totalPreorderFunds, "preorder history");
        assertEq(uAsset.balanceOf(address(launcher)), outstandingGenesis + outstandingPreorder, "launcher liability");
    }

    /// @notice Test helper for invariant_refundPathStillRespectsPreorderCap.
    function invariant_refundPathStillRespectsPreorderCap() external view {
        uint256 totalNormalFunds_ = launcher.totalNormalFunds(VERSE_ID);
        uint256 leveragedDebt = polend.getTotalLeveragedDebt(VERSE_ID);
        (uint256 totalFunds,,) = launcher.getPreorderStateForTest(VERSE_ID);
        uint256 preorderBase = (totalNormalFunds_ + leveragedDebt) * 7 / 10;
        uint256 maxCapacity = preorderBase * launcher.preorderCapRatio() / launcher.RATIO();

        assertLe(totalFunds, maxCapacity, "refund preorder cap");
        assertEq(totalFunds + launcher.previewPreorderCapacity(VERSE_ID), maxCapacity, "refund preorder capacity");
    }
}
