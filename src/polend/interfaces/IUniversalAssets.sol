// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

/**
 * @title Outrun omnichain universal assets interface
 */
interface IUniversalAssets {
    function mint(address receiver, uint256 amount) external;

    function repay(address account, uint256 amount) external;
}
