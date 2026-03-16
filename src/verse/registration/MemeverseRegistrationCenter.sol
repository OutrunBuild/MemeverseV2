// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {OApp, Origin} from "@layerzerolabs/oapp-evm/contracts/oapp/OApp.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

import {TokenHelper} from "../../common/token/TokenHelper.sol";
import {ILzEndpointRegistry} from "../../common/omnichain/interfaces/ILzEndpointRegistry.sol";
import {IMemeverseRegistrationCenter, MessagingFee} from "../interfaces/IMemeverseRegistrationCenter.sol";
import {IMemeverseRegistrarAtLocal, IMemeverseRegistrar} from "../interfaces/IMemeverseRegistrarAtLocal.sol";

/**
 * @title Memeverse Omnichain Registration Center
 */
contract MemeverseRegistrationCenter is IMemeverseRegistrationCenter, OApp, TokenHelper {
    using Address for address;
    using OptionsBuilder for bytes;

    // uint256 public constant DAY = 24 * 3600;
    uint256 public constant DAY = 180; // OutrunTODO 180 seconds for testing
    address public immutable MEMEVERSE_REGISTRAR;
    address public immutable MEMEVERSE_COMMON_INFO;

    uint128 public minDurationDays;
    uint128 public maxDurationDays;
    uint128 public minLockupDays;
    uint128 public maxLockupDays;
    uint256 public registerGasLimit;

    // Main symbol mapping, recording the latest registration information
    mapping(string symbol => SymbolRegistration) public symbolRegistry;

    // Symbol history mapping, storing all valid registration records
    mapping(string symbol => mapping(uint256 uniqueId => SymbolRegistration)) public symbolHistory;

    mapping(address UPT => bool) supportedUPTs;

    /**
     * @notice Constructor
     * @param _owner - The owner of the contract
     * @param _lzEndpoint - The lz endpoint
     * @param _memeverseRegistrar - The memeverse registrar
     */
    constructor(address _owner, address _lzEndpoint, address _memeverseRegistrar, address _memeverseCommonInfo)
        OApp(_lzEndpoint, _owner)
        Ownable(_owner)
    {
        MEMEVERSE_REGISTRAR = _memeverseRegistrar;
        MEMEVERSE_COMMON_INFO = _memeverseCommonInfo;
    }

    /// @notice Returns preview registration.
    /// @dev See the implementation for behavior details.
    /// @param symbol The symbol value.
    /// @return bool The bool value.
    function previewRegistration(string calldata symbol) external view override returns (bool) {
        if (bytes(symbol).length >= 32) return false;
        SymbolRegistration storage currentRegistration = symbolRegistry[symbol];
        return block.timestamp > currentRegistration.endTime;
    }

    /// @notice Returns quote send.
    /// @dev See the implementation for behavior details.
    /// @param omnichainIds The omnichainIds value.
    /// @param message The message value.
    /// @return uint256 The uint256 value.
    function quoteSend(uint32[] memory omnichainIds, bytes memory message)
        public
        view
        override
        returns (uint256, uint256[] memory, uint32[] memory)
    {
        uint256 totalFee;
        uint256 length = omnichainIds.length;
        uint256[] memory fees = new uint256[](length);
        uint32[] memory eids = new uint32[](length);
        uint32 currentChainId = uint32(block.chainid);
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(uint128(registerGasLimit), 0);

        for (uint256 i = 0; i < length;) {
            uint32 omnichainId = omnichainIds[i];
            if (omnichainId == currentChainId) {
                fees[i] = 0;
                eids[i] = 0;
                unchecked {
                    i++;
                }
                continue;
            }

            uint32 eid = ILzEndpointRegistry(MEMEVERSE_COMMON_INFO).lzEndpointIdOfChain(omnichainId);
            require(eid != 0, InvalidOmnichainId(omnichainId));

            uint256 fee = _quote(eid, message, options, false).nativeFee;
            totalFee += fee;
            fees[i] = fee;
            eids[i] = eid;
            unchecked {
                i++;
            }
        }

        return (totalFee, fees, eids);
    }

    /// @notice Executes registration.
    /// @dev See the implementation for behavior details.
    /// @param param The param value.
    function registration(RegistrationParam memory param) public payable override {
        _registrationParamValidation(param);

        uint256 currentTime = block.timestamp;
        SymbolRegistration storage currentRegistration = symbolRegistry[param.symbol];
        uint64 currentEndTime = currentRegistration.endTime;
        uint192 currentNonce = currentRegistration.nonce;
        require(currentTime > currentEndTime, SymbolNotUnlock(currentEndTime));

        if (currentEndTime != 0) {
            symbolHistory[param.symbol][currentRegistration.uniqueId] = SymbolRegistration({
                uniqueId: currentRegistration.uniqueId, endTime: currentEndTime, nonce: currentNonce
            });
        }

        uint64 endTime = uint64(currentTime + param.durationDays * DAY);
        uint256 uniqueId = uint256(keccak256(abi.encodePacked(param.symbol, currentNonce + 1, param.UPT)));
        currentRegistration.uniqueId = uniqueId;
        currentRegistration.endTime = endTime;

        IMemeverseRegistrar.MemeverseParam memory memeverseParam = IMemeverseRegistrar.MemeverseParam({
            name: param.name,
            symbol: param.symbol,
            uri: param.uri,
            desc: param.desc,
            communities: param.communities,
            uniqueId: uniqueId,
            endTime: endTime,
            unlockTime: endTime + uint64(param.lockupDays * DAY),
            omnichainIds: param.omnichainIds,
            UPT: param.UPT,
            flashGenesis: param.flashGenesis
        });
        _omnichainSend(param.omnichainIds, memeverseParam);

        emit Registration(uniqueId, param);
    }

    /// @notice Executes remove gas dust.
    /// @dev See the implementation for behavior details.
    /// @param receiver The receiver value.
    function removeGasDust(address receiver) external override onlyOwner {
        uint256 dust = address(this).balance;
        _transferOut(NATIVE, receiver, dust);

        emit RemoveGasDust(receiver, dust);
    }

    /// @notice Executes lz send.
    /// @dev See the implementation for behavior details.
    /// @param dstEid The dstEid value.
    /// @param message The message value.
    /// @param options The options value.
    /// @param fee The fee value.
    /// @param refundAddress The refundAddress value.
    function lzSend(
        uint32 dstEid,
        bytes memory message,
        bytes memory options,
        MessagingFee memory fee,
        address refundAddress
    ) public payable override {
        require(msg.sender == address(this), PermissionDenied());

        _lzSend(dstEid, message, options, fee, refundAddress);
    }

    /**
     * @notice Omnichain send
     * @param omnichainIds - The omnichain ids
     * @param param - The registration parameter
     */
    function _omnichainSend(uint32[] memory omnichainIds, IMemeverseRegistrar.MemeverseParam memory param) internal {
        bytes memory message = abi.encode(param);
        (uint256 totalFee, uint256[] memory fees, uint32[] memory eids) = quoteSend(omnichainIds, message);
        require(msg.value >= totalFee, InsufficientLzFee());

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(uint128(registerGasLimit), 0);
        for (uint256 i = 0; i < eids.length;) {
            uint256 fee = fees[i];
            uint32 eid = eids[i];
            unchecked {
                i++;
            }
            if (eid == 0) {
                IMemeverseRegistrarAtLocal(MEMEVERSE_REGISTRAR).localRegistration(param);
                continue;
            }

            bytes memory functionSignature = abi.encodeWithSignature(
                "lzSend(uint32,bytes,bytes,(uint256,uint256),address)",
                eid,
                message,
                options,
                MessagingFee({nativeFee: fee, lzTokenFee: 0}),
                msg.sender
            );
            address(this).functionCallWithValue(functionSignature, fee);
        }
    }

    /**
     * @notice Registration parameter validation
     * @param param - The registration parameter
     */
    function _registrationParamValidation(RegistrationParam memory param) internal view {
        require(param.lockupDays >= minLockupDays && param.lockupDays <= maxLockupDays, InvalidLockupDays());
        require(param.durationDays >= minDurationDays && param.durationDays <= maxDurationDays, InvalidDurationDays());
        require(bytes(param.name).length > 0 && bytes(param.name).length < 32, InvalidLength());
        require(bytes(param.symbol).length > 0 && bytes(param.symbol).length < 32, InvalidLength());
        require(bytes(param.uri).length > 0, InvalidLength());
        require(bytes(param.desc).length > 0 && bytes(param.desc).length < 256, InvalidLength());
        require(supportedUPTs[param.UPT], InvalidUPT());

        uint32[] memory omnichainIds = param.omnichainIds;
        require(omnichainIds.length > 0 && omnichainIds.length < 32, InvalidLength());
        param.omnichainIds = _deduplicate(omnichainIds);
    }

    function _deduplicate(uint32[] memory input) internal pure returns (uint32[] memory) {
        if (input.length == 0) {
            return new uint32[](0);
        }

        uint32[] memory temp = new uint32[](input.length);
        uint256 uniqueCount = 0;
        bool found;

        for (uint256 i = 0; i < input.length;) {
            found = false;
            for (uint256 j = 0; j < uniqueCount;) {
                if (temp[j] == input[i]) {
                    found = true;
                    unchecked {
                        j++;
                    }
                    break;
                }
                unchecked {
                    j++;
                }
            }
            if (!found) {
                temp[uniqueCount] = input[i];
                uniqueCount++;
            }
            unchecked {
                i++;
            }
        }

        uint32[] memory unique = new uint32[](uniqueCount);
        for (uint256 i = 0; i < uniqueCount;) {
            unique[i] = temp[i];
            unchecked {
                i++;
            }
        }

        return unique;
    }

    /**
     * @notice Internal function to implement lzReceive logic
     */
    function _lzReceive(
        Origin calldata _origin,
        bytes32,
        /*_guid*/
        bytes calldata _message,
        address,
        /*_executor*/
        bytes calldata /*_extraData*/
    )
        internal
        virtual
        override
    {
        require(_origin.sender == bytes32(uint256(uint160(MEMEVERSE_REGISTRAR))), PermissionDenied());
        registration(abi.decode(_message, (RegistrationParam)));
    }

    /*/////////////////////////////////////////////////////
                Memeverse Registration Config
    /////////////////////////////////////////////////////*/

    /// @notice Executes set supported upt.
    /// @dev See the implementation for behavior details.
    /// @param UPT The UPT value.
    /// @param isSupported The isSupported value.
    function setSupportedUPT(address UPT, bool isSupported) external override onlyOwner {
        require(UPT != address(0), ZeroInput());
        supportedUPTs[UPT] = isSupported;

        emit SetSupportedUPT(UPT, isSupported);
    }

    /// @notice Executes set duration days range.
    /// @dev See the implementation for behavior details.
    /// @param _minDurationDays The _minDurationDays value.
    /// @param _maxDurationDays The _maxDurationDays value.
    function setDurationDaysRange(uint128 _minDurationDays, uint128 _maxDurationDays) external override onlyOwner {
        require(_minDurationDays != 0 && _maxDurationDays != 0 && _minDurationDays < _maxDurationDays, InvalidInput());

        minDurationDays = _minDurationDays;
        maxDurationDays = _maxDurationDays;

        emit SetDurationDaysRange(_minDurationDays, _maxDurationDays);
    }

    /// @notice Executes set lockup days range.
    /// @dev See the implementation for behavior details.
    /// @param _minLockupDays The _minLockupDays value.
    /// @param _maxLockupDays The _maxLockupDays value.
    function setLockupDaysRange(uint128 _minLockupDays, uint128 _maxLockupDays) external override onlyOwner {
        require(_minLockupDays != 0 && _maxLockupDays != 0 && _minLockupDays < _maxLockupDays, InvalidInput());

        minLockupDays = _minLockupDays;
        maxLockupDays = _maxLockupDays;

        emit SetLockupDaysRange(_minLockupDays, _maxLockupDays);
    }

    /// @notice Executes set register gas limit.
    /// @dev See the implementation for behavior details.
    /// @param _registerGasLimit The _registerGasLimit value.
    function setRegisterGasLimit(uint256 _registerGasLimit) external override onlyOwner {
        require(_registerGasLimit > 0, ZeroInput());

        registerGasLimit = _registerGasLimit;

        emit SetRegisterGasLimit(_registerGasLimit);
    }
}
