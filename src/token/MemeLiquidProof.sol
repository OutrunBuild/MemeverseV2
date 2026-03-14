// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {OutrunNoncesInit} from "../common/token/OutrunNoncesInit.sol";
import {IMemeLiquidProof, PoolId} from "./interfaces/IMemeLiquidProof.sol";
import {OutrunOFTInit} from "../common/omnichain/oft/OutrunOFTInit.sol";
import {OutrunERC20PermitInit} from "../common/token/OutrunERC20PermitInit.sol";
import {OutrunERC20Init, OutrunERC20VotesInit} from "../common/token/extensions/governance/OutrunERC20VotesInit.sol";

/**
 * @title Omnichain Memecoin Proof Of Liquidity(POL) Token
 */
contract MemeLiquidProof is IMemeLiquidProof, OutrunERC20PermitInit, OutrunERC20VotesInit, OutrunOFTInit {
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

    /**
     * @dev Initialize the memecoin liquidProof.
     * @param name_ - The name of the memecoin liquidProof.
     * @param symbol_ - The symbol of the memecoin liquidProof.
     * @param memecoin_ - The address of the memecoin.
     * @param memeverseLauncher_ - The address of the memeverse launcher.
     * @param delegate_ - The address of the OFT delegate.
     */
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

    /// @notice Returns clock.
    /// @dev See the implementation for behavior details.
    /// @return uint48 The uint48 value.
    function clock() public view override returns (uint48) {
        return uint48(block.timestamp);
    }

    /// @notice Returns clock mode.
    /// @dev See the implementation for behavior details.
    /// @return The return value.
    function CLOCK_MODE() public pure override returns (string memory) {
        return "mode=timestamp";
    }

    /**
     * @dev Set PoolId(Uniswap V4) after deploying liquidity
     */
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

    /**
     * @dev Burn the liquid proof by self.
     */
    /// @notice Executes burn.
    /// @dev See the implementation for behavior details.
    /// @param amount The amount value.
    function burn(uint256 amount) external {
        require(amount != 0, ZeroInput());
        _burn(msg.sender, amount);
    }

    /// @notice Returns nonces.
    /// @dev See the implementation for behavior details.
    /// @param owner The owner value.
    /// @return uint256 The uint256 value.
    function nonces(address owner) public view override(OutrunERC20PermitInit, OutrunNoncesInit) returns (uint256) {
        return super.nonces(owner);
    }

    function _update(address from, address to, uint256 value) internal override(OutrunERC20Init, OutrunERC20VotesInit) {
        super._update(from, to, value);
    }
}
