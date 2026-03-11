// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {MemeverseLauncher} from "../src/verse/MemeverseLauncher.sol";
import {IMemeverseLauncher} from "../src/verse/interfaces/IMemeverseLauncher.sol";

contract MockSwapRouter {
    struct Quote {
        uint256 fee0;
        uint256 fee1;
    }

    mapping(bytes32 => Quote) internal quotes;

    function setQuote(address tokenA, address tokenB, address owner, uint256 fee0, uint256 fee1) external {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        quotes[keccak256(abi.encode(token0, token1, owner))] = Quote({fee0: fee0, fee1: fee1});
    }

    function previewClaimableFees(address tokenA, address tokenB, address owner)
        external
        view
        returns (uint256 fee0, uint256 fee1)
    {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        Quote memory quote = quotes[keccak256(abi.encode(token0, token1, owner))];
        return (quote.fee0, quote.fee1);
    }
}

contract TestableMemeverseLauncher is MemeverseLauncher {
    constructor(
        address _owner,
        address _localLzEndpoint,
        address _memeverseRegistrar,
        address _memeverseProxyDeployer,
        address _oftDispatcher,
        address _memeverseCommonInfo,
        uint256 _executorRewardRate,
        uint128 _oftReceiveGasLimit,
        uint128 _oftDispatcherGasLimit
    )
        MemeverseLauncher(
            _owner,
            _localLzEndpoint,
            _memeverseRegistrar,
            _memeverseProxyDeployer,
            _oftDispatcher,
            _memeverseCommonInfo,
            _executorRewardRate,
            _oftReceiveGasLimit,
            _oftDispatcherGasLimit
        )
    {}

    function setMemeverseForTest(uint256 verseId, Memeverse memory verse) external {
        memeverses[verseId] = verse;
    }
}

contract MemeverseLauncherPreviewFeesTest is Test {
    TestableMemeverseLauncher internal launcher;
    MockSwapRouter internal router;

    function setUp() external {
        launcher = new TestableMemeverseLauncher(
            address(this), address(0x1), address(0x2), address(0x3), address(0x4), address(0x5), 25, 115_000, 135_000
        );
        router = new MockSwapRouter();
        launcher.setMemeverseSwapRouter(address(router));
    }

    function testPreviewGenesisMakerFees_MapsFeesCorrectly() external {
        uint256 verseId = 1;
        address upt = address(0x1000);
        address memecoin = address(0x2000);
        address liquidProof = address(0x3000);

        IMemeverseLauncher.Memeverse memory verse;
        verse.UPT = upt;
        verse.memecoin = memecoin;
        verse.liquidProof = liquidProof;
        verse.currentStage = IMemeverseLauncher.Stage.Locked;
        verse.omnichainIds = new uint32[](1);
        verse.omnichainIds[0] = uint32(block.chainid);

        launcher.setMemeverseForTest(verseId, verse);

        router.setQuote(memecoin, upt, address(launcher), 11 ether, 22 ether);
        router.setQuote(liquidProof, upt, address(launcher), 33 ether, 44 ether);

        (uint256 uptFee, uint256 memecoinFee) = launcher.previewGenesisMakerFees(verseId);

        assertEq(memecoinFee, 22 ether, "memecoin fee");
        assertEq(uptFee, 44 ether, "upt fee");
    }

    function testPreviewGenesisMakerFees_RevertsWhenNotLocked() external {
        uint256 verseId = 1;
        IMemeverseLauncher.Memeverse memory verse;
        verse.currentStage = IMemeverseLauncher.Stage.Genesis;
        launcher.setMemeverseForTest(verseId, verse);

        vm.expectRevert(IMemeverseLauncher.NotReachedLockedStage.selector);
        launcher.previewGenesisMakerFees(verseId);
    }
}
