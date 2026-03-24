// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {
    MessagingFee,
    MessagingParams,
    MessagingReceipt
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {Origin} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppReceiver.sol";
import {OFTMsgCodec} from "@layerzerolabs/oft-evm/contracts/libs/OFTMsgCodec.sol";
import {SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {OutrunOFTInit} from "../../../../src/common/omnichain/oft/OutrunOFTInit.sol";
import {IOFTCompose} from "../../../../src/common/omnichain/oft/IOFTCompose.sol";

contract MockOFTEndpoint {
    address public delegate;
    address public lzToken;
    uint256 public quoteNativeFee;
    uint32 public lastDstEid;
    bytes32 public lastReceiver;
    bytes public lastMessage;
    bytes public lastOptions;
    bool public lastPayInLzToken;
    address public lastComposeTo;
    bytes32 public lastComposeGuid;
    uint16 public lastComposeIndex;
    bytes public lastComposeMessage;

    /// @notice Set delegate.
    /// @param delegate_ See implementation.
    function setDelegate(address delegate_) external {
        delegate = delegate_;
    }

    /// @notice Set lz token.
    /// @param lzToken_ See implementation.
    function setLzToken(address lzToken_) external {
        lzToken = lzToken_;
    }

    /// @notice Set quote native fee.
    /// @param nativeFee See implementation.
    function setQuoteNativeFee(uint256 nativeFee) external {
        quoteNativeFee = nativeFee;
    }

    /// @notice Quote.
    /// @param params See implementation.
    /// @param sender See implementation.
    /// @return fee See implementation.
    function quote(MessagingParams calldata params, address sender) external view returns (MessagingFee memory fee) {
        params;
        sender;
        fee = MessagingFee({nativeFee: quoteNativeFee, lzTokenFee: 0});
    }

    /// @notice Send.
    /// @param params See implementation.
    /// @param refundAddress See implementation.
    /// @return receipt See implementation.
    function send(MessagingParams calldata params, address refundAddress)
        external
        payable
        returns (MessagingReceipt memory receipt)
    {
        refundAddress;
        lastDstEid = params.dstEid;
        lastReceiver = params.receiver;
        lastMessage = params.message;
        lastOptions = params.options;
        lastPayInLzToken = params.payInLzToken;
        receipt = MessagingReceipt({
            guid: bytes32("guid"), nonce: 1, fee: MessagingFee({nativeFee: msg.value, lzTokenFee: 0})
        });
    }

    /// @notice Send compose.
    /// @param to See implementation.
    /// @param guid See implementation.
    /// @param index See implementation.
    /// @param message See implementation.
    function sendCompose(address to, bytes32 guid, uint16 index, bytes calldata message) external {
        lastComposeTo = to;
        lastComposeGuid = guid;
        lastComposeIndex = index;
        lastComposeMessage = message;
    }
}

contract OFTHarness is OutrunOFTInit {
    constructor(address endpoint_) OutrunOFTInit(endpoint_) {}

    /// @notice Initialize.
    /// @param owner_ See implementation.
    /// @param name_ See implementation.
    /// @param symbol_ See implementation.
    /// @param delegate_ See implementation.
    function initialize(address owner_, string memory name_, string memory symbol_, address delegate_)
        external
        initializer
    {
        __OutrunOFT_init(name_, symbol_, delegate_);
        __OutrunOwnable_init(owner_);
    }

    /// @notice Mint test.
    /// @param to See implementation.
    /// @param amount See implementation.
    function mintTest(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /// @notice Seed compose.
    /// @param guid See implementation.
    /// @param composer See implementation.
    /// @param ubo See implementation.
    /// @param amount See implementation.
    /// @param executed See implementation.
    function seedCompose(bytes32 guid, address composer, address ubo, uint256 amount, bool executed) external {
        ComposeTxStatus storage txStatus = _getOFTCoreStorage().composeTxs[guid];
        txStatus.composer = composer;
        txStatus.UBO = ubo;
        txStatus.amount = amount;
        txStatus.isExecuted = executed;
    }
}

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
