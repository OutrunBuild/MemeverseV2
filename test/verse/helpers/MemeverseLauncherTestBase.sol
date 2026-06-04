// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {MemeverseLauncher} from "../../../src/verse/MemeverseLauncher.sol";

/// @notice Shared test base for all MemeverseLauncher test helpers.
/// @dev Consolidates duplicate _testStorage(), createProxy(), getPreorderStateForTest(),
///      and claimablePreorderMemecoinForTest() that were previously copied across
///      PreorderInvariant, EndToEndInvariant, Registration, Views, Lifecycle, and
///      POLendIntegration test files.
abstract contract MemeverseLauncherTestBase is MemeverseLauncher {
    function _testStorage() internal pure returns (MemeverseLauncherStorage storage $) {
        assembly {
            $.slot := MEMEVERSE_LAUNCHER_STORAGE_LOCATION
        }
    }

    /// @notice Deploy a proxy pointing at this implementation and call initialize.
    /// @dev Internal helper so derived contracts can wrap it with their own typed createProxy().
    function _createProxy(
        address _owner,
        address _localLzEndpoint,
        address _memeverseRegistrar,
        address _memeverseProxyDeployer,
        address _yieldDispatcher,
        address _lzEndpointRegistry,
        address _polend,
        address _polSplitter,
        uint256 _executorRewardRate,
        uint128 _oftReceiveGasLimit,
        uint128 _yieldDispatcherGasLimit,
        uint256 _preorderCapRatio,
        uint256 _preorderVestingDuration
    ) internal returns (MemeverseLauncherTestBase) {
        bytes memory data = abi.encodeCall(
            MemeverseLauncher.initialize,
            (
                _owner,
                _localLzEndpoint,
                _memeverseRegistrar,
                _memeverseProxyDeployer,
                _yieldDispatcher,
                _lzEndpointRegistry,
                _polend,
                _polSplitter,
                _executorRewardRate,
                _oftReceiveGasLimit,
                _yieldDispatcherGasLimit,
                _preorderCapRatio,
                _preorderVestingDuration
            )
        );
        return MemeverseLauncherTestBase(address(new ERC1967Proxy(address(this), data)));
    }

    function getPreorderStateForTest(uint256 verseId)
        external
        view
        returns (uint256 totalFunds, uint256 settledMemecoin, uint40 settlementTimestamp)
    {
        PreorderState storage preorderState = _testStorage().preorderStates[verseId];
        return (preorderState.totalFunds, preorderState.settledMemecoin, preorderState.settlementTimestamp);
    }

    function claimablePreorderMemecoinForTest(uint256 verseId, address account) external view returns (uint256 amount) {
        return _claimablePreorderMemecoinForAccount(verseId, account);
    }
}
