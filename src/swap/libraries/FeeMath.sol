// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";

/// @title FeeMath
/// @notice Shared fee split math for Memeverse swap fees.
/// @dev Basis points (bps) use 10_000 as 100%. The protocol receives 30% of the total fee and LPs receive the rest.
library FeeMath {
    uint256 internal constant BPS_BASE = 10_000;
    uint256 internal constant PROTOCOL_FEE_SHARE_BPS = 3_000;

    /// @notice Returns the protocol-owned portion of a total fee value.
    /// @dev Uses FullMath.mulDiv so rounding stays identical anywhere the split is applied.
    /// @param feeBps Total fee in basis points.
    /// @return protocolFeeBps_ Protocol fee in basis points.
    function protocolFeeBps(uint256 feeBps) internal pure returns (uint256 protocolFeeBps_) {
        return FullMath.mulDiv(feeBps, PROTOCOL_FEE_SHARE_BPS, BPS_BASE);
    }

    /// @notice Returns the LP-owned portion of a total fee value.
    /// @dev The protocol share is subtracted after rounding down so protocol and LP shares always sum to `feeBps`.
    /// @param feeBps Total fee in basis points.
    /// @return lpFeeBps_ LP fee in basis points.
    function lpFeeBps(uint256 feeBps) internal pure returns (uint256 lpFeeBps_) {
        uint256 protocolFeeBps_ = protocolFeeBps(feeBps);
        unchecked {
            // Safe: protocol share is below BPS_BASE, so protocol fee bps cannot exceed total fee bps.
            return feeBps - protocolFeeBps_;
        }
    }

    /// @notice Returns both LP and protocol portions of a total fee value.
    /// @dev Computes the protocol share once for call sites that need both split values.
    /// @param feeBps Total fee in basis points.
    /// @return lpFeeBps_ LP fee in basis points.
    /// @return protocolFeeBps_ Protocol fee in basis points.
    function splitFeeBps(uint256 feeBps) internal pure returns (uint256 lpFeeBps_, uint256 protocolFeeBps_) {
        protocolFeeBps_ = protocolFeeBps(feeBps);
        unchecked {
            // Safe: protocol share is below BPS_BASE, so protocol fee bps cannot exceed total fee bps.
            lpFeeBps_ = feeBps - protocolFeeBps_;
        }
    }
}
