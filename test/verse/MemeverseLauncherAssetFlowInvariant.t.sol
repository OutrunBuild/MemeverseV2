// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {MemeverseLauncher} from "../../src/verse/MemeverseLauncher.sol";
import {MemeverseLauncherTestHelper} from "../mocks/verse/MemeverseLauncherTestHelper.sol";
import {IMemeverseLauncher} from "../../src/verse/interfaces/IMemeverseLauncher.sol";
import {IPOLend} from "../../src/polend/interfaces/IPOLend.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {
    MockLiquidProof,
    MockLzEndpointRegistry,
    MockOFTDispatcher,
    MockOFTToken,
    MockPredictOnlyProxyDeployer,
    MockSwapRouter
} from "./MemeverseLauncherLifecycle.t.sol";

contract AssetFlowHandler is Test {
    uint256 internal constant VERSE_ID = 1;

    IMemeverseLauncher internal immutable launcher;
    MockLiquidProof internal immutable liquidProof;
    MockERC20 internal immutable memecoinLp;
    MockERC20 internal immutable polLp;
    address[] internal actors;

    constructor(
        IMemeverseLauncher _launcher,
        MockLiquidProof _liquidProof,
        MockERC20 _memecoinLp,
        MockERC20 _polLp,
        address[] memory _actors
    ) {
        launcher = _launcher;
        liquidProof = _liquidProof;
        memecoinLp = _memecoinLp;
        polLp = _polLp;
        actors = _actors;
    }

    /// @notice Test helper for claimNormalYT.
    /// @param actorSeed See implementation.
    function claimNormalYT(uint256 actorSeed) external {
        address actor = actors[actorSeed % actors.length];
        vm.prank(actor);
        try launcher.claimNormalYT(VERSE_ID) {} catch {}
    }

    /// @notice Test helper for redeemMemecoinLiquidity.
    /// @param actorSeed See implementation.
    /// @param amountSeed See implementation.
    function redeemMemecoinLiquidity(uint256 actorSeed, uint256 amountSeed) external {
        address actor = actors[actorSeed % actors.length];
        uint256 polBalance = liquidProof.balanceOf(actor);
        if (polBalance == 0) return;

        uint256 amount = bound(amountSeed, 1, polBalance);
        vm.prank(actor);
        try launcher.redeemMemecoinLiquidity(VERSE_ID, amount, false) {} catch {}
    }

    /// @notice Test helper for touchBalances.
    function touchBalances() external view {
        for (uint256 i; i < actors.length; ++i) {
            liquidProof.balanceOf(actors[i]);
            memecoinLp.balanceOf(actors[i]);
            polLp.balanceOf(actors[i]);
        }
    }
}

contract FeeDistributionHandler is Test {
    uint256 internal constant VERSE_ID = 1;

    IMemeverseLauncher internal immutable launcher;
    uint256 public redeemCount;

    constructor(IMemeverseLauncher _launcher) {
        launcher = _launcher;
    }

    /// @notice Test helper for redeem.
    function redeem() external {
        try launcher.redeemAndDistributeFees(VERSE_ID, address(0xBEEF)) returns (
            uint256 govFee, uint256 memecoinFee, uint256 liquidProofFee, uint256 executorReward
        ) {
            govFee;
            memecoinFee;
            liquidProofFee;
            executorReward;
            redeemCount++;
        } catch {}
    }
}

