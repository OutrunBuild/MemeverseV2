// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

import {IPoolManager, SwapParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";

import {FeeMath} from "./libraries/FeeMath.sol";
import {UniswapLP} from "./tokens/UniswapLP.sol";
import {IMemeverseDynamicFeeEngine} from "./interfaces/IMemeverseDynamicFeeEngine.sol";
import {IMemeverseUniswapHook} from "./interfaces/IMemeverseUniswapHook.sol";
import {IMemeverseUniswapHookLens} from "./interfaces/IMemeverseUniswapHookLens.sol";

/// @title MemeverseUniswapHookLens
/// @notice Stateless read-only calculator for Memeverse hook quote and fee preview APIs.
/// @dev This contract assumes the queried hook and this lens are bound to the same PoolManager.
contract MemeverseUniswapHookLens is IMemeverseUniswapHookLens {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    uint256 internal constant FEE_GROWTH_Q128 = uint256(1) << 128;

    IPoolManager public immutable poolManager;

    /// @param manager_ Uniswap v4 PoolManager that owns the pools being quoted.
    constructor(IPoolManager manager_) {
        if (address(manager_) == address(0)) revert IMemeverseUniswapHook.ZeroAddress();
        poolManager = manager_;
    }

    /// @inheritdoc IMemeverseUniswapHookLens
    function quoteSwap(IMemeverseUniswapHook hook, PoolKey calldata key, SwapParams calldata params, address trader)
        external
        view
        returns (IMemeverseUniswapHook.SwapQuote memory quote)
    {
        _revertIfNativeCurrencyUnsupported(key.currency0, key.currency1);
        if (address(key.hooks) != address(hook)) revert IMemeverseUniswapHook.HookAddressMismatch();
        PoolId poolId = key.toId();
        _revertIfNoActiveLiquidityShares(hook, poolId, params.amountSpecified);
        _revertIfPublicSwapBlocked(hook, poolId);

        (uint160 preSqrtPriceX96,,,) = poolManager.getSlot0(poolId);
        uint128 liquidity = poolManager.getLiquidity(poolId);
        bool protocolFeeOnInput = _protocolFeeOnInput(hook, key, params.zeroForOne);

        // Fee quoting is bridged through the hook so the engine still sees its authorized caller.
        IMemeverseDynamicFeeEngine.PreparedSwapFee memory feeQuote =
            hook.quoteSwapFeeWithContext(poolId, params, trader, preSqrtPriceX96, liquidity, protocolFeeOnInput);
        (uint256 lpFeeBps, uint256 protocolFeeBps) = FeeMath.splitFeeBps(feeQuote.feeBps);

        quote.feeBps = feeQuote.feeBps;
        quote.protocolFeeOnInput = protocolFeeOnInput;

        if (params.amountSpecified < 0) {
            uint256 userInputAmount = uint256(-params.amountSpecified);
            quote.estimatedUserInputAmount = userInputAmount;
            quote.estimatedLpFeeAmount = FeeMath.feeOnAmount(userInputAmount, lpFeeBps);
            if (protocolFeeOnInput) {
                quote.estimatedProtocolFeeAmount = FeeMath.feeOnAmount(userInputAmount, protocolFeeBps);
                quote.estimatedUserOutputAmount = feeQuote.estimatedOutputAmount;
            } else {
                quote.estimatedProtocolFeeAmount =
                    FeeMath.feeOnAmount(feeQuote.estimatedGrossOutputAmount, protocolFeeBps);
                quote.estimatedUserOutputAmount = feeQuote.estimatedGrossOutputAmount - quote.estimatedProtocolFeeAmount;
            }
        } else {
            uint256 requestedOutputAmount = uint256(params.amountSpecified);
            quote.estimatedUserOutputAmount = requestedOutputAmount;
            quote.estimatedLpFeeAmount = FeeMath.feeOnAmount(feeQuote.estimatedInputAmount, lpFeeBps);
            if (protocolFeeOnInput) {
                quote.estimatedProtocolFeeAmount = FeeMath.feeOnAmount(feeQuote.estimatedInputAmount, protocolFeeBps);
                quote.estimatedUserInputAmount =
                    feeQuote.estimatedInputAmount + quote.estimatedLpFeeAmount + quote.estimatedProtocolFeeAmount;
            } else {
                quote.estimatedProtocolFeeAmount = feeQuote.estimatedGrossOutputAmount - requestedOutputAmount;
                quote.estimatedUserInputAmount = feeQuote.estimatedInputAmount + quote.estimatedLpFeeAmount;
            }
        }
    }

    /// @inheritdoc IMemeverseUniswapHookLens
    function claimableFees(IMemeverseUniswapHook hook, PoolKey calldata key, address owner)
        external
        view
        returns (uint256 fee0Amount, uint256 fee1Amount)
    {
        _revertIfNativeCurrencyUnsupported(key.currency0, key.currency1);
        PoolId poolId = key.toId();
        (address liquidityToken, uint256 fee0PerShare, uint256 fee1PerShare) = hook.poolInfo(poolId);
        if (liquidityToken == address(0) || owner == address(0)) return (0, 0);

        (uint256 fee0Offset, uint256 fee1Offset, uint256 pendingFee0, uint256 pendingFee1) =
            hook.userFeeState(poolId, owner);
        fee0Amount = pendingFee0;
        fee1Amount = pendingFee1;

        uint256 balance = UniswapLP(liquidityToken).balanceOf(owner);
        if (balance == 0) return (fee0Amount, fee1Amount);

        // Fee growth is Q128-scaled by the hook; round down to avoid over-previewing claimable fees.
        if (fee0PerShare > fee0Offset) {
            fee0Amount += FullMath.mulDiv(balance, fee0PerShare - fee0Offset, FEE_GROWTH_Q128);
        }
        if (fee1PerShare > fee1Offset) {
            fee1Amount += FullMath.mulDiv(balance, fee1PerShare - fee1Offset, FEE_GROWTH_Q128);
        }
    }

    /// @inheritdoc IMemeverseUniswapHookLens
    function poolDynamicFeeState(IMemeverseUniswapHook hook, PoolId poolId)
        external
        view
        returns (
            uint256 weightedVolume0,
            uint256 weightedPriceVolume0,
            uint256 ewVWAPX18,
            uint160 volAnchorSqrtPriceX96,
            uint40 volLastMoveTs,
            uint24 volDeviationAccumulator,
            uint24 volCarryAccumulator,
            uint24 shortImpactPpm,
            uint40 shortLastTs
        )
    {
        IMemeverseDynamicFeeEngine.DynamicFeeState memory state =
            hook.dynamicFeeEngine().getDynamicFeeState(address(hook), poolId);
        return (
            state.weightedVolume0,
            state.weightedPriceVolume0,
            state.ewVWAPX18,
            state.volAnchorSqrtPriceX96,
            state.volLastMoveTs,
            state.volDeviationAccumulator,
            state.volCarryAccumulator,
            state.shortImpactPpm,
            state.shortLastTs
        );
    }

    /// @dev Mirrors `MemeverseUniswapHook._resolveSwapFeeContext` protocol-fee side — keep in sync if hook validation changes.
    function _protocolFeeOnInput(IMemeverseUniswapHook hook, PoolKey calldata key, bool zeroForOne)
        internal
        view
        returns (bool)
    {
        Currency currencyIn = zeroForOne ? key.currency0 : key.currency1;
        Currency currencyOut = zeroForOne ? key.currency1 : key.currency0;
        if (hook.supportedProtocolFeeCurrencies(Currency.unwrap(currencyIn))) return true;
        if (hook.supportedProtocolFeeCurrencies(Currency.unwrap(currencyOut))) return false;
        revert IMemeverseUniswapHook.CurrencyNotSupported();
    }

    /// @dev Mirrors `MemeverseUniswapHook._revertIfPublicSwapBlocked` — keep in sync if hook validation changes.
    function _revertIfPublicSwapBlocked(IMemeverseUniswapHook hook, PoolId poolId) internal view {
        uint40 resumeTime = hook.publicSwapResumeTime(poolId);
        if (resumeTime != 0 && block.timestamp < resumeTime) revert IMemeverseUniswapHook.PublicSwapDisabled();
    }

    /// @dev Mirrors `MemeverseUniswapHook._revertIfNoActiveLiquidityShares` — keep in sync if hook validation changes.
    function _revertIfNoActiveLiquidityShares(IMemeverseUniswapHook hook, PoolId poolId, int256 amountSpecified)
        internal
        view
    {
        if (amountSpecified == 0) return;
        if (hook.cachedLpTotalSupply(poolId) != 0) return;
        if (poolManager.getLiquidity(poolId) == 0) return;
        revert IMemeverseUniswapHook.NoActiveLiquidityShares();
    }

    /// @dev Mirrors `MemeverseUniswapHook._revertIfNativeCurrencyUnsupported` — keep in sync if hook validation changes.
    function _revertIfNativeCurrencyUnsupported(Currency currency0, Currency currency1) internal pure {
        if (currency0.isAddressZero() || currency1.isAddressZero()) {
            revert IMemeverseUniswapHook.NativeCurrencyUnsupported();
        }
    }
}
