// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {MemeverseLauncher} from "../../src/verse/MemeverseLauncher.sol";
import {MemeversePOLMinter} from "../../src/verse/MemeversePOLMinter.sol";
import {MemeverseLauncherTestHelper} from "../mocks/verse/MemeverseLauncherTestHelper.sol";
import {IMemeverseLauncher} from "../../src/verse/interfaces/IMemeverseLauncher.sol";
import {OutrunOwnableUpgradeable} from "../../src/common/access/OutrunOwnableUpgradeable.sol";

import {MockPOLendForLifecycle, MockPOLSplitterForLifecycle} from "../mocks/verse/LauncherLifecycleMocks.sol";

/// @notice Targeted guard tests for the `polMinterImpl` zero-address check.
/// @dev The launcher facade delegatecalls the `MemeversePOLMinter` sibling for POL minting (`mintPOLToken`);
///      if the sibling is unset the facade reverts with `POLMinterImplNotSet` before the delegatecall. Mirrors
///      the `MemeverseLauncherFeeDistributorImpl` guard-test structure. The guard fires before any external
///      call, so the fixture seeds a Locked verse directly via storage (no bootstrap liquidity deployment).
contract MemeverseLauncherPOLMinterImplTest is Test, MemeverseLauncherTestHelper {
    IMemeverseLauncher internal launcher;
    address internal launcherProxy;
    MockERC20 internal uAsset;
    MockERC20 internal memecoin;
    MockERC20 internal pol;
    MockPOLendForLifecycle internal polend;
    MockPOLSplitterForLifecycle internal splitter;

    /// @notice Deploys the launcher proxy and supporting mocks, but intentionally leaves `polMinterImpl` unset.
    function setUp() external {
        uAsset = new MockERC20("UASSET", "UASSET", 18);
        memecoin = new MockERC20("MEME", "MEME", 18);
        pol = new MockERC20("POL", "POL", 18);
        polend = new MockPOLendForLifecycle();
        splitter = new MockPOLSplitterForLifecycle(address(pol), address(uAsset));
        MemeverseLauncher impl = new MemeverseLauncher();
        launcherProxy = address(
            new ERC1967Proxy(
                address(impl),
                abi.encodeCall(
                    MemeverseLauncher.initialize,
                    (
                        address(this),
                        address(0x1),
                        address(0x2),
                        address(0x3),
                        address(0x4),
                        address(0x5),
                        address(polend),
                        address(splitter),
                        25,
                        115_000,
                        135_000,
                        2_500,
                        7 days
                    )
                )
            )
        );
        launcher = IMemeverseLauncher(launcherProxy);
        // Deliberately omitted: launcher.setPOLMinterImpl(...). Each test asserts the guard explicitly.
    }

    /// @notice Seeds a verse directly to `Locked` so `mintPOLToken` passes its stage precheck and reaches the
    ///         `polMinterImpl` zero-address guard.
    function _seedLockedVerse(uint256 verseId) internal {
        setMemeverseForTest(
            launcherProxy,
            verseId,
            address(uAsset),
            address(memecoin),
            address(pol),
            address(0),
            address(0),
            address(0),
            0,
            0,
            IMemeverseLauncher.Stage.Locked,
            false
        );
    }

    /// @notice Verifies `mintPOLToken` reverts when `polMinterImpl` is unset.
    /// @dev The facade validates input non-zero / stage >= Locked, then hits the guard before the delegatecall.
    function test_revertsWhenPOLMinterImplNotSet_mintPOLToken() external {
        uint256 verseId = 1;
        _seedLockedVerse(verseId);

        vm.expectRevert(IMemeverseLauncher.POLMinterImplNotSet.selector);
        launcher.mintPOLToken(verseId, 1 ether, 1 ether, 0, 0, 0, block.timestamp);
    }

    /// @notice A direct (non-delegatecall) invocation of the sibling must revert in both liquidity modes.
    /// @dev The sibling shares no storage with the proxy; its own `memeverseLauncherStorage` is permanently
    ///      uninitialized, so `memeverseSwapRouter` reads as address(0) and the router external call reverts on
    ///      empty returndata decode. Locks the "mintPOLToken is facade-delegatecall-only" invariant for both the
    ///      auto-liquidity (`amountOutDesired == 0`) and exact-liquidity (`amountOutDesired != 0`) branches.
    function test_directCallToPOLMinterReverts_autoLiquidity() external {
        MemeversePOLMinter sibling = new MemeversePOLMinter();
        address attacker = makeAddr("attacker");

        vm.prank(attacker);
        vm.expectRevert();
        sibling.mintPOLToken(
            address(uAsset), address(memecoin), address(pol), 1 ether, 1 ether, 0, 0, 0, block.timestamp
        );
    }

    function test_directCallToPOLMinterReverts_exactLiquidity() external {
        MemeversePOLMinter sibling = new MemeversePOLMinter();
        address attacker = makeAddr("attacker");

        vm.prank(attacker);
        vm.expectRevert();
        sibling.mintPOLToken(
            address(uAsset), address(memecoin), address(pol), 1 ether, 1 ether, 0, 0, 1 ether, block.timestamp
        );
    }

    /// @notice `setPOLMinterImpl` rejects a zero address and unauthorized callers.
    function test_setPOLMinterImplGuards() external {
        // Zero address rejected (owner caller).
        vm.expectRevert(IMemeverseLauncher.ZeroInput.selector);
        launcher.setPOLMinterImpl(address(0));

        // Non-owner rejected.
        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(OutrunOwnableUpgradeable.OwnableUnauthorizedAccount.selector, attacker));
        launcher.setPOLMinterImpl(address(1));
    }

    /// @notice Once `polMinterImpl` is bound, `mintPOLToken` proceeds past the guard (full mint path is covered
    ///         by `MemeverseLauncherLifecycleTest` / `MemeverseLauncherSwapIntegrationTest` with real router stack).
    function test_mintPOLTokenProceedsAfterPOLMinterBound() external {
        uint256 verseId = 1;
        _seedLockedVerse(verseId);
        launcher.setPOLMinterImpl(address(new MemeversePOLMinter()));

        // With the guard passed, the call now reaches the sibling's router interaction. The router is unset in
        // this minimal fixture, so the sibling reverts on the address(0) router call rather than POLMinterImplNotSet.
        vm.expectRevert();
        launcher.mintPOLToken(verseId, 1 ether, 1 ether, 0, 0, 0, block.timestamp);
    }
}
