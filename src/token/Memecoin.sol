// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {IMemecoin} from "./interfaces/IMemecoin.sol";
import {OutrunOFTInit} from "../common/omnichain/oft/OutrunOFTInit.sol";

/**
 * @title Omnichain Memecoin
 */
contract Memecoin is IMemecoin, OutrunOFTInit {
    address public memeverseLauncher;

    /**
     * @param _lzEndpoint The local LayerZero endpoint address.
     */
    constructor(address _lzEndpoint) OutrunOFTInit(_lzEndpoint) {}

    /**
     * @notice Initialize the memecoin.
     * @param name_ - The name of the memecoin.
     * @param symbol_ - The symbol of the memecoin.
     * @param _memeverseLauncher - The address of the memeverse launcher.
     * @param _delegate - The address of the OFT delegate.
     */
    /// @notice Executes initialize.
    /// @dev See the implementation for behavior details.
    /// @param name_ The name_ value.
    /// @param symbol_ The symbol_ value.
    /// @param _memeverseLauncher The _memeverseLauncher value.
    /// @param _delegate The _delegate value.
    function initialize(string memory name_, string memory symbol_, address _memeverseLauncher, address _delegate)
        external
        override
        initializer
    {
        __OutrunOFT_init(name_, symbol_, _delegate);
        __OutrunOwnable_init(_delegate);

        memeverseLauncher = _memeverseLauncher;
    }

    /**
     * @notice Mint the memecoin.
     * @param account - The address of the account.
     * @param amount - The amount of the memecoin.
     */
    /// @notice Executes mint.
    /// @dev See the implementation for behavior details.
    /// @param account The account value.
    /// @param amount The amount value.
    function mint(address account, uint256 amount) external override {
        require(amount != 0, ZeroInput());
        require(msg.sender == memeverseLauncher, PermissionDenied());
        _mint(account, amount);
    }

    /**
     * @notice Burn the memecoin.
     * @param amount - The amount of the memecoin.
     */
    /// @notice Executes burn.
    /// @dev See the implementation for behavior details.
    /// @param amount The amount value.
    function burn(uint256 amount) external override {
        require(amount != 0, ZeroInput());
        _burn(msg.sender, amount);
    }
}
