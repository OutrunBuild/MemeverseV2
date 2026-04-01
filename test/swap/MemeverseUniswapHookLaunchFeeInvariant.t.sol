// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {IPoolManager, SwapParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {wadExp} from "solmate/utils/SignedWadMath.sol";

import {MemeverseSwapRouter} from "../../src/swap/MemeverseSwapRouter.sol";
import {IMemeverseUniswapHook} from "../../src/swap/interfaces/IMemeverseUniswapHook.sol";
import {MockPoolManagerForHookLiquidity, TestableMemeverseUniswapHook} from "./MemeverseUniswapHookLiquidity.t.sol";
import {MockPoolManagerForRouterTest, TestableMemeverseUniswapHookForRouter} from "./MemeverseSwapRouter.t.sol";

contract LaunchFeeQuoteHandler is Test {
    uint160 internal constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    TestableMemeverseUniswapHook internal immutable hook;
    PoolKey internal key;
    uint256 public lastObservedFeeBps;

    constructor(TestableMemeverseUniswapHook _hook, PoolKey memory _key) {
        hook = _hook;
        key = _key;
        lastObservedFeeBps = _currentQuoteFee();
    }

    /// @notice Test helper for warp.
    /// @param deltaSeed See implementation.
    function warp(uint256 deltaSeed) external {
        vm.warp(block.timestamp + bound(deltaSeed, 0, 30 minutes));

        uint256 currentFee = _currentQuoteFee();
        assertLe(currentFee, lastObservedFeeBps, "launch fee must not increase with time");
        lastObservedFeeBps = currentFee;
    }

    /// @notice Test helper for quoteVariants.
    /// @param amountSeed See implementation.
    function quoteVariants(uint256 amountSeed) external view {
        uint256 amount = bound(amountSeed, 1 ether, 10_000 ether);
        uint256 expectedFee = _currentQuoteFee();

        IMemeverseUniswapHook.SwapQuote memory zeroForOneExactInput =
            hook.quoteSwap(key, SwapParams({zeroForOne: true, amountSpecified: -int256(amount), sqrtPriceLimitX96: 0}));
        IMemeverseUniswapHook.SwapQuote memory zeroForOneExactOutput =
            hook.quoteSwap(key, SwapParams({zeroForOne: true, amountSpecified: int256(amount), sqrtPriceLimitX96: 0}));
        IMemeverseUniswapHook.SwapQuote memory oneForZeroExactInput = hook.quoteSwap(
            key, SwapParams({zeroForOne: false, amountSpecified: -int256(amount), sqrtPriceLimitX96: SQRT_PRICE_1_1})
        );
        IMemeverseUniswapHook.SwapQuote memory oneForZeroExactOutput = hook.quoteSwap(
            key, SwapParams({zeroForOne: false, amountSpecified: int256(amount), sqrtPriceLimitX96: SQRT_PRICE_1_1})
        );

        assertEq(zeroForOneExactInput.feeBps, expectedFee, "zfo exact-input fee");
        assertEq(zeroForOneExactOutput.feeBps, expectedFee, "zfo exact-output fee");
        assertEq(oneForZeroExactInput.feeBps, expectedFee, "ofz exact-input fee");
        assertEq(oneForZeroExactOutput.feeBps, expectedFee, "ofz exact-output fee");
    }

    function _currentQuoteFee() internal view returns (uint256 feeBps) {
        return
            hook.quoteSwap(key, SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}))
            .feeBps;
    }
}

