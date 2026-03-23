// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {IPoolManager, SwapParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";

import {MemeverseSwapRouter} from "../../src/swap/MemeverseSwapRouter.sol";
import {IMemeverseUniswapHook} from "../../src/swap/interfaces/IMemeverseUniswapHook.sol";
import {MockPoolManagerForRouterTest, TestableMemeverseUniswapHookForRouter} from "./MemeverseSwapRouter.t.sol";

contract RouterSettlementAccountingHandler is Test {
    bytes32 internal constant LAUNCH_SETTLEMENT_HOOKDATA_HASH = keccak256("memeverse.launch-settlement.hookdata");
    uint160 internal constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    MemeverseSwapRouter internal router;
    TestableMemeverseUniswapHookForRouter internal immutable hook;
    MockERC20 internal immutable token0;
    address internal immutable treasury;
    PoolKey internal key;

    uint256 public expectedRegularTreasuryFee;
    uint256 public expectedSettlementTreasuryFee;

    constructor(
        TestableMemeverseUniswapHookForRouter _hook,
        MockERC20 _token0,
        address _treasury,
        PoolKey memory _key
    ) {
        hook = _hook;
        token0 = _token0;
        treasury = _treasury;
        key = _key;
    }

    /// @notice Binds the deployed router to the accounting handler.
    /// @dev One-time wiring step used by the invariant harness.
    /// @param _router Router under test.
    function setRouter(MemeverseSwapRouter _router) external {
        require(address(router) == address(0), "router already set");
        router = _router;
        token0.approve(address(router), type(uint256).max);
    }

    /// @notice Advances time for the invariant harness.
    /// @dev Used to explore fee decay and launch window transitions.
    /// @param deltaSeed Fuzzed time delta seed.
    function warp(uint256 deltaSeed) external {
        vm.warp(block.timestamp + bound(deltaSeed, 0, 40 minutes));
    }

    /// @notice Executes a regular routed swap and records treasury fee accounting.
    /// @dev Exercises the non-settlement path under invariant fuzzing.
    /// @param amountSeed Fuzzed swap amount seed.
    function regularSwap(uint256 amountSeed) external {
        uint256 balance = token0.balanceOf(address(this));
        if (balance < 1 ether) return;

        uint256 amount = bound(amountSeed, 1 ether, _min(balance, 10_000 ether));
        uint160 priceLimit = uint160((uint256(SQRT_PRICE_1_1) * 99) / 100);
        SwapParams memory params =
            SwapParams({zeroForOne: true, amountSpecified: -int256(amount), sqrtPriceLimitX96: priceLimit});

        IMemeverseUniswapHook.SwapQuote memory quote = hook.quoteSwap(key, params);
        uint256 treasuryBefore = token0.balanceOf(treasury);

        BalanceDelta delta =
            router.swap(key, params, address(this), address(this), block.timestamp, 0, amount, bytes("regular"));

        assertLt(delta.amount0(), 0, "regular delta0");
        assertGt(delta.amount1(), 0, "regular delta1");

        uint256 treasuryDelta = token0.balanceOf(treasury) - treasuryBefore;
        assertEq(treasuryDelta, quote.estimatedProtocolFeeAmount, "regular protocol fee");
        expectedRegularTreasuryFee += treasuryDelta;
    }

    /// @notice Executes the fixed-fee launch settlement swap and records treasury accounting.
    /// @dev Exercises the marker-gated settlement path under invariant fuzzing.
    /// @param amountSeed Fuzzed swap amount seed.
    function settlementSwap(uint256 amountSeed) external {
        uint256 balance = token0.balanceOf(address(this));
        if (balance < 1 ether) return;

        uint256 amount = bound(amountSeed, 1 ether, _min(balance, 10_000 ether));
        uint160 priceLimit = uint160((uint256(SQRT_PRICE_1_1) * 99) / 100);
        uint256 treasuryBefore = token0.balanceOf(treasury);

        BalanceDelta delta = router.swap(
            key,
            SwapParams({zeroForOne: true, amountSpecified: -int256(amount), sqrtPriceLimitX96: priceLimit}),
            address(this),
            address(this),
            block.timestamp,
            0,
            amount,
            abi.encode(LAUNCH_SETTLEMENT_HOOKDATA_HASH)
        );

        assertLt(delta.amount0(), 0, "settlement delta0");
        assertGt(delta.amount1(), 0, "settlement delta1");

        uint256 treasuryDelta = token0.balanceOf(treasury) - treasuryBefore;
        uint256 expectedDelta = amount * 30 / 10_000;
        assertEq(treasuryDelta, expectedDelta, "settlement protocol fee");
        expectedSettlementTreasuryFee += treasuryDelta;
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}

contract RouterSettlementSpoofHandler is Test {
    bytes32 internal constant LAUNCH_SETTLEMENT_HOOKDATA_HASH = keccak256("memeverse.launch-settlement.hookdata");
    uint160 internal constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    MemeverseSwapRouter internal immutable router;
    MockERC20 internal immutable token0;
    PoolKey internal key;

    bool public unexpectedSuccess;

    constructor(MemeverseSwapRouter _router, MockERC20 _token0, PoolKey memory _key) {
        router = _router;
        token0 = _token0;
        key = _key;
        token0.approve(address(router), type(uint256).max);
    }

    /// @notice Advances time for the spoof handler.
    /// @dev Keeps spoof attempts independent from a fixed timestamp.
    /// @param deltaSeed Fuzzed time delta seed.
    function warp(uint256 deltaSeed) external {
        vm.warp(block.timestamp + bound(deltaSeed, 0, 40 minutes));
    }

    /// @notice Attempts to spoof the settlement marker from an unauthorized caller.
    /// @dev Any success would indicate a broken router-side authorization boundary.
    /// @param amountSeed Fuzzed swap amount seed.
    function spoofSettlement(uint256 amountSeed) external {
        uint256 balance = token0.balanceOf(address(this));
        if (balance < 1 ether) return;

        uint256 amount = bound(amountSeed, 1 ether, _min(balance, 10_000 ether));
        uint160 priceLimit = uint160((uint256(SQRT_PRICE_1_1) * 99) / 100);

        try router.swap(
            key,
            SwapParams({zeroForOne: true, amountSpecified: -int256(amount), sqrtPriceLimitX96: priceLimit}),
            address(this),
            address(this),
            block.timestamp,
            0,
            amount,
            abi.encode(LAUNCH_SETTLEMENT_HOOKDATA_HASH)
        ) returns (
            BalanceDelta delta
        ) {
            delta;
            unexpectedSuccess = true;
        } catch {}
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}

contract MemeverseSwapRouterSettlementInvariantTest is StdInvariant, Test {
    uint160 internal constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    MockPoolManagerForRouterTest internal manager;
    TestableMemeverseUniswapHookForRouter internal hook;
    MemeverseSwapRouter internal router;
    MockERC20 internal token0;
    MockERC20 internal token1;
    address internal treasury;
    PoolKey internal key;

    RouterSettlementAccountingHandler internal accountingHandler;
    RouterSettlementSpoofHandler internal spoofHandler;

    /// @notice Deploys the router settlement invariant harness.
    /// @dev Wires router, hook, handlers, and seeded balances before invariant fuzzing.
    function setUp() external {
        manager = new MockPoolManagerForRouterTest();
        treasury = makeAddr("treasury");
        hook = new TestableMemeverseUniswapHookForRouter(
            IPoolManager(address(manager)), address(this), treasury, address(this)
        );

        token0 = new MockERC20("Token0", "TK0", 18);
        token1 = new MockERC20("Token1", "TK1", 18);

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

        accountingHandler = new RouterSettlementAccountingHandler(hook, token0, treasury, key);
        router = new MemeverseSwapRouter(
            IPoolManager(address(manager)),
            IMemeverseUniswapHook(address(hook)),
            IPermit2(address(0xBEEF)),
            address(accountingHandler)
        );
        accountingHandler.setRouter(router);
        spoofHandler = new RouterSettlementSpoofHandler(router, token0, key);

        hook.setLaunchSettlementCaller(address(router));
        token0.mint(address(accountingHandler), 1_000_000 ether);
        token0.mint(address(spoofHandler), 1_000_000 ether);

        targetContract(address(accountingHandler));
        targetContract(address(spoofHandler));
    }

    /// @notice Ensures treasury fees equal the sum of regular and settlement expectations.
    /// @dev Guards end-to-end accounting across both router paths.
    function invariant_treasuryAccountingMatchesRegularPlusSettlementPaths() external view {
        assertEq(
            token0.balanceOf(treasury),
            accountingHandler.expectedRegularTreasuryFee() + accountingHandler.expectedSettlementTreasuryFee(),
            "treasury accounting"
        );
    }

    /// @notice Ensures unauthorized spoof attempts never succeed.
    /// @dev The spoof handler records unexpected success explicitly.
    function invariant_spoofedSettlementNeverSucceeds() external view {
        assertFalse(spoofHandler.unexpectedSuccess(), "spoofed marker succeeded");
    }

    /// @notice Ensures the router settlement operator remains pinned to the accounting handler.
    /// @dev Protects the invariant harness assumptions around the authorized caller.
    function invariant_launchSettlementOperatorRemainsBoundedToAccountingHandler() external view {
        assertEq(router.launchSettlementOperator(), address(accountingHandler), "launch settlement operator");
    }

    /// @notice Ensures spoof reverts never create untracked treasury fees.
    /// @dev Treasury growth must come only from successful accounting-handler swaps.
    function invariant_spoofRevertsDoNotCreateUntrackedTreasuryFees() external view {
        assertLe(
            token0.balanceOf(treasury),
            accountingHandler.expectedRegularTreasuryFee() + accountingHandler.expectedSettlementTreasuryFee(),
            "spoof path changed treasury"
        );
    }
}
