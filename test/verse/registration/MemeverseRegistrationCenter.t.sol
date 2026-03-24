// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {
    MessagingFee,
    MessagingParams,
    MessagingReceipt
} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {Origin} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";

import {MemeverseRegistrationCenter} from "../../../src/verse/registration/MemeverseRegistrationCenter.sol";
import {IMemeverseRegistrar} from "../../../src/verse/interfaces/IMemeverseRegistrar.sol";
import {IMemeverseRegistrationCenter} from "../../../src/verse/interfaces/IMemeverseRegistrationCenter.sol";
import {LzEndpointRegistry} from "../../../src/common/omnichain/LzEndpointRegistry.sol";
import {ILzEndpointRegistry} from "../../../src/common/omnichain/interfaces/ILzEndpointRegistry.sol";

contract MockCenterEndpoint {
    address public delegate;
    uint256 public quotedNativeFee;
    uint256 public actualNativeFee;
    address public lastRefundAddress;
    uint256 public lastSendValue;
    uint256 public lastRefundedNative;
    uint32 public lastDstEid;
    bytes32 public lastReceiver;
    bytes public lastMessage;
    bytes public lastOptions;
    bool public lastPayInLzToken;
    bytes32 public sendGuid = bytes32("guid");
    uint64 public sendNonce = 7;

    /// @notice Set delegate.
    /// @param delegate_ See implementation.
    function setDelegate(address delegate_) external {
        delegate = delegate_;
    }

    /// @notice Lz token.
    /// @return See implementation.
    function lzToken() external pure returns (address) {
        return address(0);
    }

    /// @notice Set quoted native fee.
    /// @param fee See implementation.
    function setQuotedNativeFee(uint256 fee) external {
        quotedNativeFee = fee;
    }

    /// @notice Set actual native fee.
    /// @param fee See implementation.
    function setActualNativeFee(uint256 fee) external {
        actualNativeFee = fee;
    }

    /// @notice Quote.
    /// @param params See implementation.
    /// @param sender See implementation.
    /// @return fee See implementation.
    function quote(MessagingParams calldata params, address sender) external view returns (MessagingFee memory fee) {
        params;
        sender;
        fee = MessagingFee({nativeFee: quotedNativeFee, lzTokenFee: 0});
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
        lastSendValue = msg.value;
        uint256 retainedNativeFee = actualNativeFee == 0 ? quotedNativeFee : actualNativeFee;
        if (msg.value > retainedNativeFee) {
            lastRefundedNative = msg.value - retainedNativeFee;
            (bool success,) = payable(refundAddress).call{value: lastRefundedNative}("");
            require(success, "refund failed");
        } else {
            lastRefundedNative = 0;
        }
        receipt = MessagingReceipt({
            guid: sendGuid, nonce: sendNonce, fee: MessagingFee({nativeFee: quotedNativeFee, lzTokenFee: 0})
        });
    }
}

contract MockCenterRegistrar {
    uint256 public lastUniqueId;
    address public lastUPT;
    bool public lastFlashGenesis;
    string public lastName;
    string public lastSymbol;

    /// @notice Local registration.
    /// @param param See implementation.
    function localRegistration(IMemeverseRegistrar.MemeverseParam calldata param) external {
        lastUniqueId = param.uniqueId;
        lastUPT = param.UPT;
        lastFlashGenesis = param.flashGenesis;
        lastName = param.name;
        lastSymbol = param.symbol;
    }
}

