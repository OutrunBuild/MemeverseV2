// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {MemeverseLauncher} from "../../src/verse/MemeverseLauncher.sol";
import {IMemeverseLauncher} from "../../src/verse/interfaces/IMemeverseLauncher.sol";
import {MemeverseSwapRouter} from "../../src/swap/MemeverseSwapRouter.sol";
import {IMemeverseUniswapHook} from "../../src/swap/interfaces/IMemeverseUniswapHook.sol";
import {TestableMemeverseUniswapHookForLauncherIntegration} from "./MemeverseLauncherPreorderIntegration.t.sol";
import {
    MockIntegrationMemecoin,
    MockLauncherIntegrationLzEndpointRegistry,
    MockLauncherIntegrationProxyDeployer
} from "./MemeverseLauncherPreorderIntegration.t.sol";
import {MockPoolManagerForRouterTest} from "../swap/MemeverseSwapRouter.t.sol";

contract InspectableMemeverseLauncher is MemeverseLauncher {
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

    /// @notice Test helper for getPreorderStateForTest.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
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
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
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

        uint256 purchasedMemecoin = preorderState.settledMemecoin * userFunds / totalFunds;
        if (purchasedMemecoin <= preorderData.claimedMemecoin) return 0;

        uint256 elapsed = block.timestamp - settlementTimestamp;
        if (elapsed >= preorderVestingDuration) {
            return purchasedMemecoin - preorderData.claimedMemecoin;
        }

        uint256 vested = purchasedMemecoin * elapsed / preorderVestingDuration;
        if (vested <= preorderData.claimedMemecoin) return 0;
        return vested - preorderData.claimedMemecoin;
    }
}

abstract contract MemeverseLauncherPreorderInvariantBase is Test {
    address internal constant REGISTRAR = address(0xBEEF);
    uint32 internal constant REMOTE_GOV_CHAIN_ID = 202;
    uint32 internal constant REMOTE_EID = 302;
    uint256 internal constant VERSE_ID = 1;

    address[] internal actors;

    function _setActors(address alice, address bob, address charlie) internal {
        actors.push(alice);
        actors.push(bob);
        actors.push(charlie);
    }

    function _registerVerse(InspectableMemeverseLauncher launcher, address upt) internal {
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
            upt,
            false
        );
    }
}

