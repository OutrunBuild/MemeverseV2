// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {
    MessagingFee,
    MessagingParams
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {Origin} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppReceiver.sol";
import {OFTMsgCodec} from "@layerzerolabs/oft-evm/contracts/libs/OFTMsgCodec.sol";
import {SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {IOFTCompose} from "../../../../src/common/omnichain/oft/IOFTCompose.sol";
import {MockOFTEndpoint} from "../../../mocks/common/CommonMocks.sol";
import {OFTHarness} from "../../../mocks/infrastructure/OFTHarness.sol";

error AmountSDOverflowed(uint256 amountSD);

contract OutrunOFTInitTest is Test {
    using Clones for address;
    using OFTMsgCodec for bytes;

    address internal constant OWNER = address(0xABCD);
    address internal constant DELEGATE = address(0xCAFE);
    address internal constant UBO = address(0xBEEF);
    address internal constant RECEIVER = address(0xA11CE);
    uint32 internal constant DST_EID = 101;

    MockOFTEndpoint internal endpoint;
    OFTHarness internal implementation;
    OFTHarness internal oft;

    /// @notice Set up.
    function setUp() external {
        endpoint = new MockOFTEndpoint();
        implementation = new OFTHarness(address(endpoint));
        oft = OFTHarness(address(implementation).clone());
        oft.initialize(OWNER, "OFT Token", "OFT", DELEGATE);

        vm.prank(OWNER);
        oft.setPeer(DST_EID, bytes32(uint256(uint160(address(0xBEEF)))));
    }

    /// @notice Test initialize sets metadata and token config.
    function testInitializeSetsMetadataAndTokenConfig() external view {
        assertEq(oft.name(), "OFT Token");
        assertEq(oft.symbol(), "OFT");
        assertEq(oft.owner(), OWNER);
        assertEq(oft.token(), address(oft));
        assertFalse(oft.approvalRequired());
        assertEq(oft.sharedDecimals(), 6);
        assertEq(oft.decimalConversionRate(), 1e12);
    }

    /// @notice Test quote send and send use peer and burn sender balance.
    function testQuoteSendAndSendUsePeerAndBurnSenderBalance() external {
        endpoint.setQuoteNativeFee(0.2 ether);
        oft.mintTest(address(this), 5 ether);

        SendParam memory sendParam = SendParam({
            dstEid: DST_EID,
            to: bytes32(uint256(uint160(address(0xBEEF)))),
            amountLD: 5 ether,
            minAmountLD: 0,
            extraOptions: bytes("opts"),
            composeMsg: bytes(""),
            oftCmd: bytes("")
        });

        vm.expectCall(
            address(endpoint),
            abi.encodeWithSelector(
                MockOFTEndpoint.quote.selector,
                MessagingParams({
                    dstEid: DST_EID,
                    receiver: sendParam.to,
                    message: bytes(
                        hex"000000000000000000000000000000000000000000000000000000000000beef00000000004c4b40"
                    ),
                    options: bytes("opts"),
                    payInLzToken: false
                }),
                address(oft)
            )
        );
        MessagingFee memory fee = oft.quoteSend(sendParam, false);
        assertEq(fee.nativeFee, 0.2 ether);

        oft.send{value: 0.2 ether}(sendParam, fee, address(this));
        assertEq(oft.balanceOf(address(this)), 0);
    }

    /// @notice Test quoteSend reverts when the shared-decimal amount exceeds uint64 capacity.
    function testQuoteSendRevertsWhenAmountSDOverflows() external {
        uint256 overflowAmountLD = (uint256(type(uint64).max) + 1) * oft.decimalConversionRate();

        SendParam memory sendParam = SendParam({
            dstEid: DST_EID,
            to: bytes32(uint256(uint160(address(0xBEEF)))),
            amountLD: overflowAmountLD,
            minAmountLD: 0,
            extraOptions: bytes("opts"),
            composeMsg: bytes(""),
            oftCmd: bytes("")
        });

        vm.expectRevert(abi.encodeWithSelector(AmountSDOverflowed.selector, uint256(type(uint64).max) + 1));
        oft.quoteSend(sendParam, false);
    }

    /// @notice Test withdraw if not executed requires uboand transfers composer balance.
    function testWithdrawIfNotExecutedRequiresUBOAndTransfersComposerBalance() external {
        bytes32 guid = bytes32("guid");
        oft.mintTest(address(0x1234), 3 ether);
        oft.seedCompose(guid, address(0x1234), UBO, 3 ether, false);

        vm.expectRevert(IOFTCompose.PermissionDenied.selector);
        oft.withdrawIfNotExecuted(guid, RECEIVER);

        vm.prank(UBO);
        uint256 amount = oft.withdrawIfNotExecuted(guid, RECEIVER);

        assertEq(amount, 3 ether);
        assertEq(oft.balanceOf(RECEIVER), 3 ether);
        assertTrue(oft.getComposeTxExecutedStatus(guid));

        vm.prank(UBO);
        vm.expectRevert(IOFTCompose.AlreadyExecuted.selector);
        oft.withdrawIfNotExecuted(guid, RECEIVER);
    }

    /// @notice Test lz receive credits recipient and creates compose status.
    function testLzReceiveCreditsRecipientAndCreatesComposeStatus() external {
        Origin memory origin = Origin({srcEid: DST_EID, sender: bytes32(uint256(uint160(address(0xBEEF)))), nonce: 1});
        bytes memory message;
        bool hasCompose;
        (message, hasCompose) =
            OFTMsgCodec.encode(bytes32(uint256(uint160(address(0x1234)))), 2_000_000, abi.encode(UBO));
        assertTrue(hasCompose);

        vm.prank(address(endpoint));
        oft.lzReceive(origin, bytes32("compose-guid"), message, address(0), "");

        assertEq(oft.balanceOf(address(0x1234)), 2 ether);
        assertFalse(oft.getComposeTxExecutedStatus(bytes32("compose-guid")));
        assertEq(endpoint.lastComposeTo(), address(0x1234));
        assertEq(endpoint.lastComposeGuid(), bytes32("compose-guid"));
        assertEq(endpoint.lastComposeIndex(), 0);

        vm.prank(address(0x1234));
        oft.notifyComposeExecuted(bytes32("compose-guid"));
        assertTrue(oft.getComposeTxExecutedStatus(bytes32("compose-guid")));
    }
}
