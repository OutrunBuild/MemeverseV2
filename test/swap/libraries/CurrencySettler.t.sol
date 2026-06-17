// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {CurrencySettler} from "../../../src/swap/libraries/CurrencySettler.sol";

import {FalseTransferFromToken, FalseTransferToken, MockPoolManager} from "../../mocks/swap/CurrencySettlerMocks.sol";

contract CurrencySettlerHarness {
    using CurrencySettler for Currency;

    function settle(Currency currency, IPoolManager manager, address payer, uint256 amount, bool burn) external {
        currency.settle(manager, payer, amount, burn);
    }
}

contract CurrencySettlerTest is Test {
    CurrencySettlerHarness internal harness;
    MockPoolManager internal manager;

    function setUp() external {
        harness = new CurrencySettlerHarness();
        manager = new MockPoolManager();
    }

    function testSettleRevertsWithERC20TransferFromFailed() external {
        FalseTransferFromToken token = new FalseTransferFromToken();

        vm.expectRevert(
            abi.encodeWithSelector(
                CurrencySettler.ERC20TransferFromFailed.selector, address(this), address(manager), 1 ether
            )
        );
        harness.settle(Currency.wrap(address(token)), IPoolManager(address(manager)), address(this), 1 ether, false);
    }

    function testSettleRevertsWithERC20TransferFailed() external {
        FalseTransferToken token = new FalseTransferToken();

        vm.expectRevert(abi.encodeWithSelector(CurrencySettler.ERC20TransferFailed.selector, address(manager), 1 ether));
        vm.prank(address(harness));
        harness.settle(Currency.wrap(address(token)), IPoolManager(address(manager)), address(harness), 1 ether, false);
    }
}
