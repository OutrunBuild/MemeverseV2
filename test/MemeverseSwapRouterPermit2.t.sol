// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {IPoolManager, ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta, BalanceDeltaLibrary, toBalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {BaseHook} from "@uniswap/v4-periphery/src/utils/BaseHook.sol";
import {ISignatureTransfer} from "lib/v4-periphery/lib/permit2/src/interfaces/ISignatureTransfer.sol";
import {IPermit2} from "lib/v4-periphery/lib/permit2/src/interfaces/IPermit2.sol";

import {LiquidityAmounts} from "../src/libraries/LiquidityAmounts.sol";
import {MemeverseUniswapHook} from "../src/swap/MemeverseUniswapHook.sol";
import {MemeverseSwapRouter} from "../src/swap/MemeverseSwapRouter.sol";
import {IMemeverseSwapRouter} from "../src/swap/interfaces/IMemeverseSwapRouter.sol";
import {IMemeverseUniswapHook} from "../src/swap/interfaces/IMemeverseUniswapHook.sol";

contract MockPoolManagerForPermit2RouterTest {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using BeforeSwapDeltaLibrary for BeforeSwapDelta;

    error ManagerLocked();

    struct Slot0State {
        uint160 sqrtPriceX96;
        int24 tick;
        uint24 protocolFee;
        uint24 lpFee;
    }

    bytes internal constant ZERO_BYTES = bytes("");
    bytes32 internal constant POOLS_SLOT = bytes32(uint256(6));
    uint256 internal constant LIQUIDITY_OFFSET = 3;
    uint160 internal constant SQRT_PRICE_LOWER_X96 = 4_310_618_292;
    uint160 internal constant SQRT_PRICE_UPPER_X96 = 1_456_195_216_270_955_103_206_513_029_158_776_779_468_408_838_535;

    bool internal unlocked;
    mapping(bytes32 => bytes32) internal extStorage;
    mapping(PoolId => Slot0State) internal slot0State;
    mapping(PoolId => uint128) internal liquidityState;

    function initialize(PoolKey memory key, uint160 sqrtPriceX96) external returns (int24 tick) {
        PoolId poolId = key.toId();
        slot0State[poolId] = Slot0State({sqrtPriceX96: sqrtPriceX96, tick: 0, protocolFee: 0, lpFee: 0});
        liquidityState[poolId] = 1e24;
        _syncPoolStorage(poolId);
        key.hooks.beforeInitialize(msg.sender, key, sqrtPriceX96);
        tick = 0;
    }

    function unlock(bytes calldata data) external returns (bytes memory result) {
        unlocked = true;
        result = IUnlockCallbackLike(msg.sender).unlockCallback(data);
        unlocked = false;
    }

    function modifyLiquidity(PoolKey memory key, ModifyLiquidityParams memory params, bytes calldata)
        external
        returns (BalanceDelta delta, BalanceDelta feesAccrued)
    {
        if (!unlocked) revert ManagerLocked();
        uint256 amount0Used;
        uint256 amount1Used;

        if (params.liquidityDelta > 0) {
            key.hooks.beforeAddLiquidity(msg.sender, key, params, ZERO_BYTES);
            liquidityState[key.toId()] += uint128(uint256(params.liquidityDelta));
            _syncPoolStorage(key.toId());
            (amount0Used, amount1Used) = LiquidityAmounts.getAmountsForLiquidity(
                slot0State[key.toId()].sqrtPriceX96,
                SQRT_PRICE_LOWER_X96,
                SQRT_PRICE_UPPER_X96,
                uint128(uint256(params.liquidityDelta))
            );
            delta = toBalanceDelta(-int128(int256(amount0Used)), -int128(int256(amount1Used)));
            return (delta, feesAccrued);
        }

        liquidityState[key.toId()] -= uint128(uint256(-params.liquidityDelta));
        _syncPoolStorage(key.toId());
        (amount0Used, amount1Used) = LiquidityAmounts.getAmountsForLiquidity(
            slot0State[key.toId()].sqrtPriceX96,
            SQRT_PRICE_LOWER_X96,
            SQRT_PRICE_UPPER_X96,
            uint128(uint256(-params.liquidityDelta))
        );
        delta = toBalanceDelta(int128(int256(amount0Used)), int128(int256(amount1Used)));
    }

    function swap(PoolKey memory key, SwapParams memory params, bytes calldata hookData)
        external
        returns (BalanceDelta delta)
    {
        if (!unlocked) revert ManagerLocked();

        (, BeforeSwapDelta beforeSwapDelta,) = key.hooks.beforeSwap(msg.sender, key, params, hookData);
        int256 amountToSwap = params.amountSpecified + beforeSwapDelta.getSpecifiedDelta();

        BalanceDelta poolDelta = BalanceDeltaLibrary.ZERO_DELTA;
        if (amountToSwap != 0) {
            if (params.amountSpecified < 0) {
                uint256 inputAmount = uint256(-amountToSwap);
                uint256 outputAmount = inputAmount / 2;
                if (params.zeroForOne) {
                    poolDelta = toBalanceDelta(-int128(int256(inputAmount)), int128(int256(outputAmount)));
                } else {
                    poolDelta = toBalanceDelta(int128(int256(outputAmount)), -int128(int256(inputAmount)));
                }
            } else {
                uint256 outputAmount = uint256(amountToSwap);
                uint256 inputAmount = outputAmount * 2;
                if (params.zeroForOne) {
                    poolDelta = toBalanceDelta(-int128(int256(inputAmount)), int128(int256(outputAmount)));
                } else {
                    poolDelta = toBalanceDelta(int128(int256(outputAmount)), -int128(int256(inputAmount)));
                }
            }
        }

        (, int128 afterSwapUnspecifiedDelta) = key.hooks.afterSwap(msg.sender, key, params, poolDelta, hookData);

        int128 hookDeltaSpecified = beforeSwapDelta.getSpecifiedDelta();
        int128 hookDeltaUnspecified = beforeSwapDelta.getUnspecifiedDelta() + afterSwapUnspecifiedDelta;
        if (hookDeltaSpecified != 0 || hookDeltaUnspecified != 0) {
            BalanceDelta hookDelta = (params.amountSpecified < 0 == params.zeroForOne)
                ? toBalanceDelta(hookDeltaSpecified, hookDeltaUnspecified)
                : toBalanceDelta(hookDeltaUnspecified, hookDeltaSpecified);
            delta = poolDelta - hookDelta;
        } else {
            delta = poolDelta;
        }
    }

    function take(Currency currency, address to, uint256 amount) external {
        if (currency.isAddressZero()) {
            (bool success,) = to.call{value: amount}("");
            require(success, "native take");
        } else {
            MockERC20(Currency.unwrap(currency)).transfer(to, amount);
        }
    }

    function sync(Currency) external {}

    function settle() external payable returns (uint256) {
        return msg.value;
    }

    function extsload(bytes32 slot) external view returns (bytes32) {
        return extStorage[slot];
    }

    function getSlot0(PoolId poolId) external view returns (uint160, int24, uint24, uint24) {
        Slot0State memory state = slot0State[poolId];
        return (state.sqrtPriceX96, state.tick, state.protocolFee, state.lpFee);
    }

    function getLiquidity(PoolId poolId) external view returns (uint128) {
        return liquidityState[poolId];
    }

    function _syncPoolStorage(PoolId poolId) internal {
        bytes32 stateSlot = keccak256(abi.encodePacked(PoolId.unwrap(poolId), POOLS_SLOT));
        Slot0State memory state = slot0State[poolId];
        extStorage[stateSlot] = bytes32(uint256(state.sqrtPriceX96));
        extStorage[bytes32(uint256(stateSlot) + LIQUIDITY_OFFSET)] = bytes32(uint256(liquidityState[poolId]));
    }

    receive() external payable {}
}

