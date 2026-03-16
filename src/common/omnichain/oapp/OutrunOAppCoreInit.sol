// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {OutrunOwnableInit} from "../../access/OutrunOwnableInit.sol";
import {IOAppCore, ILayerZeroEndpointV2} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppCore.sol";

/**
 * @title OutrunOAppCoreInit (Just for minimal proxy)
 * @dev Abstract contract implementing the IOAppCore interface with basic OApp configurations.
 */
abstract contract OutrunOAppCoreInit is IOAppCore, OutrunOwnableInit {
    struct OAppCoreStorage {
        // Mapping to store peers associated with corresponding endpoints
        mapping(uint32 eid => bytes32 peer) peers;
    }

    // The LayerZero endpoint associated with the given OApp
    ILayerZeroEndpointV2 public immutable endpoint;

    // keccak256(abi.encode(uint256(keccak256("outrun.layerzerov2.storage.OAppCore")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant OAPP_CORE_STORAGE_LOCATION =
        0x7c5e164903b57308a9588eaf98afe7394cf4b3ef4aeeacd4cf0d6c6393897400;

    function _getOAppCoreStorage() internal pure returns (OAppCoreStorage storage $) {
        assembly {
            $.slot := OAPP_CORE_STORAGE_LOCATION
        }
    }

    /**
     * @dev Constructor to initialize the OAppCore with the provided endpoint and delegate.
     * @param _endpoint The address of the LOCAL Layer Zero endpoint.
     */
    constructor(address _endpoint) {
        endpoint = ILayerZeroEndpointV2(_endpoint);
    }

    /**
     * @dev Initializes the OAppCore with the provided delegate.
     * @param _delegate The delegate capable of making OApp configurations inside of the endpoint.
     *
     * @dev The delegate typically should be set as the owner of the contract.
     * @dev Ownable is not initialized here on purpose. It should be initialized in the child contract to
     * accommodate the different version of Ownable.
     */
    function __OutrunOAppCore_init(address _delegate) internal onlyInitializing {
        __OutrunOAppCore_init_unchained(_delegate);
    }

    function __OutrunOAppCore_init_unchained(address _delegate) internal onlyInitializing {
        if (_delegate == address(0)) revert InvalidDelegate();
        endpoint.setDelegate(_delegate);
    }

    /// @notice Returns peers.
    /// @dev See the implementation for behavior details.
    /// @param _eid The _eid value.
    /// @return bytes32 The bytes32 value.
    function peers(uint32 _eid) public view override returns (bytes32) {
        OAppCoreStorage storage $ = _getOAppCoreStorage();
        return $.peers[_eid];
    }

    /// @notice Executes set peer.
    /// @dev See the implementation for behavior details.
    /// @param _eid The _eid value.
    /// @param _peer The _peer value.
    function setPeer(uint32 _eid, bytes32 _peer) public virtual onlyOwner {
        OAppCoreStorage storage $ = _getOAppCoreStorage();
        $.peers[_eid] = _peer;
        emit PeerSet(_eid, _peer);
    }

    /**
     * @notice Internal function to get the peer address associated with a specific endpoint; reverts if NOT set.
     * ie. the peer is set to bytes32(0).
     * @param _eid The endpoint ID.
     * @return peer The address of the peer associated with the specified endpoint.
     */
    function _getPeerOrRevert(uint32 _eid) internal view virtual returns (bytes32) {
        OAppCoreStorage storage $ = _getOAppCoreStorage();
        bytes32 peer = $.peers[_eid];
        if (peer == bytes32(0)) revert NoPeer(_eid);
        return peer;
    }

    /// @notice Executes set delegate.
    /// @dev See the implementation for behavior details.
    /// @param _delegate The _delegate value.
    function setDelegate(address _delegate) public onlyOwner {
        endpoint.setDelegate(_delegate);
    }
}
