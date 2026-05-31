// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {BaseHook} from "@uniswap/v4-hooks-public/src/base/BaseHook.sol";

import {MemeverseLauncher} from "../../src/verse/MemeverseLauncher.sol";
import {IMemeverseLauncher} from "../../src/verse/interfaces/IMemeverseLauncher.sol";
import {IPOLend} from "../../src/polend/interfaces/IPOLend.sol";
import {MemeverseSwapRouter} from "../../src/swap/MemeverseSwapRouter.sol";
import {MemeverseUniswapHook} from "../../src/swap/MemeverseUniswapHook.sol";
import {IMemeverseUniswapHook} from "../../src/swap/interfaces/IMemeverseUniswapHook.sol";
import {MockPoolManagerForRouterTest} from "../swap/MemeverseSwapRouter.t.sol";

contract MockPOLendForPreorderIntegration {
    address internal pt_;
    address internal yt_;

    function setLendMarket(address pt, address yt) external {
        pt_ = pt;
        yt_ = yt;
    }

    function registerLendMarket(uint256) external {}

    function settlementDustStates(address) external pure virtual returns (uint128 reserve, uint128 maxReserve) {
        return (0, type(uint128).max);
    }

    function fundSettlementDustReserve(address, uint256) external virtual {}

    function getTotalLeveragedDebt(uint256) external pure returns (uint256) {
        return 0;
    }

    function getTotalLeveragedInterest(uint256) external pure returns (uint256) {
        return 0;
    }

    function getLendMarket(uint256) external view returns (IPOLend.LendMarket memory market) {
        market.yt = yt_;
    }

    function finalizeLeveragedGenesis(uint256) external {}

    function recordLeveragedYT(uint256, address, uint256) external {}

    function markRefundable(uint256) external {}

    function executeGlobalSettlement(uint256) external {}
}

contract MockPOLSplitterForPreorderIntegration {
    address internal immutable pt;
    address internal immutable yt;
    mapping(uint256 verseId => uint256 numerator) internal ptBackingNumerators;
    mapping(uint256 verseId => uint256 denominator) internal ptBackingDenominators;
    mapping(uint256 verseId => uint256 previewPTToUAssetResults) internal previewPTToUAssetResults;
    mapping(uint256 verseId => bool enabled) internal previewPTToUAssetOverrideEnabled;

    constructor(address pt_, address yt_) {
        pt = pt_;
        yt = yt_;
    }

    function initializeVerse(uint256, address, address, address, string calldata, string calldata)
        external
        view
        returns (address, address)
    {
        return (pt, yt);
    }

    function splitInfos(uint256)
        external
        view
        returns (address, address, address, address, address, uint256, uint256, uint256, uint256, uint256, bool)
    {
        return (pt, yt, address(0), address(0), address(0), 0, 0, 0, 0, 0, false);
    }

    function getPT(uint256) external view returns (address) {
        return pt;
    }

    function getYT(uint256) external view returns (address) {
        return yt;
    }

    function getMemecoin(uint256) external pure returns (address) {
        return address(0);
    }

    function getPTAndYT(uint256) external view returns (address, address) {
        return (pt, yt);
    }

    function getPTSettlementState(uint256) external view returns (address, bool) {
        return (pt, false);
    }

    function split(uint256, uint256 polAmount) external returns (uint256 ptAmount, uint256 ytAmount) {
        MockERC20(pt).mint(msg.sender, polAmount);
        MockERC20(yt).mint(msg.sender, polAmount);
        return (polAmount, polAmount);
    }

    function settle(uint256) external pure returns (uint256 settlementUAsset, uint256 settlementMemecoin) {
        return (0, 0);
    }

    function merge(uint256, uint256) external pure returns (uint256) {
        revert("unused");
    }

    function recordPTBackingRatio(uint256 verseId, uint256 numerator, uint256 denominator) external {
        ptBackingNumerators[verseId] = numerator;
        ptBackingDenominators[verseId] = denominator;
    }

    function previewPTToUAsset(uint256 verseId, uint256 ptAmount) external view returns (uint256 uAssetAmount) {
        if (previewPTToUAssetOverrideEnabled[verseId]) return previewPTToUAssetResults[verseId];
        uint256 denominator = ptBackingDenominators[verseId];
        if (denominator == 0) return ptAmount;
        return ptAmount * ptBackingNumerators[verseId] / denominator;
    }

    function setPreviewPTToUAssetResult(uint256 verseId, uint256 result) external {
        previewPTToUAssetResults[verseId] = result;
        previewPTToUAssetOverrideEnabled[verseId] = true;
    }

    function redeemPT(uint256, uint256, address) external pure returns (uint256) {
        revert("unused");
    }

    function redeemYT(uint256, uint256, address) external pure returns (uint256, uint256) {
        revert("unused");
    }

    function previewRedeemYTUAsset(uint256, uint256) external pure returns (uint256 uAssetAmount) {
        return 0;
    }
}

