// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {
    MessagingFee,
    MessagingParams,
    MessagingReceipt
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

import {OutrunOAppCoreInit} from "../../../../src/common/omnichain/oapp/OutrunOAppCoreInit.sol";
import {OutrunOAppSenderInit} from "../../../../src/common/omnichain/oapp/OutrunOAppSenderInit.sol";

contract MockOAppSenderEndpoint {
    address public delegate;
    address public lzToken;
    address public lastRefundAddress;
    uint256 public lastNativeValue;
    uint32 public lastDstEid;
    bytes32 public lastReceiver;
    bytes public lastMessage;
    bytes public lastOptions;
    bool public lastPayInLzToken;
    uint256 public quoteNativeFee;
    uint256 public quoteLzTokenFee;

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

    /// @notice Set quote fee.
    /// @param nativeFee See implementation.
    /// @param lzTokenFee See implementation.
    function setQuoteFee(uint256 nativeFee, uint256 lzTokenFee) external {
        quoteNativeFee = nativeFee;
        quoteLzTokenFee = lzTokenFee;
    }

    /// @notice Quote.
    /// @param params See implementation.
    /// @param sender See implementation.
    /// @return fee See implementation.
    function quote(MessagingParams calldata params, address sender) external view returns (MessagingFee memory fee) {
        params;
        sender;
        fee = MessagingFee({nativeFee: quoteNativeFee, lzTokenFee: quoteLzTokenFee});
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
        lastDstEid = params.dstEid;
        lastReceiver = params.receiver;
        lastMessage = params.message;
        lastOptions = params.options;
        lastPayInLzToken = params.payInLzToken;
        lastRefundAddress = refundAddress;
        lastNativeValue = msg.value;
        receipt = MessagingReceipt({
            guid: bytes32("guid"), nonce: 1, fee: MessagingFee({nativeFee: quoteNativeFee, lzTokenFee: quoteLzTokenFee})
        });
    }
}

contract OAppSenderHarness is OutrunOAppSenderInit {
    constructor(address endpoint_) OutrunOAppCoreInit(endpoint_) {}

    /// @notice Initialize.
    /// @param owner_ See implementation.
    /// @param delegate_ See implementation.
    function initialize(address owner_, address delegate_) external initializer {
        __OutrunOwnable_init(owner_);
        __OutrunOAppSender_init(delegate_);
    }

    /// @notice Quote external.
    /// @param dstEid See implementation.
    /// @param message See implementation.
    /// @param options See implementation.
    /// @param payInLzToken See implementation.
    /// @return See implementation.
    function quoteExternal(uint32 dstEid, bytes memory message, bytes memory options, bool payInLzToken)
        external
        view
        returns (MessagingFee memory)
    {
        return _quote(dstEid, message, options, payInLzToken);
    }

    /// @notice Send external.
    /// @param dstEid See implementation.
    /// @param message See implementation.
    /// @param options See implementation.
    /// @param fee See implementation.
    /// @param refundAddress See implementation.
    /// @return See implementation.
    function sendExternal(
        uint32 dstEid,
        bytes memory message,
        bytes memory options,
        MessagingFee memory fee,
        address refundAddress
    ) external payable returns (MessagingReceipt memory) {
        return _lzSend(dstEid, message, options, fee, refundAddress);
    }
}

contract OutrunOAppSenderInitTest is Test {
    using Clones for address;

    address internal constant OWNER = address(0xABCD);
    address internal constant DELEGATE = address(0xCAFE);
    uint32 internal constant DST_EID = 101;
    bytes32 internal constant PEER = bytes32(uint256(uint160(address(0xBEEF))));

    MockOAppSenderEndpoint internal endpoint;
    OAppSenderHarness internal implementation;
    OAppSenderHarness internal harness;
    MockERC20 internal lzToken;

    /// @notice Set up.
    function setUp() external {
        endpoint = new MockOAppSenderEndpoint();
        implementation = new OAppSenderHarness(address(endpoint));
        harness = OAppSenderHarness(address(implementation).clone());
        harness.initialize(OWNER, DELEGATE);

        vm.prank(OWNER);
        harness.setPeer(DST_EID, PEER);

        lzToken = new MockERC20("LZ", "LZ", 18);
    }

    /// @notice Test quote uses configured peer and endpoint quote.
    function testQuoteUsesConfiguredPeerAndEndpointQuote() external {
        endpoint.setQuoteFee(0.3 ether, 0);

        vm.expectCall(
            address(endpoint),
            abi.encodeWithSelector(
                MockOAppSenderEndpoint.quote.selector,
                MessagingParams({
                    dstEid: DST_EID,
                    receiver: PEER,
                    message: bytes("hello"),
                    options: bytes("opts"),
                    payInLzToken: false
                }),
                address(harness)
            )
        );
        MessagingFee memory fee = harness.quoteExternal(DST_EID, bytes("hello"), bytes("opts"), false);

        assertEq(fee.nativeFee, 0.3 ether);
    }

    /// @notice Test send rejects wrong native fee and missing lz token.
    function testSendRejectsWrongNativeFeeAndMissingLzToken() external {
        vm.expectRevert(abi.encodeWithSelector(OutrunOAppSenderInit.NotEnoughNative.selector, 0));
        harness.sendExternal(
            DST_EID, bytes("hello"), bytes("opts"), MessagingFee({nativeFee: 1 ether, lzTokenFee: 0}), address(this)
        );

        vm.expectRevert(OutrunOAppSenderInit.LzTokenUnavailable.selector);
        harness.sendExternal(
            DST_EID, bytes("hello"), bytes("opts"), MessagingFee({nativeFee: 0, lzTokenFee: 1 ether}), address(this)
        );
    }

    /// @notice Test send forwards native fee and refund address.
    function testSendForwardsNativeFeeAndRefundAddress() external {
        harness.sendExternal{value: 1 ether}(
            DST_EID, bytes("hello"), bytes("opts"), MessagingFee({nativeFee: 1 ether, lzTokenFee: 0}), address(this)
        );

        assertEq(endpoint.lastDstEid(), DST_EID);
        assertEq(endpoint.lastReceiver(), PEER);
        assertEq(endpoint.lastNativeValue(), 1 ether);
        assertEq(endpoint.lastRefundAddress(), address(this));
        assertFalse(endpoint.lastPayInLzToken());
    }

    /// @notice Test send transfers lz token fee when configured.
    function testSendTransfersLzTokenFeeWhenConfigured() external {
        endpoint.setLzToken(address(lzToken));
        lzToken.mint(address(this), 2 ether);
        lzToken.approve(address(harness), type(uint256).max);

        harness.sendExternal(
            DST_EID, bytes("hello"), bytes("opts"), MessagingFee({nativeFee: 0, lzTokenFee: 2 ether}), address(this)
        );

        assertEq(lzToken.balanceOf(address(endpoint)), 2 ether);
        assertTrue(endpoint.lastPayInLzToken());
    }
}
