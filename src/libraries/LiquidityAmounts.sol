// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {FixedPoint96} from "@uniswap/v4-core/src/libraries/FixedPoint96.sol";

import {SafeCast} from "./SafeCast.sol";

/// @title LiquidityAmounts
/// @notice Internal liquidity math helpers for full-range and bounded-range Uniswap-style positions.
/// @dev This is a production-owned copy of the standard liquidity amount formulas so Memeverse code does not depend
/// on upstream test utilities.
library LiquidityAmounts {
    using SafeCast for uint256;

    /// @notice Computes the liquidity supported by a token0 amount across a price range.
    /// @param sqrtPriceAX96 One boundary sqrt price.
    /// @param sqrtPriceBX96 The other boundary sqrt price.
    /// @param amount0 The token0 amount.
    /// @return liquidity The supported liquidity.
    function getLiquidityForAmount0(uint160 sqrtPriceAX96, uint160 sqrtPriceBX96, uint256 amount0)
        internal
        pure
        returns (uint128 liquidity)
    {
        unchecked {
            if (sqrtPriceAX96 > sqrtPriceBX96) (sqrtPriceAX96, sqrtPriceBX96) = (sqrtPriceBX96, sqrtPriceAX96);
            uint256 intermediate = FullMath.mulDiv(sqrtPriceAX96, sqrtPriceBX96, FixedPoint96.Q96);
            return FullMath.mulDiv(amount0, intermediate, sqrtPriceBX96 - sqrtPriceAX96).toUint128();
        }
    }

    /// @notice Computes the liquidity supported by a token1 amount across a price range.
    /// @param sqrtPriceAX96 One boundary sqrt price.
    /// @param sqrtPriceBX96 The other boundary sqrt price.
    /// @param amount1 The token1 amount.
    /// @return liquidity The supported liquidity.
    function getLiquidityForAmount1(uint160 sqrtPriceAX96, uint160 sqrtPriceBX96, uint256 amount1)
        internal
        pure
        returns (uint128 liquidity)
    {
        unchecked {
            if (sqrtPriceAX96 > sqrtPriceBX96) (sqrtPriceAX96, sqrtPriceBX96) = (sqrtPriceBX96, sqrtPriceAX96);
            return FullMath.mulDiv(amount1, FixedPoint96.Q96, sqrtPriceBX96 - sqrtPriceAX96).toUint128();
        }
    }

    /// @notice Computes the maximum liquidity supported by token budgets at a current pool price.
    /// @param sqrtPriceX96 The current pool sqrt price.
    /// @param sqrtPriceAX96 One boundary sqrt price.
    /// @param sqrtPriceBX96 The other boundary sqrt price.
    /// @param amount0 The token0 budget.
    /// @param amount1 The token1 budget.
    /// @return liquidity The supported liquidity.
    function getLiquidityForAmounts(
        uint160 sqrtPriceX96,
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96,
        uint256 amount0,
        uint256 amount1
    ) internal pure returns (uint128 liquidity) {
        if (sqrtPriceAX96 > sqrtPriceBX96) {
            (sqrtPriceAX96, sqrtPriceBX96) = (sqrtPriceBX96, sqrtPriceAX96);
        }

        if (sqrtPriceX96 <= sqrtPriceAX96) {
            liquidity = getLiquidityForAmount0(sqrtPriceAX96, sqrtPriceBX96, amount0);
        } else if (sqrtPriceX96 < sqrtPriceBX96) {
            uint128 liquidity0 = getLiquidityForAmount0(sqrtPriceX96, sqrtPriceBX96, amount0);
            uint128 liquidity1 = getLiquidityForAmount1(sqrtPriceAX96, sqrtPriceX96, amount1);
            liquidity = liquidity0 < liquidity1 ? liquidity0 : liquidity1;
        } else {
            liquidity = getLiquidityForAmount1(sqrtPriceAX96, sqrtPriceBX96, amount1);
        }
    }

    /// @notice Computes the token0 amount represented by liquidity over a price range.
    /// @param sqrtPriceAX96 One boundary sqrt price.
    /// @param sqrtPriceBX96 The other boundary sqrt price.
    /// @param liquidity The liquidity amount.
    /// @return amount0 The token0 amount represented by `liquidity`.
    function getAmount0ForLiquidity(uint160 sqrtPriceAX96, uint160 sqrtPriceBX96, uint128 liquidity)
        internal
        pure
        returns (uint256 amount0)
    {
        if (sqrtPriceAX96 > sqrtPriceBX96) (sqrtPriceAX96, sqrtPriceBX96) = (sqrtPriceBX96, sqrtPriceAX96);

        return FullMath.mulDiv(
            uint256(liquidity) << FixedPoint96.RESOLUTION, sqrtPriceBX96 - sqrtPriceAX96, sqrtPriceBX96
        ) / sqrtPriceAX96;
    }

    /// @notice Computes the token1 amount represented by liquidity over a price range.
    /// @param sqrtPriceAX96 One boundary sqrt price.
    /// @param sqrtPriceBX96 The other boundary sqrt price.
    /// @param liquidity The liquidity amount.
    /// @return amount1 The token1 amount represented by `liquidity`.
    function getAmount1ForLiquidity(uint160 sqrtPriceAX96, uint160 sqrtPriceBX96, uint128 liquidity)
        internal
        pure
        returns (uint256 amount1)
    {
        if (sqrtPriceAX96 > sqrtPriceBX96) (sqrtPriceAX96, sqrtPriceBX96) = (sqrtPriceBX96, sqrtPriceAX96);
        return FullMath.mulDiv(liquidity, sqrtPriceBX96 - sqrtPriceAX96, FixedPoint96.Q96);
    }

    /// @notice Computes the token0 and token1 amounts represented by liquidity at a current pool price.
    /// @param sqrtPriceX96 The current pool sqrt price.
    /// @param sqrtPriceAX96 One boundary sqrt price.
    /// @param sqrtPriceBX96 The other boundary sqrt price.
    /// @param liquidity The liquidity amount.
    /// @return amount0 The token0 amount represented by `liquidity`.
    /// @return amount1 The token1 amount represented by `liquidity`.
    function getAmountsForLiquidity(
        uint160 sqrtPriceX96,
        uint160 sqrtPriceAX96,
        uint160 sqrtPriceBX96,
        uint128 liquidity
    ) internal pure returns (uint256 amount0, uint256 amount1) {
        if (sqrtPriceAX96 > sqrtPriceBX96) {
            (sqrtPriceAX96, sqrtPriceBX96) = (sqrtPriceBX96, sqrtPriceAX96);
        }

        if (sqrtPriceX96 <= sqrtPriceAX96) {
            amount0 = getAmount0ForLiquidity(sqrtPriceAX96, sqrtPriceBX96, liquidity);
        } else if (sqrtPriceX96 < sqrtPriceBX96) {
            amount0 = getAmount0ForLiquidity(sqrtPriceX96, sqrtPriceBX96, liquidity);
            amount1 = getAmount1ForLiquidity(sqrtPriceAX96, sqrtPriceX96, liquidity);
        } else {
            amount1 = getAmount1ForLiquidity(sqrtPriceAX96, sqrtPriceBX96, liquidity);
        }
    }
}
