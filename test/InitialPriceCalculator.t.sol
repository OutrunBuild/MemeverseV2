// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

import {InitialPriceCalculator} from "../src/libraries/InitialPriceCalculator.sol";

contract InitialPriceCalculatorTest is Test {
    uint160 internal constant Q96 = uint160(1 << 96);

    address internal constant LOWER = address(0x1000);
    address internal constant HIGHER = address(0x2000);

    /// @notice Exposes the amount-based start-price helper for external revert assertions.
    /// @dev Allows `vm.expectRevert` to target the library via an external call.
    /// @param tokenA The first token address supplied to the helper.
    /// @param tokenB The second token address supplied to the helper.
    /// @param amountADesired The raw amount for `tokenA`.
    /// @param amountBDesired The raw amount for `tokenB`.
    /// @return sqrtPriceX96 The computed Uniswap v4 start price.
    function calculateInitialSqrtPriceX96External(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired
    ) external pure returns (uint160) {
        return InitialPriceCalculator.calculateInitialSqrtPriceX96(tokenA, tokenB, amountADesired, amountBDesired);
    }

    /// @notice Exposes the `fundBasedAmount` helper for external revert assertions.
    /// @dev Allows `vm.expectRevert` to target the library via an external call.
    /// @param memecoin The memecoin address.
    /// @param upt The UPT address.
    /// @param fundBasedAmount The memecoin units minted per 1 UPT.
    /// @return sqrtPriceX96 The computed Uniswap v4 start price.
    function calculateMemecoinStartPriceX96External(address memecoin, address upt, uint256 fundBasedAmount)
        external
        pure
        returns (uint160)
    {
        return InitialPriceCalculator.calculateMemecoinStartPriceX96(memecoin, upt, fundBasedAmount);
    }

    /// @notice Verifies equal budgets produce the canonical 1:1 `sqrtPriceX96`.
    /// @dev Confirms the helper returns `Q96` for a 1:1 18-decimal pair.
    function testCalculateInitialSqrtPriceX96AtOneToOne() external pure {
        uint160 sqrtPriceX96 = InitialPriceCalculator.calculateInitialSqrtPriceX96(LOWER, HIGHER, 1 ether, 1 ether);
        assertEq(sqrtPriceX96, Q96);
    }

    /// @notice Verifies the amount-based helper respects Uniswap token sorting.
    /// @dev The same economic ratio should resolve to the same sorted pool price.
    function testCalculateInitialSqrtPriceX96RespectsAddressSorting() external pure {
        uint160 sqrtPriceX96 = InitialPriceCalculator.calculateInitialSqrtPriceX96(LOWER, HIGHER, 4 ether, 1 ether);
        assertEq(sqrtPriceX96, Q96 / 2);

        sqrtPriceX96 = InitialPriceCalculator.calculateInitialSqrtPriceX96(HIGHER, LOWER, 1 ether, 4 ether);
        assertEq(sqrtPriceX96, Q96 / 2);
    }

    /// @notice Verifies `fundBasedAmount` mapping when memecoin sorts as token0.
    /// @dev When memecoin is token0, `fundBasedAmount` maps to the inverse pool price.
    function testCalculateMemecoinStartPriceX96UsesFundBasedAmountWhenMemecoinSortsFirst() external pure {
        uint160 sqrtPriceX96 = InitialPriceCalculator.calculateMemecoinStartPriceX96(LOWER, HIGHER, 4);
        assertEq(sqrtPriceX96, Q96 / 2);
    }

    /// @notice Verifies `fundBasedAmount` mapping when UPT sorts as token0.
    /// @dev When UPT is token0, `fundBasedAmount` maps directly to the pool price.
    function testCalculateMemecoinStartPriceX96UsesFundBasedAmountWhenUptSortsFirst() external pure {
        uint160 sqrtPriceX96 = InitialPriceCalculator.calculateMemecoinStartPriceX96(HIGHER, LOWER, 4);
        assertEq(sqrtPriceX96, Q96 * 2);
    }

    /// @notice Verifies zero amount input is rejected for the amount-based helper.
    /// @dev Zero budgets must fail before any price math executes.
    function testCalculateInitialSqrtPriceX96RevertOnZeroInput() external {
        vm.expectRevert(InitialPriceCalculator.ZeroInput.selector);
        this.calculateInitialSqrtPriceX96External(LOWER, HIGHER, 0, 1 ether);
    }

    /// @notice Verifies zero `fundBasedAmount` is rejected for the memecoin helper.
    /// @dev A zero bootstrap ratio is invalid for the launcher-scoped helper.
    function testCalculateMemecoinStartPriceX96RevertOnZeroInput() external {
        vm.expectRevert(InitialPriceCalculator.ZeroInput.selector);
        this.calculateMemecoinStartPriceX96External(LOWER, HIGHER, 0);
    }

    /// @notice Verifies extremely low price ratios still respect the TickMath lower bound.
    /// @dev Ratios below the supported TickMath floor must revert with `InvalidSqrtPrice`.
    function testCalculateInitialSqrtPriceX96RevertOnBelowMinSqrtPrice() external {
        vm.expectRevert(abi.encodeWithSelector(InitialPriceCalculator.InvalidSqrtPrice.selector, uint160(2)));
        this.calculateInitialSqrtPriceX96External(LOWER, HIGHER, 1 << 190, 1);

        assertGt(TickMath.MIN_SQRT_PRICE, 2);
    }

    /// @notice Verifies unsupported high amount ratios fail explicitly before overflow.
    /// @dev The helper exposes its `2^64` price-ratio ceiling through a dedicated custom error.
    function testCalculateInitialSqrtPriceX96RevertOnUnsupportedHighRatio() external {
        vm.expectRevert(
            abi.encodeWithSelector(InitialPriceCalculator.PriceRatioTooHigh.selector, uint256(1), uint256(1 << 64))
        );
        this.calculateInitialSqrtPriceX96External(LOWER, HIGHER, 1, 1 << 64);
    }

    /// @notice Verifies unsupported high `fundBasedAmount` values fail explicitly.
    /// @dev Oversized launcher ratios must fail before reaching `FullMath.mulDiv`.
    function testCalculateMemecoinStartPriceX96RevertOnUnsupportedHighRatio() external {
        vm.expectRevert(
            abi.encodeWithSelector(InitialPriceCalculator.PriceRatioTooHigh.selector, uint256(1), uint256(1 << 64))
        );
        this.calculateMemecoinStartPriceX96External(HIGHER, LOWER, 1 << 64);
    }
}
