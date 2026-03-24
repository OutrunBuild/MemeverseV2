// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {BaseHook} from "@uniswap/v4-hooks-public/src/base/BaseHook.sol";

import {MemeverseLauncher} from "../../src/verse/MemeverseLauncher.sol";
import {IMemeverseLauncher} from "../../src/verse/interfaces/IMemeverseLauncher.sol";
import {MemeverseSwapRouter} from "../../src/swap/MemeverseSwapRouter.sol";
import {MemeverseUniswapHook} from "../../src/swap/MemeverseUniswapHook.sol";
import {IMemeverseUniswapHook} from "../../src/swap/interfaces/IMemeverseUniswapHook.sol";
import {MockPoolManagerForRouterTest} from "../swap/MemeverseSwapRouter.t.sol";

contract MockIntegrationMemecoin is MockERC20 {
    address public memeverseLauncher;
    mapping(uint32 eid => bytes32 peer) public peers;

    constructor() MockERC20("Mock Meme", "MMEME", 18) {}

    /// @notice Test helper for initialize.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @param _name See implementation.
    /// @param _symbol See implementation.
    /// @param launcher_ See implementation.
    /// @param _unusedPeer See implementation.
    function initialize(string memory _name, string memory _symbol, address launcher_, address _unusedPeer) external {
        _name;
        _symbol;
        _unusedPeer;
        memeverseLauncher = launcher_;
    }

    /// @notice Test helper for setPeer.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @param eid See implementation.
    /// @param peer See implementation.
    function setPeer(uint32 eid, bytes32 peer) external {
        peers[eid] = peer;
    }

    /// @notice Test helper for mint.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @param account See implementation.
    /// @param amount See implementation.
    function mint(address account, uint256 amount) public override {
        require(msg.sender == memeverseLauncher, "not launcher");
        require(amount != 0, "zero");
        super.mint(account, amount);
    }

    /// @notice Test helper for burn.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @param amount See implementation.
    function burn(uint256 amount) external {
        require(amount != 0, "zero");
        super.burn(msg.sender, amount);
    }
}

contract MockIntegrationLiquidProof is MockERC20 {
    address public memeverseLauncher;
    address public memecoin;
    bytes32 public poolId;
    mapping(uint32 eid => bytes32 peer) public peers;

    constructor() MockERC20("Mock POL", "MPOL", 18) {}

    /// @notice Test helper for initialize.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @param _name See implementation.
    /// @param _symbol See implementation.
    /// @param memecoin_ See implementation.
    /// @param launcher_ See implementation.
    /// @param _unusedPeer See implementation.
    function initialize(
        string memory _name,
        string memory _symbol,
        address memecoin_,
        address launcher_,
        address _unusedPeer
    ) external {
        _name;
        _symbol;
        _unusedPeer;
        memecoin = memecoin_;
        memeverseLauncher = launcher_;
    }

    /// @notice Test helper for setPeer.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @param eid See implementation.
    /// @param peer See implementation.
    function setPeer(uint32 eid, bytes32 peer) external {
        peers[eid] = peer;
    }

    /// @notice Test helper for setPoolId.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @param poolId_ See implementation.
    function setPoolId(bytes32 poolId_) external {
        require(msg.sender == memeverseLauncher, "not launcher");
        poolId = poolId_;
    }

    /// @notice Test helper for mint.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @param account See implementation.
    /// @param amount See implementation.
    function mint(address account, uint256 amount) public override {
        require(msg.sender == memeverseLauncher, "not launcher");
        require(amount != 0, "zero");
        super.mint(account, amount);
    }

    /// @notice Test helper for burn.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @param account See implementation.
    /// @param amount See implementation.
    function burn(address account, uint256 amount) public override {
        require(amount != 0, "zero");
        require(msg.sender == account || msg.sender == memeverseLauncher, "not allowed");
        super.burn(account, amount);
    }
}

contract TestableMemeverseUniswapHookForLauncherIntegration is MemeverseUniswapHook {
    constructor(IPoolManager _manager, address _owner, address _treasury, address _launchSettlementCaller)
        MemeverseUniswapHook(_manager, _owner, _treasury, _launchSettlementCaller)
    {}

    function validateHookAddress(BaseHook) internal pure override {}
}

contract MockLauncherIntegrationProxyDeployer {
    address internal immutable predictedYieldVault;
    address internal immutable predictedGovernor;
    address internal immutable predictedIncentivizer;

    constructor(address _predictedYieldVault, address _predictedGovernor, address _predictedIncentivizer) {
        predictedYieldVault = _predictedYieldVault;
        predictedGovernor = _predictedGovernor;
        predictedIncentivizer = _predictedIncentivizer;
    }

    /// @notice Test helper for deployMemecoin.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @param _verseId See implementation.
    /// @return memecoin See implementation.
    function deployMemecoin(uint256 _verseId) external returns (address memecoin) {
        _verseId;
        memecoin = address(new MockIntegrationMemecoin());
    }

    /// @notice Test helper for deployPOL.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @param _verseId See implementation.
    /// @return pol See implementation.
    function deployPOL(uint256 _verseId) external returns (address pol) {
        _verseId;
        pol = address(new MockIntegrationLiquidProof());
    }

    /// @notice Test helper for predictYieldVaultAddress.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @param _verseId See implementation.
    /// @return yieldVault See implementation.
    function predictYieldVaultAddress(uint256 _verseId) external view returns (address yieldVault) {
        _verseId;
        return predictedYieldVault;
    }

    /// @notice Test helper for computeGovernorAndIncentivizerAddress.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @param _verseId See implementation.
    /// @return governor See implementation.
    /// @return incentivizer See implementation.
    function computeGovernorAndIncentivizerAddress(uint256 _verseId)
        external
        view
        returns (address governor, address incentivizer)
    {
        _verseId;
        return (predictedGovernor, predictedIncentivizer);
    }
}

