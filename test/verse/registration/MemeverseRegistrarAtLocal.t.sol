// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {MemeverseRegistrarAtLocal} from "../../../src/verse/registration/MemeverseRegistrarAtLocal.sol";
import {IMemeverseRegistrar} from "../../../src/verse/interfaces/IMemeverseRegistrar.sol";
import {IMemeverseRegistrarAtLocal} from "../../../src/verse/interfaces/IMemeverseRegistrarAtLocal.sol";
import {IMemeverseRegistrationCenter} from "../../../src/verse/interfaces/IMemeverseRegistrationCenter.sol";

contract MockAtLocalRegistrationCenter {
    uint256 public quotedFee;
    address public lastRegistrationUPT;
    bool public lastRegistrationFlashGenesis;
    uint256 public lastRegistrationValue;

    /// @notice Set quoted fee.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @param fee See implementation.
    function setQuotedFee(uint256 fee) external {
        quotedFee = fee;
    }

    /// @notice Quote send.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @param omnichainIds See implementation.
    /// @return totalFee See implementation.
    /// @return fees See implementation.
    /// @return eids See implementation.
    function quoteSend(uint32[] memory omnichainIds, bytes memory)
        external
        view
        returns (uint256 totalFee, uint256[] memory fees, uint32[] memory eids)
    {
        totalFee = quotedFee;
        fees = new uint256[](omnichainIds.length);
        eids = omnichainIds;
    }

    /// @notice Registration.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @param param See implementation.
    function registration(IMemeverseRegistrationCenter.RegistrationParam calldata param) external payable {
        lastRegistrationUPT = param.UPT;
        lastRegistrationFlashGenesis = param.flashGenesis;
        lastRegistrationValue = msg.value;
    }
}

contract MockAtLocalLauncher {
    uint256 public lastRegisteredUniqueId;
    address public lastRegisteredUPT;
    bool public lastRegisteredFlashGenesis;
    uint256 public lastExternalInfoUniqueId;
    string public lastUri;
    string public lastDesc;
    string[] public lastCommunities;

    /// @notice Register memeverse.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @param name See implementation.
    /// @param symbol See implementation.
    /// @param uniqueId See implementation.
    /// @param endTime See implementation.
    /// @param unlockTime See implementation.
    /// @param omnichainIds See implementation.
    /// @param UPT See implementation.
    /// @param flashGenesis See implementation.
    function registerMemeverse(
        string memory name,
        string memory symbol,
        uint256 uniqueId,
        uint128 endTime,
        uint128 unlockTime,
        uint32[] memory omnichainIds,
        address UPT,
        bool flashGenesis
    ) external {
        name;
        symbol;
        endTime;
        unlockTime;
        omnichainIds;
        lastRegisteredUniqueId = uniqueId;
        lastRegisteredUPT = UPT;
        lastRegisteredFlashGenesis = flashGenesis;
    }

    /// @notice Set external info.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @param uniqueId See implementation.
    /// @param uri See implementation.
    /// @param desc See implementation.
    /// @param communities See implementation.
    function setExternalInfo(uint256 uniqueId, string memory uri, string memory desc, string[] memory communities)
        external
    {
        lastExternalInfoUniqueId = uniqueId;
        lastUri = uri;
        lastDesc = desc;
        lastCommunities = communities;
    }

    /// @notice Community.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @param index See implementation.
    /// @return See implementation.
    function community(uint256 index) external view returns (string memory) {
        return lastCommunities[index];
    }
}

