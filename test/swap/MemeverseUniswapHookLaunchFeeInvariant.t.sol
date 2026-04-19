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
import {wadExp} from "solmate/utils/SignedWadMath.sol";

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

contract DirectLaunchSettlementHandler is Test {
    uint160 internal constant SQRT_PRICE_1_1 = 79228162514264337593543950336;
    uint256 internal constant MAX_SWAP_AMOUNT = 10_000 ether;
    uint256 internal constant PROTOCOL_FEE_BPS = 30;
    uint256 internal constant LP_FEE_BPS = 70;
    uint256 internal constant BPS_BASE = 10_000;
    TestableMemeverseUniswapHookForRouter internal immutable hook;
    address internal immutable owner;
    address public immutable settlementRecipient;
    MockERC20 internal immutable token0;
    MockERC20 internal immutable token1;
    PoolKey internal key;

    uint256 public expectedTreasuryCurrency0Fee;
    uint256 public expectedTreasuryCurrency1Fee;
    uint256 public expectedHandlerCurrency0Balance;
    uint256 public expectedHandlerCurrency1Balance;
    uint256 public expectedRecipientCurrency0Balance;
    uint256 public expectedRecipientCurrency1Balance;
    uint256 public settlementSwapCount;
    bool internal expectedBalancesInitialized;

    constructor(
        TestableMemeverseUniswapHookForRouter _hook,
        PoolKey memory _key,
        MockERC20 _token0,
        MockERC20 _token1,
        address _owner,
        address _settlementRecipient
    ) {
        hook = _hook;
        token0 = _token0;
        token1 = _token1;
        key = _key;
        owner = _owner;
        settlementRecipient = _settlementRecipient;
    }

    /// @notice Test helper for approveHook.
    function approveHook() external {
        _initializeExpectedBalancesIfNeeded();
        token0.approve(address(hook), type(uint256).max);
        token1.approve(address(hook), type(uint256).max);
    }

    /// @notice Test helper for warp.
    /// @param deltaSeed See implementation.
    function warp(uint256 deltaSeed) external {
        vm.warp(block.timestamp + bound(deltaSeed, 0, 30 minutes));
    }

    /// @notice Test helper for settlementSwap.
    /// @param amountSeed See implementation.
    /// @param zeroForOne See implementation.
    /// @param useCurrency0AsFeeSide See implementation.
    function settlementSwap(uint256 amountSeed, bool zeroForOne, bool useCurrency0AsFeeSide) external {
        _initializeExpectedBalancesIfNeeded();

        MockERC20 inputToken = zeroForOne ? token0 : token1;
        uint256 balance = inputToken.balanceOf(address(this));
        if (balance < 1 ether) return;

        uint256 grossInputAmount = bound(amountSeed, 1 ether, _min(balance, MAX_SWAP_AMOUNT));
        bool protocolFeeOnInput = zeroForOne == useCurrency0AsFeeSide;
        uint256 protocolFeeInputAmount = protocolFeeOnInput ? grossInputAmount * PROTOCOL_FEE_BPS / BPS_BASE : 0;
        uint256 lpFeeInputAmount = grossInputAmount * LP_FEE_BPS / BPS_BASE;
        uint256 netInputAmount = grossInputAmount - lpFeeInputAmount - protocolFeeInputAmount;
        uint256 grossOutputAmount = netInputAmount / 2;
        // Output-side fee uses denominator (BPS_BASE - LP_FEE_BPS) to avoid double-counting LP fee
        uint256 protocolFeeOutputAmount = protocolFeeOnInput ? 0 : grossOutputAmount * PROTOCOL_FEE_BPS / BPS_BASE;
        uint256 netOutputAmount = grossOutputAmount - protocolFeeOutputAmount;

        vm.startPrank(owner);
        hook.setProtocolFeeCurrencySupport(key.currency0, useCurrency0AsFeeSide);
        hook.setProtocolFeeCurrencySupport(key.currency1, !useCurrency0AsFeeSide);
        vm.stopPrank();

        BalanceDelta delta = hook.executeLaunchSettlement(
            IMemeverseUniswapHook.LaunchSettlementParams({
                key: key,
                params: SwapParams({
                    zeroForOne: zeroForOne,
                    amountSpecified: -int256(grossInputAmount),
                    sqrtPriceLimitX96: zeroForOne ? 0 : SQRT_PRICE_1_1
                }),
                recipient: settlementRecipient
            })
        );

        if (zeroForOne) {
            assertLt(delta.amount0(), 0, "settlement delta0");
            assertGt(delta.amount1(), 0, "settlement delta1");
        } else {
            assertGt(delta.amount0(), 0, "settlement delta0");
            assertLt(delta.amount1(), 0, "settlement delta1");
        }

        if (zeroForOne) {
            expectedHandlerCurrency0Balance -= grossInputAmount;
            expectedRecipientCurrency1Balance += netOutputAmount;
        } else {
            expectedHandlerCurrency1Balance -= grossInputAmount;
            expectedRecipientCurrency0Balance += netOutputAmount;
        }

        if (useCurrency0AsFeeSide) {
            expectedTreasuryCurrency0Fee += protocolFeeOnInput ? protocolFeeInputAmount : protocolFeeOutputAmount;
        } else {
            expectedTreasuryCurrency1Fee += protocolFeeOnInput ? protocolFeeInputAmount : protocolFeeOutputAmount;
        }

        settlementSwapCount++;
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function _initializeExpectedBalancesIfNeeded() internal {
        if (expectedBalancesInitialized) return;

        expectedHandlerCurrency0Balance = token0.balanceOf(address(this));
        expectedHandlerCurrency1Balance = token1.balanceOf(address(this));
        expectedRecipientCurrency0Balance = token0.balanceOf(settlementRecipient);
        expectedRecipientCurrency1Balance = token1.balanceOf(settlementRecipient);
        expectedBalancesInitialized = true;
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
    MockERC20 internal token0;
    MockERC20 internal token1;
    PoolKey internal key;
    PoolId internal poolId;
    address internal treasury;
    address internal settlementRecipient;
    DirectLaunchSettlementHandler internal handler;

    /// @notice Test helper for setUp.
    function setUp() external {
        manager = new MockPoolManagerForRouterTest();
        treasury = makeAddr("treasury");
        settlementRecipient = makeAddr("settlementRecipient");
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
        poolId = key.toId();

        token0.mint(address(manager), 1_000_000 ether);
        token1.mint(address(manager), 1_000_000 ether);
        manager.initialize(key, SQRT_PRICE_1_1);
        hook.seedActiveLiquidityShares(key, address(this), 1e18);
        hook.setProtocolFeeCurrency(key.currency0);

        handler = new DirectLaunchSettlementHandler(hook, key, token0, token1, address(this), settlementRecipient);
        hook.setLauncher(address(handler));
        token0.mint(address(handler), 1_000_000 ether);
        token1.mint(address(handler), 1_000_000 ether);
        handler.approveHook();

        targetContract(address(handler));
    }

    function testSetUp_DirectSettlementHandlerPreconditions() external view {
        assertEq(hook.launcher(), address(handler), "launcher");
        assertEq(handler.settlementRecipient(), settlementRecipient, "recipient");
        assertEq(token0.balanceOf(address(handler)), 1_000_000 ether, "token0 handler balance");
        assertEq(token1.balanceOf(address(handler)), 1_000_000 ether, "token1 handler balance");
        assertEq(token0.allowance(address(handler), address(hook)), type(uint256).max, "token0 allowance");
        assertEq(token1.allowance(address(handler), address(hook)), type(uint256).max, "token1 allowance");
    }

    function testDirectSettlementHandler_OutputSideFeeComesFromSwapOutput() external {
        uint256 payerToken1Before = token1.balanceOf(address(handler));
        uint256 recipientToken1Before = token1.balanceOf(settlementRecipient);

        (bool ok,) =
            address(handler).call(abi.encodeWithSignature("settlementSwap(uint256,bool,bool)", 200 ether, true, false));

        assertTrue(ok, "zeroForOne currency1");
        assertEq(token1.balanceOf(settlementRecipient) - recipientToken1Before, 99.0021 ether, "recipient net output");
        assertEq(token1.balanceOf(address(handler)), payerToken1Before, "payer output token unchanged");
    }

    function testDirectSettlementHandler_CoversAllSupportedFeeSidesAndSwapDirections() external {
        uint256 treasury0Before = token0.balanceOf(treasury);
        uint256 treasury1Before = token1.balanceOf(treasury);
        (bool ok,) =
            address(handler).call(abi.encodeWithSignature("settlementSwap(uint256,bool,bool)", 100 ether, true, true));
        assertTrue(ok, "zeroForOne currency0");
        assertEq(token0.balanceOf(treasury) - treasury0Before, 0.3 ether, "zeroForOne currency0 treasury0");
        assertEq(token1.balanceOf(treasury) - treasury1Before, 0, "zeroForOne currency0 treasury1");
        assertEq(token1.balanceOf(settlementRecipient), 49.5 ether, "zeroForOne currency0 recipient1");

        treasury0Before = token0.balanceOf(treasury);
        treasury1Before = token1.balanceOf(treasury);
        uint256 handlerToken1Before = token1.balanceOf(address(handler));
        (ok,) =
            address(handler).call(abi.encodeWithSignature("settlementSwap(uint256,bool,bool)", 200 ether, true, false));
        assertTrue(ok, "zeroForOne currency1");
        assertEq(token0.balanceOf(treasury) - treasury0Before, 0, "zeroForOne currency1 treasury0");
        assertEq(token1.balanceOf(treasury) - treasury1Before, 0.2979 ether, "zeroForOne currency1 treasury1");
        assertEq(token1.balanceOf(settlementRecipient), 148.5021 ether, "zeroForOne currency1 recipient1");
        assertEq(token1.balanceOf(address(handler)), handlerToken1Before, "zeroForOne currency1 payer1");

        treasury0Before = token0.balanceOf(treasury);
        treasury1Before = token1.balanceOf(treasury);
        uint256 handlerToken0Before = token0.balanceOf(address(handler));
        (ok,) =
            address(handler).call(abi.encodeWithSignature("settlementSwap(uint256,bool,bool)", 300 ether, false, true));
        assertTrue(ok, "oneForZero currency0");
        assertEq(token0.balanceOf(treasury) - treasury0Before, 0.44685 ether, "oneForZero currency0 treasury0");
        assertEq(token1.balanceOf(treasury) - treasury1Before, 0, "oneForZero currency0 treasury1");
        assertEq(token0.balanceOf(settlementRecipient), 148.50315 ether, "oneForZero currency0 recipient0");
        assertEq(token0.balanceOf(address(handler)), handlerToken0Before, "oneForZero currency0 payer0");

        treasury0Before = token0.balanceOf(treasury);
        treasury1Before = token1.balanceOf(treasury);
        (ok,) = address(handler)
            .call(abi.encodeWithSignature("settlementSwap(uint256,bool,bool)", 400 ether, false, false));
        assertTrue(ok, "oneForZero currency1");
        assertEq(token0.balanceOf(treasury) - treasury0Before, 0, "oneForZero currency1 treasury0");
        assertEq(token1.balanceOf(treasury) - treasury1Before, 1.2 ether, "oneForZero currency1 treasury1");
        assertEq(token0.balanceOf(settlementRecipient), 346.50315 ether, "oneForZero currency1 recipient0");

        assertEq(handler.settlementSwapCount(), 4, "settlement count");
    }

    /// @notice Test helper for invariant_publicQuoteNeverDropsBelowSettlementFeeFloor.
    function invariant_directSettlementTreasuryAccountingMatchesExpected() external view {
        assertEq(token0.balanceOf(treasury), handler.expectedTreasuryCurrency0Fee(), "treasury token0 accounting");
        assertEq(token1.balanceOf(treasury), handler.expectedTreasuryCurrency1Fee(), "treasury token1 accounting");
    }

    /// @notice Test helper for invariant_directSettlementOutputSideProtocolFeeCountedOnce.
    function invariant_directSettlementOutputSideProtocolFeeCountedOnce() external view {
        assertEq(
            token0.balanceOf(address(handler)),
            handler.expectedHandlerCurrency0Balance(),
            "handler token0 single-fee accounting"
        );
        assertEq(
            token1.balanceOf(address(handler)),
            handler.expectedHandlerCurrency1Balance(),
            "handler token1 single-fee accounting"
        );
        assertEq(
            token0.balanceOf(settlementRecipient),
            handler.expectedRecipientCurrency0Balance(),
            "recipient token0 net output accounting"
        );
        assertEq(
            token1.balanceOf(settlementRecipient),
            handler.expectedRecipientCurrency1Balance(),
            "recipient token1 net output accounting"
        );
    }

    /// @notice Test helper for invariant_directSettlementNeverBreaksPublicQuoteFloor.
    function invariant_directSettlementNeverBreaksPublicQuoteFloor() external view {
        IMemeverseUniswapHook.SwapQuote memory quote =
            hook.quoteSwap(key, SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}));
        assertGe(quote.feeBps, 100, "public fee floor");
    }

    /// @notice Test helper for invariant_directSettlementDoesNotRewritePoolLaunchTimestamp.
    function invariant_directSettlementDoesNotRewritePoolLaunchTimestamp() external view {
        assertEq(hook.poolLaunchTimestamp(poolId), 1, "pool launch timestamp");
    }
}