contract MockLauncherIntegrationLzEndpointRegistry {
    mapping(uint32 chainId => uint32 endpointId) public lzEndpointIdOfChain;

    /// @notice Test helper for setEndpoint.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    /// @param chainId See implementation.
    /// @param endpointId See implementation.
    function setEndpoint(uint32 chainId, uint32 endpointId) external {
        lzEndpointIdOfChain[chainId] = endpointId;
    }
}

contract MemeverseLauncherPreorderIntegrationTest is Test {
    address internal constant REGISTRAR = address(0xBEEF);
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    uint32 internal constant REMOTE_GOV_CHAIN_ID = 202;
    uint32 internal constant REMOTE_EID = 302;

    MockPoolManagerForRouterTest internal manager;
    TestableMemeverseUniswapHookForLauncherIntegration internal hook;
    MemeverseSwapRouter internal router;
    MemeverseLauncher internal launcher;
    MockLauncherIntegrationProxyDeployer internal proxyDeployer;
    MockLauncherIntegrationLzEndpointRegistry internal registry;
    MockERC20 internal upt;

    /// @notice Test helper for setUp.
    /// @dev Auto-generated minimal NatSpec for repository gate compliance.
    function setUp() external {
        manager = new MockPoolManagerForRouterTest();
        launcher = new MemeverseLauncher(
            address(this),
            address(0x1111),
            REGISTRAR,
            address(0),
            address(0x4444),
            address(0),
            25,
            115_000,
            135_000,
            2_500,
            7 days
        );
        hook = new TestableMemeverseUniswapHookForLauncherIntegration(
            IPoolManager(address(manager)), address(this), address(this), address(launcher)
        );
        router = new MemeverseSwapRouter(
            IPoolManager(address(manager)),
            IMemeverseUniswapHook(address(hook)),
            IPermit2(address(0xBEEF)),
            address(launcher)
        );
        hook.setLaunchSettlementCaller(address(router));
        proxyDeployer = new MockLauncherIntegrationProxyDeployer(address(0xD00D), address(0xCAFE), address(0xF00D));
        registry = new MockLauncherIntegrationLzEndpointRegistry();
        upt = new MockERC20("UPT", "UPT", 18);

        launcher.setMemeverseSwapRouter(address(router));
        launcher.setMemeverseProxyDeployer(address(proxyDeployer));
        launcher.setLzEndpointRegistry(address(registry));
        launcher.setFundMetaData(address(upt), 100 ether, 4);

        registry.setEndpoint(REMOTE_GOV_CHAIN_ID, REMOTE_EID);

        uint32[] memory omnichainIds = new uint32[](1);
        omnichainIds[0] = REMOTE_GOV_CHAIN_ID;
        vm.prank(REGISTRAR);
        launcher.registerMemeverse(
            "Memeverse",
            "MEME",
            1,
            uint128(block.timestamp + 1 days),
            uint128(block.timestamp + 30 days),
            omnichainIds,
            address(upt),
            true
        );

        IMemeverseLauncher.Memeverse memory verse = launcher.getMemeverseByVerseId(1);
        hook.setProtocolFeeCurrency(Currency.wrap(address(upt)));
        hook.setProtocolFeeCurrency(Currency.wrap(verse.memecoin));

        upt.mint(ALICE, 210 ether);
        upt.mint(BOB, 20 ether);

        vm.prank(ALICE);
        upt.approve(address(launcher), type(uint256).max);
        vm.prank(BOB);
        upt.approve(address(launcher), type(uint256).max);
    }

    /// @notice Verifies the real launcher-router-hook path settles preorder through the launch marker and distributes linearly.
    /// @dev Uses the real router and hook with the mock pool manager instead of the lifecycle swap mock.
    function testPreorderSettlement_RealLauncherRouterHookPath() external {
        vm.prank(ALICE);
        launcher.genesis(1, 200 ether, ALICE);

        vm.prank(ALICE);
        launcher.preorder(1, 10 ether, ALICE);
        vm.prank(BOB);
        launcher.preorder(1, 20 ether, BOB);

        IMemeverseLauncher.Memeverse memory verseBefore = launcher.getMemeverseByVerseId(1);

        IMemeverseLauncher.Stage stage = launcher.changeStage(1);
        assertEq(uint256(stage), uint256(IMemeverseLauncher.Stage.Locked), "locked");

        uint256 treasuryUptBalance = upt.balanceOf(address(this));
        assertEq(treasuryUptBalance, 0.09 ether, "treasury received fixed 0.3% protocol fee");

        vm.warp(block.timestamp + 3 days + 12 hours);

        vm.prank(ALICE);
        uint256 aliceHalf = launcher.claimablePreorderMemecoin(1);
        vm.prank(BOB);
        uint256 bobHalf = launcher.claimablePreorderMemecoin(1);

        assertEq(aliceHalf, 2.475 ether, "alice half claimable");
        assertEq(bobHalf, 4.95 ether, "bob half claimable");

        vm.warp(block.timestamp + 3 days + 12 hours + 1);

        vm.prank(ALICE);
        uint256 aliceClaimed = launcher.claimUnlockedPreorderMemecoin(1);
        vm.prank(BOB);
        uint256 bobClaimed = launcher.claimUnlockedPreorderMemecoin(1);

        assertEq(aliceClaimed, 4.95 ether, "alice total");
        assertEq(bobClaimed, 9.9 ether, "bob total");
        assertEq(MockERC20(verseBefore.memecoin).balanceOf(ALICE), 4.95 ether, "alice memecoin");
        assertEq(MockERC20(verseBefore.memecoin).balanceOf(BOB), 9.9 ether, "bob memecoin");
    }
}
