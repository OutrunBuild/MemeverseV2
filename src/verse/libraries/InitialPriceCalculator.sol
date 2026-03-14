// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

/// @title InitialPriceCalculator
/// @notice Launcher-scoped helper for deriving Uniswap v4 `sqrtPriceX96` values under the 18-decimal token assumption.
library InitialPriceCalculator {
    error ZeroInput();

    error InvalidSqrtPrice(uint160 sqrtPriceX96);

    error PriceRatioTooHigh(uint256 amount0Desired, uint256 amount1Desired);

    uint256 internal constant Q192 = 1 << 192;
    uint256 internal constant MAX_SUPPORTED_PRICE_RATIO = 1 << 64;

    /// @notice Calculates the initial `sqrtPriceX96` for a pair where both tokens use 18 decimals.
    /// @dev The returned price always follows Uniswap ordering semantics: `price = token1 / token0`.
    /// @param tokenA One side of the pair.
    /// @param tokenB The other side of the pair.
    /// @param amountADesired Desired raw amount for `tokenA`.
    /// @param amountBDesired Desired raw amount for `tokenB`.
    /// @return sqrtPriceX96 The initial pool price in Q64.96 format.
    function calculateInitialSqrtPriceX96(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired
    ) internal pure returns (uint160 sqrtPriceX96) {
        require(amountADesired > 0, ZeroInput());
        require(amountBDesired > 0, ZeroInput());

        (uint256 amount0Desired, uint256 amount1Desired) =
            tokenA < tokenB ? (amountADesired, amountBDesired) : (amountBDesired, amountADesired);
        sqrtPriceX96 = _calculateFromSortedAmounts(amount0Desired, amount1Desired);
    }

    /// @notice Calculates the memecoin bootstrap price directly from `fundBasedAmount`.
    /// @dev Assumes both tokens use 18 decimals and `fundBasedAmount` is the number of memecoins minted per 1 UPT.
    /// @param memecoin The memecoin address.
    /// @param upt The funding token address.
    /// @param fundBasedAmount Memecoins minted per unit of UPT funding.
    /// @return sqrtPriceX96 The initial pool price in Q64.96 format.
    function calculateMemecoinStartPriceX96(address memecoin, address upt, uint256 fundBasedAmount)
        internal
        pure
        returns (uint160 sqrtPriceX96)
    {
        require(fundBasedAmount > 0, ZeroInput());

        (uint256 amount0Desired, uint256 amount1Desired) =
            memecoin < upt ? (fundBasedAmount, uint256(1)) : (uint256(1), fundBasedAmount);
        sqrtPriceX96 = _calculateFromSortedAmounts(amount0Desired, amount1Desired);
    }

    function _calculateFromSortedAmounts(uint256 amount0Desired, uint256 amount1Desired)
        private
        pure
        returns (uint160 sqrtPriceX96)
    {
        _validateSupportedRatio(amount0Desired, amount1Desired);
        sqrtPriceX96 = uint160(Math.sqrt(FullMath.mulDiv(amount1Desired, Q192, amount0Desired)));
        if (sqrtPriceX96 < TickMath.MIN_SQRT_PRICE || sqrtPriceX96 >= TickMath.MAX_SQRT_PRICE) {
            revert InvalidSqrtPrice(sqrtPriceX96);
        }
    }

    function _validateSupportedRatio(uint256 amount0Desired, uint256 amount1Desired) private pure {
        if (amount0Desired > type(uint256).max / MAX_SUPPORTED_PRICE_RATIO) return;
        if (amount1Desired >= amount0Desired * MAX_SUPPORTED_PRICE_RATIO) {
            revert PriceRatioTooHigh(amount0Desired, amount1Desired);
        }
    }
}
