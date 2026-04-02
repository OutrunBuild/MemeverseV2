// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {OFTComposeMsgCodec} from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";

import {IOFTCompose} from "../../src/common/omnichain/oft/IOFTCompose.sol";
import {IBurnable} from "../../src/common/interfaces/IBurnable.sol";
import {IOmnichainMemecoinStaker} from "../../src/interoperation/interfaces/IOmnichainMemecoinStaker.sol";
import {OmnichainMemecoinStaker} from "../../src/interoperation/OmnichainMemecoinStaker.sol";

contract MockStakerComposeToken is MockERC20, IOFTCompose, IBurnable {
    mapping(bytes32 guid => bool executed) internal executedStatus;
    bytes32 public lastNotifiedGuid;

    constructor() MockERC20("Memecoin", "MEME", 18) {}

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
        _burn(msg.sender, amount);
    }

    /// @notice Set executed.
    /// @param guid See implementation.
    /// @param executed See implementation.
    function setExecuted(bytes32 guid, bool executed) external {
        executedStatus[guid] = executed;
    }
}

contract MockStakerYieldVault {
    uint256 public lastDepositAmount;
    address public lastDepositReceiver;

    /// @notice Deposit.
    /// @param amount See implementation.
    /// @param receiver See implementation.
    /// @return shares See implementation.
    function deposit(uint256 amount, address receiver) external returns (uint256 shares) {
        lastDepositAmount = amount;
        lastDepositReceiver = receiver;
        shares = amount;
    }
}

contract OmnichainMemecoinStakerTest is Test {
    address internal constant LOCAL_ENDPOINT = address(0x1111);
    address internal constant RECEIVER = address(0xBEEF);

    OmnichainMemecoinStaker internal staker;
    MockStakerComposeToken internal memecoin;
    MockStakerYieldVault internal yieldVault;

    /// @notice Set up.
    function setUp() external {
        staker = new OmnichainMemecoinStaker(LOCAL_ENDPOINT);
        memecoin = new MockStakerComposeToken();
        yieldVault = new MockStakerYieldVault();
    }

    /// @notice Test lz compose rejects unauthorized caller and already executed guid.
    function testLzComposeRejectsUnauthorizedCallerAndAlreadyExecutedGuid() external {
        vm.expectRevert(IOmnichainMemecoinStaker.PermissionDenied.selector);
        staker.lzCompose(address(memecoin), bytes32(0), "", address(0), "");

        bytes32 guid = bytes32("done");
        memecoin.setExecuted(guid, true);
        bytes memory message = OFTComposeMsgCodec.encode(
            1,
            101,
            1 ether,
            abi.encodePacked(bytes32(uint256(uint160(RECEIVER))), abi.encode(RECEIVER, address(yieldVault)))
        );

        vm.prank(LOCAL_ENDPOINT);
        vm.expectRevert(IOmnichainMemecoinStaker.AlreadyExecuted.selector);
        staker.lzCompose(address(memecoin), guid, message, address(0), "");
    }

    /// @notice Test lz compose deposits into yield vault when vault exists.
    function testLzComposeDepositsIntoYieldVaultWhenVaultExists() external {
        bytes32 guid = bytes32("stake");
        memecoin.mint(address(staker), 3 ether);
        bytes memory message = OFTComposeMsgCodec.encode(
            1,
            101,
            3 ether,
            abi.encodePacked(bytes32(uint256(uint160(RECEIVER))), abi.encode(RECEIVER, address(yieldVault)))
        );

        // Contract vault targets should receive the full compose amount before the guid is marked executed.
        vm.prank(LOCAL_ENDPOINT);
        staker.lzCompose(address(memecoin), guid, message, address(0), "");

        assertEq(yieldVault.lastDepositAmount(), 3 ether);
        assertEq(yieldVault.lastDepositReceiver(), RECEIVER);
        assertEq(memecoin.lastNotifiedGuid(), guid);
        assertTrue(memecoin.getComposeTxExecutedStatus(guid));
    }

    /// @notice Test lz compose refunds receiver when vault is eoa.
    function testLzComposeRefundsReceiverWhenVaultIsEoa() external {
        bytes32 guid = bytes32("refund");
        memecoin.mint(address(staker), 2 ether);
        bytes memory message = OFTComposeMsgCodec.encode(
            1,
            101,
            2 ether,
            abi.encodePacked(bytes32(uint256(uint160(RECEIVER))), abi.encode(RECEIVER, address(0x1234)))
        );

        vm.prank(LOCAL_ENDPOINT);
        staker.lzCompose(address(memecoin), guid, message, address(0), "");

        assertEq(memecoin.balanceOf(RECEIVER), 2 ether);
        assertEq(memecoin.lastNotifiedGuid(), guid);
        assertTrue(memecoin.getComposeTxExecutedStatus(guid));
    }
}
