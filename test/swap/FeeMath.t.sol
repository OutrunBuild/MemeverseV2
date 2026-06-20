// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";

import {FeeMath} from "../../src/swap/libraries/FeeMath.sol";

/// @notice Focused tests for shared fee split math.
contract FeeMathTest is Test {
    function testSharedFeeMathKeepsProtocolAndLpSplitAtThirtySeventy() external pure {
        assertEq(FeeMath.BPS_BASE, 10_000, "bps base");
        assertEq(FeeMath.PROTOCOL_FEE_SHARE_BPS, 3_000, "protocol share");

        uint256[5] memory fees = [uint256(0), 100, 215, 5_000, 10_000];
        for (uint256 i; i < fees.length; ++i) {
            uint256 protocolFeeBps = FeeMath.protocolFeeBps(fees[i]);
            uint256 lpFeeBps = FeeMath.lpFeeBps(fees[i]);
            (uint256 splitLpFeeBps, uint256 splitProtocolFeeBps) = FeeMath.splitFeeBps(fees[i]);
            assertEq(protocolFeeBps, FullMath.mulDiv(fees[i], 3_000, 10_000), "protocol split");
            assertEq(lpFeeBps, fees[i] - protocolFeeBps, "lp split");
            assertEq(protocolFeeBps + lpFeeBps, fees[i], "split sums to fee");
            assertEq(splitProtocolFeeBps, protocolFeeBps, "shared protocol split");
            assertEq(splitLpFeeBps, lpFeeBps, "shared lp split");
        }
    }

    /// @notice Fuzz: LP and protocol shares always sum exactly to the total fee.
    function testFuzzSplitSumInvariant(uint256 feeBps) external pure {
        vm.assume(feeBps <= 10_000);
        uint256 protocolFeeBps = FeeMath.protocolFeeBps(feeBps);
        uint256 lpFeeBps = FeeMath.lpFeeBps(feeBps);
        assertEq(lpFeeBps + protocolFeeBps, feeBps, "split must sum to total fee");
    }

    /// @notice Fuzz: protocol fee matches mulDiv(feeBps, 3000, 10000) with floor rounding.
    function testFuzzProtocolFeeRatio(uint256 feeBps) external pure {
        vm.assume(feeBps <= 10_000);
        uint256 expected = (feeBps * 3_000) / 10_000;
        assertEq(FeeMath.protocolFeeBps(feeBps), expected, "protocol fee must match floor(feeBps*3000/10000)");
    }

    /// @notice Boundary: feeBps=1 gives protocol 0 and LP 1.
    function testFeeBpsOneProtocolGetsZero() external pure {
        assertEq(FeeMath.protocolFeeBps(1), 0, "feeBps=1: protocol rounds to 0");
        assertEq(FeeMath.lpFeeBps(1), 1, "feeBps=1: LP gets full fee");
    }

    /// @notice Boundary: feeBps=3 gives protocol 0 (floor(0.9)=0) and LP 3.
    function testFeeBpsThreeProtocolGetsZero() external pure {
        assertEq(FeeMath.protocolFeeBps(3), 0, "feeBps=3: protocol rounds to 0");
        assertEq(FeeMath.lpFeeBps(3), 3, "feeBps=3: LP gets full fee");
    }

    /// @notice Boundary: feeBps=7 gives protocol 2 (floor(2.1)=2) and LP 5. Note: feeBps=4 is the first value where protocol is non-zero.
    function testFeeBpsSevenProtocolGetsTwo() external pure {
        assertEq(FeeMath.protocolFeeBps(7), 2, "feeBps=7: protocol gets floor(2.1)=2");
        assertEq(FeeMath.lpFeeBps(7), 5, "feeBps=7: LP gets 5");
    }
}
