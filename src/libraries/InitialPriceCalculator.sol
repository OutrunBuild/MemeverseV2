// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

/**
 * @title InitialPriceCalculator for Uniswap V4
 */
library InitialPriceCalculator {
    error ZeroInput();

    error PriceX96Overflow();

    error InvalidSqrtPrice(uint160 sqrtPriceX96);

    error DecimalScaleOverflow(uint8 decimalsDelta);

    /// @notice Calculates the initial sqrtPriceX96 for pool creation based on raw token amounts and token decimals.
    /// @dev Native currency (`address(0)`) is treated as 18 decimals. ERC20 amounts are normalized by scaling the
    ///      lower-decimal side so the derived ratio reflects whole-token price rather than raw base units.
    /// @param token0 The pool's token0 address.
    /// @param token1 The pool's token1 address.
    /// @param amount0Desired The desired amount of token0 in raw token units.
    /// @param amount1Desired The desired amount of token1 in raw token units.
    /// @return sqrtPriceX96 The initial sqrt(price) in Q64.96 format (sqrt(price) × 2^96).
    function calculateInitialSqrtPriceX96(
        address token0,
        address token1,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) internal view returns (uint160 sqrtPriceX96) {
        require(amount0Desired > 0, ZeroInput());
        require(amount1Desired > 0, ZeroInput());

        uint8 decimals0 = _decimals(token0);
        uint8 decimals1 = _decimals(token1);

        if (decimals0 > decimals1) {
            amount1Desired = FullMath.mulDiv(amount1Desired, _pow10(decimals0 - decimals1), 1);
        } else if (decimals1 > decimals0) {
            amount0Desired = FullMath.mulDiv(amount0Desired, _pow10(decimals1 - decimals0), 1);
        }

        return calculateInitialSqrtPriceX96(amount0Desired, amount1Desired);
    }

    /// @notice Calculates the initial sqrtPriceX96 for pool creation based on the provided token amounts
    /// @dev The resulting price satisfies P = amount1 / amount0, where both amounts already share the same decimal
    ///      scale. This is suitable for wide-range or full-range bootstrap positions that want the starting price to
    ///      reflect the provided token value ratio.
    /// @param amount0Desired The desired amount of token0 to provide, normalized to the same decimal scale as token1.
    /// @param amount1Desired The desired amount of token1 to provide, normalized to the same decimal scale as token0.
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
        if (sqrtPriceX96 < TickMath.MIN_SQRT_PRICE || sqrtPriceX96 >= TickMath.MAX_SQRT_PRICE) {
            revert InvalidSqrtPrice(sqrtPriceX96);
        }
    }

    function _decimals(address token) private view returns (uint8) {
        return token == address(0) ? 18 : IERC20Metadata(token).decimals();
    }

    function _pow10(uint8 exponent) private pure returns (uint256 result) {
        result = 1;
        for (uint8 i = 0; i < exponent; ++i) {
            if (result > type(uint256).max / 10) revert DecimalScaleOverflow(exponent);
            result *= 10;
        }
    }
}