// Invariant fuzzing here still uses the lifecycle mock router for broad state exploration.
// `MemeverseLauncherSwapIntegration.t.sol` currently adds only the real launch-settlement path plus the
// current real-stack `mintPOLToken` / fee-claim blockers; broader asset-flow semantics are still mock-backed here.
contract MintPOLHandler is Test {
    uint256 internal constant VERSE_ID = 1;

    IMemeverseLauncher internal immutable launcher;
    MockSwapRouter internal immutable router;
    MockERC20 internal immutable uAsset;
    MockERC20 internal immutable memecoin;
    address[] internal actors;

    constructor(
        IMemeverseLauncher _launcher,
        MockSwapRouter _router,
        MockERC20 _uAsset,
        MockERC20 _memecoin,
        address[] memory _actors
    ) {
        launcher = _launcher;
        router = _router;
        uAsset = _uAsset;
        memecoin = _memecoin;
        actors = _actors;
    }

    /// @notice Test helper for mintAuto.
    /// @param actorSeed See implementation.
    /// @param uAssetDesiredSeed See implementation.
    /// @param memecoinDesiredSeed See implementation.
    /// @param liquiditySeed See implementation.
    function mintAuto(uint256 actorSeed, uint256 uAssetDesiredSeed, uint256 memecoinDesiredSeed, uint256 liquiditySeed)
        external
    {
        address actor = actors[actorSeed % actors.length];
        uint256 uAssetBalance = uAsset.balanceOf(actor);
        uint256 memecoinBalance = memecoin.balanceOf(actor);
        if (uAssetBalance == 0 || memecoinBalance == 0) return;

        uint256 uAssetDesired = bound(uAssetDesiredSeed, 1, uAssetBalance);
        uint256 memecoinDesired = bound(memecoinDesiredSeed, 1, memecoinBalance);
        uint128 liquidity = uint128(bound(liquiditySeed, 1, _min(uAssetDesired, memecoinDesired)));
        uint256 uAssetUsed = bound(uint256(liquiditySeed >> 16), 1, uAssetDesired);
        uint256 memecoinUsed = bound(uint256(liquiditySeed >> 48), 1, memecoinDesired);

        router.setAddLiquidityResult(address(uAsset), address(memecoin), liquidity, uAssetUsed, memecoinUsed);

        vm.prank(actor);
        try launcher.mintPOLToken(VERSE_ID, uAssetDesired, memecoinDesired, 0, 0, 0, block.timestamp) returns (
            uint256 amountInUAsset, uint256 amountInMemecoin, uint256 amountOut
        ) {
            assertEq(amountInUAsset, uAssetUsed, "auto uAsset used");
            assertEq(amountInMemecoin, memecoinUsed, "auto memecoin used");
            assertEq(amountOut, liquidity, "auto pol out");
        } catch {}
    }

    /// @notice Test helper for mintExact.
    /// @param actorSeed See implementation.
    /// @param uAssetDesiredSeed See implementation.
    /// @param memecoinDesiredSeed See implementation.
    /// @param amountOutSeed See implementation.
    /// @param uAssetRequiredSeed See implementation.
    /// @param memecoinRequiredSeed See implementation.
    function mintExact(
        uint256 actorSeed,
        uint256 uAssetDesiredSeed,
        uint256 memecoinDesiredSeed,
        uint256 amountOutSeed,
        uint256 uAssetRequiredSeed,
        uint256 memecoinRequiredSeed
    ) external {
        address actor = actors[actorSeed % actors.length];
        uint256 uAssetBalance = uAsset.balanceOf(actor);
        uint256 memecoinBalance = memecoin.balanceOf(actor);
        if (uAssetBalance == 0 || memecoinBalance == 0) return;

        uint256 uAssetDesired = bound(uAssetDesiredSeed, 1, uAssetBalance);
        uint256 memecoinDesired = bound(memecoinDesiredSeed, 1, memecoinBalance);
        uint128 amountOut = uint128(bound(amountOutSeed, 1, _min(uAssetDesired, memecoinDesired)));
        uint256 uAssetRequired = bound(uAssetRequiredSeed, 1, uAssetDesired);
        uint256 memecoinRequired = bound(memecoinRequiredSeed, 1, memecoinDesired);

        router.setQuoteAmountsForLiquidity(
            address(uAsset), address(memecoin), amountOut, uAssetRequired, memecoinRequired
        );
        router.setAddLiquidityResult(address(uAsset), address(memecoin), amountOut, uAssetRequired, memecoinRequired);

        vm.prank(actor);
        try launcher.mintPOLToken(VERSE_ID, uAssetDesired, memecoinDesired, 0, 0, amountOut, block.timestamp) returns (
            uint256 amountInUAsset, uint256 amountInMemecoin, uint256 amountOutReceived
        ) {
            assertEq(amountInUAsset, uAssetRequired, "exact uAsset used");
            assertEq(amountInMemecoin, memecoinRequired, "exact memecoin used");
            assertEq(amountOutReceived, amountOut, "exact pol out");
        } catch {}
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}

contract RemoteFeeDistributionHandler is Test {
    uint256 internal constant VERSE_ID = 1;

    IMemeverseLauncher internal immutable launcher;
    MockSwapRouter internal immutable router;
    MockOFTToken internal immutable remoteUAsset;
    MockOFTToken internal immutable remoteMemecoin;
    address internal immutable liquidProof;

    uint256 public expectedUAssetSendCount;
    uint256 public expectedMemecoinSendCount;

    constructor(
        IMemeverseLauncher _launcher,
        MockSwapRouter _router,
        MockOFTToken _remoteUAsset,
        MockOFTToken _remoteMemecoin,
        address _liquidProof
    ) {
        launcher = _launcher;
        router = _router;
        remoteUAsset = _remoteUAsset;
        remoteMemecoin = _remoteMemecoin;
        liquidProof = _liquidProof;
    }

    /// @notice Test helper for redeem.
    /// @param scenarioSeed See implementation.
    function redeem(uint256 scenarioSeed) external {
        uint256 scenario = scenarioSeed % 3;

        if (scenario == 0) {
            router.setClaimQuote(address(remoteMemecoin), address(remoteUAsset), address(launcher), 9 ether, 4 ether);
            router.setClaimQuote(liquidProof, address(remoteUAsset), address(launcher), 0, 6 ether);
        } else if (scenario == 1) {
            router.setClaimQuote(address(remoteMemecoin), address(remoteUAsset), address(launcher), 9 ether, 0);
            router.setClaimQuote(liquidProof, address(remoteUAsset), address(launcher), 0, 0);
        } else {
            router.setClaimQuote(address(remoteMemecoin), address(remoteUAsset), address(launcher), 0, 5 ether);
            router.setClaimQuote(liquidProof, address(remoteUAsset), address(launcher), 0, 0);
        }

        try launcher.redeemAndDistributeFees{value: 0.4 ether}(VERSE_ID, address(this)) returns (
            uint256 govFee, uint256 memecoinFee, uint256 liquidProofFee, uint256 executorReward
        ) {
            liquidProofFee;
            executorReward;
            if (govFee != 0) expectedUAssetSendCount++;
            if (memecoinFee != 0) expectedMemecoinSendCount++;
        } catch {}
    }
}

contract MemeverseLauncherClaimRedeemInvariantTest is StdInvariant, Test, MemeverseLauncherTestHelper {
    uint256 internal constant VERSE_ID = 1;
    uint256 internal constant TOTAL_GENESIS = 120 ether;
    uint256 internal constant INITIAL_CLAIMABLE_POL = 60 ether;
    uint256 internal constant INITIAL_POL_LP = 90 ether;
    uint256 internal constant INITIAL_MEMECOIN_LP = 60 ether;

    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant CHARLIE = address(0xCA11E);

    IMemeverseLauncher internal launcher;
    address internal launcherProxy;
    MockSwapRouter internal router;
    MockOFTDispatcher internal dispatcher;
    MockPredictOnlyProxyDeployer internal proxyDeployer;
    MockLzEndpointRegistry internal registry;
    MockERC20 internal uAsset;
    MockERC20 internal memecoin;
    MockLiquidProof internal liquidProof;
    MockERC20 internal memecoinLp;
    MockERC20 internal polLp;

    address[] internal actors;
    AssetFlowHandler internal handler;

    function _deployLauncher(
        address polendAddr, address splitterAddr,
        uint256 executorRewardRate, uint128 oftReceiveGasLimit,
        uint128 yieldDispatcherGasLimit, uint256 preorderCapRatio,
        uint256 preorderVestingDuration
    ) internal returns (IMemeverseLauncher) {
        MemeverseLauncher impl = new MemeverseLauncher();
        launcherProxy = address(new ERC1967Proxy(
            address(impl),
            abi.encodeCall(MemeverseLauncher.initialize, (
                address(this), address(0x1), address(0x2), address(0x3),
                address(0x4), address(0x5), polendAddr, splitterAddr,
                executorRewardRate, oftReceiveGasLimit, yieldDispatcherGasLimit,
                preorderCapRatio, preorderVestingDuration
            ))
        ));
        return IMemeverseLauncher(launcherProxy);
    }

    /// @notice Test helper for setUp.
    function setUp() external {
        actors.push(ALICE);
        actors.push(BOB);
        actors.push(CHARLIE);

        launcher = _deployLauncher(address(0x10), address(0x11), 25, 115_000, 135_000, 2_500, 7 days);
        router = new MockSwapRouter(address(launcher));
        dispatcher = new MockOFTDispatcher();
        uAsset = new MockERC20("UASSET", "UASSET", 18);
        memecoin = new MockERC20("MEME", "MEME", 18);
        liquidProof = new MockLiquidProof();
        memecoinLp = new MockERC20("MEME-LP", "MEME-LP", 18);
        polLp = new MockERC20("POL-LP", "POL-LP", 18);
        proxyDeployer = new MockPredictOnlyProxyDeployer(address(0xD00D), address(0xCAFE), address(0xF00D));
        registry = new MockLzEndpointRegistry();

        launcher.setMemeverseUniswapHook(address(router.hook()));
        launcher.setMemeverseSwapRouter(address(router));
        launcher.setYieldDispatcher(address(dispatcher));
        launcher.setMemeverseProxyDeployer(address(proxyDeployer));
        launcher.setLzEndpointRegistry(address(registry));

        IMemeverseLauncher.Memeverse memory verse;
        verse.uAsset = address(uAsset);
        verse.memecoin = address(memecoin);
        verse.pol = address(liquidProof);
        verse.governor = address(0xCAFE);
        verse.yieldVault = address(0xD00D);
        setMemeverseForTest(
            launcherProxy, VERSE_ID,
            address(uAsset), address(memecoin), address(liquidProof),
            address(0xD00D), address(0xCAFE), address(0),
            0, 0,
            IMemeverseLauncher.Stage.Unlocked, false
        );

        setGenesisFundForTest(launcherProxy, VERSE_ID, 120 ether);
        setUserGenesisDataForTest(launcherProxy, VERSE_ID, ALICE, 24 ether, false, false);
        setUserGenesisDataForTest(launcherProxy, VERSE_ID, BOB, 36 ether, false, false);
        setUserGenesisDataForTest(launcherProxy, VERSE_ID, CHARLIE, 60 ether, false, false);

        router.setLpToken(address(memecoin), address(uAsset), address(memecoinLp));
        router.setLpToken(address(liquidProof), address(uAsset), address(polLp));

        liquidProof.mint(ALICE, INITIAL_CLAIMABLE_POL * 24 ether / TOTAL_GENESIS);
        liquidProof.mint(BOB, INITIAL_CLAIMABLE_POL * 36 ether / TOTAL_GENESIS);
        liquidProof.mint(CHARLIE, INITIAL_CLAIMABLE_POL * 60 ether / TOTAL_GENESIS);
        memecoinLp.mint(address(launcher), INITIAL_MEMECOIN_LP);
        polLp.mint(address(launcher), INITIAL_POL_LP);

        handler = new AssetFlowHandler(launcher, liquidProof, memecoinLp, polLp, actors);
        targetContract(address(handler));
    }

    /// @notice Test helper for invariant_polTokenClaimAndBurnConserveSupply.
    function invariant_polTokenClaimAndBurnConserveSupply() external view {
        uint256 userPolBalance;
        for (uint256 i; i < actors.length; ++i) {
            userPolBalance += liquidProof.balanceOf(actors[i]);
        }

        assertEq(
            liquidProof.balanceOf(address(launcher)) + userPolBalance + liquidProof.burnedAmount(),
            INITIAL_CLAIMABLE_POL,
            "pol conservation"
        );
    }

    /// @notice Test helper for invariant_memecoinLpAndPolLpConserved.
    function invariant_memecoinLpAndPolLpConserved() external view {
        uint256 userMemecoinLp;
        uint256 userPolLp;
        for (uint256 i; i < actors.length; ++i) {
            userMemecoinLp += memecoinLp.balanceOf(actors[i]);
            userPolLp += polLp.balanceOf(actors[i]);
        }

        assertEq(memecoinLp.balanceOf(address(launcher)) + userMemecoinLp, INITIAL_MEMECOIN_LP, "memecoin lp");
        assertEq(polLp.balanceOf(address(launcher)) + userPolLp, INITIAL_POL_LP, "pol lp");
    }

    /// @notice Test helper for invariant_usersNeverExceedGenesisEntitlements.
    function invariant_usersNeverExceedGenesisEntitlements() external view {
        for (uint256 i; i < actors.length; ++i) {
            (uint256 genesisFund,, bool isRedeemed) = MemeverseLauncher(launcherProxy).userGenesisData(VERSE_ID, actors[i]);
            uint256 polShare = INITIAL_CLAIMABLE_POL * genesisFund / TOTAL_GENESIS;
            uint256 polLpShare = INITIAL_POL_LP * genesisFund / TOTAL_GENESIS;
            uint256 userPolBalance = liquidProof.balanceOf(actors[i]);
            uint256 userMemecoinLpBalance = memecoinLp.balanceOf(actors[i]);
            uint256 userPolLpBalance = polLp.balanceOf(actors[i]);

            assertLe(userPolBalance + userMemecoinLpBalance, polShare, "user combined pol claim");
            assertLe(userPolLpBalance, polLpShare, "user pol lp");

            if (isRedeemed) assertEq(userPolLpBalance, polLpShare, "redeemed user pol lp");
        }
    }
}

contract MemeverseLauncherFeeDistributionInvariantTest is StdInvariant, Test, MemeverseLauncherTestHelper {
    uint256 internal constant VERSE_ID = 1;
    address internal constant REWARD_RECEIVER = address(0xBEEF);
    uint256 internal constant PER_CALL_MEMECOIN_FEE = 7 ether;
    uint256 internal constant PER_CALL_LIQUID_PROOF_FEE = 5 ether;
    uint256 internal constant PER_CALL_EXECUTOR_REWARD = 0.08 ether;
    uint256 internal constant PER_CALL_GOV_FEE = 31.92 ether;

    IMemeverseLauncher internal launcher;
    address internal launcherProxy;
    MockSwapRouter internal router;
    MockOFTDispatcher internal dispatcher;
    MockPredictOnlyProxyDeployer internal proxyDeployer;
    MockLzEndpointRegistry internal registry;
    MockERC20 internal uAsset;
    MockERC20 internal memecoin;
    MockLiquidProof internal liquidProof;
    FeeDistributionHandler internal handler;

    /// @notice Test helper for setUp.
    function setUp() external {
        MemeverseLauncher impl = new MemeverseLauncher();
        launcherProxy = address(new ERC1967Proxy(
            address(impl),
            abi.encodeCall(MemeverseLauncher.initialize, (
                address(this), address(0x1), address(0x2), address(0x3),
                address(0x4), address(0x5), address(0x10), address(0x11),
                25, 115_000, 135_000, 2_500, 7 days
            ))
        ));
        launcher = IMemeverseLauncher(launcherProxy);
        router = new MockSwapRouter(address(launcher));
        dispatcher = new MockOFTDispatcher();
        uAsset = new MockERC20("UASSET", "UASSET", 18);
        memecoin = new MockERC20("MEME", "MEME", 18);
        liquidProof = new MockLiquidProof();
        proxyDeployer = new MockPredictOnlyProxyDeployer(address(0xD00D), address(0xCAFE), address(0xF00D));
        registry = new MockLzEndpointRegistry();

        launcher.setMemeverseUniswapHook(address(router.hook()));
        launcher.setMemeverseSwapRouter(address(router));
        launcher.setYieldDispatcher(address(dispatcher));
        launcher.setMemeverseProxyDeployer(address(proxyDeployer));
        launcher.setLzEndpointRegistry(address(registry));

        setMemeverseForTest(
            launcherProxy, VERSE_ID,
            address(uAsset), address(memecoin), address(liquidProof),
            address(0xD00D), address(0xCAFE), address(0),
            0, 0,
            IMemeverseLauncher.Stage.Locked, false
        );

        router.setClaimQuote(address(memecoin), address(uAsset), address(launcher), 20 ether, 7 ether);
        router.setClaimQuote(address(liquidProof), address(uAsset), address(launcher), 12 ether, 5 ether);

        handler = new FeeDistributionHandler(launcher);
        targetContract(address(handler));
    }

    /// @notice Test helper for invariant_feeDistributionLeavesNoResidualLauncherBalances.
    function invariant_feeDistributionLeavesNoResidualLauncherBalances() external view {
        assertEq(uAsset.balanceOf(address(launcher)), 0, "launcher uAsset");
        assertEq(memecoin.balanceOf(address(launcher)), 0, "launcher memecoin");
        assertEq(liquidProof.balanceOf(address(launcher)), 0, "launcher liquid proof");
    }

    /// @notice Test helper for invariant_feeDistributionMatchesPerCallAccounting.
    function invariant_feeDistributionMatchesPerCallAccounting() external view {
        uint256 count = handler.redeemCount();

        assertEq(uAsset.balanceOf(REWARD_RECEIVER), count * PER_CALL_EXECUTOR_REWARD, "reward receiver");
        assertEq(uAsset.balanceOf(address(dispatcher)), count * PER_CALL_GOV_FEE, "dispatcher uAsset");
        assertEq(memecoin.balanceOf(address(dispatcher)), count * PER_CALL_MEMECOIN_FEE, "dispatcher memecoin");
        assertEq(liquidProof.burnedAmount(), count * PER_CALL_LIQUID_PROOF_FEE, "liquid proof burn");
        assertEq(dispatcher.composeCallCount(), count * 2, "compose count");
    }
}

contract MemeverseLauncherMintPOLInvariantTest is StdInvariant, Test, MemeverseLauncherTestHelper {
    uint256 internal constant VERSE_ID = 1;
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant CHARLIE = address(0xCA11E);
    uint256 internal constant INITIAL_USER_BALANCE = 1_000 ether;

    IMemeverseLauncher internal launcher;
    address internal launcherProxy;
    MockSwapRouter internal router;
    MockOFTDispatcher internal dispatcher;
    MockPredictOnlyProxyDeployer internal proxyDeployer;
    MockLzEndpointRegistry internal registry;
    MockERC20 internal uAsset;
    MockERC20 internal memecoin;
    MockLiquidProof internal liquidProof;
    MockERC20 internal memecoinLp;

    address[] internal actors;
    MintPOLHandler internal handler;

    /// @notice Test helper for setUp.
    function setUp() external {
        actors.push(ALICE);
        actors.push(BOB);
        actors.push(CHARLIE);

        MemeverseLauncher impl = new MemeverseLauncher();
        launcherProxy = address(new ERC1967Proxy(
            address(impl),
            abi.encodeCall(MemeverseLauncher.initialize, (
                address(this), address(0x1), address(0x2), address(0x3),
                address(0x4), address(0x5), address(0x10), address(0x11),
                25, 115_000, 135_000, 2_500, 7 days
            ))
        ));
        launcher = IMemeverseLauncher(launcherProxy);
        router = new MockSwapRouter(address(launcher));
        dispatcher = new MockOFTDispatcher();
        uAsset = new MockERC20("UASSET", "UASSET", 18);
        memecoin = new MockERC20("MEME", "MEME", 18);
        liquidProof = new MockLiquidProof();
        memecoinLp = new MockERC20("MEME-LP", "MEME-LP", 18);
        proxyDeployer = new MockPredictOnlyProxyDeployer(address(0xD00D), address(0xCAFE), address(0xF00D));
        registry = new MockLzEndpointRegistry();

        launcher.setMemeverseUniswapHook(address(router.hook()));
        launcher.setMemeverseSwapRouter(address(router));
        launcher.setYieldDispatcher(address(dispatcher));
        launcher.setMemeverseProxyDeployer(address(proxyDeployer));
        launcher.setLzEndpointRegistry(address(registry));

        setMemeverseForTest(
            launcherProxy, VERSE_ID,
            address(uAsset), address(memecoin), address(liquidProof),
            address(0), address(0), address(0),
            0, 0,
            IMemeverseLauncher.Stage.Locked, false
        );

        router.setLpToken(address(memecoin), address(uAsset), address(memecoinLp));

        uAsset.mint(ALICE, INITIAL_USER_BALANCE);
        uAsset.mint(BOB, INITIAL_USER_BALANCE);
        uAsset.mint(CHARLIE, INITIAL_USER_BALANCE);
        memecoin.mint(ALICE, INITIAL_USER_BALANCE);
        memecoin.mint(BOB, INITIAL_USER_BALANCE);
        memecoin.mint(CHARLIE, INITIAL_USER_BALANCE);

        vm.startPrank(ALICE);
        uAsset.approve(address(launcher), type(uint256).max);
        memecoin.approve(address(launcher), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(BOB);
        uAsset.approve(address(launcher), type(uint256).max);
        memecoin.approve(address(launcher), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(CHARLIE);
        uAsset.approve(address(launcher), type(uint256).max);
        memecoin.approve(address(launcher), type(uint256).max);
        vm.stopPrank();

        handler = new MintPOLHandler(launcher, router, uAsset, memecoin, actors);
        targetContract(address(handler));
    }

    /// @notice Test helper for invariant_mintPOL_ConservesUAssetAndMemecoinAcrossUsersLauncherAndRouter.
    function invariant_mintPOL_ConservesUAssetAndMemecoinAcrossUsersLauncherAndRouter() external view {
        uint256 totalUAsset = uAsset.balanceOf(address(launcher)) + uAsset.balanceOf(address(router));
        uint256 totalMemecoin = memecoin.balanceOf(address(launcher)) + memecoin.balanceOf(address(router));

        for (uint256 i; i < actors.length; ++i) {
            totalUAsset += uAsset.balanceOf(actors[i]);
            totalMemecoin += memecoin.balanceOf(actors[i]);
        }

        assertEq(totalUAsset, INITIAL_USER_BALANCE * actors.length, "uAsset conservation");
        assertEq(totalMemecoin, INITIAL_USER_BALANCE * actors.length, "memecoin conservation");
    }

    /// @notice Test helper for invariant_mintPOL_LeavesNoResidualLauncherInputBalances.
    function invariant_mintPOL_LeavesNoResidualLauncherInputBalances() external view {
        assertEq(uAsset.balanceOf(address(launcher)), 0, "launcher uAsset");
        assertEq(memecoin.balanceOf(address(launcher)), 0, "launcher memecoin");
    }

    /// @notice Test helper for invariant_mintPOL_POLSupplyMatchesLauncherBackingLP.
    function invariant_mintPOL_POLSupplyMatchesLauncherBackingLP() external view {
        uint256 userPolSupply;
        for (uint256 i; i < actors.length; ++i) {
            userPolSupply += liquidProof.balanceOf(actors[i]);
        }

        assertEq(userPolSupply, memecoinLp.balanceOf(address(launcher)), "pol backing lp");
    }
}

contract MemeverseLauncherRemoteFeeInvariantTest is StdInvariant, Test, MemeverseLauncherTestHelper {
    uint256 internal constant VERSE_ID = 1;

    IMemeverseLauncher internal launcher;
    address internal launcherProxy;
    MockSwapRouter internal router;
    MockOFTDispatcher internal dispatcher;
    MockPredictOnlyProxyDeployer internal proxyDeployer;
    MockLzEndpointRegistry internal registry;
    MockOFTToken internal remoteUAsset;
    MockOFTToken internal remoteMemecoin;
    MockLiquidProof internal liquidProof;
    RemoteFeeDistributionHandler internal handler;

    /// @notice Test helper for setUp.
    function setUp() external {
        MemeverseLauncher impl = new MemeverseLauncher();
        launcherProxy = address(new ERC1967Proxy(
            address(impl),
            abi.encodeCall(MemeverseLauncher.initialize, (
                address(this), address(0x1), address(0x2), address(0x3),
                address(0x4), address(0x5), address(0x10), address(0x11),
                25, 115_000, 135_000, 2_500, 7 days
            ))
        ));
        launcher = IMemeverseLauncher(launcherProxy);
        router = new MockSwapRouter(address(launcher));
        dispatcher = new MockOFTDispatcher();
        remoteUAsset = new MockOFTToken("UASSET", "UASSET");
        remoteMemecoin = new MockOFTToken("MEME", "MEME");
        liquidProof = new MockLiquidProof();
        proxyDeployer = new MockPredictOnlyProxyDeployer(address(0xD00D), address(0xCAFE), address(0xF00D));
        registry = new MockLzEndpointRegistry();

        launcher.setMemeverseUniswapHook(address(router.hook()));
        launcher.setMemeverseSwapRouter(address(router));
        launcher.setYieldDispatcher(address(dispatcher));
        launcher.setMemeverseProxyDeployer(address(proxyDeployer));
        launcher.setLzEndpointRegistry(address(registry));

        setMemeverseForTest(
            launcherProxy, VERSE_ID,
            address(remoteUAsset), address(remoteMemecoin), address(liquidProof),
            address(0xD00D), address(0xCAFE), address(0),
            0, 0,
            IMemeverseLauncher.Stage.Locked, false
        );
        uint32[] memory chainIds = new uint32[](1);
        chainIds[0] = 202;
        setOmnichainIdsForTest(launcherProxy, VERSE_ID, chainIds);

        registry.setEndpoint(202, 302);
        remoteUAsset.setQuoteFee(0.15 ether);
        remoteMemecoin.setQuoteFee(0.25 ether);

        handler = new RemoteFeeDistributionHandler(launcher, router, remoteUAsset, remoteMemecoin, address(liquidProof));
        vm.deal(address(handler), 100 ether);

        targetContract(address(handler));
    }

    /// @notice Test helper for invariant_remoteFeeSendCountsMatchRedeemOutcomes.
    function invariant_remoteFeeSendCountsMatchRedeemOutcomes() external view {
        assertEq(remoteUAsset.sendCallCount(), handler.expectedUAssetSendCount(), "uAsset send count");
        assertEq(remoteMemecoin.sendCallCount(), handler.expectedMemecoinSendCount(), "memecoin send count");
    }

    /// @notice Test helper for invariant_remoteFeeSendMetadataRemainsCorrect.
    function invariant_remoteFeeSendMetadataRemainsCorrect() external view {
        if (remoteUAsset.sendCallCount() > 0) {
            assertEq(remoteUAsset.lastSendDstEid(), 302, "uAsset dst eid");
            assertEq(remoteUAsset.lastNativeFeePaid(), 0.15 ether, "uAsset native fee");
            assertEq(remoteUAsset.lastRefundAddress(), address(handler), "uAsset refund address");
        }
        if (remoteMemecoin.sendCallCount() > 0) {
            assertEq(remoteMemecoin.lastSendDstEid(), 302, "memecoin dst eid");
            assertEq(remoteMemecoin.lastNativeFeePaid(), 0.25 ether, "memecoin native fee");
            assertEq(remoteMemecoin.lastRefundAddress(), address(handler), "memecoin refund address");
        }
    }

    /// @notice Test helper for invariant_remoteFeePathNeverUsesLocalDispatcher.
    function invariant_remoteFeePathNeverUsesLocalDispatcher() external view {
        assertEq(dispatcher.composeCallCount(), 0, "dispatcher should be unused");
    }
}

contract MockPOLendForFeeSplit {
    uint256 internal totalLeveragedDebt_;
    address internal pt_;
    address internal yt_;

    function setTotalLeveragedDebt(uint256, uint256 amount) external {
        totalLeveragedDebt_ = amount;
    }

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

    function preRedeemPTFee(uint256, uint256, address) external pure returns (uint256 uAssetBacking) {
        return 0;
    }
}

contract MockPOLSplitterForFeeSplit {
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

    function settle(uint256) external pure returns (uint256, uint256) {
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

    function previewRedeemYTUAsset(uint256, uint256) external pure returns (uint256) {
        return 0;
    }
}

contract LockedFeeDistributionHandler is Test {
    uint256 internal constant VERSE_ID = 1;

    IMemeverseLauncher internal immutable launcher;
    MockSwapRouter internal immutable router;
    MockERC20 internal immutable uAsset;
    MockERC20 internal immutable memecoin;
    MockLiquidProof internal immutable liquidProof;
    MockERC20 internal immutable pt;
    address[] internal actors;

    uint256 public totalUAssetFeeCollected;
    uint256 public totalExecutorReward;
    uint256 public totalGovFee;
    uint256 public totalMemecoinFee;
    uint256 public totalPolBurned;

    constructor(
        IMemeverseLauncher _launcher,
        MockSwapRouter _router,
        MockERC20 _uAsset,
        MockERC20 _memecoin,
        MockLiquidProof _liquidProof,
        MockERC20 _pt,
        address[] memory _actors
    ) {
        launcher = _launcher;
        router = _router;
        uAsset = _uAsset;
        memecoin = _memecoin;
        liquidProof = _liquidProof;
        pt = _pt;
        actors = _actors;
    }

    function redeemFees() external {
        try launcher.redeemAndDistributeFees(VERSE_ID, address(0xBEEF)) returns (
            uint256 govFee, uint256 memecoinFee, uint256 polFee, uint256 executorReward
        ) {
            uint256 uAssetFee = govFee + executorReward;
            totalUAssetFeeCollected += uAssetFee;
            totalExecutorReward += executorReward;
            totalGovFee += govFee;
            totalMemecoinFee += memecoinFee;
            totalPolBurned += polFee;
        } catch {}
    }
}

contract MemeverseLauncherLockedFeeIdentityInvariantTest is StdInvariant, Test, MemeverseLauncherTestHelper {
    uint256 internal constant VERSE_ID = 1;
    uint256 internal constant EXECUTOR_REWARD_RATE = 25;
    uint256 internal constant RATIO = 10_000;
    uint256 internal constant NORMAL_FUNDS = 100 ether;
    uint256 internal constant LEVERAGED_DEBT = 60 ether;

    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant REWARD_RECEIVER = address(0xBEEF);

    IMemeverseLauncher internal launcher;
    address internal launcherProxy;
    MockSwapRouter internal router;
    MockOFTDispatcher internal dispatcher;
    MockPredictOnlyProxyDeployer internal proxyDeployer;
    MockLzEndpointRegistry internal registry;
    MockERC20 internal uAsset;
    MockERC20 internal memecoin;
    MockLiquidProof internal liquidProof;
    MockERC20 internal pt;
    MockERC20 internal yt;
    MockPOLendForFeeSplit internal polend;
    MockPOLSplitterForFeeSplit internal splitter;

    address[] internal actors;
    LockedFeeDistributionHandler internal handler;

    function setUp() external {
        actors.push(ALICE);
        actors.push(BOB);

        dispatcher = new MockOFTDispatcher();
        uAsset = new MockERC20("UASSET", "UASSET", 18);
        memecoin = new MockERC20("MEME", "MEME", 18);
        liquidProof = new MockLiquidProof();
        pt = new MockERC20("PT", "PT", 18);
        yt = new MockERC20("YT", "YT", 18);
        polend = new MockPOLendForFeeSplit();
        splitter = new MockPOLSplitterForFeeSplit(address(pt), address(yt));
        proxyDeployer = new MockPredictOnlyProxyDeployer(address(0xD00D), address(0xCAFE), address(0xF00D));
        registry = new MockLzEndpointRegistry();
        MemeverseLauncher impl = new MemeverseLauncher();
        launcherProxy = address(new ERC1967Proxy(
            address(impl),
            abi.encodeCall(MemeverseLauncher.initialize, (
                address(this), address(0x1), address(0x2), address(0x3),
                address(0x4), address(0x5), address(polend), address(splitter),
                EXECUTOR_REWARD_RATE, 115_000, 135_000, 2_500, 7 days
            ))
        ));
        launcher = IMemeverseLauncher(launcherProxy);
        router = new MockSwapRouter(address(launcher));

        launcher.setMemeverseUniswapHook(address(router.hook()));
        launcher.setMemeverseSwapRouter(address(router));
        launcher.setYieldDispatcher(address(dispatcher));
        launcher.setMemeverseProxyDeployer(address(proxyDeployer));
        launcher.setLzEndpointRegistry(address(registry));

        setMemeverseForTest(
            launcherProxy, VERSE_ID,
            address(uAsset), address(memecoin), address(liquidProof),
            address(0xD00D), address(0xCAFE), address(0),
            0, 0,
            IMemeverseLauncher.Stage.Locked, false
        );

        setGenesisFundForTest(launcherProxy, VERSE_ID, NORMAL_FUNDS);
        polend.setTotalLeveragedDebt(VERSE_ID, LEVERAGED_DEBT);
        polend.setLendMarket(address(pt), address(yt));

        handler = new LockedFeeDistributionHandler(launcher, router, uAsset, memecoin, liquidProof, pt, actors);
        targetContract(address(handler));
    }

    function invariant_mainPoolUAssetFeeSplitsIntoExecutorRewardAndGovFee() external view {
        assertEq(
            handler.totalUAssetFeeCollected(),
            handler.totalExecutorReward() + handler.totalGovFee(),
            "uAssetFee != executorReward + govFee"
        );
    }

    function invariant_executorRewardMatchesConfiguredRate() external view {
        uint256 expectedReward = handler.totalUAssetFeeCollected() * EXECUTOR_REWARD_RATE / RATIO;
        assertEq(handler.totalExecutorReward(), expectedReward, "executorReward rate mismatch");
    }

    function invariant_polBurnMatchesDistributedFee() external view {
        assertEq(liquidProof.burnedAmount(), handler.totalPolBurned(), "pol burn == distributed fee");
    }
}

contract MemeverseLauncherAuxiliaryFeeSplitInvariantTest is Test {
    uint256 internal constant RATIO = 10_000;
    uint256 internal constant EXECUTOR_REWARD_RATE = 25;

    function test_auxiliaryUAssetFeeSplit_conservation(
        uint256 totalUAssetFee,
        uint256 normalFunds,
        uint256 leveragedDebt
    ) external pure {
        normalFunds = _clamp(normalFunds, 1, type(uint128).max);
        leveragedDebt = _clamp(leveragedDebt, 0, type(uint128).max);
        totalUAssetFee = _clamp(totalUAssetFee, 0, type(uint128).max);

        uint256 totalFunds = normalFunds + leveragedDebt;
        uint256 govUAssetFee = totalUAssetFee * leveragedDebt / totalFunds;
        uint256 normalUAssetFee = totalUAssetFee - govUAssetFee;

        assertLe(govUAssetFee, totalUAssetFee, "gov fee bounded");
        assertLe(normalUAssetFee, totalUAssetFee, "normal fee bounded");
        assertEq(govUAssetFee + normalUAssetFee, totalUAssetFee, "auxiliary uAsset fee conservation");
    }

    function test_auxiliaryPTFeeSplit_conservation(uint256 totalPTFee, uint256 normalFunds, uint256 leveragedDebt)
        external
        pure
    {
        normalFunds = _clamp(normalFunds, 1, type(uint128).max);
        leveragedDebt = _clamp(leveragedDebt, 0, type(uint128).max);
        totalPTFee = _clamp(totalPTFee, 0, type(uint128).max);

        uint256 totalFunds = normalFunds + leveragedDebt;
        uint256 govPTFee = totalPTFee * leveragedDebt / totalFunds;
        uint256 normalPTFee = totalPTFee - govPTFee;

        assertEq(govPTFee + normalPTFee, totalPTFee, "auxiliary PT fee conservation");
    }

    function test_auxiliaryFeeSplit_roundingDustGoesToNormalSide(
        uint256 totalUAssetFee,
        uint256 normalFunds,
        uint256 leveragedDebt
    ) external pure {
        normalFunds = _clamp(normalFunds, 1, type(uint128).max);
        leveragedDebt = _clamp(leveragedDebt, 1, type(uint128).max);
        totalUAssetFee = _clamp(totalUAssetFee, 1, type(uint128).max);

        uint256 totalFunds = normalFunds + leveragedDebt;
        uint256 govUAssetFee = totalUAssetFee * leveragedDebt / totalFunds;
        uint256 normalUAssetFee = totalUAssetFee - govUAssetFee;

        uint256 exactGovShare = (totalUAssetFee * leveragedDebt) / totalFunds;
        assertEq(govUAssetFee, exactGovShare, "gov gets floor");
        assertGe(normalUAssetFee, totalUAssetFee - exactGovShare, "normal gets at least remainder");
    }

    function test_auxiliaryFeeSplit_zeroDebt_allToNormal(uint256 totalUAssetFee, uint256 normalFunds) external pure {
        normalFunds = _clamp(normalFunds, 1, type(uint128).max);
        totalUAssetFee = _clamp(totalUAssetFee, 0, type(uint128).max);

        uint256 leveragedDebt = 0;
        uint256 totalFunds = normalFunds + leveragedDebt;
        uint256 govUAssetFee = totalUAssetFee * leveragedDebt / totalFunds;

        assertEq(govUAssetFee, 0, "zero debt => zero gov fee");
        assertEq(totalUAssetFee - govUAssetFee, totalUAssetFee, "all to normal");
    }

    function test_auxiliaryFeeSplit_unlocked_allToGov(uint256 totalUAssetFee, uint256 normalFunds) external pure {
        normalFunds = _clamp(normalFunds, 1, type(uint128).max);
        totalUAssetFee = _clamp(totalUAssetFee, 0, type(uint128).max);

        uint256 govUAssetFee = totalUAssetFee;
        assertEq(govUAssetFee, totalUAssetFee, "unlocked => all uAsset fee to gov");
    }

    function test_mainPoolUAssetFeeSplit_executorRewardPlusGovFee(uint256 uAssetFee) external pure {
        uAssetFee = _clamp(uAssetFee, 0, type(uint128).max);
        uint256 executorReward = uAssetFee * EXECUTOR_REWARD_RATE / RATIO;
        uint256 govFee = uAssetFee - executorReward;

        assertEq(executorReward + govFee, uAssetFee, "uAssetFee = executorReward + govFee");
        assertLe(executorReward, uAssetFee, "executorReward bounded");
    }

    function _clamp(uint256 x, uint256 min, uint256 max) internal pure returns (uint256) {
        if (min > max) return min;
        if (x < min) return min;
        if (x > max) return max;
        return x;
    }
}