contract PreorderSuccessHandler is Test {
    uint256 internal constant VERSE_ID = 1;

    InspectableMemeverseLauncher internal immutable launcher;
    MockERC20 internal immutable upt;
    address[] internal actors;
    uint256 public recordedMemecoinDust;
    bool public memecoinDustRecorded;

    constructor(InspectableMemeverseLauncher _launcher, MockERC20 _upt, address[] memory _actors) {
        launcher = _launcher;
        upt = _upt;
        actors = _actors;
    }

    /// @notice Test helper for genesis.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @param actorSeed See implementation.
    /// @param amountSeed See implementation.
    function genesis(uint256 actorSeed, uint256 amountSeed) external {
        if (launcher.getStageByVerseId(VERSE_ID) != IMemeverseLauncher.Stage.Genesis) return;

        address actor = actors[actorSeed % actors.length];
        uint256 balance = upt.balanceOf(actor);
        if (balance == 0) return;

        uint256 amount = bound(amountSeed, 1, _min(balance, type(uint128).max));
        vm.prank(actor);
        try launcher.genesis(VERSE_ID, uint128(amount), actor) {} catch {}
    }

    /// @notice Test helper for preorder.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @param actorSeed See implementation.
    /// @param amountSeed See implementation.
    function preorder(uint256 actorSeed, uint256 amountSeed) external {
        if (launcher.getStageByVerseId(VERSE_ID) != IMemeverseLauncher.Stage.Genesis) return;

        uint256 capacity = launcher.previewPreorderCapacity(VERSE_ID);
        if (capacity == 0) return;

        address actor = actors[actorSeed % actors.length];
        uint256 balance = upt.balanceOf(actor);
        uint256 maxAmount = _min(capacity, _min(balance, type(uint128).max));
        if (maxAmount == 0) return;

        uint256 amount = bound(amountSeed, 1, maxAmount);
        vm.prank(actor);
        try launcher.preorder(VERSE_ID, uint128(amount), actor) {} catch {}
    }

    /// @notice Test helper for warp.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @param deltaSeed See implementation.
    function warp(uint256 deltaSeed) external {
        vm.warp(block.timestamp + bound(deltaSeed, 0, 5 days));
    }

    /// @notice Test helper for changeStage.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
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
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
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

contract PreorderRefundHandler is Test {
    uint256 internal constant VERSE_ID = 1;

    InspectableMemeverseLauncher internal immutable launcher;
    MockERC20 internal immutable upt;
    address[] internal actors;

    constructor(InspectableMemeverseLauncher _launcher, MockERC20 _upt, address[] memory _actors) {
        launcher = _launcher;
        upt = _upt;
        actors = _actors;
    }

    /// @notice Test helper for genesis.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @param actorSeed See implementation.
    /// @param amountSeed See implementation.
    function genesis(uint256 actorSeed, uint256 amountSeed) external {
        if (launcher.getStageByVerseId(VERSE_ID) != IMemeverseLauncher.Stage.Genesis) return;

        address actor = actors[actorSeed % actors.length];
        uint256 balance = upt.balanceOf(actor);
        if (balance == 0) return;

        uint256 amount = bound(amountSeed, 1, _min(balance, type(uint128).max));
        vm.prank(actor);
        try launcher.genesis(VERSE_ID, uint128(amount), actor) {} catch {}
    }

    /// @notice Test helper for preorder.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @param actorSeed See implementation.
    /// @param amountSeed See implementation.
    function preorder(uint256 actorSeed, uint256 amountSeed) external {
        if (launcher.getStageByVerseId(VERSE_ID) != IMemeverseLauncher.Stage.Genesis) return;

        uint256 capacity = launcher.previewPreorderCapacity(VERSE_ID);
        if (capacity == 0) return;

        address actor = actors[actorSeed % actors.length];
        uint256 balance = upt.balanceOf(actor);
        uint256 maxAmount = _min(capacity, _min(balance, type(uint128).max));
        if (maxAmount == 0) return;

        uint256 amount = bound(amountSeed, 1, maxAmount);
        vm.prank(actor);
        try launcher.preorder(VERSE_ID, uint128(amount), actor) {} catch {}
    }

    /// @notice Test helper for warp.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @param deltaSeed See implementation.
    function warp(uint256 deltaSeed) external {
        vm.warp(block.timestamp + bound(deltaSeed, 0, 3 days));
    }

    /// @notice Test helper for changeStage.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function changeStage() external {
        try launcher.changeStage(VERSE_ID) {} catch {}
    }

    /// @notice Test helper for refundGenesis.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @param actorSeed See implementation.
    function refundGenesis(uint256 actorSeed) external {
        address actor = actors[actorSeed % actors.length];
        vm.prank(actor);
        try launcher.refund(VERSE_ID) {} catch {}
    }

    /// @notice Test helper for refundPreorder.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
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

contract MemeverseLauncherPreorderSuccessInvariantTest is StdInvariant, MemeverseLauncherPreorderInvariantBase {
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant CHARLIE = address(0xCA11E);

    MockPoolManagerForRouterTest internal manager;
    TestableMemeverseUniswapHookForLauncherIntegration internal hook;
    MemeverseSwapRouter internal router;
    InspectableMemeverseLauncher internal launcher;
    MockLauncherIntegrationProxyDeployer internal proxyDeployer;
    MockLauncherIntegrationLzEndpointRegistry internal registry;
    MockERC20 internal upt;
    PreorderSuccessHandler internal handler;

    /// @notice Test helper for setUp.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function setUp() external {
        _setActors(ALICE, BOB, CHARLIE);

        manager = new MockPoolManagerForRouterTest();
        launcher = new InspectableMemeverseLauncher(
            address(this),
            address(0x1111),
            REGISTRAR,
            address(0),
            address(0x4444),
            address(0),
            25,
            115_000,
            135_000,
            2_500,
            7 days
        );
        hook = new TestableMemeverseUniswapHookForLauncherIntegration(
            IPoolManager(address(manager)), address(this), address(this), address(launcher)
        );
        router = new MemeverseSwapRouter(
            IPoolManager(address(manager)),
            IMemeverseUniswapHook(address(hook)),
            IPermit2(address(0xBEEF)),
            address(launcher)
        );
        hook.setLaunchSettlementCaller(address(router));
        proxyDeployer = new MockLauncherIntegrationProxyDeployer(address(0xD00D), address(0xCAFE), address(0xF00D));
        registry = new MockLauncherIntegrationLzEndpointRegistry();
        upt = new MockERC20("UPT", "UPT", 18);

        launcher.setMemeverseSwapRouter(address(router));
        launcher.setMemeverseProxyDeployer(address(proxyDeployer));
        launcher.setLzEndpointRegistry(address(registry));
        launcher.setFundMetaData(address(upt), 100 ether, 4);

        registry.setEndpoint(REMOTE_GOV_CHAIN_ID, REMOTE_EID);
        _registerVerse(launcher, address(upt));

        IMemeverseLauncher.Memeverse memory verse = launcher.getMemeverseByVerseId(VERSE_ID);
        hook.setProtocolFeeCurrency(Currency.wrap(address(upt)));
        hook.setProtocolFeeCurrency(Currency.wrap(verse.memecoin));

        upt.mint(ALICE, 1_000 ether);
        upt.mint(BOB, 1_000 ether);
        upt.mint(CHARLIE, 1_000 ether);

        vm.prank(ALICE);
        upt.approve(address(launcher), type(uint256).max);
        vm.prank(BOB);
        upt.approve(address(launcher), type(uint256).max);
        vm.prank(CHARLIE);
        upt.approve(address(launcher), type(uint256).max);

        vm.prank(ALICE);
        launcher.genesis(VERSE_ID, 200 ether, ALICE);

        handler = new PreorderSuccessHandler(launcher, upt, actors);
        targetContract(address(handler));
    }

    /// @notice Test helper for invariant_genesisAccountingMatchesUserBalances.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function invariant_genesisAccountingMatchesUserBalances() external view {
        (uint128 totalMemecoinFunds, uint128 totalLiquidProofFunds) = launcher.genesisFunds(VERSE_ID);
        uint256 totalUserGenesisFunds;
        for (uint256 i; i < actors.length; ++i) {
            (uint256 genesisFund,,,) = launcher.userGenesisData(VERSE_ID, actors[i]);
            totalUserGenesisFunds += genesisFund;
        }
        assertEq(totalUserGenesisFunds, uint256(totalMemecoinFunds) + uint256(totalLiquidProofFunds), "genesis sum");
    }

    /// @notice Test helper for invariant_preorderCapacityNeverExceeded.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function invariant_preorderCapacityNeverExceeded() external view {
        (uint128 totalMemecoinFunds,) = launcher.genesisFunds(VERSE_ID);
        (uint256 totalFunds,,) = launcher.getPreorderStateForTest(VERSE_ID);
        uint256 maxCapacity = uint256(totalMemecoinFunds) * launcher.preorderCapRatio() / launcher.RATIO();

        assertLe(totalFunds, maxCapacity, "preorder cap");
        assertEq(totalFunds + launcher.previewPreorderCapacity(VERSE_ID), maxCapacity, "preorder capacity accounting");
    }

    /// @notice Test helper for invariant_claimsNeverExceedEntitlement.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function invariant_claimsNeverExceedEntitlement() external view {
        (uint256 totalFunds, uint256 settledMemecoin, uint40 settlementTimestamp) =
            launcher.getPreorderStateForTest(VERSE_ID);
        uint256 totalClaimed;

        for (uint256 i; i < actors.length; ++i) {
            (uint256 funds, uint256 claimedMemecoin,) = launcher.userPreorderData(VERSE_ID, actors[i]);
            uint256 purchasedMemecoin = totalFunds == 0 ? 0 : settledMemecoin * funds / totalFunds;
            assertLe(claimedMemecoin, purchasedMemecoin, "claimed exceeds entitlement");

            uint256 claimable = launcher.claimablePreorderMemecoinForTest(VERSE_ID, actors[i]);
            assertLe(claimable + claimedMemecoin, purchasedMemecoin, "unlocked exceeds entitlement");

            totalClaimed += claimedMemecoin;
        }

        IMemeverseLauncher.Memeverse memory verse = launcher.getMemeverseByVerseId(VERSE_ID);
        if (settlementTimestamp != 0 && launcher.getStageByVerseId(VERSE_ID) >= IMemeverseLauncher.Stage.Locked) {
            uint256 launcherMemecoinBalance = MockIntegrationMemecoin(verse.memecoin).balanceOf(address(launcher));
            assertGe(launcherMemecoinBalance + totalClaimed, settledMemecoin, "settled memecoin undercollateralized");
            if (handler.memecoinDustRecorded()) {
                assertEq(
                    launcherMemecoinBalance + totalClaimed,
                    settledMemecoin + handler.recordedMemecoinDust(),
                    "settled memecoin conservation"
                );
            }
        }
    }
}

