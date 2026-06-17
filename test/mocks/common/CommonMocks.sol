// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

import {
    MessagingFee,
    MessagingParams,
    MessagingReceipt
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

/// @title MockOAppSenderEndpoint
/// @notice Simulates the LayerZero V2 endpoint for OutrunOAppSenderInit quote/send assertions.
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

/// @title MockOAppCoreEndpoint
/// @notice Minimal endpoint stub exposing only the delegate setter exercised by OutrunOAppCoreInit tests.
contract MockOAppCoreEndpoint {
    address public delegate;

    /// @notice Set delegate.
    /// @param delegate_ See implementation.
    function setDelegate(address delegate_) external {
        delegate = delegate_;
    }
}

/// @title MockOFTEndpoint
/// @notice Endpoint stub supporting quote, send, and sendCompose paths exercised by OutrunOFTInit tests.
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

/// @title MockOAppReceiverEndpoint
/// @notice Minimal endpoint stub exposing only the delegate setter exercised by OutrunOAppReceiverInit tests.
contract MockOAppReceiverEndpoint {
    address public delegate;

    /// @notice Set delegate.
    /// @param delegate_ See implementation.
    function setDelegate(address delegate_) external {
        delegate = delegate_;
    }
}

/// @title RejectETHReceiver
/// @notice Receiver that reverts on plain ETH transfer, used to trigger NativeTransferFailed in TokenHelper tests.
contract RejectETHReceiver {
    receive() external payable {
        revert("no eth");
    }
}

/// @title FalseApproveToken
/// @notice Token stub whose approve always returns false, used to trigger SafeApproveFailed in TokenHelper tests.
contract FalseApproveToken {
    /// @notice Approve always returns false.
    /// @param spender Ignored.
    /// @param value Ignored.
    /// @return Always false.
    function approve(address spender, uint256 value) external pure returns (bool) {
        spender;
        value;
        return false;
    }
}
