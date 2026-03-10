// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";

import {MemeverseLauncher} from "../src/verse/MemeverseLauncher.sol";
import {IMemeverseSwapRouter} from "../src/swap/interfaces/IMemeverseSwapRouter.sol";

contract MemeverseLauncherHarness is MemeverseLauncher {
    constructor(address owner_)
        MemeverseLauncher(owner_, address(0), address(0), address(0), address(0), address(0), 0, 0, 0)
    {}

    function exposedDeployLiquidity(
        uint256 verseId,
        address UPT,
        address memecoin,
        address pol,
        uint128 totalMemecoinFunds,
        uint128 totalLiquidProofFunds
    ) external {
        _deployLiquidity(verseId, UPT, memecoin, pol, totalMemecoinFunds, totalLiquidProofFunds);
    }
}

contract MockLauncherRouter {
    uint256 public callCount;
    address public firstTokenA;
    address public firstTokenB;
    uint256 public firstAmountADesired;
    uint256 public firstAmountBDesired;
    address public secondTokenA;
    address public secondTokenB;
    uint256 public secondAmountADesired;
    uint256 public secondAmountBDesired;

    uint128 internal immutable firstLiquidity;
    uint128 internal immutable secondLiquidity;
    PoolKey internal firstPoolKey;

    constructor(uint128 firstLiquidity_, uint128 secondLiquidity_, PoolKey memory firstPoolKey_) {
        firstLiquidity = firstLiquidity_;
        secondLiquidity = secondLiquidity_;
        firstPoolKey = firstPoolKey_;
    }

    function createPoolAndAddLiquidity(IMemeverseSwapRouter.CreatePoolAndAddLiquidityParams calldata params)
        external
        returns (uint128 liquidity, PoolKey memory poolKey)
    {
        callCount++;

        if (callCount == 1) {
            firstTokenA = params.tokenA;
            firstTokenB = params.tokenB;
            firstAmountADesired = params.amountADesired;
            firstAmountBDesired = params.amountBDesired;
            return (firstLiquidity, firstPoolKey);
        }

        secondTokenA = params.tokenA;
        secondTokenB = params.tokenB;
        secondAmountADesired = params.amountADesired;
        secondAmountBDesired = params.amountBDesired;
        return (secondLiquidity, firstPoolKey);
    }
}

contract MockMemecoin {
    uint256 public totalMinted;

    function mint(address, uint256 amount) external {
        totalMinted += amount;
    }
}

contract MockMemeLiquidProof {
    PoolId public poolId;
    uint256 public totalMinted;

    function mint(address, uint256 amount) external {
        totalMinted += amount;
    }

    function setPoolId(PoolId poolId_) external {
        poolId = poolId_;
    }
}

contract MemeverseLauncherLiquidityRouterTest is Test {
    using PoolIdLibrary for PoolKey;

    uint256 internal constant VERSE_ID = 1;
    uint128 internal constant TOTAL_MEMECOIN_FUNDS = 100 ether;
    uint128 internal constant TOTAL_LIQUID_PROOF_FUNDS = 50 ether;
    uint256 internal constant FUND_BASED_AMOUNT = 1_000;
    uint128 internal constant EXPECTED_MEMECOIN_LIQUIDITY = 90 ether;
    uint128 internal constant EXPECTED_POL_LIQUIDITY = 30 ether;

    MemeverseLauncherHarness internal harness;
    MockLauncherRouter internal mockRouter;
    MockMemecoin internal memecoin;
    MockMemeLiquidProof internal liquidProof;
    address internal UPT = address(0x1234);
    PoolKey internal expectedPoolKey;

    function setUp() external {
        harness = new MemeverseLauncherHarness(address(this));
        memecoin = new MockMemecoin();
        liquidProof = new MockMemeLiquidProof();

        expectedPoolKey = PoolKey({
            currency0: Currency.wrap(address(memecoin) < UPT ? address(memecoin) : UPT),
            currency1: Currency.wrap(address(memecoin) < UPT ? UPT : address(memecoin)),
            fee: 0x800000,
            tickSpacing: 200,
            hooks: IHooks(address(0xBEEF))
        });
        mockRouter = new MockLauncherRouter(
            EXPECTED_MEMECOIN_LIQUIDITY, EXPECTED_POL_LIQUIDITY, expectedPoolKey
        );

        harness.setFundMetaData(UPT, 1, FUND_BASED_AMOUNT);
        harness.setLiquidityRouter(address(mockRouter));
    }

    function testDeployLiquidity_UsesSwapRouterForBothPools() external {
        harness.exposedDeployLiquidity(
            VERSE_ID,
            UPT,
            address(memecoin),
            address(liquidProof),
            TOTAL_MEMECOIN_FUNDS,
            TOTAL_LIQUID_PROOF_FUNDS
        );

        uint256 expectedMemecoinAmount = uint256(TOTAL_MEMECOIN_FUNDS) * FUND_BASED_AMOUNT;
        uint256 expectedDeployedPOL = uint256(EXPECTED_MEMECOIN_LIQUIDITY) / 3;

        assertEq(mockRouter.callCount(), 2, "router call count");
        assertEq(mockRouter.firstTokenA(), address(memecoin), "first tokenA");
        assertEq(mockRouter.firstTokenB(), UPT, "first tokenB");
        assertEq(mockRouter.firstAmountADesired(), expectedMemecoinAmount, "first amountA");
        assertEq(mockRouter.firstAmountBDesired(), TOTAL_MEMECOIN_FUNDS, "first amountB");
        assertEq(mockRouter.secondTokenA(), address(liquidProof), "second tokenA");
        assertEq(mockRouter.secondTokenB(), UPT, "second tokenB");
        assertEq(mockRouter.secondAmountADesired(), expectedDeployedPOL, "second amountA");
        assertEq(mockRouter.secondAmountBDesired(), TOTAL_LIQUID_PROOF_FUNDS, "second amountB");
        assertEq(PoolId.unwrap(liquidProof.poolId()), PoolId.unwrap(expectedPoolKey.toId()), "pool id");
        assertEq(harness.totalPolLiquidity(VERSE_ID), EXPECTED_POL_LIQUIDITY, "pol liquidity");
        assertEq(
            harness.totalClaimablePOL(VERSE_ID),
            uint256(EXPECTED_MEMECOIN_LIQUIDITY) - expectedDeployedPOL,
            "claimable pol"
        );
    }
}
