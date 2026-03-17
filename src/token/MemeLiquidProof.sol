// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {IMemeLiquidProof, PoolId} from "./interfaces/IMemeLiquidProof.sol";
import {OutrunOFTInit} from "../common/omnichain/oft/OutrunOFTInit.sol";

/**
 * @title Omnichain Memecoin Proof Of Liquidity(POL) Token
 */
contract MemeLiquidProof is IMemeLiquidProof, OutrunOFTInit {
    address public memecoin;
    address public memeverseLauncher;

    PoolId public poolId;

    modifier onlyMemeverseLauncher() {
        _onlyMemeverseLauncher();
        _;
    }

    function _onlyMemeverseLauncher() internal view {
        require(msg.sender == memeverseLauncher, PermissionDenied());
    }

    /**
     * @param _lzEndpoint The local LayerZero endpoint address.
     */
    constructor(address _lzEndpoint) OutrunOFTInit(_lzEndpoint) {}

    /// @notice Executes initialize.
    /// @dev See the implementation for behavior details.
    /// @param name_ The name_ value.
    /// @param symbol_ The symbol_ value.
    /// @param memecoin_ The memecoin_ value.
    /// @param memeverseLauncher_ The memeverseLauncher_ value.
    /// @param delegate_ The delegate_ value.
    function initialize(
        string memory name_,
        string memory symbol_,
        address memecoin_,
        address memeverseLauncher_,
        address delegate_
    ) external override initializer {
        __OutrunOFT_init(name_, symbol_, delegate_);
        __OutrunOwnable_init(delegate_);

        memecoin = memecoin_;
        memeverseLauncher = memeverseLauncher_;
    }

    /// @notice Executes set pool id.
    /// @dev See the implementation for behavior details.
    /// @param _poolId The _poolId value.
    function setPoolId(PoolId _poolId) external override onlyMemeverseLauncher {
        poolId = _poolId;
    }

    /**
     * @dev Mint the memeverse proof.
     * @param account - The address of the account.
     * @param amount - The amount of the memeverse proof.
     * @notice Only the memeverse launcher can mint the memeverse proof.
     */
    function mint(address account, uint256 amount) external override onlyMemeverseLauncher {
        require(amount != 0, ZeroInput());

        _mint(account, amount);
    }

    /**
     * @dev Burn the memecoin liquid proof.
     * @param account - The address of the account.
     * @param amount - The amount of the memecoin liquid proof.
     * @notice User must have approved msg.sender to spend UPT
     */
    function burn(address account, uint256 amount) external {
        require(amount != 0, ZeroInput());
        if (msg.sender != account) _spendAllowance(account, msg.sender, amount);
        _burn(account, amount);
    }

    /// @notice Executes burn.
    /// @dev See the implementation for behavior details.
    /// @param amount The amount value.
    function burn(uint256 amount) external {
        require(amount != 0, ZeroInput());
        _burn(msg.sender, amount);
    }
}