contract LaunchSettlementHandler is Test {
    uint160 internal constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    MemeverseSwapRouter internal router;
    MockERC20 internal immutable token0;
    PoolKey internal key;
    address internal immutable treasury;

    uint256 public expectedTreasuryFee;
    uint256 public settlementSwapCount;

    constructor(MockERC20 _token0, PoolKey memory _key, address _treasury) {
        token0 = _token0;
        key = _key;
        treasury = _treasury;
    }

    /// @notice Test helper for setRouter.
    /// @param _router See implementation.
    function setRouter(MemeverseSwapRouter _router) external {
        require(address(router) == address(0), "router already set");
        router = _router;
        token0.approve(address(router), type(uint256).max);
    }

    /// @notice Test helper for warp.
    /// @param deltaSeed See implementation.
    function warp(uint256 deltaSeed) external {
        vm.warp(block.timestamp + bound(deltaSeed, 0, 30 minutes));
    }

    /// @notice Test helper for settlementSwap.
    /// @param amountSeed See implementation.
    function settlementSwap(uint256 amountSeed) external {
        uint256 balance = token0.balanceOf(address(this));
        if (balance == 0) return;

        uint256 amount = bound(amountSeed, 1 ether, _min(balance, 10_000 ether));
        uint160 priceLimit = uint160((uint256(SQRT_PRICE_1_1) * 99) / 100);

        BalanceDelta delta = router.swap(
            key,
            SwapParams({zeroForOne: true, amountSpecified: -int256(amount), sqrtPriceLimitX96: priceLimit}),
            address(this),
            block.timestamp,
            0,
            amount,
            bytes("public-swap")
        );

        assertLt(delta.amount0(), 0, "settlement delta0");
        assertGt(delta.amount1(), 0, "settlement delta1");

        expectedTreasuryFee += amount * 30 / 10_000;
        settlementSwapCount++;
        assertEq(token0.balanceOf(treasury), expectedTreasuryFee, "treasury fixed 1% protocol share");
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}

contract MemeverseUniswapHookLaunchFeeQuoteInvariantTest is StdInvariant, Test {
    using PoolIdLibrary for PoolKey;

    uint160 internal constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    MockPoolManagerForHookLiquidity internal manager;
    TestableMemeverseUniswapHook internal hook;
    MockERC20 internal token0;
    MockERC20 internal token1;
    PoolKey internal key;
    PoolId internal poolId;
    LaunchFeeQuoteHandler internal handler;

    /// @notice Test helper for setUp.
    function setUp() external {
        manager = new MockPoolManagerForHookLiquidity();
        token0 = new MockERC20("Token0", "TK0", 18);
        token1 = new MockERC20("Token1", "TK1", 18);
        hook = new TestableMemeverseUniswapHook(IPoolManager(address(manager)), address(this), address(this));

        key = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            fee: 0x800000,
            tickSpacing: 200,
            hooks: IHooks(address(hook))
        });
        poolId = key.toId();

        manager.initialize(key, SQRT_PRICE_1_1);
        hook.setProtocolFeeCurrency(key.currency0);

        handler = new LaunchFeeQuoteHandler(hook, key);
        targetContract(address(handler));
    }

    /// @notice Test helper for invariant_quoteFeeMatchesLaunchDecayFormula.
    function invariant_quoteFeeMatchesLaunchDecayFormula() external view {
        uint256 expectedFee = _expectedLaunchFee();

        IMemeverseUniswapHook.SwapQuote memory quote =
            hook.quoteSwap(key, SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}));

        assertEq(quote.feeBps, expectedFee, "launch quote mismatch");
        assertGe(quote.feeBps, 100, "fee below min");
        assertLe(quote.feeBps, 5000, "fee above start");
    }

    /// @notice Test helper for invariant_poolLaunchTimestampRemainsStable.
    function invariant_poolLaunchTimestampRemainsStable() external view {
        assertEq(hook.poolLaunchTimestamp(poolId), 1, "pool launch timestamp");
    }

    function _expectedLaunchFee() internal view returns (uint256 feeBps) {
        uint256 elapsed = block.timestamp > 1 ? block.timestamp - 1 : 0;
        if (elapsed >= 900) return 100;

        uint256 startFee = 5000;
        uint256 minFee = 100;
        int256 expAtElapsedWad = wadExp(-int256(elapsed * 4e18 / 900));
        int256 expAtEndWad = wadExp(-4e18);
        uint256 normalizedWad = uint256((expAtElapsedWad - expAtEndWad) * 1e18 / (1e18 - expAtEndWad));
        return minFee + (startFee - minFee) * normalizedWad / 1e18;
    }
}

contract MemeverseUniswapHookLaunchSettlementInvariantTest is StdInvariant, Test {
    using PoolIdLibrary for PoolKey;

    uint160 internal constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    MockPoolManagerForRouterTest internal manager;
    TestableMemeverseUniswapHookForRouter internal hook;
    MemeverseSwapRouter internal router;
    MockERC20 internal token0;
    MockERC20 internal token1;
    PoolKey internal key;
    address internal treasury;
    LaunchSettlementHandler internal handler;

    /// @notice Test helper for setUp.
    function setUp() external {
        manager = new MockPoolManagerForRouterTest();
        treasury = makeAddr("treasury");
        token0 = new MockERC20("Token0", "TK0", 18);
        token1 = new MockERC20("Token1", "TK1", 18);
        hook = new TestableMemeverseUniswapHookForRouter(IPoolManager(address(manager)), address(this), treasury);

        key = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            fee: 0x800000,
            tickSpacing: 200,
            hooks: IHooks(address(hook))
        });

        token0.mint(address(manager), 1_000_000 ether);
        token1.mint(address(manager), 1_000_000 ether);
        manager.initialize(key, SQRT_PRICE_1_1);
        hook.setProtocolFeeCurrency(key.currency0);

        handler = new LaunchSettlementHandler(token0, key, treasury);
        router = new MemeverseSwapRouter(
            IPoolManager(address(manager)), IMemeverseUniswapHook(address(hook)), IPermit2(address(0xBEEF))
        );
        handler.setRouter(router);
        token0.mint(address(handler), 1_000_000 ether);

        targetContract(address(handler));
    }

    /// @notice Test helper for invariant_launchSettlementAlwaysUsesFixedProtocolShare.
    function invariant_launchSettlementAlwaysUsesFixedProtocolShare() external view {
        assertEq(token0.balanceOf(treasury), handler.expectedTreasuryFee(), "treasury accounting");
    }

    /// @notice Test helper for invariant_publicQuoteNeverDropsBelowSettlementFeeFloor.
    function invariant_publicQuoteNeverDropsBelowSettlementFeeFloor() external view {
        IMemeverseUniswapHook.SwapQuote memory quote =
            hook.quoteSwap(key, SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}));
        assertGe(quote.feeBps, 100, "public fee floor");
    }
}