contract MemeverseLauncherPreorderRefundInvariantTest is StdInvariant, MemeverseLauncherPreorderInvariantBase {
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant CHARLIE = address(0xCA11E);

    InspectableMemeverseLauncher internal launcher;
    MockLauncherIntegrationProxyDeployer internal proxyDeployer;
    MockLauncherIntegrationLzEndpointRegistry internal registry;
    MockERC20 internal upt;
    PreorderRefundHandler internal handler;

    /// @notice Test helper for setUp.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function setUp() external {
        _setActors(ALICE, BOB, CHARLIE);

        launcher = new InspectableMemeverseLauncher(
            address(this),
            address(0x1111),
            REGISTRAR,
            address(0),
            address(0x4444),
            address(0),
            25,
            115_000,
            135_000,
            2_500,
            7 days
        );
        proxyDeployer = new MockLauncherIntegrationProxyDeployer(address(0xD00D), address(0xCAFE), address(0xF00D));
        registry = new MockLauncherIntegrationLzEndpointRegistry();
        upt = new MockERC20("UPT", "UPT", 18);

        launcher.setMemeverseProxyDeployer(address(proxyDeployer));
        launcher.setLzEndpointRegistry(address(registry));
        launcher.setFundMetaData(address(upt), 10_000 ether, 4);

        registry.setEndpoint(REMOTE_GOV_CHAIN_ID, REMOTE_EID);
        _registerVerse(launcher, address(upt));

        upt.mint(ALICE, 1_000 ether);
        upt.mint(BOB, 1_000 ether);
        upt.mint(CHARLIE, 1_000 ether);

        vm.prank(ALICE);
        upt.approve(address(launcher), type(uint256).max);
        vm.prank(BOB);
        upt.approve(address(launcher), type(uint256).max);
        vm.prank(CHARLIE);
        upt.approve(address(launcher), type(uint256).max);

        handler = new PreorderRefundHandler(launcher, upt, actors);
        targetContract(address(handler));
    }

    /// @notice Test helper for invariant_refundPathKeepsGenesisAccountingExact.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function invariant_refundPathKeepsGenesisAccountingExact() external view {
        (uint128 totalMemecoinFunds, uint128 totalLiquidProofFunds) = launcher.genesisFunds(VERSE_ID);
        uint256 outstandingGenesis;
        uint256 outstandingPreorder;
        uint256 historicalGenesis;
        uint256 historicalPreorder;

        for (uint256 i; i < actors.length; ++i) {
            (uint256 genesisFund, bool isGenesisRefunded,,) = launcher.userGenesisData(VERSE_ID, actors[i]);
            (uint256 preorderFund,, bool isPreorderRefunded) = launcher.userPreorderData(VERSE_ID, actors[i]);

            historicalGenesis += genesisFund;
            historicalPreorder += preorderFund;
            if (!isGenesisRefunded) outstandingGenesis += genesisFund;
            if (!isPreorderRefunded) outstandingPreorder += preorderFund;
        }

        assertEq(historicalGenesis, uint256(totalMemecoinFunds) + uint256(totalLiquidProofFunds), "genesis history");
        (uint256 totalFunds,,) = launcher.getPreorderStateForTest(VERSE_ID);
        assertEq(historicalPreorder, totalFunds, "preorder history");
        assertEq(upt.balanceOf(address(launcher)), outstandingGenesis + outstandingPreorder, "refund conservation");
    }

    /// @notice Test helper for invariant_refundPathNeverSettlesPreorder.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function invariant_refundPathNeverSettlesPreorder() external view {
        IMemeverseLauncher.Stage stage = launcher.getStageByVerseId(VERSE_ID);
        assertTrue(
            stage == IMemeverseLauncher.Stage.Genesis || stage == IMemeverseLauncher.Stage.Refund, "unexpected stage"
        );

        (, uint256 settledMemecoin, uint40 settlementTimestamp) = launcher.getPreorderStateForTest(VERSE_ID);
        assertEq(settledMemecoin, 0, "refund path settled memecoin");
        assertEq(settlementTimestamp, 0, "refund path settlement timestamp");
    }

    /// @notice Test helper for invariant_refundPathStillRespectsPreorderCap.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function invariant_refundPathStillRespectsPreorderCap() external view {
        (uint128 totalMemecoinFunds,) = launcher.genesisFunds(VERSE_ID);
        (uint256 totalFunds,,) = launcher.getPreorderStateForTest(VERSE_ID);
        uint256 maxCapacity = uint256(totalMemecoinFunds) * launcher.preorderCapRatio() / launcher.RATIO();

        assertLe(totalFunds, maxCapacity, "refund preorder cap");
        assertEq(totalFunds + launcher.previewPreorderCapacity(VERSE_ID), maxCapacity, "refund preorder capacity");
    }
}
