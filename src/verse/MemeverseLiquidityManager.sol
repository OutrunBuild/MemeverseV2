// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";
import { LiquidityAmounts } from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { Actions } from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import { IPositionManager } from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import { IPoolInitializer_v4 } from "@uniswap/v4-periphery/src/interfaces/IPoolInitializer_v4.sol";
import { IMulticall_v4 } from "@uniswap/v4-periphery/src/interfaces/IMulticall_v4.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

import { InitialPriceCalculator } from "../libraries/InitialPriceCalculator.sol";
import { IMemeverseLiquidityManager, IHooks } from "./interfaces/IMemeverseLiquidityManager.sol";

/**
 * @title Memeverse Liquidity Manager(For uniswap v4)
 */ 
contract MemeverseLiquidityManager is IMemeverseLiquidityManager, Ownable {
    int24 public constant TICK_SPACING = 200;
    int24 public constant TICK_LOWER = -887200;
    int24 public constant TICK_UPPER = 887200;
    // TickMath.getSqrtPriceAtTick(-887200)
    uint160 public constant SQRT_PRICE_LOWER_X96 = 4310618292;
    // TickMath.getSqrtPriceAtTick(887200)
    uint160 public constant SQRT_PRICE_UPPER_X96 = 1456195216270955103206513029158776779468408838535;

    address public immutable positionManager;
    address public immutable permit2;

    constructor(address _owner) Ownable(_owner) {}

    function createPoolAndAddLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        address recipient,
        IHooks hook
    ) external override {
        (Currency currency0, Currency currency1) = tokenA < tokenB 
            ? (Currency.wrap(tokenA), Currency.wrap(tokenB))
            : (Currency.wrap(tokenB), Currency.wrap(tokenA));
        uint256 amount0Desired = tokenA < tokenB ? amountADesired : amountBDesired;
        uint256 amount1Desired = tokenA < tokenB ? amountBDesired : amountADesired;

        uint160 startingPrice = InitialPriceCalculator.calculateInitialSqrtPriceX96(
            amount0Desired,
            amount1Desired
        );

        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            startingPrice,
            SQRT_PRICE_LOWER_X96,
            SQRT_PRICE_UPPER_X96,
            amount0Desired,
            amount1Desired
        );
        
        PoolKey memory poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: 0,
            tickSpacing: TICK_SPACING,
            hooks: hook
        });

        bytes memory hookData = new bytes(0);
        (bytes memory actions, bytes[] memory mintParams) = _mintLiquidityParams(
            poolKey, TICK_LOWER, TICK_UPPER, liquidity, amount0Desired + 1, amount1Desired + 1, recipient, hookData
        );

        bytes[] memory params = new bytes[](2);

        // Initialize Pool
        params[0] = abi.encodeWithSelector(IPoolInitializer_v4.initializePool.selector, poolKey, startingPrice, hookData);

        // Mint Liquidity
        params[1] = abi.encodeWithSelector(
            IPositionManager.modifyLiquidities.selector, abi.encode(actions, mintParams), block.timestamp
        );

        tokenApprovals(tokenA, tokenB);
        IMulticall_v4(positionManager).multicall(params);
    }

    function _mintLiquidityParams(
        PoolKey memory poolKey,
        int24 _tickLower,
        int24 _tickUpper,
        uint256 liquidity,
        uint256 amount0Max,
        uint256 amount1Max,
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

    function tokenApprovals(address tokenA, address tokenB) public {
        if (tokenA != address(0)) {
            IERC20(tokenA).approve(address(permit2), type(uint256).max);
            IPermit2(permit2).approve(address(tokenA), address(positionManager), type(uint160).max, type(uint48).max);
        }

        if (tokenB != address(0)) {
            IERC20(tokenB).approve(address(permit2), type(uint256).max);
            IPermit2(permit2).approve(address(tokenB), address(positionManager), type(uint160).max, type(uint48).max);
        }
    }
}
