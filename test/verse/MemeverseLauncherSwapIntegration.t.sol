// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {IPoolManager, SwapParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";

import {MemeverseSwapRouter} from "../../src/swap/MemeverseSwapRouter.sol";
import {IMemeverseUniswapHook} from "../../src/swap/interfaces/IMemeverseUniswapHook.sol";
import {IMemeverseLauncher} from "../../src/verse/interfaces/IMemeverseLauncher.sol";
import {
    RealisticSwapManagerHarness,
    TestableMemeverseUniswapHookForIntegration
} from "../swap/helpers/RealisticSwapManagerHarness.sol";
import {MockOFTDispatcher, TestableMemeverseLauncher} from "./MemeverseLauncherLifecycle.t.sol";
import {
    MockIntegrationLiquidProof,
    MockIntegrationMemecoin,
    MockLauncherIntegrationLzEndpointRegistry
} from "./MemeverseLauncherPreorderIntegration.t.sol";

contract MockLauncherSwapIntegrationYieldVault {
    string public name;
    string public symbol;
    address public yieldDispatcher;
    address public asset;
    uint256 public verseId;

    function initialize(
        string calldata name_,
        string calldata symbol_,
        address yieldDispatcher_,
        address asset_,
        uint256 verseId_
    ) external {
        name = name_;
        symbol = symbol_;
        yieldDispatcher = yieldDispatcher_;
        asset = asset_;
        verseId = verseId_;
    }
}

contract MockLauncherSwapIntegrationProxyDeployer {
    address internal immutable predictedGovernor;
    address internal immutable predictedIncentivizer;

    constructor(address _predictedGovernor, address _predictedIncentivizer) {
        predictedGovernor = _predictedGovernor;
        predictedIncentivizer = _predictedIncentivizer;
    }

    function deployMemecoin(uint256 uniqueId) external returns (address memecoin) {
        uniqueId;
        memecoin = address(new MockIntegrationMemecoin());
    }

    function deployPOL(uint256 uniqueId) external returns (address pol) {
        uniqueId;
        pol = address(new MockIntegrationLiquidProof());
    }

    function deployYieldVault(uint256 uniqueId) external returns (address yieldVault) {
        uniqueId;
        yieldVault = address(new MockLauncherSwapIntegrationYieldVault());
    }

    function deployGovernorAndIncentivizer(
        string calldata memecoinName,
        address UPT,
        address memecoin,
        address pol,
        address yieldVault,
        uint256 uniqueId,
        uint256 proposalThreshold
    ) external view returns (address governor, address incentivizer) {
        memecoinName;
        UPT;
        memecoin;
        pol;
        yieldVault;
        uniqueId;
        proposalThreshold;
        return (predictedGovernor, predictedIncentivizer);
    }

    function predictYieldVaultAddress(uint256 uniqueId) external pure returns (address yieldVault) {
        uniqueId;
        return address(0);
    }

    function computeGovernorAndIncentivizerAddress(uint256 uniqueId)
        external
        view
        returns (address governor, address incentivizer)
    {
        uniqueId;
        return (predictedGovernor, predictedIncentivizer);
    }

    function quorumNumerator() external pure returns (uint256) {
        return 25;
    }
}

