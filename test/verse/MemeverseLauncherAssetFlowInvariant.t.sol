// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {IMemeverseLauncher} from "../../src/verse/interfaces/IMemeverseLauncher.sol";
import {
    MockLiquidProof,
    MockLzEndpointRegistry,
    MockOFTDispatcher,
    MockOFTToken,
    MockPredictOnlyProxyDeployer,
    MockSwapRouter,
    TestableMemeverseLauncher
} from "./MemeverseLauncherLifecycle.t.sol";

contract AssetFlowHandler is Test {
    uint256 internal constant VERSE_ID = 1;

    TestableMemeverseLauncher internal immutable launcher;
    MockLiquidProof internal immutable liquidProof;
    MockERC20 internal immutable memecoinLp;
    MockERC20 internal immutable polLp;
    address[] internal actors;

    constructor(
        TestableMemeverseLauncher _launcher,
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

    /// @notice Test helper for claimPOL.
    /// @param actorSeed See implementation.
    function claimPOL(uint256 actorSeed) external {
        address actor = actors[actorSeed % actors.length];
        vm.prank(actor);
        try launcher.claimPOLToken(VERSE_ID) {} catch {}
    }

    /// @notice Test helper for redeemPolLiquidity.
    /// @param actorSeed See implementation.
    function redeemPolLiquidity(uint256 actorSeed) external {
        address actor = actors[actorSeed % actors.length];
        vm.prank(actor);
        try launcher.redeemPolLiquidity(VERSE_ID) {} catch {}
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
        try launcher.redeemMemecoinLiquidity(VERSE_ID, amount) {} catch {}
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

    TestableMemeverseLauncher internal immutable launcher;
    uint256 public redeemCount;

    constructor(TestableMemeverseLauncher _launcher) {
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

contract MintPOLHandler is Test {
    uint256 internal constant VERSE_ID = 1;

    TestableMemeverseLauncher internal immutable launcher;
    MockSwapRouter internal immutable router;
    MockERC20 internal immutable upt;
    MockERC20 internal immutable memecoin;
    address[] internal actors;

    constructor(
        TestableMemeverseLauncher _launcher,
        MockSwapRouter _router,
        MockERC20 _upt,
        MockERC20 _memecoin,
        address[] memory _actors
    ) {
        launcher = _launcher;
        router = _router;
        upt = _upt;
        memecoin = _memecoin;
        actors = _actors;
    }

    /// @notice Test helper for mintAuto.
    /// @param actorSeed See implementation.
    /// @param uptDesiredSeed See implementation.
    /// @param memecoinDesiredSeed See implementation.
    /// @param liquiditySeed See implementation.
    function mintAuto(uint256 actorSeed, uint256 uptDesiredSeed, uint256 memecoinDesiredSeed, uint256 liquiditySeed)
        external
    {
        address actor = actors[actorSeed % actors.length];
        uint256 uptBalance = upt.balanceOf(actor);
        uint256 memecoinBalance = memecoin.balanceOf(actor);
        if (uptBalance == 0 || memecoinBalance == 0) return;

        uint256 uptDesired = bound(uptDesiredSeed, 1, uptBalance);
        uint256 memecoinDesired = bound(memecoinDesiredSeed, 1, memecoinBalance);
        uint128 liquidity = uint128(bound(liquiditySeed, 1, _min(uptDesired, memecoinDesired)));
        uint256 uptUsed = bound(uint256(liquiditySeed >> 16), 1, uptDesired);
        uint256 memecoinUsed = bound(uint256(liquiditySeed >> 48), 1, memecoinDesired);

        router.setAddLiquidityResult(address(upt), address(memecoin), liquidity, uptUsed, memecoinUsed);

        vm.prank(actor);
        try launcher.mintPOLToken(VERSE_ID, uptDesired, memecoinDesired, 0, 0, 0, block.timestamp) returns (
            uint256 amountInUPT, uint256 amountInMemecoin, uint256 amountOut
        ) {
            assertEq(amountInUPT, uptUsed, "auto upt used");
            assertEq(amountInMemecoin, memecoinUsed, "auto memecoin used");
            assertEq(amountOut, liquidity, "auto pol out");
        } catch {}
    }

    /// @notice Test helper for mintExact.
    /// @param actorSeed See implementation.
    /// @param uptDesiredSeed See implementation.
    /// @param memecoinDesiredSeed See implementation.
    /// @param amountOutSeed See implementation.
    /// @param uptRequiredSeed See implementation.
    /// @param memecoinRequiredSeed See implementation.
    function mintExact(
        uint256 actorSeed,
        uint256 uptDesiredSeed,
        uint256 memecoinDesiredSeed,
        uint256 amountOutSeed,
        uint256 uptRequiredSeed,
        uint256 memecoinRequiredSeed
    ) external {
        address actor = actors[actorSeed % actors.length];
        uint256 uptBalance = upt.balanceOf(actor);
        uint256 memecoinBalance = memecoin.balanceOf(actor);
        if (uptBalance == 0 || memecoinBalance == 0) return;

        uint256 uptDesired = bound(uptDesiredSeed, 1, uptBalance);
        uint256 memecoinDesired = bound(memecoinDesiredSeed, 1, memecoinBalance);
        uint128 amountOut = uint128(bound(amountOutSeed, 1, _min(uptDesired, memecoinDesired)));
        uint256 uptRequired = bound(uptRequiredSeed, 1, uptDesired);
        uint256 memecoinRequired = bound(memecoinRequiredSeed, 1, memecoinDesired);

        router.setQuoteAmountsForLiquidity(address(upt), address(memecoin), amountOut, uptRequired, memecoinRequired);
        router.setAddLiquidityResult(address(upt), address(memecoin), amountOut, uptRequired, memecoinRequired);

        vm.prank(actor);
        try launcher.mintPOLToken(VERSE_ID, uptDesired, memecoinDesired, 0, 0, amountOut, block.timestamp) returns (
            uint256 amountInUPT, uint256 amountInMemecoin, uint256 amountOutReceived
        ) {
            assertEq(amountInUPT, uptRequired, "exact upt used");
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

    TestableMemeverseLauncher internal immutable launcher;
    MockSwapRouter internal immutable router;
    MockOFTToken internal immutable remoteUpt;
    MockOFTToken internal immutable remoteMemecoin;
    address internal immutable liquidProof;

    uint256 public expectedUptSendCount;
    uint256 public expectedMemecoinSendCount;

    constructor(
        TestableMemeverseLauncher _launcher,
        MockSwapRouter _router,
        MockOFTToken _remoteUpt,
        MockOFTToken _remoteMemecoin,
        address _liquidProof
    ) {
        launcher = _launcher;
        router = _router;
        remoteUpt = _remoteUpt;
        remoteMemecoin = _remoteMemecoin;
        liquidProof = _liquidProof;
    }

    /// @notice Test helper for redeem.
    /// @param scenarioSeed See implementation.
    function redeem(uint256 scenarioSeed) external {
        uint256 scenario = scenarioSeed % 3;

        if (scenario == 0) {
            router.setClaimQuote(address(remoteMemecoin), address(remoteUpt), address(launcher), 9 ether, 4 ether);
            router.setClaimQuote(liquidProof, address(remoteUpt), address(launcher), 0, 6 ether);
        } else if (scenario == 1) {
            router.setClaimQuote(address(remoteMemecoin), address(remoteUpt), address(launcher), 9 ether, 0);
            router.setClaimQuote(liquidProof, address(remoteUpt), address(launcher), 0, 0);
        } else {
            router.setClaimQuote(address(remoteMemecoin), address(remoteUpt), address(launcher), 0, 5 ether);
            router.setClaimQuote(liquidProof, address(remoteUpt), address(launcher), 0, 0);
        }

        try launcher.redeemAndDistributeFees{value: 0.4 ether}(VERSE_ID, address(this)) returns (
            uint256 govFee, uint256 memecoinFee, uint256 liquidProofFee, uint256 executorReward
        ) {
            liquidProofFee;
            executorReward;
            if (govFee != 0) expectedUptSendCount++;
            if (memecoinFee != 0) expectedMemecoinSendCount++;
        } catch {}
    }
}

contract MemeverseLauncherClaimRedeemInvariantTest is StdInvariant, Test {
    uint256 internal constant VERSE_ID = 1;
    uint256 internal constant TOTAL_GENESIS = 120 ether;
    uint256 internal constant INITIAL_CLAIMABLE_POL = 60 ether;
    uint256 internal constant INITIAL_POL_LP = 90 ether;
    uint256 internal constant INITIAL_MEMECOIN_LP = 60 ether;

    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant CHARLIE = address(0xCA11E);

    TestableMemeverseLauncher internal launcher;
    MockSwapRouter internal router;
    MockOFTDispatcher internal dispatcher;
    MockPredictOnlyProxyDeployer internal proxyDeployer;
    MockLzEndpointRegistry internal registry;
    MockERC20 internal upt;
    MockERC20 internal memecoin;
    MockLiquidProof internal liquidProof;
    MockERC20 internal memecoinLp;
    MockERC20 internal polLp;

    address[] internal actors;
    AssetFlowHandler internal handler;

    /// @notice Test helper for setUp.
    function setUp() external {
        actors.push(ALICE);
        actors.push(BOB);
        actors.push(CHARLIE);

        launcher = new TestableMemeverseLauncher(
            address(this),
            address(0x1),
            address(0x2),
            address(0x3),
            address(0x4),
            address(0x5),
            25,
            115_000,
            135_000,
            2_500,
            7 days
        );
        router = new MockSwapRouter(address(launcher));
        dispatcher = new MockOFTDispatcher();
        upt = new MockERC20("UPT", "UPT", 18);
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
        verse.UPT = address(upt);
        verse.memecoin = address(memecoin);
        verse.liquidProof = address(liquidProof);
        verse.governor = address(0xCAFE);
        verse.yieldVault = address(0xD00D);
        verse.currentStage = IMemeverseLauncher.Stage.Unlocked;
        verse.omnichainIds = new uint32[](1);
        verse.omnichainIds[0] = uint32(block.chainid);
        launcher.setMemeverseForTest(VERSE_ID, verse);

        launcher.setGenesisFundForTest(VERSE_ID, 90 ether, 30 ether);
        launcher.setUserGenesisDataForTest(VERSE_ID, ALICE, 24 ether, false, false, false);
        launcher.setUserGenesisDataForTest(VERSE_ID, BOB, 36 ether, false, false, false);
        launcher.setUserGenesisDataForTest(VERSE_ID, CHARLIE, 60 ether, false, false, false);
        launcher.setTotalClaimablePOLForTest(VERSE_ID, INITIAL_CLAIMABLE_POL);
        launcher.setTotalPolLiquidityForTest(VERSE_ID, INITIAL_POL_LP);

        router.setLpToken(address(memecoin), address(upt), address(memecoinLp));
        router.setLpToken(address(liquidProof), address(upt), address(polLp));

        liquidProof.mint(address(launcher), INITIAL_CLAIMABLE_POL);
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
            (uint256 genesisFund,,, bool isRedeemed) = launcher.userGenesisData(VERSE_ID, actors[i]);
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

contract MemeverseLauncherFeeDistributionInvariantTest is StdInvariant, Test {
    uint256 internal constant VERSE_ID = 1;
    address internal constant REWARD_RECEIVER = address(0xBEEF);
    uint256 internal constant PER_CALL_MEMECOIN_FEE = 7 ether;
    uint256 internal constant PER_CALL_LIQUID_PROOF_FEE = 5 ether;
    uint256 internal constant PER_CALL_EXECUTOR_REWARD = 0.08 ether;
    uint256 internal constant PER_CALL_GOV_FEE = 31.92 ether;

    TestableMemeverseLauncher internal launcher;
    MockSwapRouter internal router;
    MockOFTDispatcher internal dispatcher;
    MockPredictOnlyProxyDeployer internal proxyDeployer;
    MockLzEndpointRegistry internal registry;
    MockERC20 internal upt;
    MockERC20 internal memecoin;
    MockLiquidProof internal liquidProof;
    FeeDistributionHandler internal handler;

    /// @notice Test helper for setUp.
    function setUp() external {
        launcher = new TestableMemeverseLauncher(
            address(this),
            address(0x1),
            address(0x2),
            address(0x3),
            address(0x4),
            address(0x5),
            25,
            115_000,
            135_000,
            2_500,
            7 days
        );
        router = new MockSwapRouter(address(launcher));
        dispatcher = new MockOFTDispatcher();
        upt = new MockERC20("UPT", "UPT", 18);
        memecoin = new MockERC20("MEME", "MEME", 18);
        liquidProof = new MockLiquidProof();
        proxyDeployer = new MockPredictOnlyProxyDeployer(address(0xD00D), address(0xCAFE), address(0xF00D));
        registry = new MockLzEndpointRegistry();

        launcher.setMemeverseUniswapHook(address(router.hook()));
        launcher.setMemeverseSwapRouter(address(router));
        launcher.setYieldDispatcher(address(dispatcher));
        launcher.setMemeverseProxyDeployer(address(proxyDeployer));
        launcher.setLzEndpointRegistry(address(registry));

        IMemeverseLauncher.Memeverse memory verse;
        verse.UPT = address(upt);
        verse.memecoin = address(memecoin);
        verse.liquidProof = address(liquidProof);
        verse.governor = address(0xCAFE);
        verse.yieldVault = address(0xD00D);
        verse.currentStage = IMemeverseLauncher.Stage.Locked;
        verse.omnichainIds = new uint32[](1);
        verse.omnichainIds[0] = uint32(block.chainid);
        launcher.setMemeverseForTest(VERSE_ID, verse);

        router.setClaimQuote(address(memecoin), address(upt), address(launcher), 20 ether, 7 ether);
        router.setClaimQuote(address(liquidProof), address(upt), address(launcher), 12 ether, 5 ether);

        handler = new FeeDistributionHandler(launcher);
        targetContract(address(handler));
    }

    /// @notice Test helper for invariant_feeDistributionLeavesNoResidualLauncherBalances.
    function invariant_feeDistributionLeavesNoResidualLauncherBalances() external view {
        assertEq(upt.balanceOf(address(launcher)), 0, "launcher upt");
        assertEq(memecoin.balanceOf(address(launcher)), 0, "launcher memecoin");
        assertEq(liquidProof.balanceOf(address(launcher)), 0, "launcher liquid proof");
    }

    /// @notice Test helper for invariant_feeDistributionMatchesPerCallAccounting.
    function invariant_feeDistributionMatchesPerCallAccounting() external view {
        uint256 count = handler.redeemCount();

        assertEq(upt.balanceOf(REWARD_RECEIVER), count * PER_CALL_EXECUTOR_REWARD, "reward receiver");
        assertEq(upt.balanceOf(address(dispatcher)), count * PER_CALL_GOV_FEE, "dispatcher upt");
        assertEq(memecoin.balanceOf(address(dispatcher)), count * PER_CALL_MEMECOIN_FEE, "dispatcher memecoin");
        assertEq(liquidProof.burnedAmount(), count * PER_CALL_LIQUID_PROOF_FEE, "liquid proof burn");
        assertEq(dispatcher.composeCallCount(), count * 2, "compose count");
    }
}

contract MemeverseLauncherMintPOLInvariantTest is StdInvariant, Test {
    uint256 internal constant VERSE_ID = 1;
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant CHARLIE = address(0xCA11E);
    uint256 internal constant INITIAL_USER_BALANCE = 1_000 ether;

    TestableMemeverseLauncher internal launcher;
    MockSwapRouter internal router;
    MockOFTDispatcher internal dispatcher;
    MockPredictOnlyProxyDeployer internal proxyDeployer;
    MockLzEndpointRegistry internal registry;
    MockERC20 internal upt;
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

        launcher = new TestableMemeverseLauncher(
            address(this),
            address(0x1),
            address(0x2),
            address(0x3),
            address(0x4),
            address(0x5),
            25,
            115_000,
            135_000,
            2_500,
            7 days
        );
        router = new MockSwapRouter(address(launcher));
        dispatcher = new MockOFTDispatcher();
        upt = new MockERC20("UPT", "UPT", 18);
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

        IMemeverseLauncher.Memeverse memory verse;
        verse.UPT = address(upt);
        verse.memecoin = address(memecoin);
        verse.liquidProof = address(liquidProof);
        verse.currentStage = IMemeverseLauncher.Stage.Locked;
        launcher.setMemeverseForTest(VERSE_ID, verse);

        router.setLpToken(address(memecoin), address(upt), address(memecoinLp));

        upt.mint(ALICE, INITIAL_USER_BALANCE);
        upt.mint(BOB, INITIAL_USER_BALANCE);
        upt.mint(CHARLIE, INITIAL_USER_BALANCE);
        memecoin.mint(ALICE, INITIAL_USER_BALANCE);
        memecoin.mint(BOB, INITIAL_USER_BALANCE);
        memecoin.mint(CHARLIE, INITIAL_USER_BALANCE);

        vm.startPrank(ALICE);
        upt.approve(address(launcher), type(uint256).max);
        memecoin.approve(address(launcher), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(BOB);
        upt.approve(address(launcher), type(uint256).max);
        memecoin.approve(address(launcher), type(uint256).max);
        vm.stopPrank();
        vm.startPrank(CHARLIE);
        upt.approve(address(launcher), type(uint256).max);
        memecoin.approve(address(launcher), type(uint256).max);
        vm.stopPrank();

        handler = new MintPOLHandler(launcher, router, upt, memecoin, actors);
        targetContract(address(handler));
    }

    /// @notice Test helper for invariant_mintPOL_ConservesUPTAndMemecoinAcrossUsersLauncherAndRouter.
    function invariant_mintPOL_ConservesUPTAndMemecoinAcrossUsersLauncherAndRouter() external view {
        uint256 totalUpt = upt.balanceOf(address(launcher)) + upt.balanceOf(address(router));
        uint256 totalMemecoin = memecoin.balanceOf(address(launcher)) + memecoin.balanceOf(address(router));

        for (uint256 i; i < actors.length; ++i) {
            totalUpt += upt.balanceOf(actors[i]);
            totalMemecoin += memecoin.balanceOf(actors[i]);
        }

        assertEq(totalUpt, INITIAL_USER_BALANCE * actors.length, "upt conservation");
        assertEq(totalMemecoin, INITIAL_USER_BALANCE * actors.length, "memecoin conservation");
    }

    /// @notice Test helper for invariant_mintPOL_LeavesNoResidualLauncherInputBalances.
    function invariant_mintPOL_LeavesNoResidualLauncherInputBalances() external view {
        assertEq(upt.balanceOf(address(launcher)), 0, "launcher upt");
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

contract MemeverseLauncherRemoteFeeInvariantTest is StdInvariant, Test {
    uint256 internal constant VERSE_ID = 1;

    TestableMemeverseLauncher internal launcher;
    MockSwapRouter internal router;
    MockOFTDispatcher internal dispatcher;
    MockPredictOnlyProxyDeployer internal proxyDeployer;
    MockLzEndpointRegistry internal registry;
    MockOFTToken internal remoteUpt;
    MockOFTToken internal remoteMemecoin;
    MockLiquidProof internal liquidProof;
    RemoteFeeDistributionHandler internal handler;

    /// @notice Test helper for setUp.
    function setUp() external {
        launcher = new TestableMemeverseLauncher(
            address(this),
            address(0x1),
            address(0x2),
            address(0x3),
            address(0x4),
            address(0x5),
            25,
            115_000,
            135_000,
            2_500,
            7 days
        );
        router = new MockSwapRouter(address(launcher));
        dispatcher = new MockOFTDispatcher();
        remoteUpt = new MockOFTToken("UPT", "UPT");
        remoteMemecoin = new MockOFTToken("MEME", "MEME");
        liquidProof = new MockLiquidProof();
        proxyDeployer = new MockPredictOnlyProxyDeployer(address(0xD00D), address(0xCAFE), address(0xF00D));
        registry = new MockLzEndpointRegistry();

        launcher.setMemeverseUniswapHook(address(router.hook()));
        launcher.setMemeverseSwapRouter(address(router));
        launcher.setYieldDispatcher(address(dispatcher));
        launcher.setMemeverseProxyDeployer(address(proxyDeployer));
        launcher.setLzEndpointRegistry(address(registry));

        IMemeverseLauncher.Memeverse memory verse;
        verse.UPT = address(remoteUpt);
        verse.memecoin = address(remoteMemecoin);
        verse.liquidProof = address(liquidProof);
        verse.governor = address(0xCAFE);
        verse.yieldVault = address(0xD00D);
        verse.currentStage = IMemeverseLauncher.Stage.Locked;
        verse.omnichainIds = new uint32[](1);
        verse.omnichainIds[0] = 202;
        launcher.setMemeverseForTest(VERSE_ID, verse);

        registry.setEndpoint(202, 302);
        remoteUpt.setQuoteFee(0.15 ether);
        remoteMemecoin.setQuoteFee(0.25 ether);

        handler = new RemoteFeeDistributionHandler(launcher, router, remoteUpt, remoteMemecoin, address(liquidProof));
        vm.deal(address(handler), 100 ether);

        targetContract(address(handler));
    }

    /// @notice Test helper for invariant_remoteFeeSendCountsMatchRedeemOutcomes.
    function invariant_remoteFeeSendCountsMatchRedeemOutcomes() external view {
        assertEq(remoteUpt.sendCallCount(), handler.expectedUptSendCount(), "upt send count");
        assertEq(remoteMemecoin.sendCallCount(), handler.expectedMemecoinSendCount(), "memecoin send count");
    }

    /// @notice Test helper for invariant_remoteFeeSendMetadataRemainsCorrect.
    function invariant_remoteFeeSendMetadataRemainsCorrect() external view {
        if (remoteUpt.sendCallCount() > 0) {
            assertEq(remoteUpt.lastSendDstEid(), 302, "upt dst eid");
            assertEq(remoteUpt.lastNativeFeePaid(), 0.15 ether, "upt native fee");
            assertEq(remoteUpt.lastRefundAddress(), address(handler), "upt refund address");
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
