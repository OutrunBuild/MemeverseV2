// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
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

import {IMemeverseLauncher} from "../../src/verse/interfaces/IMemeverseLauncher.sol";
import {
    IMemeverseOmnichainInteroperation
} from "../../src/interoperation/interfaces/IMemeverseOmnichainInteroperation.sol";
import {MemeverseOmnichainInteroperation} from "../../src/interoperation/MemeverseOmnichainInteroperation.sol";

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

contract MockInteroperationRegistry {
    mapping(uint32 chainId => uint32 endpointId) public lzEndpointIdOfChain;

    /// @notice Set endpoint.
    /// @param chainId See implementation.
    /// @param endpointId See implementation.
    function setEndpoint(uint32 chainId, uint32 endpointId) external {
        lzEndpointIdOfChain[chainId] = endpointId;
    }
}

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

contract MemeverseOmnichainInteroperationTest is Test {
    using OptionsBuilder for bytes;

    address internal constant OWNER = address(0xABCD);
    address internal constant RECEIVER = address(0xBEEF);
    address internal constant OMNICHAIN_STAKER = address(0xCAFE);
    uint32 internal constant REMOTE_CHAIN_ID = 202;
    uint32 internal constant REMOTE_EID = 302;

    MockInteroperationLauncher internal launcher;
    MockInteroperationRegistry internal registry;
    MockInteroperationYieldVault internal yieldVault;
    MockInteroperationOFT internal memecoin;
    MemeverseOmnichainInteroperation internal interoperation;

    /// @notice Set up.
    function setUp() external {
        launcher = new MockInteroperationLauncher();
        registry = new MockInteroperationRegistry();
        yieldVault = new MockInteroperationYieldVault();
        memecoin = new MockInteroperationOFT();
        interoperation = new MemeverseOmnichainInteroperation(
            OWNER, address(registry), address(launcher), OMNICHAIN_STAKER, 115_000, 135_000
        );
    }

    /// @notice Test quote memecoin staking rejects zero input.
    function testQuoteMemecoinStakingRejectsZeroInput() external {
        vm.expectRevert(IMemeverseOmnichainInteroperation.ZeroInput.selector);
        interoperation.quoteMemecoinStaking(address(0), RECEIVER, 1 ether);
    }

    /// @notice Test quote memecoin staking rejects unregistered memecoin.
    function testQuoteMemecoinStakingRejectsUnregisteredMemecoin() external {
        _setLocalVerse(address(yieldVault));

        vm.expectRevert(IMemeverseLauncher.InvalidVerseId.selector);
        interoperation.quoteMemecoinStaking(address(0x9999), RECEIVER, 1 ether);
    }

    /// @notice Test quote memecoin staking returns zero for local governance chain.
    function testQuoteMemecoinStakingReturnsZeroForLocalGovernanceChain() external {
        _setLocalVerse(address(yieldVault));

        uint256 fee = interoperation.quoteMemecoinStaking(address(memecoin), RECEIVER, 1 ether);
        assertEq(fee, 0);
    }

    /// @notice Test quote memecoin staking builds remote send param.
    function testQuoteMemecoinStakingBuildsRemoteSendParam() external {
        _setRemoteVerse(address(yieldVault));
        memecoin.setQuoteFee(0.25 ether);

        bytes memory expectedOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(115_000, 0)
            .addExecutorLzComposeOption(0, 135_000, 0);

        vm.expectCall(
            address(memecoin),
            abi.encodeWithSelector(
                IOFT.quoteSend.selector,
                SendParam({
                    dstEid: REMOTE_EID,
                    to: bytes32(uint256(uint160(OMNICHAIN_STAKER))),
                    amountLD: 2 ether,
                    minAmountLD: 0,
                    extraOptions: expectedOptions,
                    composeMsg: abi.encode(RECEIVER, address(yieldVault)),
                    oftCmd: abi.encode()
                }),
                false
            )
        );

        uint256 fee = interoperation.quoteMemecoinStaking(address(memecoin), RECEIVER, 2 ether);
        assertEq(fee, 0.25 ether);
    }

    /// @notice Test memecoin staking local path rejects empty vault and deposits to yield vault.
    function testMemecoinStakingLocalPathRejectsEmptyVaultAndDepositsToYieldVault() external {
        _setLocalVerse(address(0));
        memecoin.mint(address(this), 3 ether);
        memecoin.approve(address(interoperation), type(uint256).max);

        vm.expectRevert(IMemeverseOmnichainInteroperation.EmptyYieldVault.selector);
        interoperation.memecoinStaking(address(memecoin), RECEIVER, 3 ether);

        _setLocalVerse(address(yieldVault));
        interoperation.memecoinStaking(address(memecoin), RECEIVER, 3 ether);

        assertEq(yieldVault.lastDepositAmount(), 3 ether);
        assertEq(yieldVault.lastDepositReceiver(), RECEIVER);
    }

    /// @notice Test memecoin staking remote path checks fee and sends oft.
    function testMemecoinStakingRemotePathChecksFeeAndSendsOFT() external {
        _setRemoteVerse(address(yieldVault));
        memecoin.setQuoteFee(0.4 ether);
        memecoin.mint(address(this), 5 ether);
        memecoin.approve(address(interoperation), type(uint256).max);
        uint256 quotedFee = interoperation.quoteMemecoinStaking(address(memecoin), RECEIVER, 5 ether);

        vm.expectRevert(abi.encodeWithSelector(IMemeverseOmnichainInteroperation.InvalidLzFee.selector, quotedFee, 0));
        interoperation.memecoinStaking(address(memecoin), RECEIVER, 5 ether);

        interoperation.memecoinStaking{value: quotedFee}(address(memecoin), RECEIVER, 5 ether);

        assertEq(memecoin.lastRefundAddress(), address(this));
        assertEq(memecoin.lastSendValue(), quotedFee);
        assertEq(memecoin.lastSendNativeFee(), quotedFee);
        assertEq(memecoin.lastSendDstEid(), REMOTE_EID);
        assertEq(memecoin.lastSendTo(), bytes32(uint256(uint160(OMNICHAIN_STAKER))));
        assertEq(memecoin.lastSendComposeMsg(), abi.encode(RECEIVER, address(yieldVault)));
    }

    /// @notice Verifies the OFT mock rejects stale quoted fees and mismatched msg.value.
    function testMockInteroperationOFTSendRejectsStaleQuotedFee() external {
        memecoin.mint(address(this), 1 ether);

        SendParam memory sendParam = SendParam({
            dstEid: REMOTE_EID,
            to: bytes32(uint256(uint160(OMNICHAIN_STAKER))),
            amountLD: 1 ether,
            minAmountLD: 0,
            extraOptions: "",
            composeMsg: abi.encode(RECEIVER, address(yieldVault)),
            oftCmd: abi.encode()
        });
        memecoin.setQuoteFee(0.2 ether);
        MessagingFee memory staleFee = memecoin.quoteSend(sendParam, false);
        memecoin.setQuoteFee(0.3 ether);

        vm.expectRevert(
            abi.encodeWithSelector(
                MockInteroperationOFT.InvalidQuotedSendFee.selector, 0.3 ether, 0, 0.2 ether, 0, 0.2 ether
            )
        );
        memecoin.send{value: staleFee.nativeFee}(sendParam, staleFee, RECEIVER);
    }

    /// @notice Verifies remote staking rejects overpayment instead of trapping extra ETH in the interoperation contract.
    /// @dev Requires callers to provide the exact quoted LayerZero fee.
    function testMemecoinStakingRemotePathRevertsWhenLzFeeIsNotExact() external {
        _setRemoteVerse(address(yieldVault));
        memecoin.setQuoteFee(0.4 ether);
        memecoin.mint(address(this), 5 ether);
        memecoin.approve(address(interoperation), type(uint256).max);

        vm.expectRevert(
            abi.encodeWithSelector(IMemeverseOmnichainInteroperation.InvalidLzFee.selector, 0.4 ether, 0.41 ether)
        );
        interoperation.memecoinStaking{value: 0.41 ether}(address(memecoin), RECEIVER, 5 ether);
    }

    /// @notice Verifies local staking rejects accidental native value.
    /// @dev Prevents same-chain staking calls from trapping ETH in the interoperation contract.
    function testMemecoinStakingLocalPathRevertsWhenMsgValueProvided() external {
        _setLocalVerse(address(yieldVault));
        memecoin.mint(address(this), 3 ether);
        memecoin.approve(address(interoperation), type(uint256).max);

        vm.expectRevert(abi.encodeWithSelector(IMemeverseOmnichainInteroperation.InvalidLzFee.selector, 0, 1));
        interoperation.memecoinStaking{value: 1}(address(memecoin), RECEIVER, 3 ether);
    }

    /// @notice Test memecoin staking rejects unregistered memecoin.
    function testMemecoinStakingRejectsUnregisteredMemecoin() external {
        _setLocalVerse(address(yieldVault));

        vm.expectRevert(IMemeverseLauncher.InvalidVerseId.selector);
        interoperation.memecoinStaking(address(0x9999), RECEIVER, 1 ether);
    }

    /// @notice Test set gas limits only owner and rejects zero.
    function testSetGasLimitsOnlyOwnerAndRejectsZero() external {
        vm.prank(address(0x1234));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(0x1234)));
        interoperation.setGasLimits(1, 1);

        vm.prank(OWNER);
        vm.expectRevert(IMemeverseOmnichainInteroperation.ZeroInput.selector);
        interoperation.setGasLimits(0, 1);

        vm.prank(OWNER);
        interoperation.setGasLimits(1, 2);
        assertEq(interoperation.oftReceiveGasLimit(), 1);
        assertEq(interoperation.omnichainStakingGasLimit(), 2);
    }

    function _setLocalVerse(address yieldVaultAddress) internal {
        launcher.setMemeverse(address(memecoin), _verse(uint32(block.chainid), yieldVaultAddress));
    }

    function _setRemoteVerse(address yieldVaultAddress) internal {
        registry.setEndpoint(REMOTE_CHAIN_ID, REMOTE_EID);
        launcher.setMemeverse(address(memecoin), _verse(REMOTE_CHAIN_ID, yieldVaultAddress));
    }

    function _verse(uint32 govChainId, address yieldVaultAddress)
        internal
        pure
        returns (IMemeverseLauncher.Memeverse memory verse)
    {
        verse.yieldVault = yieldVaultAddress;
        verse.omnichainIds = new uint32[](1);
        verse.omnichainIds[0] = govChainId;
    }
}
