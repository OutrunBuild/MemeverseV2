// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {OFTComposeMsgCodec} from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";

import {IOmnichainMemecoinStaker} from "../../src/interoperation/interfaces/IOmnichainMemecoinStaker.sol";
import {OmnichainMemecoinStaker} from "../../src/interoperation/OmnichainMemecoinStaker.sol";
import {MockStakerComposeToken, MockStakerYieldVault} from "../mocks/interoperation/InteroperationMocks.sol";

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
        staker.lzCompose(address(memecoin), bytes32(0), "", LOCAL_ENDPOINT, "");

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

    /// @notice Test lz compose ignores executor and native value when refunding the receiver.
    function testLzComposeIgnoresExecutorAndNativeValueWhenRefundingReceiver() external {
        bytes32 guid = bytes32("value");
        memecoin.mint(address(staker), 5 ether);
        bytes memory message = OFTComposeMsgCodec.encode(
            1,
            101,
            2 ether,
            abi.encodePacked(bytes32(uint256(uint160(RECEIVER))), abi.encode(RECEIVER, address(0x1234)))
        );

        vm.deal(LOCAL_ENDPOINT, 1 wei);
        vm.prank(LOCAL_ENDPOINT);
        staker.lzCompose{value: 1 wei}(address(memecoin), guid, message, address(0xCAFE), hex"1234");

        assertEq(memecoin.balanceOf(RECEIVER), 2 ether);
        assertEq(memecoin.balanceOf(address(staker)), 3 ether);
        assertEq(address(staker).balance, 1 wei);
        assertEq(memecoin.lastNotifiedGuid(), guid);
        assertTrue(memecoin.getComposeTxExecutedStatus(guid));
    }

    /// @notice Test failed deposits do not consume the guid and replays are blocked after success.
    function testLzComposeAllowsRetryAfterFailedDepositAndBlocksReplayAfterSuccess() external {
        bytes32 guid = bytes32("retry");
        memecoin.mint(address(staker), 4 ether);
        bytes memory message = OFTComposeMsgCodec.encode(
            1,
            101,
            4 ether,
            abi.encodePacked(bytes32(uint256(uint160(RECEIVER))), abi.encode(RECEIVER, address(yieldVault)))
        );

        yieldVault.setShouldRevert(true);
        vm.prank(LOCAL_ENDPOINT);
        vm.expectRevert("deposit failed");
        staker.lzCompose(address(memecoin), guid, message, address(0xCAFE), "");

        assertEq(memecoin.lastNotifiedGuid(), bytes32(0));
        assertFalse(memecoin.getComposeTxExecutedStatus(guid));
        assertEq(yieldVault.lastDepositAmount(), 0);

        yieldVault.setShouldRevert(false);
        vm.prank(LOCAL_ENDPOINT);
        staker.lzCompose(address(memecoin), guid, message, address(0xCAFE), "");

        assertEq(yieldVault.lastDepositAmount(), 4 ether);
        assertEq(yieldVault.lastDepositReceiver(), RECEIVER);
        assertEq(memecoin.lastNotifiedGuid(), guid);
        assertTrue(memecoin.getComposeTxExecutedStatus(guid));

        vm.prank(LOCAL_ENDPOINT);
        vm.expectRevert(IOmnichainMemecoinStaker.AlreadyExecuted.selector);
        staker.lzCompose(address(memecoin), guid, message, address(0xCAFE), "");
    }

    /// @notice Test lz compose reverts on malformed compose message.
    function testLzComposeRevertsOnMalformedComposeMessage() external {
        bytes32 guid = bytes32("malformed");
        memecoin.mint(address(staker), 1 ether);

        // ComposeMsg contains only the receiver prefix but no (address, address) tuple for abi.decode.
        bytes memory message = OFTComposeMsgCodec.encode(1, 101, 1 ether, hex"deadbeef");

        vm.prank(LOCAL_ENDPOINT);
        vm.expectRevert();
        staker.lzCompose(address(memecoin), guid, message, address(0), "");
    }
}