interface IUnlockCallbackLike {
    function unlockCallback(bytes calldata data) external returns (bytes memory);
}

contract TestableMemeverseUniswapHookForPermit2Router is MemeverseUniswapHook {
    constructor(
        IPoolManager _manager,
        address _owner,
        address _treasury,
        uint256 _antiSnipeDurationBlocks,
        uint256 _maxAntiSnipeProbabilityBase
    ) MemeverseUniswapHook(_manager, _owner, _treasury, _antiSnipeDurationBlocks, _maxAntiSnipeProbabilityBase) {}

    function validateHookAddress(BaseHook) internal pure override {}
}

contract MockPermit2ForRouterTest {
    address public lastOwner;
    address public lastRecipient;
    address public lastToken;
    uint256 public lastRequestedAmount;
    address public lastBatchOwner;
    uint256 public lastBatchLength;
    bytes32 public lastWitness;
    string public lastWitnessTypeString;
    bytes public lastSignature;

    function permitWitnessTransferFrom(
        ISignatureTransfer.PermitTransferFrom memory permit,
        ISignatureTransfer.SignatureTransferDetails calldata transferDetails,
        address owner,
        bytes32 witness,
        string calldata witnessTypeString,
        bytes calldata signature
    ) external {
        lastOwner = owner;
        lastRecipient = transferDetails.to;
        lastToken = permit.permitted.token;
        lastRequestedAmount = transferDetails.requestedAmount;
        lastWitness = witness;
        lastWitnessTypeString = witnessTypeString;
        lastSignature = signature;

        MockERC20(permit.permitted.token).transferFrom(owner, transferDetails.to, transferDetails.requestedAmount);
    }

    function permitWitnessTransferFrom(
        ISignatureTransfer.PermitBatchTransferFrom memory permit,
        ISignatureTransfer.SignatureTransferDetails[] calldata transferDetails,
        address owner,
        bytes32 witness,
        string calldata witnessTypeString,
        bytes calldata signature
    ) external {
        lastBatchOwner = owner;
        lastBatchLength = transferDetails.length;
        lastWitness = witness;
        lastWitnessTypeString = witnessTypeString;
        lastSignature = signature;

        for (uint256 i = 0; i < transferDetails.length; ++i) {
            MockERC20(permit.permitted[i].token).transferFrom(owner, transferDetails[i].to, transferDetails[i].requestedAmount);
        }
    }
}

