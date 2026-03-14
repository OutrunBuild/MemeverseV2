//SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {IMemeverseRegistrar} from "./IMemeverseRegistrar.sol";

interface IMemeverseRegistrarAtLocal {
    /// @notice Executes local registration.
    /// @dev See the implementation for behavior details.
    /// @param param The param value.
    function localRegistration(IMemeverseRegistrar.MemeverseParam calldata param) external;

    /// @notice Executes set registration center.
    /// @dev See the implementation for behavior details.
    /// @param registrationCenter The registrationCenter value.
    function setRegistrationCenter(address registrationCenter) external;

    event SetRegistrationCenter(address registrationCenter);

    error ZeroAddress();

    error PermissionDenied();
}