contract MockIntegrationMemecoin is MockERC20 {
    address public memeverseLauncher;
    mapping(uint32 eid => bytes32 peer) public peers;

    constructor() MockERC20("Mock Meme", "MMEME", 18) {}

    /// @notice Test helper for initialize.
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
    /// @param eid See implementation.
    /// @param peer See implementation.
    function setPeer(uint32 eid, bytes32 peer) external {
        peers[eid] = peer;
    }

    /// @notice Test helper for mint.
    /// @param account See implementation.
    /// @param amount See implementation.
    function mint(address account, uint256 amount) public override {
        require(msg.sender == memeverseLauncher, "not launcher");
        require(amount != 0, "zero");
        super.mint(account, amount);
    }

    /// @notice Test helper for burn.
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
    /// @param eid See implementation.
    /// @param peer See implementation.
    function setPeer(uint32 eid, bytes32 peer) external {
        peers[eid] = peer;
    }

    /// @notice Test helper for setPoolId.
    /// @param poolId_ See implementation.
    function setPoolId(bytes32 poolId_) external {
        require(msg.sender == memeverseLauncher, "not launcher");
        poolId = poolId_;
    }

    /// @notice Test helper for mint.
    /// @param account See implementation.
    /// @param amount See implementation.
    function mint(address account, uint256 amount) public override {
        require(msg.sender == memeverseLauncher, "not launcher");
        require(amount != 0, "zero");
        super.mint(account, amount);
    }

    /// @notice Test helper for burn.
    /// @param account See implementation.
    /// @param amount See implementation.
    function burn(address account, uint256 amount) public override {
        require(amount != 0, "zero");
        require(msg.sender == account || msg.sender == memeverseLauncher, "not allowed");
        super.burn(account, amount);
    }
}

