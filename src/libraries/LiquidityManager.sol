// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IPoolInitializer_v4} from "@uniswap/v4-periphery/src/interfaces/IPoolInitializer_v4.sol";
import {IMulticall_v4} from "@uniswap/v4-periphery/src/interfaces/IMulticall_v4.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";

import {InitialPriceCalculator} from "../libraries/InitialPriceCalculator.sol";

interface IHookLiquidityManager {
    struct AddLiquidityParams {
        Currency currency0;
        Currency currency1;
        uint24 fee;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address to;
        uint256 deadline;
    }

    function addLiquidity(AddLiquidityParams calldata params) external returns (uint128 liquidity);
}

/**
 * @title Liquidity Manager(For uniswap v4)
 */
library LiquidityManager {
    int24 public constant TICK_SPACING = 200;
    int24 public constant TICK_LOWER = -887200;
    int24 public constant TICK_UPPER = 887200;
    // TickMath.getSqrtPriceAtTick(-887200)
    uint160 public constant SQRT_PRICE_LOWER_X96 = 4310618292;
    // TickMath.getSqrtPriceAtTick(887200)
    uint160 public constant SQRT_PRICE_UPPER_X96 = 1456195216270955103206513029158776779468408838535;

    error InvalidTokenPair();

    error ZeroLiquidity();

    error AmountExceedsUint128();

    function createPoolAndAddLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        address permit2,
        address positionManager,
        address recipient,
        IHooks hook
    ) internal returns (uint128 liquidity, PoolKey memory poolKey) {
        if (tokenA == tokenB) revert InvalidTokenPair();

        (Currency currency0, Currency currency1) = tokenA < tokenB
            ? (Currency.wrap(tokenA), Currency.wrap(tokenB))
            : (Currency.wrap(tokenB), Currency.wrap(tokenA));
        uint256 amount0Desired = tokenA < tokenB ? amountADesired : amountBDesired;
        uint256 amount1Desired = tokenA < tokenB ? amountBDesired : amountADesired;
        uint24 fee = _poolFee(hook);

        uint160 startingPrice = InitialPriceCalculator.calculateInitialSqrtPriceX96(amount0Desired, amount1Desired);

        poolKey =
            PoolKey({currency0: currency0, currency1: currency1, fee: fee, tickSpacing: TICK_SPACING, hooks: hook});

        bytes memory hookData = new bytes(0);
        if (address(hook) == address(0)) {
            liquidity = LiquidityAmounts.getLiquidityForAmounts(
                startingPrice, SQRT_PRICE_LOWER_X96, SQRT_PRICE_UPPER_X96, amount0Desired, amount1Desired
            );
            if (liquidity == 0) revert ZeroLiquidity();

            (bytes memory actions, bytes[] memory mintParams) = mintLiquidityParams(
                poolKey,
                TICK_LOWER,
                TICK_UPPER,
                liquidity,
                _toUint128WithDust(amount0Desired),
                _toUint128WithDust(amount1Desired),
                recipient,
                hookData
            );

            bytes[] memory params = new bytes[](2);
            params[0] = abi.encodeWithSelector(IPoolInitializer_v4.initializePool.selector, poolKey, startingPrice);
            params[1] = abi.encodeWithSelector(
                IPositionManager.modifyLiquidities.selector, abi.encode(actions, mintParams), block.timestamp
            );

            tokenApprovalsForPermit2(tokenA, tokenB, permit2, positionManager);
            IMulticall_v4(positionManager).multicall(params);
            return (liquidity, poolKey);
        }

        // For hook-based pools (for example MemeverseUniswapHook), liquidity must be added through the hook.
        IPoolInitializer_v4(positionManager).initializePool(poolKey, startingPrice);
        tokenApprovalsToSpender(tokenA, tokenB, address(hook));
        liquidity = IHookLiquidityManager(address(hook))
            .addLiquidity(
                IHookLiquidityManager.AddLiquidityParams({
                    currency0: currency0,
                    currency1: currency1,
                    fee: fee,
                    amount0Desired: amount0Desired,
                    amount1Desired: amount1Desired,
                    amount0Min: 0,
                    amount1Min: 0,
                    to: recipient,
                    deadline: block.timestamp
                })
            );
        if (liquidity == 0) revert ZeroLiquidity();
    }

    function mintLiquidityParams(
        PoolKey memory poolKey,
        int24 _tickLower,
        int24 _tickUpper,
        uint128 liquidity,
        uint128 amount0Max,
        uint128 amount1Max,
        address recipient,
        bytes memory hookData
    ) internal pure returns (bytes memory, bytes[] memory) {
        bytes memory actions = abi.encodePacked(
            uint8(Actions.MINT_POSITION), uint8(Actions.SETTLE_PAIR), uint8(Actions.SWEEP), uint8(Actions.SWEEP)
        );

        bytes[] memory params = new bytes[](4);
        params[0] = abi.encode(poolKey, _tickLower, _tickUpper, liquidity, amount0Max, amount1Max, recipient, hookData);
        params[1] = abi.encode(poolKey.currency0, poolKey.currency1);
        params[2] = abi.encode(poolKey.currency0, recipient);
        params[3] = abi.encode(poolKey.currency1, recipient);

        return (actions, params);
    }

    function tokenApprovalsForPermit2(address tokenA, address tokenB, address permit2, address positionManager)
        internal
    {
        if (tokenA != address(0)) {
            IERC20(tokenA).approve(address(permit2), type(uint256).max);
            IPermit2(permit2).approve(address(tokenA), address(positionManager), type(uint160).max, type(uint48).max);
        }

        if (tokenB != address(0)) {
            IERC20(tokenB).approve(address(permit2), type(uint256).max);
            IPermit2(permit2).approve(address(tokenB), address(positionManager), type(uint160).max, type(uint48).max);
        }
    }

    function tokenApprovalsToSpender(address tokenA, address tokenB, address spender) internal {
        if (tokenA != address(0)) IERC20(tokenA).approve(spender, type(uint256).max);
        if (tokenB != address(0)) IERC20(tokenB).approve(spender, type(uint256).max);
    }

    function _poolFee(IHooks hook) private pure returns (uint24 fee) {
        if (address(hook) == address(0)) return 0;
        return LPFeeLibrary.DYNAMIC_FEE_FLAG;
    }

    function _toUint128WithDust(uint256 amount) private pure returns (uint128) {
        if (amount > type(uint128).max - 1) revert AmountExceedsUint128();
        return uint128(amount + 1);
    }
}
