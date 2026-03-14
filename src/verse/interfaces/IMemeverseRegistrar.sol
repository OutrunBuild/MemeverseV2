//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {IMemeverseRegistrationCenter} from "./IMemeverseRegistrationCenter.sol";

/**
 * @dev Interface for the Memeverse Registrar.
 */
interface IMemeverseRegistrar {
    struct MemeverseParam {
        string name; // Token name
        string symbol; // Token symbol
        string uri; // Token icon uri
        string desc; // Description
        string[] communities; // Community, index -> 0:Website, 1:X, 2:Discord, 3:Telegram, >4:Others
        uint256 uniqueId; // Memeverse uniqueId
        uint64 endTime; // EndTime of launchPool
        uint64 unlockTime; // UnlockTime of liquidity
        uint32[] omnichainIds; // ChainIds of the token's omnichain(EVM)
        address UPT; // UPT of Memeverse
        bool flashGenesis; // Allowing the transition to the liquidity lock stage once the minimum funding requirement is met, without waiting for the genesis stage to end.
    }

    /// @notice Returns quote register.
    /// @dev See the implementation for behavior details.
    /// @param param The param value.
    /// @param value The value value.
    /// @return lzFee The lzFee value.
    function quoteRegister(IMemeverseRegistrationCenter.RegistrationParam calldata param, uint128 value)
        external
        view
        returns (uint256 lzFee);

    /**
     * @dev Register through cross-chain at the RegistrationCenter
     */
    /// @notice Executes register at center.
    /// @dev See the implementation for behavior details.
    /// @param param The param value.
    /// @param value The value value.
    function registerAtCenter(IMemeverseRegistrationCenter.RegistrationParam calldata param, uint128 value)
        external
        payable;
}
