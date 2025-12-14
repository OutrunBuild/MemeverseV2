//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";

/**
 * @dev Interface for the Memeverse Liquidity Manager.
 */
interface IMemeverseLiquidityManager {
    function createPoolAndAddLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        address recipient,
        IHooks hook
    ) external;
}