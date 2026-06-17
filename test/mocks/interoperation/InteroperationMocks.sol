// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {
    IOFT,
    SendParam,
    MessagingFee,
    MessagingReceipt,
    OFTReceipt,
    OFTLimit,
    OFTFeeDetail
} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";

import {IOFTCompose} from "../../../src/common/omnichain/oft/IOFTCompose.sol";
import {IBurnable} from "../../../src/common/interfaces/IBurnable.sol";
import {IMemeverseLauncher} from "../../../src/verse/interfaces/IMemeverseLauncher.sol";

/// @notice Mock compose token used by the omnichain staker tests.
/// @dev Implements `IOFTCompose`/`IBurnable` so production code that calls the compose/burn path can
///      exercise it without a full LayerZero deployment.
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

/// @notice Mock yield vault recording the last deposit for assertions.
contract MockStakerYieldVault {
    uint256 public lastDepositAmount;
    address public lastDepositReceiver;
    bool public shouldRevert;

    /// @notice Set whether deposits should revert.
    /// @param shouldRevert_ See implementation.
    function setShouldRevert(bool shouldRevert_) external {
        shouldRevert = shouldRevert_;
    }

    /// @notice Deposit.
    /// @param amount See implementation.
    /// @param receiver See implementation.
    /// @return shares See implementation.
    function deposit(uint256 amount, address receiver) external returns (uint256 shares) {
        require(!shouldRevert, "deposit failed");
        lastDepositAmount = amount;
        lastDepositReceiver = receiver;
        shares = amount;
    }
}

/// @notice Mock launcher exposing the memecoin -> verse lookup used by interoperation tests.
contract MockInteroperationLauncher {
    IMemeverseLauncher.Memeverse internal verse;
    address internal registeredMemecoin;

    /// @notice Set memeverse.
    /// @param memecoin See implementation.
    /// @param verse_ See implementation.
    function setMemeverse(address memecoin, IMemeverseLauncher.Memeverse memory verse_) external {
        registeredMemecoin = memecoin;
        verse = verse_;
    }

    /// @notice Get memeverse by memecoin.
    /// @param memecoin See implementation.
    /// @return See implementation.
    function getMemeverseByMemecoin(address memecoin) external view returns (IMemeverseLauncher.Memeverse memory) {
        if (memecoin != registeredMemecoin) {
            revert IMemeverseLauncher.InvalidVerseId();
        }
        return verse;
    }
}

/// @notice Mock registry mapping chain ids to LayerZero endpoint ids.
contract MockInteroperationRegistry {
    mapping(uint32 chainId => uint32 endpointId) public lzEndpointIdOfChain;

    /// @notice Set endpoint.
    /// @param chainId See implementation.
    /// @param endpointId See implementation.
    function setEndpoint(uint32 chainId, uint32 endpointId) external {
        lzEndpointIdOfChain[chainId] = endpointId;
    }
}

/// @notice Mock yield vault recording the last deposit for interoperation assertions.
contract MockInteroperationYieldVault {
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

/// @notice Mock OFT that records send inputs and enforces the quoted fee.
/// @dev Asserts `fee` and `msg.value` match the last `quoteFee` so callers cannot reuse a stale quote.
contract MockInteroperationOFT is MockERC20, IOFT {
    using OptionsBuilder for bytes;

    error InvalidQuotedSendFee(
        uint256 expectedNativeFee,
        uint256 expectedLzTokenFee,
        uint256 providedNativeFee,
        uint256 providedLzTokenFee,
        uint256 msgValue
    );

    MessagingFee internal quoteFee;
    uint32 public lastSendDstEid;
    bytes32 public lastSendTo;
    bytes public lastSendComposeMsg;
    uint256 public lastSendNativeFee;
    address public lastRefundAddress;
    uint256 public lastSendValue;
    bytes32 public nextGuid = bytes32("stake-guid");

    constructor() MockERC20("Memecoin", "MEME", 18) {}

    /// @notice Set quote fee.
    /// @param nativeFee See implementation.
    function setQuoteFee(uint256 nativeFee) external {
        quoteFee = MessagingFee({nativeFee: nativeFee, lzTokenFee: 0});
    }

    /// @notice Oft version.
    /// @return interfaceId See implementation.
    /// @return version See implementation.
    function oftVersion() external pure returns (bytes4 interfaceId, uint64 version) {
        return (type(IOFT).interfaceId, 1);
    }

    /// @notice Token.
    /// @return See implementation.
    function token() external view returns (address) {
        return address(this);
    }

    /// @notice Approval required.
    /// @return See implementation.
    function approvalRequired() external pure returns (bool) {
        return false;
    }

    /// @notice Shared decimals.
    /// @return See implementation.
    function sharedDecimals() external pure returns (uint8) {
        return 6;
    }

    /// @notice Quote oft.
    /// @return See implementation.
    function quoteOFT(SendParam calldata)
        external
        pure
        returns (OFTLimit memory, OFTFeeDetail[] memory, OFTReceipt memory)
    {
        revert("unused");
    }

    /// @notice Quote send.
    /// @param sendParam See implementation.
    /// @param payInLzToken See implementation.
    /// @return fee See implementation.
    function quoteSend(SendParam calldata sendParam, bool payInLzToken)
        external
        view
        returns (MessagingFee memory fee)
    {
        sendParam;
        payInLzToken;
        fee = quoteFee;
    }

    /// @notice Send.
    /// @param sendParam See implementation.
    /// @param fee See implementation.
    /// @param refundAddress See implementation.
    /// @return receipt See implementation.
    /// @return oftReceipt See implementation.
    function send(SendParam calldata sendParam, MessagingFee calldata fee, address refundAddress)
        external
        payable
        returns (MessagingReceipt memory receipt, OFTReceipt memory oftReceipt)
    {
        if (
            fee.nativeFee != quoteFee.nativeFee || fee.lzTokenFee != quoteFee.lzTokenFee
                || msg.value != quoteFee.nativeFee
        ) {
            revert InvalidQuotedSendFee(
                quoteFee.nativeFee, quoteFee.lzTokenFee, fee.nativeFee, fee.lzTokenFee, msg.value
            );
        }

        lastSendDstEid = sendParam.dstEid;
        lastSendTo = sendParam.to;
        lastSendComposeMsg = sendParam.composeMsg;
        lastSendNativeFee = fee.nativeFee;
        lastRefundAddress = refundAddress;
        lastSendValue = msg.value;
        _burn(msg.sender, sendParam.amountLD);

        receipt = MessagingReceipt({guid: nextGuid, nonce: 1, fee: fee});
        oftReceipt = OFTReceipt({amountSentLD: sendParam.amountLD, amountReceivedLD: sendParam.amountLD});
    }
}
