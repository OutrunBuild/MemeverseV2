// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {MemeverseSwapRouter} from "../../src/swap/MemeverseSwapRouter.sol";
import {IMemeverseSwapRouter} from "../../src/swap/interfaces/IMemeverseSwapRouter.sol";

contract MemeverseSwapRouterInterfaceTest is Test {
    /// @notice Verifies the router public interface selectors match the implementation selectors.
    /// @dev Guards against selector drift while refactoring router internals.
    function testInterfaceSelectorsMatchRouter() external pure {
        bytes4[] memory interfaceSelectors = new bytes4[](12);
        interfaceSelectors[0] = IMemeverseSwapRouter.hook.selector;
        interfaceSelectors[1] = IMemeverseSwapRouter.permit2.selector;
        interfaceSelectors[2] = IMemeverseSwapRouter.quoteSwap.selector;
        interfaceSelectors[3] = IMemeverseSwapRouter.swap.selector;
        interfaceSelectors[4] = IMemeverseSwapRouter.swapWithPermit2.selector;
        interfaceSelectors[5] = IMemeverseSwapRouter.addLiquidity.selector;
        interfaceSelectors[6] = IMemeverseSwapRouter.addLiquidityWithPermit2.selector;
        interfaceSelectors[7] = IMemeverseSwapRouter.removeLiquidity.selector;
        interfaceSelectors[8] = IMemeverseSwapRouter.removeLiquidityWithPermit2.selector;
        interfaceSelectors[9] = IMemeverseSwapRouter.claimFees.selector;
        interfaceSelectors[10] = IMemeverseSwapRouter.createPoolAndAddLiquidity.selector;
        interfaceSelectors[11] = IMemeverseSwapRouter.createPoolAndAddLiquidityWithPermit2.selector;

        bytes4[] memory routerSelectors = new bytes4[](12);
        routerSelectors[0] = bytes4(keccak256("hook()"));
        routerSelectors[1] = bytes4(keccak256("permit2()"));
        routerSelectors[2] = MemeverseSwapRouter.quoteSwap.selector;
        routerSelectors[3] = MemeverseSwapRouter.swap.selector;
        routerSelectors[4] = MemeverseSwapRouter.swapWithPermit2.selector;
        routerSelectors[5] = MemeverseSwapRouter.addLiquidity.selector;
        routerSelectors[6] = MemeverseSwapRouter.addLiquidityWithPermit2.selector;
        routerSelectors[7] = MemeverseSwapRouter.removeLiquidity.selector;
        routerSelectors[8] = MemeverseSwapRouter.removeLiquidityWithPermit2.selector;
        routerSelectors[9] = MemeverseSwapRouter.claimFees.selector;
        routerSelectors[10] = MemeverseSwapRouter.createPoolAndAddLiquidity.selector;
        routerSelectors[11] = MemeverseSwapRouter.createPoolAndAddLiquidityWithPermit2.selector;

        for (uint256 i = 0; i < interfaceSelectors.length; ++i) {
            assertEq(interfaceSelectors[i], routerSelectors[i]);
        }
    }

    /// @notice Verifies the simplified swap selector no longer includes a refund-recipient parameter.
    /// @dev This guards the router-surface simplification that always refunds unused budgets back to the caller.
    function testSwapSelector_DropsRefundRecipientParameter() external pure {
        assertEq(
            IMemeverseSwapRouter.swap.selector,
            bytes4(
                keccak256(
                    "swap((address,address,uint24,int24,address),(bool,int256,uint160),address,uint256,uint256,uint256,bytes)"
                )
            )
        );
    }

    /// @notice Verifies the simplified Permit2 swap selector no longer includes a refund-recipient parameter.
    /// @dev Permit2 swaps now share the same caller-refund semantics as regular swaps.
    function testSwapWithPermit2Selector_DropsRefundRecipientParameter() external pure {
        bytes4 oldSelector = bytes4(
            keccak256(
                "swapWithPermit2(((address,uint256),uint256,uint256,(address,uint256),bytes),(address,address,uint24,int24,address),(bool,int256,uint160),address,address,uint256,uint256,uint256,bytes)"
            )
        );
        assertNotEq(IMemeverseSwapRouter.swapWithPermit2.selector, oldSelector);
        assertEq(IMemeverseSwapRouter.swapWithPermit2.selector, MemeverseSwapRouter.swapWithPermit2.selector);
    }

    /// @notice Verifies the router accessor selectors remain unchanged.
    /// @dev Keeps a tiny focused regression check on the immutable public accessors.
    function testAccessorSelectorsRemainStable() external pure {
        assertEq(IMemeverseSwapRouter.hook.selector, bytes4(keccak256("hook()")));
        assertEq(IMemeverseSwapRouter.permit2.selector, bytes4(keccak256("permit2()")));
    }
}
