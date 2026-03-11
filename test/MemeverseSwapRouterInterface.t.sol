// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {MemeverseSwapRouter} from "../src/swap/MemeverseSwapRouter.sol";
import {IMemeverseSwapRouter} from "../src/swap/interfaces/IMemeverseSwapRouter.sol";

contract MemeverseSwapRouterInterfaceTest is Test {
    function testInterfaceSelectorsMatchRouter() external pure {
        bytes4[] memory interfaceSelectors = new bytes4[](8);
        interfaceSelectors[0] = IMemeverseSwapRouter.hook.selector;
        interfaceSelectors[1] = IMemeverseSwapRouter.quoteSwap.selector;
        interfaceSelectors[2] = IMemeverseSwapRouter.quoteFailedAttempt.selector;
        interfaceSelectors[3] = IMemeverseSwapRouter.swap.selector;
        interfaceSelectors[4] = IMemeverseSwapRouter.addLiquidity.selector;
        interfaceSelectors[5] = IMemeverseSwapRouter.removeLiquidity.selector;
        interfaceSelectors[6] = IMemeverseSwapRouter.claimFees.selector;
        interfaceSelectors[7] = IMemeverseSwapRouter.createPoolAndAddLiquidity.selector;

        bytes4[] memory routerSelectors = new bytes4[](8);
        routerSelectors[0] = bytes4(keccak256("hook()"));
        routerSelectors[1] = MemeverseSwapRouter.quoteSwap.selector;
        routerSelectors[2] = MemeverseSwapRouter.quoteFailedAttempt.selector;
        routerSelectors[3] = MemeverseSwapRouter.swap.selector;
        routerSelectors[4] = MemeverseSwapRouter.addLiquidity.selector;
        routerSelectors[5] = MemeverseSwapRouter.removeLiquidity.selector;
        routerSelectors[6] = MemeverseSwapRouter.claimFees.selector;
        routerSelectors[7] = MemeverseSwapRouter.createPoolAndAddLiquidity.selector;

        for (uint256 i = 0; i < interfaceSelectors.length; ++i) {
            assertEq(interfaceSelectors[i], routerSelectors[i]);
        }
    }
}
