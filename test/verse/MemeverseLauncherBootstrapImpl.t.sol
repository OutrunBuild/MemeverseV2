// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {MemeverseLauncher} from "../../src/verse/MemeverseLauncher.sol";
import {MemeverseBootstrap} from "../../src/verse/MemeverseBootstrap.sol";
import {MemeverseLauncherTestHelper} from "../mocks/verse/MemeverseLauncherTestHelper.sol";
import {IMemeverseLauncher} from "../../src/verse/interfaces/IMemeverseLauncher.sol";

import {
    MockSwapRouter,
    MockLiquidProof,
    MockPredictOnlyProxyDeployer,
    MockPOLendForLifecycle,
    MockPOLSplitterForLifecycle,
    MockOFTDispatcher,
    MockLzEndpointRegistry
} from "../mocks/verse/LauncherLifecycleMocks.sol";

/// @notice Targeted guard tests for the `bootstrapImpl` zero-address check in `_deployLiquidity`.
/// @dev The launcher facade delegatecalls the `MemeverseBootstrap` sibling to deploy liquidity; if the
///      sibling is unset the facade reverts with `BootstrapImplNotSet` before the delegatecall.
contract MemeverseLauncherBootstrapImplTest is Test, MemeverseLauncherTestHelper {
    IMemeverseLauncher internal launcher;
    address internal launcherProxy;
    MockSwapRouter internal router;
    MockOFTDispatcher internal dispatcher;
    MockPredictOnlyProxyDeployer internal proxyDeployer;
    MockPOLendForLifecycle internal polend;
    MockPOLSplitterForLifecycle internal splitter;
    MockLzEndpointRegistry internal registry;
    MockERC20 internal uAsset;
    MockERC20 internal memecoin;
    MockLiquidProof internal liquidProof;
    MockERC20 internal pt;
    MockERC20 internal yt;

    /// @notice Deploys the launcher proxy and supporting mocks, but intentionally leaves `bootstrapImpl` unset.
    /// @dev Mirrors `MemeverseLauncherLifecycleTest.setUp` minus the `setBootstrapImpl` call so each test
    ///      can control sibling availability explicitly.
    function setUp() external {
        dispatcher = new MockOFTDispatcher();
        uAsset = new MockERC20("UASSET", "UASSET", 18);
        memecoin = new MockERC20("MEME", "MEME", 18);
        liquidProof = new MockLiquidProof();
        pt = new MockERC20("PT", "PT", 18);
        yt = new MockERC20("YT", "YT", 18);
        proxyDeployer = new MockPredictOnlyProxyDeployer(address(0xD00D), address(0xCAFE), address(0xF00D));
        polend = new MockPOLendForLifecycle();
        splitter = new MockPOLSplitterForLifecycle(address(pt), address(yt));
        registry = new MockLzEndpointRegistry();
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
        router = new MockSwapRouter(address(launcher));

        launcher.setMemeverseUniswapHook(address(router.hook()));
        launcher.setMemeverseSwapRouter(address(router));
        // Deliberately omitted: launcher.setBootstrapImpl(...). Each test asserts the guard explicitly.
        launcher.setYieldDispatcher(address(dispatcher));
        launcher.setMemeverseProxyDeployer(address(proxyDeployer));
        launcher.setLzEndpointRegistry(address(registry));
        router.setLpToken(address(liquidProof), address(uAsset), address(new MockERC20("POL-U", "POL-U", 18)));
        router.setLpToken(address(pt), address(uAsset), address(new MockERC20("PT-U", "PT-U", 18)));
        router.setLpToken(address(pt), address(liquidProof), address(new MockERC20("PT-POL", "PT-POL", 18)));
    }

    /// @notice Seeds a flash-Genesis verse that satisfies the minimum funding target so `changeStage`
    ///         routes into `_deployAndSetupMemeverse` -> `_deployLiquidity`.
    /// @dev Reuses the lifecycle fixture proven to reach `Locked` when a bootstrap sibling is bound.
    ///      `omnichainIds[0] != block.chainid` forces the remote governance branch, which only predicts
    ///      addresses instead of deploying and initializing concrete vaults/governor contracts.
    function _seedFlashGenesisVerseReadyToLock(uint256 verseId) internal {
        setMemeverseForTest(
            launcherProxy,
            verseId,
            address(uAsset),
            address(memecoin),
            address(liquidProof),
            address(0),
            address(0),
            address(0),
            0,
            0,
            IMemeverseLauncher.Stage.Genesis,
            true // flashGenesis allows locking before endTime once minTotalFund is met
        );
        setOmnichainIdsForTest(launcherProxy, verseId, _array(uint32(block.chainid + 1)));
        launcher.setFundMetaData(address(uAsset), 10 ether, 4);
        setGenesisFundForTest(launcherProxy, verseId, 120 ether);
        router.setAddLiquidityResult(address(memecoin), address(uAsset), 90 ether, 0, 0);
        router.setAddLiquidityResult(address(liquidProof), address(uAsset), 30 ether, 0, 0);
    }

    function _array(uint32 value) internal pure returns (uint32[] memory arr) {
        arr = new uint32[](1);
        arr[0] = value;
    }

    /// @notice Verifies `changeStage` reverts when `bootstrapImpl` is unset even though funding qualifies for launch.
    /// @dev Exercises the zero-address guard in `_deployLiquidity`; the revert must surface as `BootstrapImplNotSet`.
    function test_revertsWhenBootstrapImplNotSet() external {
        uint256 verseId = 1;
        _seedFlashGenesisVerseReadyToLock(verseId);

        vm.expectRevert(IMemeverseLauncher.BootstrapImplNotSet.selector);
        launcher.changeStage(verseId);

        // Reaching `_deployLiquidity` means Genesis pre-checks passed and the verse was about to lock;
        // the guard must leave the stage untouched so the call is safe to retry after binding a sibling.
        assertEq(
            uint256(launcher.getStageByVerseId(verseId)),
            uint256(IMemeverseLauncher.Stage.Genesis),
            "stage unchanged after guard revert"
        );
    }

    /// @notice Verifies the bootstrap sibling runs via delegatecall once bound, advancing the verse to `Locked`.
    /// @dev Same fixture as the guard test, but `setBootstrapImpl` is invoked first; the sibling deploys the
    ///      main and POL pools, mints POL, and records bootstrap residual state in the facade's storage.
    function test_bootstrapRunsViaSiblingAfterSet() external {
        uint256 verseId = 1;
        _seedFlashGenesisVerseReadyToLock(verseId);

        launcher.setBootstrapImpl(address(new MemeverseBootstrap()));

        IMemeverseLauncher.Stage stage = launcher.changeStage(verseId);

        assertEq(uint256(stage), uint256(IMemeverseLauncher.Stage.Locked), "returned stage");
        assertEq(uint256(launcher.getStageByVerseId(verseId)), uint256(IMemeverseLauncher.Stage.Locked), "stored stage");
        // The bootstrap sibling records the POL/uAsset LP amount in the facade's auxiliary-liquidity slot.
        (uint256 polUAssetLp,,) = MemeverseLauncher(launcherProxy).auxiliaryLiquidities(verseId);
        assertGt(polUAssetLp, 0, "bootstrap deployed POL/uAsset liquidity");
    }

    /// @notice A direct (non-delegatecall) invocation of sibling.deployLiquidity must revert.
    /// @dev The sibling has no initializer and no setter, so its own storage is permanently
    ///      uninitialized: memeverseSwapRouter / memeverseUniswapHook read as address(0), and
    ///      MemeverseLauncherLib.validateSettlementWiring reverts on its zero-address require. Locks the
    ///      "deployLiquidity is facade-delegatecall-only" invariant so a future initializer/setter
    ///      added to the sibling cannot silently break it.
    function test_directCallToSiblingReverts() external {
        MemeverseBootstrap sibling = new MemeverseBootstrap();
        address attacker = makeAddr("attacker");

        // Non-zero _polend / _polSplitter bypass deployLiquidity's first require so the call reaches
        // MemeverseLauncherLib.validateSettlementWiring, where empty sibling storage forces the revert.
        vm.prank(attacker);
        vm.expectRevert(IMemeverseLauncher.InvalidPreorderSettlementConfig.selector);
        sibling.deployLiquidity(
            1, address(uAsset), address(memecoin), address(liquidProof), 0, address(polend), address(splitter)
        );
    }
}
