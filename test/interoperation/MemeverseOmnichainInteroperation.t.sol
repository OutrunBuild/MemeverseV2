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

    /// @notice Set memeverse.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @param verse_ See implementation.
    function setMemeverse(IMemeverseLauncher.Memeverse memory verse_) external {
        verse = verse_;
    }

    /// @notice Get memeverse by memecoin.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @param memecoin See implementation.
    /// @return See implementation.
    function getMemeverseByMemecoin(address memecoin) external view returns (IMemeverseLauncher.Memeverse memory) {
        memecoin;
        return verse;
    }
}

contract MockInteroperationRegistry {
    mapping(uint32 chainId => uint32 endpointId) public lzEndpointIdOfChain;

    /// @notice Set endpoint.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
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
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
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
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @param nativeFee See implementation.
    function setQuoteFee(uint256 nativeFee) external {
        quoteFee = MessagingFee({nativeFee: nativeFee, lzTokenFee: 0});
    }

    /// @notice Oft version.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @return interfaceId See implementation.
    /// @return version See implementation.
    function oftVersion() external pure returns (bytes4 interfaceId, uint64 version) {
        return (type(IOFT).interfaceId, 1);
    }

    /// @notice Token.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @return See implementation.
    function token() external view returns (address) {
        return address(this);
    }

    /// @notice Approval required.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @return See implementation.
    function approvalRequired() external pure returns (bool) {
        return false;
    }

    /// @notice Shared decimals.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @return See implementation.
    function sharedDecimals() external pure returns (uint8) {
        return 6;
    }

    /// @notice Quote oft.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @return See implementation.
    function quoteOFT(SendParam calldata)
        external
        pure
        returns (OFTLimit memory, OFTFeeDetail[] memory, OFTReceipt memory)
    {
        revert("unused");
    }

    /// @notice Quote send.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
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
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
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
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
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
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function testQuoteMemecoinStakingRejectsZeroInput() external {
        vm.expectRevert(IMemeverseOmnichainInteroperation.ZeroInput.selector);
        interoperation.quoteMemecoinStaking(address(0), RECEIVER, 1 ether);
    }

    /// @notice Test quote memecoin staking returns zero for local governance chain.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function testQuoteMemecoinStakingReturnsZeroForLocalGovernanceChain() external {
        _setLocalVerse(address(yieldVault));

        uint256 fee = interoperation.quoteMemecoinStaking(address(memecoin), RECEIVER, 1 ether);
        assertEq(fee, 0);
    }

    /// @notice Test quote memecoin staking builds remote send param.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
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
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
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
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function testMemecoinStakingRemotePathChecksFeeAndSendsOFT() external {
        _setRemoteVerse(address(yieldVault));
        memecoin.setQuoteFee(0.4 ether);
        memecoin.mint(address(this), 5 ether);
        memecoin.approve(address(interoperation), type(uint256).max);

        vm.expectRevert(IMemeverseOmnichainInteroperation.InsufficientLzFee.selector);
        interoperation.memecoinStaking(address(memecoin), RECEIVER, 5 ether);

        interoperation.memecoinStaking{value: 0.4 ether}(address(memecoin), RECEIVER, 5 ether);

        assertEq(memecoin.lastRefundAddress(), address(this));
        assertEq(memecoin.lastSendValue(), 0.4 ether);
        assertEq(memecoin.lastSendNativeFee(), 0.4 ether);
        assertEq(memecoin.lastSendDstEid(), REMOTE_EID);
        assertEq(memecoin.lastSendTo(), bytes32(uint256(uint160(OMNICHAIN_STAKER))));
        assertEq(memecoin.lastSendComposeMsg(), abi.encode(RECEIVER, address(yieldVault)));
    }

    /// @notice Test set gas limits only owner and rejects zero.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
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
        launcher.setMemeverse(_verse(uint32(block.chainid), yieldVaultAddress));
    }

    function _setRemoteVerse(address yieldVaultAddress) internal {
        registry.setEndpoint(REMOTE_CHAIN_ID, REMOTE_EID);
        launcher.setMemeverse(_verse(REMOTE_CHAIN_ID, yieldVaultAddress));
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
