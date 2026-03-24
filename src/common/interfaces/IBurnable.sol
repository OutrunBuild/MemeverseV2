// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

/**
 * @title Burnable Token Interface
 */
interface IBurnable {
    /**
     * @notice Burns `amount` tokens from the caller.
     * @dev Implementations are expected to revert when balance is insufficient.
     * @param amount Amount of tokens to burn.
     */
    function burn(uint256 amount) external;
}
