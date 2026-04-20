// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {IMemeverseUniswapHook} from "../../src/swap/interfaces/IMemeverseUniswapHook.sol";
import {RealisticSwapIntegrationBase, RealisticSwapManagerHarness} from "./helpers/RealisticSwapManagerHarness.sol";

contract MemeverseUniswapHookIntegrationTest is RealisticSwapIntegrationBase {
    using BalanceDeltaLibrary for BalanceDelta;

    function setUp() public {
        _setUpIntegration(IPermit2(address(0)));
    }

    function testDirectManager_ExactInput_InputFee_PartialFill_RevertsAndRollsBack() external {
        hook.setProtocolFeeCurrency(key.currency0);
        integrator.swap(
            key,
            SwapParams({
                zeroForOne: true, amountSpecified: -10 ether, sqrtPriceLimitX96: _validExecutionPriceLimit(true)
            }),
            address(this),
            bytes("")
        );
        _matureLaunchWindow();
        manager.setNextExactInputPoolInputAmount(poolId, 98 ether);

        RollbackSnapshot memory before_ = _rollbackSnapshot(address(this));

        vm.expectRevert(IMemeverseUniswapHook.ExactInputPartialFill.selector);
        integrator.swap(
            key,
            SwapParams({
                zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: _validExecutionPriceLimit(true)
            }),
            address(this),
            bytes("")
        );

        _assertRollback(address(this), before_);
    }

    function testDirectManager_ExactInput_OutputFee_FullFill_Succeeds() external {
        hook.setProtocolFeeCurrency(key.currency1);
        _matureLaunchWindow();

        SwapParams memory params = SwapParams({
            zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: _validExecutionPriceLimit(true)
        });
        IMemeverseUniswapHook.SwapQuote memory quote = hook.quoteSwap(key, params);
        uint256 payer0Before = token0.balanceOf(address(this));
        uint256 payer1Before = token1.balanceOf(address(this));
        uint256 treasury1Before = token1.balanceOf(treasury);
        (, uint256 fee0PerShareBefore,) = hook.poolInfo(poolId);

        BalanceDelta delta = integrator.swap(key, params, address(this), bytes(""));

        (, uint256 fee0PerShareAfter,) = hook.poolInfo(poolId);
        assertEq(payer0Before - token0.balanceOf(address(this)), quote.estimatedUserInputAmount, "exact user spend");
        assertEq(
            token1.balanceOf(address(this)) - payer1Before, quote.estimatedUserOutputAmount, "exact recipient output"
        );
        assertEq(token1.balanceOf(treasury) - treasury1Before, quote.estimatedProtocolFeeAmount, "exact treasury fee");
        assertEq(
            fee0PerShareAfter - fee0PerShareBefore,
            _expectedLpFeeGrowth(quote.estimatedLpFeeAmount),
            "exact lp fee growth"
        );
        assertEq(delta.amount0(), -int128(int256(quote.estimatedUserInputAmount)), "delta0 exact");
        assertEq(delta.amount1(), int128(int256(quote.estimatedUserOutputAmount)), "delta1 exact");
    }

    function testDirectManager_RawTransferBypass_RevertsAtUnlock() external {
        hook.setProtocolFeeCurrency(key.currency1);
        _matureLaunchWindow();

        vm.expectRevert(RealisticSwapManagerHarness.CurrencyNotSettled.selector);
        rawTransferIntegrator.swap(
            key,
            SwapParams({
                zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: _validExecutionPriceLimit(true)
            }),
            address(this),
            bytes("")
        );
    }
}
