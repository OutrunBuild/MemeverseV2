// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IPoolManager, SwapParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
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

contract PaddedQuoteRouterAdapter {
    using SafeERC20 for IERC20;

    MemeverseSwapRouter internal immutable realRouter;

    constructor(MemeverseSwapRouter realRouter_) {
        realRouter = realRouter_;
    }

    function hook() external view returns (address) {
        return address(realRouter.hook());
    }

    function lpToken(address tokenA, address tokenB) external view returns (address liquidityToken) {
        return realRouter.lpToken(tokenA, tokenB);
    }

    function quoteAmountsForLiquidity(address tokenA, address tokenB, uint128 liquidityDesired)
        external
        view
        returns (uint256 amountARequired, uint256 amountBRequired)
    {
        (amountARequired, amountBRequired) = realRouter.quoteAmountsForLiquidity(tokenA, tokenB, liquidityDesired);
        if (liquidityDesired != 0) {
            if (amountARequired != 0) ++amountARequired;
            if (amountBRequired != 0) ++amountBRequired;
        }
    }

    function quoteExactAmountsForLiquidity(address tokenA, address tokenB, uint128 liquidityDesired)
        external
        view
        returns (uint256 amountARequired, uint256 amountBRequired)
    {
        return realRouter.quoteExactAmountsForLiquidity(tokenA, tokenB, liquidityDesired);
    }

    function getHookPoolKey(address tokenA, address tokenB) external view returns (PoolKey memory key) {
        return realRouter.getHookPoolKey(tokenA, tokenB);
    }

    function addLiquidityDetailed(
        Currency currency0,
        Currency currency1,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        address to,
        uint256 deadline
    ) external returns (uint128 liquidity, uint256 amount0Used, uint256 amount1Used) {
        address token0 = Currency.unwrap(currency0);
        address token1 = Currency.unwrap(currency1);

        if (amount0Desired != 0) IERC20(token0).safeTransferFrom(msg.sender, address(this), amount0Desired);
        if (amount1Desired != 0) IERC20(token1).safeTransferFrom(msg.sender, address(this), amount1Desired);

        _approveIfNeeded(token0, amount0Desired);
        _approveIfNeeded(token1, amount1Desired);

        (liquidity, amount0Used, amount1Used) = realRouter.addLiquidityDetailed(
            currency0, currency1, amount0Desired, amount1Desired, amount0Min, amount1Min, to, deadline
        );

        if (amount0Desired > amount0Used) IERC20(token0).safeTransfer(msg.sender, amount0Desired - amount0Used);
        if (amount1Desired > amount1Used) IERC20(token1).safeTransfer(msg.sender, amount1Desired - amount1Used);
    }

    function _approveIfNeeded(address token, uint256 amount) internal {
        if (amount == 0) return;
        if (IERC20(token).allowance(address(this), address(realRouter)) < amount) {
            IERC20(token).forceApprove(address(realRouter), type(uint256).max);
        }
    }
}

