// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {OFTComposeMsgCodec} from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";

import {IOFTCompose} from "../../src/common/omnichain/oft/IOFTCompose.sol";
import {IBurnable} from "../../src/common/interfaces/IBurnable.sol";
import {MemeverseOFTDispatcher} from "../../src/verse/MemeverseOFTDispatcher.sol";
import {IMemeverseOFTDispatcher} from "../../src/verse/interfaces/IMemeverseOFTDispatcher.sol";
import {MemeverseOFTEnum} from "../../src/common/types/MemeverseOFTEnum.sol";

contract MockDispatcherComposeToken is MockERC20, IOFTCompose, IBurnable {
    mapping(bytes32 guid => bool executed) internal executedStatus;
    bytes32 public lastNotifiedGuid;
    uint256 public lastBurnAmount;

    constructor(string memory name_, string memory symbol_) MockERC20(name_, symbol_, 18) {}

    /// @notice Get compose tx executed status.
    /// @param guid See implementation.
    /// @return See implementation.
    function getComposeTxExecutedStatus(bytes32 guid) external view returns (bool) {
        return executedStatus[guid];
    }

    /// @notice Notify compose executed.
    /// @param guid See implementation.
    function notifyComposeExecuted(bytes32 guid) external {
        executedStatus[guid] = true;
        lastNotifiedGuid = guid;
    }

    /// @notice Withdraw if not executed.
    /// @param guid See implementation.
    /// @param account See implementation.
    /// @return See implementation.
    function withdrawIfNotExecuted(bytes32 guid, address account) external pure returns (uint256) {
        guid;
        account;
        revert("unused");
    }

    /// @notice Burn.
    /// @param amount See implementation.
    function burn(uint256 amount) external {
        lastBurnAmount = amount;
        _burn(msg.sender, amount);
    }

    /// @notice Set executed.
    /// @param guid See implementation.
    /// @param executed See implementation.
    function setExecuted(bytes32 guid, bool executed) external {
        executedStatus[guid] = executed;
    }
}

contract MockDispatcherYieldVault {
    uint256 public lastAccumulatedAmount;

    /// @notice Accumulate yields.
    /// @param amount See implementation.
    function accumulateYields(uint256 amount) external {
        lastAccumulatedAmount = amount;
    }
}

contract MockDispatcherGovernor {
    address public lastToken;
    uint256 public lastAmount;

    /// @notice Receive treasury income.
    /// @param token See implementation.
    /// @param amount See implementation.
    function receiveTreasuryIncome(address token, uint256 amount) external {
        lastToken = token;
        lastAmount = amount;
    }
}

contract MemeverseOFTDispatcherTest is Test {
    using OFTComposeMsgCodec for bytes;

    address internal constant OWNER = address(0xABCD);
    address internal constant LOCAL_ENDPOINT = address(0x1111);
    address internal constant LAUNCHER = address(0x2222);
    address internal constant ALICE = address(0xA11CE);

    MemeverseOFTDispatcher internal dispatcher;
    MockDispatcherComposeToken internal token;
    MockDispatcherYieldVault internal yieldVault;
    MockDispatcherGovernor internal governor;

    /// @notice Set up.
    function setUp() external {
        dispatcher = new MemeverseOFTDispatcher(OWNER, LOCAL_ENDPOINT, LAUNCHER);
        token = new MockDispatcherComposeToken("Compose Token", "CMP");
        yieldVault = new MockDispatcherYieldVault();
        governor = new MockDispatcherGovernor();
    }

    /// @notice Test lz compose rejects unauthorized caller.
    function testLzComposeRejectsUnauthorizedCaller() external {
        vm.expectRevert(IMemeverseOFTDispatcher.PermissionDenied.selector);
        dispatcher.lzCompose(address(token), bytes32(0), "", address(0), "");
    }

    /// @notice Test launcher path burns memecoin for eoa receiver.
    function testLauncherPathBurnsMemecoinForEoaReceiver() external {
        uint256 amount = 5 ether;
        token.mint(address(dispatcher), amount);

        bytes memory message = abi.encode(ALICE, MemeverseOFTEnum.TokenType.MEMECOIN, amount);

        vm.prank(LAUNCHER);
        dispatcher.lzCompose(address(token), bytes32("launcher-guid"), message, address(0), "");

        assertEq(token.lastBurnAmount(), amount);
        assertEq(token.balanceOf(address(dispatcher)), 0);
    }

    /// @notice Test launcher path approves and calls receivers.
    function testLauncherPathApprovesAndCallsReceivers() external {
        uint256 memeAmount = 7 ether;
        uint256 uptAmount = 11 ether;
        token.mint(address(dispatcher), memeAmount + uptAmount);

        vm.prank(LAUNCHER);
        dispatcher.lzCompose(
            address(token),
            bytes32("yield-guid"),
            abi.encode(address(yieldVault), MemeverseOFTEnum.TokenType.MEMECOIN, memeAmount),
            address(0),
            ""
        );
        assertEq(yieldVault.lastAccumulatedAmount(), memeAmount);
        assertEq(token.allowance(address(dispatcher), address(yieldVault)), type(uint256).max);

        vm.prank(LAUNCHER);
        dispatcher.lzCompose(
            address(token),
            bytes32("gov-guid"),
            abi.encode(address(governor), MemeverseOFTEnum.TokenType.UPT, uptAmount),
            address(0),
            ""
        );
        assertEq(governor.lastToken(), address(token));
        assertEq(governor.lastAmount(), uptAmount);
        assertEq(token.allowance(address(dispatcher), address(governor)), type(uint256).max);
    }

    /// @notice Test local endpoint path rejects already executed compose.
    function testLocalEndpointPathRejectsAlreadyExecutedCompose() external {
        bytes32 guid = bytes32("done");
        token.setExecuted(guid, true);
        bytes memory composeMessage = abi.encodePacked(
            bytes32(uint256(uint160(ALICE))), abi.encode(address(governor), MemeverseOFTEnum.TokenType.UPT)
        );
        bytes memory message = OFTComposeMsgCodec.encode(1, 101, 1 ether, composeMessage);

        vm.prank(LOCAL_ENDPOINT);
        vm.expectRevert(IMemeverseOFTDispatcher.AlreadyExecuted.selector);
        dispatcher.lzCompose(address(token), guid, message, address(0), "");
    }

    /// @notice Test local endpoint path marks compose executed and routes funds.
    function testLocalEndpointPathMarksComposeExecutedAndRoutesFunds() external {
        bytes32 guid = bytes32("new");
        uint256 amount = 9 ether;
        token.mint(address(dispatcher), amount);

        bytes memory composeMessage = abi.encodePacked(
            bytes32(uint256(uint160(ALICE))), abi.encode(address(governor), MemeverseOFTEnum.TokenType.UPT)
        );
        bytes memory message = OFTComposeMsgCodec.encode(1, 101, amount, composeMessage);

        vm.prank(LOCAL_ENDPOINT);
        dispatcher.lzCompose(address(token), guid, message, address(0), "");

        assertEq(token.lastNotifiedGuid(), guid);
        assertTrue(token.getComposeTxExecutedStatus(guid));
        assertEq(governor.lastToken(), address(token));
        assertEq(governor.lastAmount(), amount);
    }
}