contract MemeverseLauncherSwapIntegrationTest is Test {
    uint256 internal constant VERSE_ID = 1;
    address internal constant REGISTRAR = address(0xBEEF);
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant TREASURY = address(0x7EA5);
    address internal constant REWARD_RECEIVER = address(0xCAFE);

    RealisticSwapManagerHarness internal manager;
    TestableMemeverseUniswapHookForIntegration internal hook;
    MemeverseSwapRouter internal router;
    TestableMemeverseLauncher internal launcher;
    MockLauncherSwapIntegrationProxyDeployer internal proxyDeployer;
    MockLauncherIntegrationLzEndpointRegistry internal registry;
    MockOFTDispatcher internal dispatcher;
    MockERC20 internal upt;

    function setUp() external {
        manager = new RealisticSwapManagerHarness();
        launcher = new TestableMemeverseLauncher(
            address(this),
            address(0x1111),
            REGISTRAR,
            address(0),
            address(0),
            address(0),
            25,
            115_000,
            135_000,
            2_500,
            7 days
        );
        hook = new TestableMemeverseUniswapHookForIntegration(IPoolManager(address(manager)), address(this), TREASURY);
        router = new MemeverseSwapRouter(
            IPoolManager(address(manager)), IMemeverseUniswapHook(address(hook)), IPermit2(address(0))
        );
        proxyDeployer = new MockLauncherSwapIntegrationProxyDeployer(address(0xCAFE), address(0xF00D));
        registry = new MockLauncherIntegrationLzEndpointRegistry();
        dispatcher = new MockOFTDispatcher();
        upt = new MockERC20("UPT", "UPT", 18);

        hook.setLauncher(address(launcher));

        launcher.setMemeverseUniswapHook(address(hook));
        launcher.setMemeverseSwapRouter(address(router));
        launcher.setMemeverseProxyDeployer(address(proxyDeployer));
        launcher.setLzEndpointRegistry(address(registry));
        launcher.setYieldDispatcher(address(dispatcher));
        launcher.setFundMetaData(address(upt), 100 ether, 4);

        uint32[] memory omnichainIds = new uint32[](1);
        omnichainIds[0] = uint32(block.chainid);
        vm.prank(REGISTRAR);
        launcher.registerMemeverse(
            "Memeverse",
            "MEME",
            VERSE_ID,
            uint128(block.timestamp + 30 days),
            uint128(block.timestamp + 60 days),
            omnichainIds,
            address(upt),
            true
        );

        IMemeverseLauncher.Memeverse memory verse = launcher.getMemeverseByVerseId(VERSE_ID);
        hook.setProtocolFeeCurrency(Currency.wrap(address(upt)));
        hook.setProtocolFeeCurrency(Currency.wrap(verse.memecoin));
        hook.setProtocolFeeCurrency(Currency.wrap(verse.pol));

        upt.mint(ALICE, 250 ether);
        upt.mint(BOB, 100 ether);

        vm.prank(ALICE);
        upt.approve(address(launcher), type(uint256).max);
        vm.prank(BOB);
        upt.approve(address(launcher), type(uint256).max);
    }

    function testExecuteLaunchSettlement_RealRouterHookManagerPath() external {
        IMemeverseLauncher.Memeverse memory verse = _lockVerseWithLiquidity();

        (uint256 totalFunds, uint256 settledMemecoin, uint40 settlementTimestamp) =
            launcher.getPreorderStateForTest(VERSE_ID);

        assertEq(uint256(launcher.getStageByVerseId(VERSE_ID)), uint256(IMemeverseLauncher.Stage.Locked), "stage");
        assertEq(totalFunds, 30 ether, "preorder total funds");
        assertEq(settlementTimestamp, block.timestamp, "settlement timestamp");
        assertGt(settledMemecoin, 0, "settled memecoin");
        uint256 launcherMemecoinBalance = MockIntegrationMemecoin(verse.memecoin).balanceOf(address(launcher));
        assertGe(launcherMemecoinBalance, settledMemecoin, "launcher received settlement output");
        assertLe(launcherMemecoinBalance - settledMemecoin, 1, "launcher memecoin dust bounded");
        assertGt(upt.balanceOf(TREASURY), 0, "treasury received launch protocol fee");

        vm.warp(block.timestamp + 7 days + 1);
        vm.prank(ALICE);
        uint256 aliceClaimed = launcher.claimUnlockedPreorderMemecoin(VERSE_ID);
        vm.prank(BOB);
        uint256 bobClaimed = launcher.claimUnlockedPreorderMemecoin(VERSE_ID);

        uint256 launcherMemecoinAfterClaims = MockIntegrationMemecoin(verse.memecoin).balanceOf(address(launcher));
        assertEq(
            aliceClaimed + bobClaimed + launcherMemecoinAfterClaims,
            launcherMemecoinBalance,
            "settlement assets conserved through claims"
        );
        assertEq(
            launcherMemecoinAfterClaims,
            launcherMemecoinBalance - aliceClaimed - bobClaimed,
            "launcher retained only preexisting dust"
        );
    }

    function testMintPOLToken_RealRouterPath_BlocksOnUnsortedLauncherInputs() external {
        IMemeverseLauncher.Memeverse memory verse = _lockVerseWithLiquidity();
        _claimUnlockedPreorderMemecoin(BOB);

        address memecoinLp = router.lpToken(verse.memecoin, verse.UPT);
        uint128 desiredLiquidity = 0.1 ether;
        (uint256 quotedUPT, uint256 quotedMemecoin) =
            router.quoteAmountsForLiquidity(verse.UPT, verse.memecoin, desiredLiquidity);
        uint256 uptBudget = quotedUPT + 0.01 ether;
        uint256 memecoinBudget = quotedMemecoin + 0.01 ether;

        vm.prank(BOB);
        MockIntegrationMemecoin(verse.memecoin).approve(address(launcher), type(uint256).max);

        uint256 bobUPTBefore = upt.balanceOf(BOB);
        uint256 bobMemecoinBefore = MockIntegrationMemecoin(verse.memecoin).balanceOf(BOB);
        uint256 bobPolBefore = MockIntegrationLiquidProof(verse.pol).balanceOf(BOB);
        uint256 launcherLpBefore = MockERC20(memecoinLp).balanceOf(address(launcher));

        vm.prank(BOB);
        vm.expectRevert(IMemeverseUniswapHook.PoolNotInitialized.selector);
        launcher.mintPOLToken(VERSE_ID, uptBudget, memecoinBudget, 0, 0, desiredLiquidity, block.timestamp);

        assertEq(upt.balanceOf(BOB), bobUPTBefore, "payer UPT rolled back");
        assertEq(
            MockIntegrationMemecoin(verse.memecoin).balanceOf(BOB), bobMemecoinBefore, "payer memecoin rolled back"
        );
        assertEq(MockIntegrationLiquidProof(verse.pol).balanceOf(BOB), bobPolBefore, "recipient POL unchanged");
        assertEq(MockERC20(memecoinLp).balanceOf(address(launcher)), launcherLpBefore, "launcher LP unchanged");
    }

    function testRedeemAndDistributeFees_RealRouterPath_BlocksOnClaimSignature() external {
        IMemeverseLauncher.Memeverse memory verse = _lockVerseWithLiquidity();
        _claimUnlockedPreorderMemecoin(ALICE);
        _claimUnlockedPreorderMemecoin(BOB);

        vm.prank(ALICE);
        launcher.claimPOLToken(VERSE_ID);

        _approveRouter(ALICE, verse.memecoin);
        _approveRouter(ALICE, verse.pol);
        _approveRouter(ALICE, verse.UPT);
        _approveRouter(BOB, verse.memecoin);
        _approveRouter(BOB, verse.UPT);

        _swapExactInput(BOB, verse.memecoin, verse.UPT, 1 ether);
        _swapExactInput(BOB, verse.UPT, verse.pol, 1 ether);
        _swapExactInput(ALICE, verse.pol, verse.UPT, 1 ether);

        (uint256 memecoinFeeFromMemecoinPair, uint256 uptFeeFromMemecoinPair) =
            router.previewClaimableFees(verse.memecoin, verse.UPT, address(launcher));
        (uint256 polFeeFromPolPair, uint256 uptFeeFromPolPair) =
            router.previewClaimableFees(verse.pol, verse.UPT, address(launcher));
        uint256 expectedUPTFee = uptFeeFromMemecoinPair + uptFeeFromPolPair;
        uint256 expectedMemecoinFee = memecoinFeeFromMemecoinPair;
        uint256 expectedPolFee = polFeeFromPolPair;
        assertGt(expectedUPTFee, 0, "previewed UPT fee");
        assertGt(expectedMemecoinFee, 0, "previewed memecoin fee");
        assertGt(expectedPolFee, 0, "previewed POL fee");

        uint256 treasuryUPTBefore = upt.balanceOf(TREASURY);
        uint256 treasuryMemecoinBefore = MockIntegrationMemecoin(verse.memecoin).balanceOf(TREASURY);
        uint256 treasuryPolBefore = MockIntegrationLiquidProof(verse.pol).balanceOf(TREASURY);
        uint256 rewardReceiverUPTBefore = upt.balanceOf(REWARD_RECEIVER);
        uint256 dispatcherUPTBefore = upt.balanceOf(address(dispatcher));
        uint256 dispatcherMemecoinBefore = MockIntegrationMemecoin(verse.memecoin).balanceOf(address(dispatcher));
        uint256 launcherPolBefore = MockIntegrationLiquidProof(verse.pol).balanceOf(address(launcher));
        uint256 composeCountBefore = dispatcher.composeCallCount();

        vm.expectRevert(IMemeverseUniswapHook.InvalidClaimSignature.selector);
        launcher.redeemAndDistributeFees(VERSE_ID, REWARD_RECEIVER);

        assertEq(upt.balanceOf(REWARD_RECEIVER), rewardReceiverUPTBefore, "reward receiver unchanged");
        assertEq(upt.balanceOf(address(dispatcher)), dispatcherUPTBefore, "dispatcher UPT unchanged");
        assertEq(
            MockIntegrationMemecoin(verse.memecoin).balanceOf(address(dispatcher)),
            dispatcherMemecoinBefore,
            "dispatcher memecoin unchanged"
        );
        assertEq(
            MockIntegrationLiquidProof(verse.pol).balanceOf(address(launcher)),
            launcherPolBefore,
            "launcher POL unchanged"
        );
        assertEq(dispatcher.composeCallCount(), composeCountBefore, "compose count unchanged");
        assertEq(upt.balanceOf(TREASURY), treasuryUPTBefore, "treasury UPT unchanged on revert");
        assertEq(
            MockIntegrationMemecoin(verse.memecoin).balanceOf(TREASURY),
            treasuryMemecoinBefore,
            "treasury memecoin unchanged on revert"
        );
        assertEq(MockIntegrationLiquidProof(verse.pol).balanceOf(TREASURY), treasuryPolBefore, "treasury POL unchanged");
    }

    function _lockVerseWithLiquidity() internal returns (IMemeverseLauncher.Memeverse memory verse) {
        vm.prank(ALICE);
        launcher.genesis(VERSE_ID, 200 ether, ALICE);

        vm.prank(ALICE);
        launcher.preorder(VERSE_ID, 10 ether, ALICE);
        vm.prank(BOB);
        launcher.preorder(VERSE_ID, 20 ether, BOB);

        launcher.changeStage(VERSE_ID);
        verse = launcher.getMemeverseByVerseId(VERSE_ID);
    }

    function _claimUnlockedPreorderMemecoin(address account) internal {
        vm.warp(block.timestamp + 7 days + 1);
        vm.prank(account);
        launcher.claimUnlockedPreorderMemecoin(VERSE_ID);
    }

    function _approveRouter(address owner, address token) internal {
        vm.prank(owner);
        MockERC20(token).approve(address(router), type(uint256).max);
    }

    function _swapExactInput(address trader, address tokenIn, address tokenOut, uint256 amountIn) internal {
        PoolKey memory key = router.getHookPoolKey(tokenIn, tokenOut);
        bool zeroForOne = Currency.unwrap(key.currency0) == tokenIn;
        uint160 sqrtPriceLimitX96 = zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;

        vm.prank(trader);
        router.swap(
            key,
            SwapParams({
                zeroForOne: zeroForOne, amountSpecified: -int256(amountIn), sqrtPriceLimitX96: sqrtPriceLimitX96
            }),
            trader,
            block.timestamp,
            0,
            amountIn,
            ""
        );
    }
}
