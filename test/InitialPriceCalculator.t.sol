// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

import {InitialPriceCalculator} from "../src/libraries/InitialPriceCalculator.sol";

contract InitialPriceCalculatorTest is Test {
    uint160 internal constant Q96 = uint160(1 << 96);

    MockERC20 internal token18A;
    MockERC20 internal token18B;
    MockERC20 internal token6;

    /// @notice Deploys mock ERC20 tokens used by the decimals-aware tests.
    /// @dev Creates two 18-decimal tokens and one 6-decimal token.
    function setUp() external {
        token18A = new MockERC20("Token18A", "T18A", 18);
        token18B = new MockERC20("Token18B", "T18B", 18);
        token6 = new MockERC20("Token6", "T6", 6);
    }

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

    /// @notice Proxies the decimals-aware library call so revert behavior can be asserted via an external call.
    /// @dev Used by tests that need to exercise the address-aware overload through an external call.
    /// @param token0 Token0 address used to read decimals metadata.
    /// @param token1 Token1 address used to read decimals metadata.
    /// @param amount0Desired Desired amount of token0 in raw token units.
    /// @param amount1Desired Desired amount of token1 in raw token units.
    /// @return The computed `sqrtPriceX96`.
    function calculateInitialSqrtPriceX96WithTokensExternal(
        address token0,
        address token1,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) external view returns (uint160) {
        return InitialPriceCalculator.calculateInitialSqrtPriceX96(token0, token1, amount0Desired, amount1Desired);
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

    /// @notice Spec: decimals-aware pricing preserves 1:1 value for two 18-decimal tokens.
    /// @dev Verifies the address-aware overload matches the expected 1:1 Q96 ratio for equal-decimal assets.
    function testCalculateInitialSqrtPriceX96WithTokenDecimalsAtOneToOne18And18() external view {
        uint160 sqrtPriceX96 =
            InitialPriceCalculator.calculateInitialSqrtPriceX96(address(token18A), address(token18B), 1e18, 1e18);
        assertEq(sqrtPriceX96, Q96);
    }

    /// @notice Spec: decimals-aware pricing normalizes a 18-decimal token against a 6-decimal token.
    /// @dev Verifies equal-value raw amounts across 18/6 decimals still produce a 1:1 initial price.
    function testCalculateInitialSqrtPriceX96WithTokenDecimalsAtOneToOne18And6() external view {
        uint160 sqrtPriceX96 =
            InitialPriceCalculator.calculateInitialSqrtPriceX96(address(token18A), address(token6), 1e18, 1e6);
        assertEq(sqrtPriceX96, Q96);
    }

    /// @notice Spec: decimals-aware pricing normalizes a 6-decimal token against a 18-decimal token.
    /// @dev Verifies equal-value raw amounts across 6/18 decimals still produce a 1:1 initial price.
    function testCalculateInitialSqrtPriceX96WithTokenDecimalsAtOneToOne6And18() external view {
        uint160 sqrtPriceX96 =
            InitialPriceCalculator.calculateInitialSqrtPriceX96(address(token6), address(token18A), 1e6, 1e18);
        assertEq(sqrtPriceX96, Q96);
    }

    /// @notice Spec: reverts with `ZeroInput` when either side of the ratio is zero.
    /// @dev Exercises the explicit zero-input guard in the library.
    function testCalculateInitialSqrtPriceX96RevertOnZeroInput() external {
        vm.expectRevert(InitialPriceCalculator.ZeroInput.selector);
        this.calculateInitialSqrtPriceX96External(0, 1e18);
    }

    /// @notice Spec: reverts when the derived sqrt price falls below the Uniswap v4 valid range.
    /// @dev Exercises the explicit TickMath lower-bound guard for extremely imbalanced normalized amounts.
    function testCalculateInitialSqrtPriceX96RevertOnBelowMinSqrtPrice() external {
        vm.expectRevert(abi.encodeWithSelector(InitialPriceCalculator.InvalidSqrtPrice.selector, uint160(2)));
        this.calculateInitialSqrtPriceX96External(1 << 190, 1);

        assertGt(TickMath.MIN_SQRT_PRICE, 2);
    }
}