contract TestableMemeverseUniswapHookForLauncherIntegration is MemeverseUniswapHook {
    constructor(IPoolManager _manager) MemeverseUniswapHook(_manager) {}

    function validateHookAddress(BaseHook) internal pure override {}

    function _validateProxyHookAddress() internal view virtual override {}
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
    /// @param _verseId See implementation.
    /// @return memecoin See implementation.
    function deployMemecoin(uint256 _verseId) external returns (address memecoin) {
        _verseId;
        memecoin = address(new MockIntegrationMemecoin());
    }

    /// @notice Test helper for deployPOL.
    /// @param _verseId See implementation.
    /// @return pol See implementation.
    function deployPOL(uint256 _verseId) external returns (address pol) {
        _verseId;
        pol = address(new MockIntegrationLiquidProof());
    }

    /// @notice Test helper for predictYieldVaultAddress.
    /// @param _verseId See implementation.
    /// @return yieldVault See implementation.
    function predictYieldVaultAddress(uint256 _verseId) external view returns (address yieldVault) {
        _verseId;
        return predictedYieldVault;
    }

    /// @notice Test helper for computeGovernorAndIncentivizerAddress.
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
    MockPOLendForPreorderIntegration internal polend;
    MockPOLSplitterForPreorderIntegration internal splitter;
    MockERC20 internal uAsset;
    MockERC20 internal pt;
    MockERC20 internal yt;

    /// @notice Test helper for setUp.
    function setUp() external {
        manager = new MockPoolManagerForRouterTest();
        proxyDeployer = new MockLauncherIntegrationProxyDeployer(address(0xD00D), address(0xCAFE), address(0xF00D));
        registry = new MockLauncherIntegrationLzEndpointRegistry();
        uAsset = new MockERC20("UASSET", "UASSET", 18);
        pt = new MockERC20("PT", "PT", 18);
        yt = new MockERC20("YT", "YT", 18);
        polend = new MockPOLendForPreorderIntegration();
        splitter = new MockPOLSplitterForPreorderIntegration(address(pt), address(yt));
        launcher = new MemeverseLauncher(
            address(this),
            address(0x1111),
            REGISTRAR,
            address(0),
            address(0x4444),
            address(0),
            address(polend),
            address(splitter),
            25,
            115_000,
            135_000,
            2_500,
            7 days
        );
        TestableMemeverseUniswapHookForLauncherIntegration implementation =
            new TestableMemeverseUniswapHookForLauncherIntegration(IPoolManager(address(manager)));
        bytes memory data = abi.encodeCall(MemeverseUniswapHook.initialize, (address(this), address(this)));
        hook = TestableMemeverseUniswapHookForLauncherIntegration(
            address(new ERC1967Proxy(address(implementation), data))
        );
        router = new MemeverseSwapRouter(
            IPoolManager(address(manager)), IMemeverseUniswapHook(address(hook)), IPermit2(address(0xBEEF))
        );
        hook.setLauncher(address(launcher));
        hook.setPoolInitializer(address(router));

        launcher.setMemeverseUniswapHook(address(router.hook()));
        launcher.setMemeverseSwapRouter(address(router));
        assertEq(address(router.hook()), address(hook), "router hook");
        assertEq(hook.launcher(), address(launcher), "hook launcher");
        assertEq(hook.poolInitializer(), address(router), "hook initializer");
        launcher.setMemeverseProxyDeployer(address(proxyDeployer));
        launcher.setLzEndpointRegistry(address(registry));
        launcher.setFundMetaData(address(uAsset), 10 ether, 4);
        polend.setLendMarket(address(pt), address(yt));

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
            address(uAsset),
            true
        );

        IMemeverseLauncher.Memeverse memory verse = launcher.getMemeverseByVerseId(1);
        hook.setProtocolFeeCurrency(Currency.wrap(address(uAsset)));
        hook.setProtocolFeeCurrency(Currency.wrap(verse.memecoin));

        uAsset.mint(ALICE, 210 ether);
        uAsset.mint(BOB, 20 ether);

        vm.prank(ALICE);
        uAsset.approve(address(launcher), type(uint256).max);
        vm.prank(BOB);
        uAsset.approve(address(launcher), type(uint256).max);
    }

    /// @notice Verifies the real launcher-router-hook path settles preorder through the launch marker and distributes linearly.
    /// @dev Uses the real router and hook with the mock pool manager instead of the lifecycle swap mock.
    function testPreorderSettlement_RealLauncherRouterHookPath() external {
        vm.prank(ALICE);
        launcher.genesis(1, 10 ether, ALICE);

        vm.prank(ALICE);
        launcher.preorder(1, 1 ether, ALICE);
        vm.prank(BOB);
        launcher.preorder(1, 0.5 ether, BOB);

        IMemeverseLauncher.Memeverse memory verseBefore = launcher.getMemeverseByVerseId(1);
        vm.prank(address(launcher));
        MockIntegrationLiquidProof(verseBefore.pol).mint(address(this), 300 ether);
        pt.mint(address(this), 200 ether);
        uAsset.mint(address(this), 300 ether);
        MockERC20(verseBefore.pol).approve(address(router), type(uint256).max);
        pt.approve(address(router), type(uint256).max);
        uAsset.approve(address(router), type(uint256).max);
        hook.setLauncher(address(this));
        router.createPoolAndAddLiquidity(
            verseBefore.pol, address(uAsset), 100 ether, 100 ether, uint160(1 << 96), address(this), block.timestamp
        );
        router.createPoolAndAddLiquidity(
            address(pt), address(uAsset), 50 ether, 50 ether, uint160(1 << 96), address(this), block.timestamp
        );
        router.createPoolAndAddLiquidity(
            address(pt), verseBefore.pol, 50 ether, 50 ether, uint160(1 << 96), address(this), block.timestamp
        );
        hook.setLauncher(address(launcher));
        uint256 treasuryUAssetBalanceBefore = uAsset.balanceOf(address(this));

        IMemeverseLauncher.Stage stage = launcher.changeStage(1);
        assertEq(uint256(stage), uint256(IMemeverseLauncher.Stage.Locked), "locked");

        uint256 treasuryUAssetBalance = uAsset.balanceOf(address(this)) - treasuryUAssetBalanceBefore;
        assertEq(treasuryUAssetBalance, 0.0045 ether, "treasury received fixed 0.3% protocol fee");

        vm.warp(block.timestamp + 3 days + 12 hours);

        vm.prank(ALICE);
        uint256 aliceHalf = launcher.claimablePreorderMemecoin(1);
        vm.prank(BOB);
        uint256 bobHalf = launcher.claimablePreorderMemecoin(1);

        assertEq(aliceHalf, 0.2475 ether, "alice half claimable");
        assertEq(bobHalf, 0.12375 ether, "bob half claimable");

        vm.warp(block.timestamp + 3 days + 12 hours + 1);

        vm.prank(ALICE);
        uint256 aliceClaimed = launcher.claimUnlockedPreorderMemecoin(1);
        vm.prank(BOB);
        uint256 bobClaimed = launcher.claimUnlockedPreorderMemecoin(1);

        assertEq(aliceClaimed, 0.495 ether, "alice total");
        assertEq(bobClaimed, 0.2475 ether, "bob total");
        assertEq(MockERC20(verseBefore.memecoin).balanceOf(ALICE), 0.495 ether, "alice memecoin");
        assertEq(MockERC20(verseBefore.memecoin).balanceOf(BOB), 0.2475 ether, "bob memecoin");
    }
}
