// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {InitialPriceCalculator} from "../src/libraries/InitialPriceCalculator.sol";

contract InitialPriceCalculatorTest is Test {
    uint160 internal constant Q96 = uint160(1 << 96);

    /// @notice Proxies the library call so revert behavior can be asserted via an external call.
    /// @dev Used only by the revert-path test in this contract.
    /// @param amount0Desired Desired amount of token0 used to derive the initial price.
    /// @param amount1Desired Desired amount of token1 used to derive the initial price.
    /// @return The computed initial `sqrtPriceX96`.
    function calculateInitialSqrtPriceX96External(uint256 amount0Desired, uint256 amount1Desired)
        external
        pure
        returns (uint160)
    {
        return InitialPriceCalculator.calculateInitialSqrtPriceX96(amount0Desired, amount1Desired);
    }

    /// @notice Spec: returns `Q96` when token0 and token1 inputs are equal.
    /// @dev Verifies the 1:1 price initialization path.
    function testCalculateInitialSqrtPriceX96AtOneToOne() external pure {
        uint160 sqrtPriceX96 = InitialPriceCalculator.calculateInitialSqrtPriceX96(1e18, 1e18);
        assertEq(sqrtPriceX96, Q96);
    }

    /// @notice Spec: returns `2 * Q96` when token1 amount is 4x token0 amount.
    /// @dev Verifies initialization for a price ratio of 4:1.
    function testCalculateInitialSqrtPriceX96AtFourToOne() external pure {
        uint160 sqrtPriceX96 = InitialPriceCalculator.calculateInitialSqrtPriceX96(1e18, 4e18);
        assertEq(sqrtPriceX96, Q96 * 2);
    }

    /// @notice Spec: returns `Q96 / 2` when token0 amount is 4x token1 amount.
    /// @dev Verifies initialization for a price ratio of 1:4.
    function testCalculateInitialSqrtPriceX96AtOneToFour() external pure {
        uint160 sqrtPriceX96 = InitialPriceCalculator.calculateInitialSqrtPriceX96(4e18, 1e18);
        assertEq(sqrtPriceX96, Q96 / 2);
    }

    /// @notice Spec: reverts with `ZeroInput` when either side of the ratio is zero.
    /// @dev Exercises the explicit zero-input guard in the library.
    function testCalculateInitialSqrtPriceX96RevertOnZeroInput() external {
        vm.expectRevert(InitialPriceCalculator.ZeroInput.selector);
        this.calculateInitialSqrtPriceX96External(0, 1e18);
    }
}