contract MemeverseSwapRouterPermit2Test is Test {
    using PoolIdLibrary for PoolKey;

    uint160 internal constant SQRT_PRICE_1_1 = 79228162514264337593543950336;
    uint256 internal constant ALICE_PK = 0xA11CE;

    MockPoolManagerForPermit2RouterTest internal manager;
    TestableMemeverseUniswapHookForPermit2Router internal hook;
    MockPermit2ForRouterTest internal mockPermit2;
    MemeverseSwapRouter internal router;
    MockERC20 internal token0;
    MockERC20 internal token1;
    address internal treasury;
    address internal alice;
    PoolKey internal key;
    PoolId internal poolId;

    function setUp() public {
        manager = new MockPoolManagerForPermit2RouterTest();
        treasury = makeAddr("treasury");
        alice = vm.addr(ALICE_PK);
        hook =
            new TestableMemeverseUniswapHookForPermit2Router(IPoolManager(address(manager)), address(this), treasury, 10, 1);
        mockPermit2 = new MockPermit2ForRouterTest();
        router = new MemeverseSwapRouter(
            IPoolManager(address(manager)), IMemeverseUniswapHook(address(hook)), IPermit2(address(mockPermit2))
        );

        token0 = new MockERC20("Token0", "TK0", 18);
        token1 = new MockERC20("Token1", "TK1", 18);
        token0.mint(alice, 1_000_000 ether);
        token1.mint(alice, 1_000_000 ether);
        token0.mint(address(manager), 1_000_000 ether);
        token1.mint(address(manager), 1_000_000 ether);

        vm.prank(alice);
        token0.approve(address(mockPermit2), type(uint256).max);
        vm.prank(alice);
        token1.approve(address(mockPermit2), type(uint256).max);

        key = _dynamicPoolKey(Currency.wrap(address(token0)), Currency.wrap(address(token1)));
        poolId = key.toId();
        manager.initialize(key, SQRT_PRICE_1_1);
    }

    function testSwapWithPermit2_TransfersInputAndExecutes() external {
        hook.setProtocolFeeCurrency(key.currency0);

        IMemeverseSwapRouter.Permit2SingleParams memory singlePermit = _singlePermit(address(token0), 100 ether);
        uint256 balance0Before = token0.balanceOf(alice);
        uint256 balance1Before = token1.balanceOf(alice);
        uint160 priceLimit = uint160((uint256(SQRT_PRICE_1_1) * 99) / 100);

        vm.prank(alice);
        (BalanceDelta delta, bool executed, IMemeverseUniswapHook.AntiSnipeFailureReason reason) = router
            .swapWithPermit2(
            singlePermit,
            key,
            SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: priceLimit}),
            alice,
            alice,
            block.timestamp,
            40 ether,
            100 ether,
            ""
        );

        assertEq(address(router.permit2()), address(mockPermit2), "permit2");
        assertEq(mockPermit2.lastOwner(), alice, "owner");
        assertEq(mockPermit2.lastRecipient(), address(router), "recipient");
        assertEq(mockPermit2.lastToken(), address(token0), "token");
        assertEq(mockPermit2.lastRequestedAmount(), 100 ether, "amount");
        assertTrue(executed, "executed");
        assertEq(uint8(reason), uint8(IMemeverseUniswapHook.AntiSnipeFailureReason.None), "reason");
        assertLt(int256(delta.amount0()), 0, "delta0");
        assertGt(int256(delta.amount1()), 0, "delta1");
        assertLt(token0.balanceOf(alice), balance0Before, "token0 spent");
        assertGt(token1.balanceOf(alice), balance1Before, "token1 received");
    }

    function testSwapWithPermit2_SoftFailRefundsUnusedInput() external {
        hook.setProtocolFeeCurrency(key.currency0);

        IMemeverseUniswapHook.FailedAttemptQuote memory failureQuote = hook.quoteFailedAttempt(
            key, SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}), 100 ether
        );
        IMemeverseSwapRouter.Permit2SingleParams memory singlePermit = _singlePermit(address(token0), 100 ether);
        uint256 aliceBalanceBefore = token0.balanceOf(alice);
        uint256 treasuryBalanceBefore = token0.balanceOf(treasury);

        vm.prank(alice);
        (BalanceDelta delta, bool executed, IMemeverseUniswapHook.AntiSnipeFailureReason reason) = router
            .swapWithPermit2(
            singlePermit,
            key,
            SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}),
            alice,
            alice,
            block.timestamp,
            0,
            100 ether,
            ""
        );

        assertEq(BalanceDelta.unwrap(delta), 0, "delta");
        assertFalse(executed, "executed");
        assertEq(uint8(reason), uint8(IMemeverseUniswapHook.AntiSnipeFailureReason.NoPriceLimitSet), "reason");
        assertEq(token0.balanceOf(alice), aliceBalanceBefore - failureQuote.feeAmount, "only failure fee retained");
        assertEq(token0.balanceOf(treasury), treasuryBalanceBefore + failureQuote.feeAmount, "treasury charged");
        assertEq(token0.balanceOf(address(router)), 0, "router refunded surplus");
    }

    function testAddLiquidityWithPermit2_TwoErc20Inputs() external {
        IMemeverseSwapRouter.Permit2BatchParams memory batchPermit =
            _batchPermit(address(token0), 100 ether, address(token1), 100 ether);

        vm.prank(alice);
        uint128 liquidity = router.addLiquidityWithPermit2(
            batchPermit,
            MemeverseSwapRouter.AddLiquidityParams({
                currency0: key.currency0,
                currency1: key.currency1,
                amount0Desired: 100 ether,
                amount1Desired: 100 ether,
                amount0Min: 90 ether,
                amount1Min: 90 ether,
                to: alice,
                nativeRefundRecipient: alice,
                deadline: block.timestamp
            })
        );

        (address liquidityToken,,,) = hook.poolInfo(poolId);
        assertGt(liquidity, 0, "liquidity");
        assertEq(mockPermit2.lastBatchOwner(), alice, "owner");
        assertEq(mockPermit2.lastBatchLength(), 2, "batch length");
        assertGt(MockERC20(liquidityToken).balanceOf(alice), 0, "lp balance");
    }

    function testAddLiquidityWithPermit2_OneErc20PlusNative() external {
        PoolKey memory nativeKey = _dynamicPoolKey(CurrencyLibrary.ADDRESS_ZERO, Currency.wrap(address(token1)));
        PoolId nativePoolId = nativeKey.toId();
        vm.deal(alice, 1_000_000 ether);
        manager.initialize(nativeKey, SQRT_PRICE_1_1);

        IMemeverseSwapRouter.Permit2BatchParams memory batchPermit = _batchPermitSingle(address(token1), 100 ether);

        vm.prank(alice);
        uint128 liquidity = router.addLiquidityWithPermit2{value: 100 ether}(
            batchPermit,
            MemeverseSwapRouter.AddLiquidityParams({
                currency0: nativeKey.currency0,
                currency1: nativeKey.currency1,
                amount0Desired: 100 ether,
                amount1Desired: 100 ether,
                amount0Min: 90 ether,
                amount1Min: 90 ether,
                to: alice,
                nativeRefundRecipient: alice,
                deadline: block.timestamp
            })
        );

        (address liquidityToken,,,) = hook.poolInfo(nativePoolId);
        assertGt(liquidity, 0, "liquidity");
        assertEq(mockPermit2.lastBatchLength(), 1, "batch length");
        assertGt(MockERC20(liquidityToken).balanceOf(alice), 0, "lp balance");
        assertEq(address(router).balance, 0, "router keeps no native");
    }

    function testRemoveLiquidityWithPermit2() external {
        uint128 liquidity = _mintAliceLiquidity();
        (address liquidityToken,,,) = hook.poolInfo(poolId);

        vm.prank(alice);
        MockERC20(liquidityToken).approve(address(mockPermit2), type(uint256).max);

        IMemeverseSwapRouter.Permit2SingleParams memory singlePermit =
            _singlePermit(liquidityToken, uint256(liquidity));
        uint256 balance0Before = token0.balanceOf(alice);
        uint256 balance1Before = token1.balanceOf(alice);

        vm.prank(alice);
        BalanceDelta delta = router.removeLiquidityWithPermit2(
            singlePermit,
            MemeverseSwapRouter.RemoveLiquidityParams({
                currency0: key.currency0,
                currency1: key.currency1,
                liquidity: liquidity,
                amount0Min: 1,
                amount1Min: 1,
                to: alice,
                deadline: block.timestamp
            })
        );

        assertGt(int256(delta.amount0()), 0, "delta0");
        assertGt(int256(delta.amount1()), 0, "delta1");
        assertGt(token0.balanceOf(alice), balance0Before, "token0 returned");
        assertGt(token1.balanceOf(alice), balance1Before, "token1 returned");
        assertEq(MockERC20(liquidityToken).balanceOf(alice), 0, "lp burned");
    }

    function testCreatePoolAndAddLiquidityWithPermit2() external {
        MockERC20 tokenA = new MockERC20("A", "A", 18);
        MockERC20 tokenB = new MockERC20("B", "B", 18);
        tokenA.mint(alice, 1_000_000 ether);
        tokenB.mint(alice, 1_000_000 ether);
        vm.prank(alice);
        tokenA.approve(address(mockPermit2), type(uint256).max);
        vm.prank(alice);
        tokenB.approve(address(mockPermit2), type(uint256).max);

        IMemeverseSwapRouter.Permit2BatchParams memory batchPermit =
            _batchPermit(address(tokenA), 100 ether, address(tokenB), 100 ether);

        vm.prank(alice);
        (uint128 liquidity, PoolKey memory createdKey) = router.createPoolAndAddLiquidityWithPermit2(
            batchPermit,
            MemeverseSwapRouter.CreatePoolAndAddLiquidityParams({
                tokenA: address(tokenA),
                tokenB: address(tokenB),
                amountADesired: 100 ether,
                amountBDesired: 100 ether,
                recipient: alice,
                nativeRefundRecipient: alice,
                deadline: block.timestamp
            })
        );

        (address liquidityToken,,,) = hook.poolInfo(createdKey.toId());
        assertGt(liquidity, 0, "liquidity");
        assertEq(address(createdKey.hooks), address(hook), "hook");
        assertGt(MockERC20(liquidityToken).balanceOf(alice), 0, "lp balance");
    }

    function testCreatePoolAndAddLiquidityWithPermit2_InvalidBatchLengthReverts() external {
        MockERC20 tokenA = new MockERC20("A", "A", 18);
        MockERC20 tokenB = new MockERC20("B", "B", 18);
        tokenA.mint(alice, 1_000_000 ether);
        tokenB.mint(alice, 1_000_000 ether);
        vm.prank(alice);
        tokenA.approve(address(mockPermit2), type(uint256).max);

        IMemeverseSwapRouter.Permit2BatchParams memory batchPermit = _batchPermitSingle(address(tokenA), 100 ether);

        vm.expectRevert(MemeverseSwapRouter.InvalidPermit2Length.selector);
        vm.prank(alice);
        router.createPoolAndAddLiquidityWithPermit2(
            batchPermit,
            MemeverseSwapRouter.CreatePoolAndAddLiquidityParams({
                tokenA: address(tokenA),
                tokenB: address(tokenB),
                amountADesired: 100 ether,
                amountBDesired: 100 ether,
                recipient: alice,
                nativeRefundRecipient: alice,
                deadline: block.timestamp
            })
        );
    }

    function testAddLiquidityWithPermit2_TokenMismatchReverts() external {
        IMemeverseSwapRouter.Permit2BatchParams memory batchPermit =
            _batchPermit(address(token0), 100 ether, address(0xBEEF), 100 ether);

        vm.expectRevert(
            abi.encodeWithSelector(
                MemeverseSwapRouter.InvalidPermit2Token.selector, 1, address(token1), address(0xBEEF)
            )
        );
        vm.prank(alice);
        router.addLiquidityWithPermit2(
            batchPermit,
            MemeverseSwapRouter.AddLiquidityParams({
                currency0: key.currency0,
                currency1: key.currency1,
                amount0Desired: 100 ether,
                amount1Desired: 100 ether,
                amount0Min: 90 ether,
                amount1Min: 90 ether,
                to: alice,
                nativeRefundRecipient: alice,
                deadline: block.timestamp
            })
        );
    }

    function _dynamicPoolKey(Currency currency0, Currency currency1) internal view returns (PoolKey memory) {
        return PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 0x800000,
            tickSpacing: 200,
            hooks: IHooks(address(hook))
        });
    }

    function _mintAliceLiquidity() internal returns (uint128 liquidity) {
        vm.prank(alice);
        token0.approve(address(router), type(uint256).max);
        vm.prank(alice);
        token1.approve(address(router), type(uint256).max);

        vm.prank(alice);
        liquidity = router.addLiquidity(
            MemeverseSwapRouter.AddLiquidityParams({
                currency0: key.currency0,
                currency1: key.currency1,
                amount0Desired: 100 ether,
                amount1Desired: 100 ether,
                amount0Min: 90 ether,
                amount1Min: 90 ether,
                to: alice,
                nativeRefundRecipient: alice,
                deadline: block.timestamp
            })
        );
    }

    function _singlePermit(address token, uint256 amount)
        internal
        view
        returns (IMemeverseSwapRouter.Permit2SingleParams memory permitParams)
    {
        permitParams = IMemeverseSwapRouter.Permit2SingleParams({
            permit: ISignatureTransfer.PermitTransferFrom({
                permitted: ISignatureTransfer.TokenPermissions({token: token, amount: amount}),
                nonce: 1,
                deadline: block.timestamp
            }),
            transferDetails: ISignatureTransfer.SignatureTransferDetails({to: address(router), requestedAmount: amount}),
            signature: hex"1234"
        });
    }

    function _batchPermit(address token0_, uint256 amount0_, address token1_, uint256 amount1_)
        internal
        view
        returns (IMemeverseSwapRouter.Permit2BatchParams memory permitParams)
    {
        permitParams.permit.permitted = new ISignatureTransfer.TokenPermissions[](2);
        permitParams.permit.permitted[0] = ISignatureTransfer.TokenPermissions({token: token0_, amount: amount0_});
        permitParams.permit.permitted[1] = ISignatureTransfer.TokenPermissions({token: token1_, amount: amount1_});
        permitParams.permit.nonce = 2;
        permitParams.permit.deadline = block.timestamp;
        permitParams.transferDetails = new ISignatureTransfer.SignatureTransferDetails[](2);
        permitParams.transferDetails[0] =
            ISignatureTransfer.SignatureTransferDetails({to: address(router), requestedAmount: amount0_});
        permitParams.transferDetails[1] =
            ISignatureTransfer.SignatureTransferDetails({to: address(router), requestedAmount: amount1_});
        permitParams.signature = hex"1234";
    }

    function _batchPermitSingle(address token, uint256 amount)
        internal
        view
        returns (IMemeverseSwapRouter.Permit2BatchParams memory permitParams)
    {
        permitParams.permit.permitted = new ISignatureTransfer.TokenPermissions[](1);
        permitParams.permit.permitted[0] = ISignatureTransfer.TokenPermissions({token: token, amount: amount});
        permitParams.permit.nonce = 3;
        permitParams.permit.deadline = block.timestamp;
        permitParams.transferDetails = new ISignatureTransfer.SignatureTransferDetails[](1);
        permitParams.transferDetails[0] =
            ISignatureTransfer.SignatureTransferDetails({to: address(router), requestedAmount: amount});
        permitParams.signature = hex"1234";
    }
}
