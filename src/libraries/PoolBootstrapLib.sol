// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {LiquidityAmounts} from "./LiquidityAmounts.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IPoolInitializer_v4} from "@uniswap/v4-periphery/src/interfaces/IPoolInitializer_v4.sol";
import {IMulticall_v4} from "@uniswap/v4-periphery/src/interfaces/IMulticall_v4.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";

import {InitialPriceCalculator} from "../libraries/InitialPriceCalculator.sol";
import {LiquidityQuote} from "../libraries/LiquidityQuote.sol";

interface IHookLiquidityManager {
    struct AddLiquidityCoreParams {
        Currency currency0;
        Currency currency1;
        uint256 amount0Desired;
        uint256 amount1Desired;
        address to;
    }

    function addLiquidityCore(AddLiquidityCoreParams calldata params)
        external
        payable
        returns (uint128 liquidity, BalanceDelta delta);
}

/**
 * @title PoolBootstrapLib
 * @notice Bootstrap helpers for initializing Memeverse-compatible pools and seeding first liquidity.
 */
library PoolBootstrapLib {
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
            // No-hook path:
            // - Bootstrap goes through the standard position manager mint flow.
            // - Liquidity is computed directly from the desired token budgets at the initialized price.
            // - The desired amounts are then forwarded as the position manager's max token budgets
            //   (with the usual 1 wei dust padding via `_toUint128WithDust`).
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

        // Hook path:
        // - Bootstrap must go through the hook Core entrypoint instead of the standard position manager mint flow.
        // - The hook still receives the caller's desired token budgets, but the bootstrap helper separately quotes
        //   the actual token usage implied by those budgets at the initialized price.
        // - That quote is used here only to determine the exact native value that must accompany the hook call,
        //   because hook-backed liquidity adds enforce exact native funding.
        IPoolInitializer_v4(positionManager).initializePool(poolKey, startingPrice);
        tokenApprovalsToSpender(tokenA, tokenB, address(hook));
        (, uint256 amount0Used, uint256 amount1Used) =
            LiquidityQuote.quote(startingPrice, amount0Desired, amount1Desired);
        uint256 nativeValue = currency0 == Currency.wrap(address(0))
            ? amount0Used
            : currency1 == Currency.wrap(address(0)) ? amount1Used : 0;
        (liquidity,) = IHookLiquidityManager(address(hook)).addLiquidityCore{value: nativeValue}(
            IHookLiquidityManager.AddLiquidityCoreParams({
                currency0: currency0,
                currency1: currency1,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                to: recipient
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
