// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {SwapParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";

import {IMemeverseUniswapHook} from "../../src/swap/interfaces/IMemeverseUniswapHook.sol";
import {RealisticSwapIntegrationBase} from "./helpers/RealisticSwapManagerHarness.sol";

contract MemeverseSwapRouterIntegrationTest is RealisticSwapIntegrationBase {
    using BalanceDeltaLibrary for BalanceDelta;

    function setUp() public {
        _setUpIntegration(IPermit2(address(0)));
    }

    function testExactInput_InputFee_FullFill_Succeeds() external {
        hook.setProtocolFeeCurrency(key.currency0);
        _matureLaunchWindow();

        SwapParams memory params = SwapParams({
            zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: _validExecutionPriceLimit(true)
        });
        IMemeverseUniswapHook.SwapQuote memory quote = router.quoteSwap(key, params);
        uint256 payer0Before = token0.balanceOf(address(this));
        uint256 payer1Before = token1.balanceOf(address(this));
        uint256 treasury0Before = token0.balanceOf(treasury);
        (, uint256 fee0PerShareBefore,) = hook.poolInfo(poolId);

        BalanceDelta delta = router.swap(key, params, address(this), block.timestamp, 0, 100 ether, "");

        (, uint256 fee0PerShareAfter,) = hook.poolInfo(poolId);
        assertEq(payer0Before - token0.balanceOf(address(this)), quote.estimatedUserInputAmount, "exact user spend");
        assertEq(
            token1.balanceOf(address(this)) - payer1Before, quote.estimatedUserOutputAmount, "exact recipient output"
        );
        assertEq(token0.balanceOf(treasury) - treasury0Before, quote.estimatedProtocolFeeAmount, "exact treasury fee");
        assertEq(
            fee0PerShareAfter - fee0PerShareBefore,
            _expectedLpFeeGrowth(quote.estimatedLpFeeAmount),
            "exact lp fee growth"
        );
        assertEq(delta.amount0(), -int128(int256(quote.estimatedUserInputAmount)), "delta0 exact");
        assertEq(delta.amount1(), int128(int256(quote.estimatedUserOutputAmount)), "delta1 exact");
    }

    function testExactInput_OutputFee_FullFill_Succeeds() external {
        hook.setProtocolFeeCurrency(key.currency1);
        _matureLaunchWindow();

        SwapParams memory params = SwapParams({
            zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: _validExecutionPriceLimit(true)
        });
        IMemeverseUniswapHook.SwapQuote memory quote = router.quoteSwap(key, params);
        uint256 payer0Before = token0.balanceOf(address(this));
        uint256 payer1Before = token1.balanceOf(address(this));
        uint256 treasury1Before = token1.balanceOf(treasury);
        (, uint256 fee0PerShareBefore,) = hook.poolInfo(poolId);

        BalanceDelta delta = router.swap(key, params, address(this), block.timestamp, 0, 100 ether, "");

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

    function testExactInput_InputFee_PartialFill_RevertsAndRollsBack() external {
        hook.setProtocolFeeCurrency(key.currency0);
        router.swap(
            key,
            SwapParams({
                zeroForOne: true, amountSpecified: -10 ether, sqrtPriceLimitX96: _validExecutionPriceLimit(true)
            }),
            address(this),
            block.timestamp,
            0,
            10 ether,
            ""
        );
        _matureLaunchWindow();
        manager.setNextExactInputPoolInputAmount(poolId, 98 ether);

        RollbackSnapshot memory before_ = _rollbackSnapshot(address(this));

        vm.expectRevert(IMemeverseUniswapHook.ExactInputPartialFill.selector);
        router.swap(
            key,
            SwapParams({
                zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: _validExecutionPriceLimit(true)
            }),
            address(this),
            block.timestamp,
            0,
            100 ether,
            ""
        );

        _assertRollback(address(this), before_);
    }
}
