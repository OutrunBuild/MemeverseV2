// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {IERC20} from "../../common/token/OutrunERC20Init.sol";

interface IMemecoinYieldVault is IERC20 {
    struct RedeemRequest {
        uint192 amount; // Requested redeem amount
        uint64 requestTime; // Time when the redeem request was made
    }

    /// @notice Returns asset.
    /// @dev See the implementation for behavior details.
    /// @return assetTokenAddress The assetTokenAddress value.
    function asset() external view returns (address assetTokenAddress);

    /// @notice Returns total assets.
    /// @dev See the implementation for behavior details.
    /// @return totalManagedAssets The totalManagedAssets value.
    function totalAssets() external view returns (uint256 totalManagedAssets);

    /// @notice Returns preview deposit.
    /// @dev See the implementation for behavior details.
    /// @param assets The assets value.
    /// @return shares The shares value.
    function previewDeposit(uint256 assets) external view returns (uint256 shares);

    /// @notice Returns preview redeem.
    /// @dev See the implementation for behavior details.
    /// @param shares The shares value.
    /// @return assets The assets value.
    function previewRedeem(uint256 shares) external view returns (uint256 assets);

    /// @notice Executes initialize.
    /// @dev See the implementation for behavior details.
    /// @param name The name value.
    /// @param symbol The symbol value.
    /// @param yieldDispatcher The yieldDispatcher value.
    /// @param asset The asset value.
    /// @param verseId The verseId value.
    function initialize(
        string memory name,
        string memory symbol,
        address yieldDispatcher,
        address asset,
        uint256 verseId
    ) external;

    /// @notice Executes accumulate yields.
    /// @dev See the implementation for behavior details.
    /// @param amount The amount value.
    function accumulateYields(uint256 amount) external;

    /// @notice Executes re accumulate yields.
    /// @dev See the implementation for behavior details.
    /// @param lzGuid The lzGuid value.
    function reAccumulateYields(bytes32 lzGuid) external;

    /// @notice Executes deposit.
    /// @dev See the implementation for behavior details.
    /// @param assets The assets value.
    /// @param receiver The receiver value.
    /// @return shares The shares value.
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    /// @notice Executes request redeem.
    /// @dev See the implementation for behavior details.
    /// @param shares The shares value.
    /// @param receiver The receiver value.
    /// @return assets The assets value.
    function requestRedeem(uint256 shares, address receiver) external returns (uint256 assets);

    /// @notice Executes execute redeem.
    /// @dev See the implementation for behavior details.
    /// @return redeemedAmount The redeemedAmount value.
    function executeRedeem() external returns (uint256 redeemedAmount);

    event AccumulateYields(address indexed yieldSource, uint256 yield, uint256 exchangeRate);

    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);

    event RedeemRequested(
        address indexed sender, address indexed receiver, uint256 assets, uint256 shares, uint256 requestTime
    );

    event RedeemExecuted(address indexed receiver, uint256 amount);

    error ZeroAddress();

    error ZeroRedeemRequest();

    error MaxRedeemRequestsReached();
}
