// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";

/**
 * @title InitialPriceCalculator for Uniswap V4
 */
library InitialPriceCalculator {
    error ZeroInput();

    error PriceX96Overflow();

    /// @notice Calculates the initial sqrtPriceX96 for pool creation based on the provided token amounts
    /// @dev The resulting price satisfies P = (amount1 / amount0)^2, ensuring both token amounts are fully utilized
    ///      (applicable for wide-range or full-range initial positions)
    /// @param amount0Desired The desired amount of token0 to provide (adjusted for decimals)
    /// @param amount1Desired The desired amount of token1 to provide (adjusted for decimals)
    /// @return sqrtPriceX96 The initial sqrt(price) in Q64.96 format (sqrt(price) × 2^96)
    function calculateInitialSqrtPriceX96(uint256 amount0Desired, uint256 amount1Desired)
        internal
        pure
        returns (uint160 sqrtPriceX96)
    {
        require(amount0Desired > 0, ZeroInput());
        require(amount1Desired > 0, ZeroInput());

        // Mirrors Uniswap's encodeSqrtRatioX96 flow: sqrt((amount1 << 192) / amount0).
        uint256 ratioX192 = FullMath.mulDiv(amount1Desired, 1 << 192, amount0Desired);
        uint256 sqrtRatioX96 = Math.sqrt(ratioX192);
        require(sqrtRatioX96 <= type(uint160).max, PriceX96Overflow());
        sqrtPriceX96 = uint160(sqrtRatioX96);

        // Safety check: prevent zero result
        require(sqrtPriceX96 > 0, PriceX96Overflow());
    }
}
