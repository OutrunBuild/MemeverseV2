// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

library MemeversePoolKeyLib {
    int24 internal constant DEFAULT_TICK_SPACING = 200;

    function sortedCurrencies(address tokenA, address tokenB)
        internal
        pure
        returns (Currency currency0, Currency currency1, bool tokenAIsCurrency0)
    {
        tokenAIsCurrency0 = tokenA < tokenB;
        currency0 = Currency.wrap(tokenAIsCurrency0 ? tokenA : tokenB);
        currency1 = Currency.wrap(tokenAIsCurrency0 ? tokenB : tokenA);
    }

    function hookPoolKey(address tokenA, address tokenB, address hookAddress)
        internal
        pure
        returns (PoolKey memory key)
    {
        (Currency currency0, Currency currency1,) = sortedCurrencies(tokenA, tokenB);
        key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: DEFAULT_TICK_SPACING,
            hooks: IHooks(hookAddress)
        });
    }
}
