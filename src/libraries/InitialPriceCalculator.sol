// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import { FullMath } from "@uniswap/v4-core/src/libraries/FullMath.sol";

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
    function calculateInitialSqrtPriceX96(
        uint256 amount0Desired,
        uint256 amount1Desired
    ) internal pure returns (uint160 sqrtPriceX96) {
        require(amount0Desired > 0, ZeroInput());
        require(amount1Desired > 0, ZeroInput());

        // Compute ratio = amount1 / amount0 using 512-bit multiplication to avoid overflow
        // Equivalent to (amount1 << 192) / amount0
        uint256 ratioX192 = FullMath.mulDiv(amount1Desired, 1 << 192, amount0Desired);

        // Compute sqrt(ratioX192) → this equals sqrt(amount1 / amount0) × 2^96
        uint256 sqrtRatioX192 = exactSqrt(ratioX192);

        // Downcast to uint160 after shifting right by 96 bits to obtain Q64.96 format
        sqrtPriceX96 = uint160(sqrtRatioX192 >> 96);

        // Safety check: prevent overflow or zero result
        require(sqrtPriceX96 > 0, PriceX96Overflow());
    }

        /// @dev Exact floor integer square root using binary search with bit-length initial guess
    ///      Reduces worst-case iterations from ~256 to ~128
    function exactSqrt(uint256 x) private pure returns (uint256 z) {
        if (x == 0) return 0;
        if (x == 1) return 1;

        // Initial guess: 2 ** ((bit length of x + 1) / 2)
        // This is a very close overestimate (usually within factor of 2)
        uint256 msb = mostSignificantBit(x);
        z = uint256(1) << ((msb + 1) >> 1);

        // Binary search refinement to find largest z where z*z <= x
        uint256 left = (z >> 1);  // Safe lower bound
        uint256 right = z << 1;   // Safe upper bound

        while (left <= right) {
            uint256 mid = left + (right - left) / 2;

            // Overflow-safe multiplication check
            if (mid > type(uint256).max / mid) {
                right = mid - 1;
                continue;
            }

            uint256 square = mid * mid;

            if (square == x) {
                return mid;
            } else if (square < x) {
                left = mid + 1;
            } else {
                right = mid - 1;
            }
        }

        return right; // right is the largest integer where right*right <= x
    }

    /// @dev Computes the position of the most significant bit (bit length - 1)
    ///      Equivalent to x.bit_length() - 1 in Python
    function mostSignificantBit(uint256 x) private pure returns (uint256 msb) {
        unchecked {
            if (x >= 1 << 128) {
                x >>= 128;
                msb = 128;
            }
            if (x >= 1 << 64) {
                x >>= 64;
                msb += 64;
            }
            if (x >= 1 << 32) {
                x >>= 32;
                msb += 32;
            }
            if (x >= 1 << 16) {
                x >>= 16;
                msb += 16;
            }
            if (x >= 1 << 8) {
                x >>= 8;
                msb += 8;
            }
            if (x >= 1 << 4) {
                x >>= 4;
                msb += 4;
            }
            if (x >= 1 << 2) {
                x >>= 2;
                msb += 2;
            }
            if (x >= 1 << 1) {
                msb += 1;
            }
        }
    }
}
