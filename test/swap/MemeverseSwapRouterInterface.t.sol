// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {MemeverseSwapRouter} from "../../src/swap/MemeverseSwapRouter.sol";
import {IMemeverseSwapRouter} from "../../src/swap/interfaces/IMemeverseSwapRouter.sol";

contract MemeverseSwapRouterInterfaceTest is Test {
    /// @notice Verifies the router public interface selectors match the implementation selectors.
    /// @dev Guards against selector drift while refactoring router internals.
    function testInterfaceSelectorsMatchRouter() external pure {
        bytes4[] memory interfaceSelectors = new bytes4[](13);
        interfaceSelectors[0] = IMemeverseSwapRouter.hook.selector;
        interfaceSelectors[1] = IMemeverseSwapRouter.permit2.selector;
        interfaceSelectors[2] = IMemeverseSwapRouter.quoteSwap.selector;
        interfaceSelectors[3] = IMemeverseSwapRouter.quoteFailedAttempt.selector;
        interfaceSelectors[4] = IMemeverseSwapRouter.swap.selector;
        interfaceSelectors[5] = IMemeverseSwapRouter.swapWithPermit2.selector;
        interfaceSelectors[6] = IMemeverseSwapRouter.addLiquidity.selector;
        interfaceSelectors[7] = IMemeverseSwapRouter.addLiquidityWithPermit2.selector;
        interfaceSelectors[8] = IMemeverseSwapRouter.removeLiquidity.selector;
        interfaceSelectors[9] = IMemeverseSwapRouter.removeLiquidityWithPermit2.selector;
        interfaceSelectors[10] = IMemeverseSwapRouter.claimFees.selector;
        interfaceSelectors[11] = IMemeverseSwapRouter.createPoolAndAddLiquidity.selector;
        interfaceSelectors[12] = IMemeverseSwapRouter.createPoolAndAddLiquidityWithPermit2.selector;

        bytes4[] memory routerSelectors = new bytes4[](13);
        routerSelectors[0] = bytes4(keccak256("hook()"));
        routerSelectors[1] = bytes4(keccak256("permit2()"));
        routerSelectors[2] = MemeverseSwapRouter.quoteSwap.selector;
        routerSelectors[3] = MemeverseSwapRouter.quoteFailedAttempt.selector;
        routerSelectors[4] = MemeverseSwapRouter.swap.selector;
        routerSelectors[5] = MemeverseSwapRouter.swapWithPermit2.selector;
        routerSelectors[6] = MemeverseSwapRouter.addLiquidity.selector;
        routerSelectors[7] = MemeverseSwapRouter.addLiquidityWithPermit2.selector;
        routerSelectors[8] = MemeverseSwapRouter.removeLiquidity.selector;
        routerSelectors[9] = MemeverseSwapRouter.removeLiquidityWithPermit2.selector;
        routerSelectors[10] = MemeverseSwapRouter.claimFees.selector;
        routerSelectors[11] = MemeverseSwapRouter.createPoolAndAddLiquidity.selector;
        routerSelectors[12] = MemeverseSwapRouter.createPoolAndAddLiquidityWithPermit2.selector;

        for (uint256 i = 0; i < interfaceSelectors.length; ++i) {
            assertEq(interfaceSelectors[i], routerSelectors[i]);
        }
    }

    /// @notice Verifies the router accessor selectors remain unchanged.
    /// @dev Keeps a tiny focused regression check on the immutable public accessors.
    function testAccessorSelectorsRemainStable() external pure {
        assertEq(IMemeverseSwapRouter.hook.selector, bytes4(keccak256("hook()")));
        assertEq(IMemeverseSwapRouter.permit2.selector, bytes4(keccak256("permit2()")));
    }
}
