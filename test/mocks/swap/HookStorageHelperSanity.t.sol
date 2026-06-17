// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

import {MemeverseDynamicFeeEngine} from "../../../src/swap/MemeverseDynamicFeeEngine.sol";
import {MemeverseUniswapHook} from "../../../src/swap/MemeverseUniswapHook.sol";
import {HookStorageHelper} from "./HookStorageHelper.sol";
import {MockPoolManagerForHookLiquidity} from "./HookLiquidityMocks.sol";

/// @notice Proves flag-address deployment still uses real hook and engine proxies.
contract HookStorageHelperSanityTest is Test, HookStorageHelper {
    function test_deployHookAtFlagAddress_proxyCarriesFlags() external {
        IPoolManager manager = IPoolManager(address(new MockPoolManagerForHookLiquidity()));
        address treasury = address(0xBEEF);

        (address hookProxy, address engineProxy) = deployHookAtFlagAddress(manager, address(this), treasury);

        assertEq(uint160(hookProxy) & HOOK_FLAG_MASK, HOOK_REQUIRED_FLAGS, "proxy missing flags");

        assertEq(MemeverseUniswapHook(hookProxy).treasury(), treasury, "treasury");
        assertEq(address(MemeverseUniswapHook(hookProxy).dynamicFeeEngine()), engineProxy, "engine bound");
        assertEq(MemeverseUniswapHook(hookProxy).owner(), address(this), "owner");

        assertEq(MemeverseDynamicFeeEngine(engineProxy).owner(), hookProxy, "engine owner");
        assertEq(MemeverseDynamicFeeEngine(engineProxy).authorizedHook(), hookProxy, "engine authorizedHook");

        Hooks.Permissions memory perms = MemeverseUniswapHook(hookProxy).getHookPermissions();
        assertTrue(perms.beforeInitialize, "beforeInitialize");
        assertTrue(perms.beforeAddLiquidity, "beforeAddLiquidity");
        assertTrue(perms.beforeSwap, "beforeSwap");
        assertTrue(perms.afterSwap, "afterSwap");
        assertTrue(perms.beforeSwapReturnDelta, "beforeSwapReturnDelta");
        assertTrue(perms.afterSwapReturnDelta, "afterSwapReturnDelta");
    }
}