contract MemeverseRegistrationCenterTest is Test {
    address internal constant OWNER = address(0xABCD);
    uint32 internal constant REMOTE_CHAIN_ID = 202;
    uint32 internal constant REMOTE_EID = 302;
    uint32 internal constant SOURCE_EID = 401;

    MockCenterEndpoint internal endpoint;
    MockCenterRegistrar internal registrar;
    LzEndpointRegistry internal registry;
    MemeverseRegistrationCenter internal center;

    /// @notice Set up.
    function setUp() external {
        endpoint = new MockCenterEndpoint();
        registrar = new MockCenterRegistrar();
        registry = new LzEndpointRegistry(OWNER);
        center = new MemeverseRegistrationCenter(OWNER, address(endpoint), address(registrar), address(registry));

        vm.prank(OWNER);
        registry.setLzEndpointIds(_endpointPairs());

        vm.startPrank(OWNER);
        center.setSupportedUPT(address(0x7777), true);
        center.setDurationDaysRange(1, 10);
        center.setLockupDaysRange(2, 20);
        center.setRegisterGasLimit(150);
        center.setPeer(REMOTE_EID, bytes32(uint256(uint160(address(0xBEEF)))));
        center.setPeer(SOURCE_EID, bytes32(uint256(uint160(address(registrar)))));
        vm.stopPrank();
    }

    /// @notice Test config setters and preview registration.
    function testConfigSettersAndPreviewRegistration() external {
        vm.prank(OWNER);
        center.setSupportedUPT(address(0x8888), true);
        vm.prank(OWNER);
        center.setDurationDaysRange(2, 12);
        vm.prank(OWNER);
        center.setLockupDaysRange(3, 13);
        vm.prank(OWNER);
        center.setRegisterGasLimit(321);

        assertTrue(center.previewRegistration("NEW"));
        string memory longSymbol = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef";
        assertFalse(center.previewRegistration(longSymbol));
        assertEq(center.minDurationDays(), 2);
        assertEq(center.maxDurationDays(), 12);
        assertEq(center.minLockupDays(), 3);
        assertEq(center.maxLockupDays(), 13);
        assertEq(center.registerGasLimit(), 321);
    }

    /// @notice Test preview registration returns false while symbol is still locked.
    function testPreviewRegistrationReturnsFalseWhileSymbolIsStillLocked() external {
        endpoint.setQuotedNativeFee(0.5 ether);
        IMemeverseRegistrationCenter.RegistrationParam memory param = _registrationParam();

        center.registration{value: 0.5 ether}(param);

        assertFalse(center.previewRegistration(param.symbol));
    }

    /// @notice Test config setters reject invalid inputs.
    function testConfigSettersRejectInvalidInputs() external {
        vm.prank(OWNER);
        vm.expectRevert(IMemeverseRegistrationCenter.ZeroInput.selector);
        center.setSupportedUPT(address(0), true);

        vm.prank(OWNER);
        vm.expectRevert(IMemeverseRegistrationCenter.InvalidInput.selector);
        center.setDurationDaysRange(0, 1);

        vm.prank(OWNER);
        vm.expectRevert(IMemeverseRegistrationCenter.InvalidInput.selector);
        center.setLockupDaysRange(5, 5);

        vm.prank(OWNER);
        vm.expectRevert(IMemeverseRegistrationCenter.ZeroInput.selector);
        center.setRegisterGasLimit(0);
    }

    /// @notice Test quote send skips local and quotes remote path.
    function testQuoteSendSkipsLocalAndQuotesRemotePath() external {
        endpoint.setQuotedNativeFee(0.4 ether);
        uint32[] memory omnichainIds = new uint32[](2);
        omnichainIds[0] = uint32(block.chainid);
        omnichainIds[1] = REMOTE_CHAIN_ID;

        (uint256 totalFee, uint256[] memory fees, uint32[] memory eids) = center.quoteSend(omnichainIds, bytes("hello"));

        assertEq(totalFee, 0.4 ether);
        assertEq(fees.length, 2);
        assertEq(fees[0], 0);
        assertEq(fees[1], 0.4 ether);
        assertEq(eids[0], 0);
        assertEq(eids[1], REMOTE_EID);
    }

    /// @notice Test quote send returns zero for all local targets.
    function testQuoteSendReturnsZeroForAllLocalTargets() external view {
        uint32[] memory omnichainIds = new uint32[](1);
        omnichainIds[0] = uint32(block.chainid);

        (uint256 totalFee, uint256[] memory fees, uint32[] memory eids) = center.quoteSend(omnichainIds, bytes("hello"));

        assertEq(totalFee, 0);
        assertEq(fees.length, 1);
        assertEq(fees[0], 0);
        assertEq(eids[0], 0);
    }

    /// @notice Test quote send reverts on invalid remote omnichain id.
    function testQuoteSendRevertsOnInvalidRemoteOmnichainId() external {
        uint32[] memory omnichainIds = new uint32[](1);
        omnichainIds[0] = 999;

        vm.expectRevert(abi.encodeWithSelector(IMemeverseRegistrationCenter.InvalidOmnichainId.selector, uint32(999)));
        center.quoteSend(omnichainIds, bytes("hello"));
    }

    /// @notice Test registration stores symbol registers local and sends remote.
    function testRegistrationStoresSymbolRegistersLocalAndSendsRemote() external {
        endpoint.setQuotedNativeFee(0.5 ether);
        IMemeverseRegistrationCenter.RegistrationParam memory param = _registrationParam();

        center.registration{value: 0.5 ether}(param);

        uint256 expectedUniqueId = uint256(keccak256(abi.encodePacked(param.symbol, uint192(1), param.UPT)));
        (uint256 uniqueId, uint64 endTime, uint192 nonce) = center.symbolRegistry(param.symbol);
        assertEq(uniqueId, expectedUniqueId);
        assertEq(endTime, uint64(block.timestamp + param.durationDays * center.DAY()));
        assertEq(nonce, 1);

        assertEq(registrar.lastUniqueId(), expectedUniqueId);
        assertEq(registrar.lastUPT(), param.UPT);
        assertEq(registrar.lastFlashGenesis(), param.flashGenesis);
        assertEq(endpoint.lastDstEid(), REMOTE_EID);
        assertEq(endpoint.lastRefundAddress(), address(center));
        assertEq(endpoint.lastSendValue(), 0.5 ether);
    }

    /// @notice Test registration accepts native refunds sent back to the center contract.
    /// @dev Confirms remote endpoint refunds no longer revert when the center is the refund target.
    function testRegistrationAcceptsRemoteNativeRefundsAtCenter() external {
        endpoint.setQuotedNativeFee(0.4 ether);
        endpoint.setActualNativeFee(0.35 ether);
        IMemeverseRegistrationCenter.RegistrationParam memory param = _registrationParam();

        center.registration{value: 0.4 ether}(param);

        assertEq(endpoint.lastRefundAddress(), address(center));
        assertEq(endpoint.lastSendValue(), 0.4 ether);
        assertEq(endpoint.lastRefundedNative(), 0.05 ether);
        assertEq(address(center).balance, 0.05 ether);
    }

    /// @notice Test registration increments nonce and changes unique id on re-registration.
    function testRegistrationIncrementsNonceAndChangesUniqueIdOnReregistration() external {
        endpoint.setQuotedNativeFee(0.5 ether);
        IMemeverseRegistrationCenter.RegistrationParam memory param = _registrationParam();

        center.registration{value: 0.5 ether}(param);
        (uint256 firstUniqueId, uint64 firstEndTime, uint192 firstNonce) = center.symbolRegistry(param.symbol);

        assertEq(firstUniqueId, uint256(keccak256(abi.encodePacked(param.symbol, uint192(1), param.UPT))));
        assertEq(firstNonce, 1);

        vm.warp(firstEndTime + 1);
        center.registration{value: 0.5 ether}(param);

        (uint256 secondUniqueId,, uint192 secondNonce) = center.symbolRegistry(param.symbol);
        (uint256 historyUniqueId, uint64 historyEndTime, uint192 historyNonce) =
            center.symbolHistory(param.symbol, firstUniqueId);

        assertEq(secondUniqueId, uint256(keccak256(abi.encodePacked(param.symbol, uint192(2), param.UPT))));
        assertTrue(secondUniqueId != firstUniqueId);
        assertEq(secondNonce, 2);
        assertEq(historyUniqueId, firstUniqueId);
        assertEq(historyEndTime, firstEndTime);
        assertEq(historyNonce, 1);
    }

    /// @notice Test registration rejects invalid params and stores prior registration in history.
    function testRegistrationRejectsInvalidParamsAndStoresPriorRegistrationInHistory() external {
        endpoint.setQuotedNativeFee(0.5 ether);
        IMemeverseRegistrationCenter.RegistrationParam memory param = _registrationParam();

        param.lockupDays = 1;
        vm.expectRevert(IMemeverseRegistrationCenter.InvalidLockupDays.selector);
        center.registration(param);

        param = _registrationParam();
        param.durationDays = 11;
        vm.expectRevert(IMemeverseRegistrationCenter.InvalidDurationDays.selector);
        center.registration(param);

        param = _registrationParam();
        param.UPT = address(0x9999);
        vm.expectRevert(IMemeverseRegistrationCenter.InvalidUPT.selector);
        center.registration(param);

        param = _registrationParam();
        param.name = "";
        vm.expectRevert(IMemeverseRegistrationCenter.InvalidLength.selector);
        center.registration(param);

        param = _registrationParam();
        param.symbol = "";
        vm.expectRevert(IMemeverseRegistrationCenter.InvalidLength.selector);
        center.registration(param);

        param = _registrationParam();
        param.uri = "";
        vm.expectRevert(IMemeverseRegistrationCenter.InvalidLength.selector);
        center.registration(param);

        param = _registrationParam();
        param.desc = "";
        vm.expectRevert(IMemeverseRegistrationCenter.InvalidLength.selector);
        center.registration(param);

        param = _registrationParam();
        param.omnichainIds = new uint32[](0);
        vm.expectRevert(IMemeverseRegistrationCenter.InvalidLength.selector);
        center.registration(param);

        param = _registrationParam();
        center.registration{value: 0.5 ether}(param);
        (uint256 firstUniqueId, uint64 firstEndTime, uint192 firstNonce) = center.symbolRegistry(param.symbol);
        assertEq(firstNonce, 1);

        vm.warp(firstEndTime + 1);
        center.registration{value: 0.5 ether}(param);

        (uint256 currentUniqueId,,) = center.symbolRegistry(param.symbol);
        (uint256 historyUniqueId, uint64 historyEndTime, uint192 historyNonce) =
            center.symbolHistory(param.symbol, firstUniqueId);
        assertTrue(currentUniqueId != 0);
        assertTrue(currentUniqueId != firstUniqueId);
        assertEq(historyUniqueId, firstUniqueId);
        assertEq(historyEndTime, firstEndTime);
        assertEq(historyNonce, 1);

        (, uint64 currentEndTime,) = center.symbolRegistry(param.symbol);
        vm.expectRevert(
            abi.encodeWithSelector(IMemeverseRegistrationCenter.SymbolNotUnlock.selector, uint256(currentEndTime))
        );
        center.registration(param);
    }

    /// @notice Test registration deduplicates omnichain ids and requires enough fee.
    function testRegistrationDeduplicatesOmnichainIdsAndRequiresEnoughFee() external {
        endpoint.setQuotedNativeFee(0.5 ether);
        IMemeverseRegistrationCenter.RegistrationParam memory param = _registrationParam();
        param.omnichainIds = new uint32[](3);
        param.omnichainIds[0] = uint32(block.chainid);
        param.omnichainIds[1] = REMOTE_CHAIN_ID;
        param.omnichainIds[2] = REMOTE_CHAIN_ID;

        vm.expectRevert(IMemeverseRegistrationCenter.InsufficientLzFee.selector);
        center.registration(param);

        center.registration{value: 0.5 ether}(param);
        assertEq(endpoint.lastDstEid(), REMOTE_EID);
    }

    /// @notice Test lz receive from registrar sender triggers registration.
    function testLzReceiveFromRegistrarSenderTriggersRegistration() external {
        IMemeverseRegistrationCenter.RegistrationParam memory param = _localOnlyRegistrationParam();
        Origin memory origin =
            Origin({srcEid: SOURCE_EID, sender: bytes32(uint256(uint160(address(registrar)))), nonce: 1});

        vm.prank(address(endpoint));
        center.lzReceive(origin, bytes32("guid"), abi.encode(param), address(0), "");

        assertEq(registrar.lastUPT(), param.UPT);
        assertEq(registrar.lastName(), param.name);
        assertEq(registrar.lastSymbol(), param.symbol);
    }

    /// @notice Test lz receive rejects unexpected sender and lz send is self only.
    function testLzReceiveRejectsUnexpectedSenderAndLzSendIsSelfOnly() external {
        IMemeverseRegistrationCenter.RegistrationParam memory param = _localOnlyRegistrationParam();
        vm.prank(OWNER);
        center.setPeer(SOURCE_EID, bytes32(uint256(uint160(address(0x1234)))));
        Origin memory badOrigin =
            Origin({srcEid: SOURCE_EID, sender: bytes32(uint256(uint160(address(0x1234)))), nonce: 1});

        vm.prank(address(endpoint));
        vm.expectRevert(IMemeverseRegistrationCenter.PermissionDenied.selector);
        center.lzReceive(badOrigin, bytes32("guid"), abi.encode(param), address(0), "");

        vm.expectRevert(IMemeverseRegistrationCenter.PermissionDenied.selector);
        center.lzSend(
            REMOTE_EID, bytes("msg"), bytes("opts"), MessagingFee({nativeFee: 0, lzTokenFee: 0}), address(this)
        );
    }

    /// @notice Test remove gas dust owner path transfers balance.
    function testRemoveGasDustOwnerPathTransfersBalance() external {
        vm.deal(address(center), 1 ether);
        uint256 before = OWNER.balance;

        vm.prank(OWNER);
        center.removeGasDust(OWNER);

        assertEq(OWNER.balance - before, 1 ether);
        assertEq(address(center).balance, 0);
    }

    function _registrationParam() internal view returns (IMemeverseRegistrationCenter.RegistrationParam memory param) {
        param.name = "CenterVerse";
        param.symbol = "CNTR";
        param.uri = "ipfs://center";
        param.desc = "Center desc";
        param.communities = new string[](1);
        param.communities[0] = "https://center.example";
        param.durationDays = 3;
        param.lockupDays = 5;
        param.omnichainIds = new uint32[](2);
        param.omnichainIds[0] = uint32(block.chainid);
        param.omnichainIds[1] = REMOTE_CHAIN_ID;
        param.UPT = address(0x7777);
        param.flashGenesis = true;
    }

    function _localOnlyRegistrationParam()
        internal
        view
        returns (IMemeverseRegistrationCenter.RegistrationParam memory param)
    {
        param = _registrationParam();
        param.symbol = "LCL";
        param.omnichainIds = new uint32[](1);
        param.omnichainIds[0] = uint32(block.chainid);
    }

    function _endpointPairs() internal pure returns (ILzEndpointRegistry.LzEndpointIdPair[] memory pairs) {
        pairs = new ILzEndpointRegistry.LzEndpointIdPair[](1);
        pairs[0] = ILzEndpointRegistry.LzEndpointIdPair({chainId: REMOTE_CHAIN_ID, endpointId: REMOTE_EID});
    }
}