contract MemeverseLauncherSwapIntegrationTest is Test {
    using PoolIdLibrary for PoolKey;

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

    function testMintPOLToken_RealRouterPath_MintsPOLWithExactLiquidity() external {
        IMemeverseLauncher.Memeverse memory verse = _lockVerseWithLiquidity();
        _claimUnlockedPreorderMemecoin(BOB);

        PaddedQuoteRouterAdapter paddedRouter = new PaddedQuoteRouterAdapter(router);
        launcher.setMemeverseSwapRouter(address(paddedRouter));

        address memecoinLp = paddedRouter.lpToken(verse.memecoin, verse.UPT);
        uint128 desiredLiquidity = 0.1 ether;
        (uint256 paddedUPT, uint256 paddedMemecoin) =
            paddedRouter.quoteAmountsForLiquidity(verse.UPT, verse.memecoin, desiredLiquidity);
        (uint256 uptBudget, uint256 memecoinBudget) =
            paddedRouter.quoteExactAmountsForLiquidity(verse.UPT, verse.memecoin, desiredLiquidity);
        assertLt(uptBudget, paddedUPT, "exact UPT quote below padded");
        assertLt(memecoinBudget, paddedMemecoin, "exact memecoin quote below padded");

        vm.prank(BOB);
        MockIntegrationMemecoin(verse.memecoin).approve(address(launcher), type(uint256).max);

        uint256 bobUPTBefore = upt.balanceOf(BOB);
        uint256 bobMemecoinBefore = MockIntegrationMemecoin(verse.memecoin).balanceOf(BOB);
        uint256 bobPolBefore = MockIntegrationLiquidProof(verse.pol).balanceOf(BOB);
        uint256 launcherLpBefore = MockERC20(memecoinLp).balanceOf(address(launcher));

        vm.prank(BOB);
        (uint256 amountInUPT, uint256 amountInMemecoin, uint256 amountOut) =
            launcher.mintPOLToken(VERSE_ID, uptBudget, memecoinBudget, 0, 0, desiredLiquidity, block.timestamp);

        assertLe(amountInUPT, uptBudget, "UPT spend bounded by budget");
        assertLe(amountInMemecoin, memecoinBudget, "memecoin spend bounded by budget");
        assertEq(amountOut, desiredLiquidity, "desired POL minted");
        assertEq(upt.balanceOf(BOB), bobUPTBefore - amountInUPT, "payer UPT debited");
        assertEq(
            MockIntegrationMemecoin(verse.memecoin).balanceOf(BOB),
            bobMemecoinBefore - amountInMemecoin,
            "payer memecoin debited"
        );
        assertEq(
            MockIntegrationLiquidProof(verse.pol).balanceOf(BOB),
            bobPolBefore + desiredLiquidity,
            "recipient POL minted"
        );
        assertEq(
            MockERC20(memecoinLp).balanceOf(address(launcher)),
            launcherLpBefore + desiredLiquidity,
            "launcher LP increased"
        );
    }

    function testMintPOLToken_RealRouterPath_MintsSmallExactLiquidity() external {
        IMemeverseLauncher.Memeverse memory verse = _lockVerseWithLiquidity();
        _claimUnlockedPreorderMemecoin(BOB);

        uint128 desiredLiquidity = 1;
        (uint256 quotedUPT, uint256 quotedMemecoin) =
            router.quoteAmountsForLiquidity(verse.UPT, verse.memecoin, desiredLiquidity);

        uint256 uptBudget = quotedUPT + 1;
        uint256 memecoinBudget = quotedMemecoin + 1;

        vm.prank(BOB);
        MockIntegrationMemecoin(verse.memecoin).approve(address(launcher), type(uint256).max);

        uint256 bobUPTBefore = upt.balanceOf(BOB);
        uint256 bobMemecoinBefore = MockIntegrationMemecoin(verse.memecoin).balanceOf(BOB);

        vm.prank(BOB);
        (uint256 amountInUPT, uint256 amountInMemecoin, uint256 amountOut) =
            launcher.mintPOLToken(VERSE_ID, uptBudget, memecoinBudget, 0, 0, desiredLiquidity, block.timestamp);

        assertEq(amountOut, desiredLiquidity, "small exact POL minted");
        assertLe(amountInUPT, uptBudget, "small UPT spend bounded by budget");
        assertLe(amountInMemecoin, memecoinBudget, "small memecoin spend bounded by budget");
        assertEq(upt.balanceOf(BOB), bobUPTBefore - amountInUPT, "small UPT debited");
        assertEq(
            MockIntegrationMemecoin(verse.memecoin).balanceOf(BOB),
            bobMemecoinBefore - amountInMemecoin,
            "small memecoin debited"
        );
    }

    function testMintPOLToken_RealRouterPath_RevertsWhenPriceMovesAfterExactLiquidityQuote() external {
        IMemeverseLauncher.Memeverse memory verse = _lockVerseWithLiquidity();
        _claimUnlockedPreorderMemecoin(BOB);

        uint128 desiredLiquidity = 0.1 ether;
        (uint256 quotedUPT, uint256 quotedMemecoin) =
            router.quoteExactAmountsForLiquidity(verse.UPT, verse.memecoin, desiredLiquidity);
        PoolKey memory key = router.getHookPoolKey(verse.UPT, verse.memecoin);
        (uint160 sqrtPriceX96,,,) = manager.getSlot0(key.toId());
        manager.setCallerSlot0OverrideX96(key.toId(), address(hook), uint160((uint256(sqrtPriceX96) * 120) / 100));

        vm.prank(BOB);
        MockIntegrationMemecoin(verse.memecoin).approve(address(launcher), type(uint256).max);

        vm.expectRevert(IMemeverseUniswapHook.TooMuchSlippage.selector);
        vm.prank(BOB);
        launcher.mintPOLToken(VERSE_ID, quotedUPT, quotedMemecoin, 0, 0, desiredLiquidity, block.timestamp);
    }

    function testMintPOLToken_RealRouterPath_AutoLiquiditySucceedsWhenUPTSortsAfterMemecoin() external {
        IMemeverseLauncher.Memeverse memory verse = _lockVerseWithLiquidity();
        _claimUnlockedPreorderMemecoin(BOB);

        assertGt(uint160(verse.UPT), uint160(verse.memecoin), "fixture locks UPT > memecoin");

        address memecoinLp = router.lpToken(verse.memecoin, verse.UPT);
        uint128 quotedLiquidity = 0.1 ether;
        (uint256 quotedUPT, uint256 quotedMemecoin) =
            router.quoteAmountsForLiquidity(verse.UPT, verse.memecoin, quotedLiquidity);
        uint256 uptBudget = quotedUPT;
        uint256 memecoinBudget = quotedMemecoin + 0.01 ether;

        vm.prank(BOB);
        MockIntegrationMemecoin(verse.memecoin).approve(address(launcher), type(uint256).max);

        uint256 bobUPTBefore = upt.balanceOf(BOB);
        uint256 bobMemecoinBefore = MockIntegrationMemecoin(verse.memecoin).balanceOf(BOB);
        uint256 bobPolBefore = MockIntegrationLiquidProof(verse.pol).balanceOf(BOB);
        uint256 launcherLpBefore = MockERC20(memecoinLp).balanceOf(address(launcher));

        vm.prank(BOB);
        (uint256 amountInUPT, uint256 amountInMemecoin, uint256 amountOut) =
            launcher.mintPOLToken(VERSE_ID, uptBudget, memecoinBudget, 0, 0, 0, block.timestamp);

        assertLe(amountInUPT, uptBudget, "UPT spend bounded by budget");
        assertLt(amountInMemecoin, memecoinBudget, "memecoin excess refunded");
        assertGt(amountOut, 0, "auto-liquidity minted POL");
        assertEq(upt.balanceOf(BOB), bobUPTBefore - amountInUPT, "auto path UPT debited");
        assertEq(
            MockIntegrationMemecoin(verse.memecoin).balanceOf(BOB),
            bobMemecoinBefore - amountInMemecoin,
            "auto path memecoin debited"
        );
        assertEq(
            MockIntegrationLiquidProof(verse.pol).balanceOf(BOB),
            bobPolBefore + amountOut,
            "auto path recipient POL minted"
        );
        assertEq(
            MockERC20(memecoinLp).balanceOf(address(launcher)),
            launcherLpBefore + amountOut,
            "auto path launcher LP increased"
        );
    }

    function testRedeemAndDistributeFees_RealRouterPath_ClaimsAndDistributesFees() external {
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

        (uint256 govFee, uint256 memecoinFee, uint256 polFee, uint256 executorReward) =
            launcher.redeemAndDistributeFees(VERSE_ID, REWARD_RECEIVER);

        assertEq(executorReward, expectedUPTFee * launcher.executorRewardRate() / launcher.RATIO(), "executor reward");
        assertEq(govFee, expectedUPTFee - executorReward, "governance fee");
        assertEq(memecoinFee, expectedMemecoinFee, "memecoin fee");
        assertEq(polFee, expectedPolFee, "pol fee");
        assertEq(upt.balanceOf(REWARD_RECEIVER), rewardReceiverUPTBefore + executorReward, "reward receiver paid");
        assertEq(upt.balanceOf(address(dispatcher)), dispatcherUPTBefore + govFee, "dispatcher UPT received gov fee");
        assertEq(
            MockIntegrationMemecoin(verse.memecoin).balanceOf(address(dispatcher)),
            dispatcherMemecoinBefore + expectedMemecoinFee,
            "dispatcher memecoin received yield fee"
        );
        assertEq(
            MockIntegrationLiquidProof(verse.pol).balanceOf(address(launcher)),
            launcherPolBefore,
            "launcher POL claim burned in place"
        );
        assertEq(dispatcher.composeCallCount(), composeCountBefore + 2, "compose count incremented");
        assertEq(upt.balanceOf(TREASURY), treasuryUPTBefore, "treasury UPT unchanged");
        assertEq(
            MockIntegrationMemecoin(verse.memecoin).balanceOf(TREASURY),
            treasuryMemecoinBefore,
            "treasury memecoin unchanged"
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