contract MemeverseRegistrarAtLocalTest is Test {
    address internal constant OWNER = address(0xABCD);
    address internal constant OTHER = address(0xCAFE);

    MockAtLocalRegistrationCenter internal registrationCenter;
    MockAtLocalLauncher internal launcher;
    MemeverseRegistrarAtLocal internal registrar;

    /// @notice Set up.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function setUp() external {
        registrationCenter = new MockAtLocalRegistrationCenter();
        launcher = new MockAtLocalLauncher();
        registrar =
            new MemeverseRegistrarAtLocal(OWNER, address(registrationCenter), address(launcher), address(0x1234));
    }

    /// @notice Test quote register builds memeverse param and returns center quote.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function testQuoteRegisterBuildsMemeverseParamAndReturnsCenterQuote() external {
        registrationCenter.setQuotedFee(99 ether);

        IMemeverseRegistrationCenter.RegistrationParam memory param = _registrationParam();
        uint256 quoted = registrar.quoteRegister(param, 0);

        assertEq(quoted, 99 ether);
    }

    /// @notice Test local registration only center and forwards to launcher.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function testLocalRegistrationOnlyCenterAndForwardsToLauncher() external {
        IMemeverseRegistrar.MemeverseParam memory param = _memeverseParam();

        vm.expectRevert(IMemeverseRegistrarAtLocal.PermissionDenied.selector);
        registrar.localRegistration(param);

        vm.prank(address(registrationCenter));
        registrar.localRegistration(param);

        assertEq(launcher.lastRegisteredUniqueId(), param.uniqueId);
        assertEq(launcher.lastRegisteredUPT(), param.UPT);
        assertEq(launcher.lastRegisteredFlashGenesis(), param.flashGenesis);
        assertEq(launcher.lastExternalInfoUniqueId(), param.uniqueId);
        assertEq(launcher.lastUri(), param.uri);
        assertEq(launcher.lastDesc(), param.desc);
        assertEq(launcher.community(0), "https://memeverse.example");
    }

    /// @notice Test register at center forwards value and set registration center is owner only.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function testRegisterAtCenterForwardsValueAndSetRegistrationCenterIsOwnerOnly() external {
        IMemeverseRegistrationCenter.RegistrationParam memory param = _registrationParam();

        registrar.registerAtCenter{value: 1 ether}(param, uint128(1 ether));
        assertEq(registrationCenter.lastRegistrationValue(), 1 ether);
        assertEq(registrationCenter.lastRegistrationUPT(), param.UPT);
        assertEq(registrationCenter.lastRegistrationFlashGenesis(), param.flashGenesis);

        vm.prank(OTHER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, OTHER));
        registrar.setRegistrationCenter(address(0x9999));

        vm.prank(OWNER);
        vm.expectRevert(IMemeverseRegistrarAtLocal.ZeroAddress.selector);
        registrar.setRegistrationCenter(address(0));

        vm.prank(OWNER);
        registrar.setRegistrationCenter(address(0x9999));
        assertEq(registrar.registrationCenter(), address(0x9999));
    }

    function _registrationParam() internal view returns (IMemeverseRegistrationCenter.RegistrationParam memory param) {
        param.name = "Memeverse";
        param.symbol = "MEME";
        param.uri = "ipfs://memeverse";
        param.desc = "Memeverse desc";
        param.communities = new string[](1);
        param.communities[0] = "https://memeverse.example";
        param.durationDays = 3;
        param.lockupDays = 5;
        param.omnichainIds = new uint32[](2);
        param.omnichainIds[0] = uint32(block.chainid);
        param.omnichainIds[1] = 101;
        param.UPT = address(0x7777);
        param.flashGenesis = true;
    }

    function _memeverseParam() internal view returns (IMemeverseRegistrar.MemeverseParam memory param) {
        IMemeverseRegistrationCenter.RegistrationParam memory registrationParam = _registrationParam();
        param.name = registrationParam.name;
        param.symbol = registrationParam.symbol;
        param.uri = registrationParam.uri;
        param.desc = registrationParam.desc;
        param.communities = registrationParam.communities;
        param.uniqueId = 1234;
        param.endTime = uint64(block.timestamp + 3 days);
        param.unlockTime = uint64(block.timestamp + 8 days);
        param.omnichainIds = registrationParam.omnichainIds;
        param.UPT = registrationParam.UPT;
        param.flashGenesis = registrationParam.flashGenesis;
    }
}
