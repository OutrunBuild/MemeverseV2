// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {MemeverseLauncher} from "../src/verse/MemeverseLauncher.sol";
import {IMemeverseLauncher} from "../src/verse/interfaces/IMemeverseLauncher.sol";

contract MockSwapRouter {
    using SafeERC20 for IERC20;

    struct Quote {
        uint256 fee0;
        uint256 fee1;
    }

    struct AddLiquidityResult {
        uint128 liquidity;
        uint256 amount0Used;
        uint256 amount1Used;
    }

    mapping(bytes32 => Quote) internal previewQuotes;
    mapping(bytes32 => Quote) internal claimQuotes;
    mapping(bytes32 => address) internal lpTokens;
    mapping(bytes32 => AddLiquidityResult) internal addLiquidityResults;
    mapping(bytes32 => uint256) internal liquidityQuoteAmountA;
    mapping(bytes32 => uint256) internal liquidityQuoteAmountB;

    function _pairKey(address tokenA, address tokenB) internal pure returns (bytes32) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        return keccak256(abi.encode(token0, token1));
    }

    function _liquidityKey(address tokenA, address tokenB, uint128 liquidityDesired) internal pure returns (bytes32) {
        return keccak256(abi.encode(_pairKey(tokenA, tokenB), liquidityDesired));
    }

    /// @notice Sets both preview and claim fee quotes for a token pair and owner.
    /// @dev Used by tests to keep preview and redemption expectations aligned.
    /// @param tokenA First token in the pair.
    /// @param tokenB Second token in the pair.
    /// @param owner Owner whose quote should be returned.
    /// @param fee0 Mock fee amount for token0.
    /// @param fee1 Mock fee amount for token1.
    function setQuote(address tokenA, address tokenB, address owner, uint256 fee0, uint256 fee1) external {
        setPreviewQuote(tokenA, tokenB, owner, fee0, fee1);
        setClaimQuote(tokenA, tokenB, owner, fee0, fee1);
    }

    /// @notice Sets the preview fee quote for a token pair and owner.
    /// @dev Stores fees using normalized token ordering.
    /// @param tokenA First token in the pair.
    /// @param tokenB Second token in the pair.
    /// @param owner Owner whose preview quote should be returned.
    /// @param fee0 Mock fee amount for token0.
    /// @param fee1 Mock fee amount for token1.
    function setPreviewQuote(address tokenA, address tokenB, address owner, uint256 fee0, uint256 fee1) public {
        previewQuotes[keccak256(abi.encode(_pairKey(tokenA, tokenB), owner))] = Quote({fee0: fee0, fee1: fee1});
    }

    /// @notice Sets the claim fee quote for a token pair and owner.
    /// @dev Stores fees using normalized token ordering.
    /// @param tokenA First token in the pair.
    /// @param tokenB Second token in the pair.
    /// @param owner Owner whose claim quote should be returned.
    /// @param fee0 Mock fee amount for token0.
    /// @param fee1 Mock fee amount for token1.
    function setClaimQuote(address tokenA, address tokenB, address owner, uint256 fee0, uint256 fee1) public {
        claimQuotes[keccak256(abi.encode(_pairKey(tokenA, tokenB), owner))] = Quote({fee0: fee0, fee1: fee1});
    }

    /// @notice Sets the LP token returned for a token pair.
    /// @dev Stores the LP token using normalized token ordering.
    /// @param tokenA First token in the pair.
    /// @param tokenB Second token in the pair.
    /// @param liquidityToken Mock LP token address for the pair.
    function setLpToken(address tokenA, address tokenB, address liquidityToken) external {
        lpTokens[_pairKey(tokenA, tokenB)] = liquidityToken;
    }

    /// @notice Sets the mocked add-liquidity execution result for a pair.
    /// @dev Stores the actual token usage and LP liquidity that `addLiquidity(...)` should produce.
    /// @param tokenA First token in the pair.
    /// @param tokenB Second token in the pair.
    /// @param liquidity Mock LP liquidity to mint.
    /// @param amountAUsed Mock amount of `tokenA` consumed.
    /// @param amountBUsed Mock amount of `tokenB` consumed.
    function setAddLiquidityResult(
        address tokenA,
        address tokenB,
        uint128 liquidity,
        uint256 amountAUsed,
        uint256 amountBUsed
    ) external {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        (uint256 amount0Used, uint256 amount1Used) =
            tokenA < tokenB ? (amountAUsed, amountBUsed) : (amountBUsed, amountAUsed);
        addLiquidityResults[_pairKey(token0, token1)] =
            AddLiquidityResult({liquidity: liquidity, amount0Used: amount0Used, amount1Used: amount1Used});
    }

    /// @notice Sets the mocked exact-liquidity quote for a pair.
    /// @dev Stores the required input amounts using the caller-facing token order.
    /// @param tokenA First token in the pair.
    /// @param tokenB Second token in the pair.
    /// @param liquidityDesired Target liquidity to quote.
    /// @param amountARequired Mock required amount of `tokenA`.
    /// @param amountBRequired Mock required amount of `tokenB`.
    function setQuoteAmountsForLiquidity(
        address tokenA,
        address tokenB,
        uint128 liquidityDesired,
        uint256 amountARequired,
        uint256 amountBRequired
    ) external {
        bytes32 key = _liquidityKey(tokenA, tokenB, liquidityDesired);
        liquidityQuoteAmountA[key] = amountARequired;
        liquidityQuoteAmountB[key] = amountBRequired;
    }

    /// @notice Returns the mocked preview fees for a token pair and owner.
    /// @dev Mimics router-side pair normalization.
    /// @param tokenA First token in the pair.
    /// @param tokenB Second token in the pair.
    /// @param owner Owner whose preview quote is requested.
    /// @return fee0 Mock fee amount for token0.
    /// @return fee1 Mock fee amount for token1.
    function previewClaimableFees(address tokenA, address tokenB, address owner)
        external
        view
        returns (uint256 fee0, uint256 fee1)
    {
        Quote memory quote = previewQuotes[keccak256(abi.encode(_pairKey(tokenA, tokenB), owner))];
        return (quote.fee0, quote.fee1);
    }

    /// @notice Returns the mocked LP token for a token pair.
    /// @dev Mimics router-side pair normalization.
    /// @param tokenA First token in the pair.
    /// @param tokenB Second token in the pair.
    /// @return liquidityToken Mock LP token address for the pair.
    function lpToken(address tokenA, address tokenB) external view returns (address liquidityToken) {
        return lpTokens[_pairKey(tokenA, tokenB)];
    }

    /// @notice Returns the mocked required token amounts for a target liquidity.
    /// @dev Reads the caller-facing token-order quote seeded by the test.
    /// @param tokenA First token in the pair.
    /// @param tokenB Second token in the pair.
    /// @param liquidityDesired Target liquidity to quote.
    /// @return amountARequired Mock required amount of `tokenA`.
    /// @return amountBRequired Mock required amount of `tokenB`.
    function quoteAmountsForLiquidity(address tokenA, address tokenB, uint128 liquidityDesired)
        external
        view
        returns (uint256 amountARequired, uint256 amountBRequired)
    {
        bytes32 key = _liquidityKey(tokenA, tokenB, liquidityDesired);
        return (liquidityQuoteAmountA[key], liquidityQuoteAmountB[key]);
    }

    /// @notice Returns a normalized mock pool key for a token pair.
    /// @dev Matches the launcher's expectations for router pool-key derivation.
    /// @param tokenA First token in the pair.
    /// @param tokenB Second token in the pair.
    /// @return key Mock pool key for the pair.
    function getHookPoolKey(address tokenA, address tokenB) external pure returns (PoolKey memory key) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        return PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: 0,
            tickSpacing: 0,
            hooks: IHooks(address(0))
        });
    }

    /// @notice Mints mocked claim fees to the requested recipient.
    /// @dev Uses the caller as the fee owner, matching launcher integration tests.
    /// @param key Mock pool key whose fees are claimed.
    /// @param recipient Recipient of the mocked claimed fees.
    /// @param deadline Unused mock signature deadline.
    /// @param v Unused mock signature recovery byte.
    /// @param r Unused mock signature r value.
    /// @param s Unused mock signature s value.
    /// @return fee0 Mock claimed fee amount for token0.
    /// @return fee1 Mock claimed fee amount for token1.
    function claimFees(PoolKey calldata key, address recipient, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
        returns (uint256 fee0, uint256 fee1)
    {
        deadline;
        v;
        r;
        s;
        address token0 = Currency.unwrap(key.currency0);
        address token1 = Currency.unwrap(key.currency1);
        Quote memory quote = claimQuotes[keccak256(abi.encode(_pairKey(token0, token1), msg.sender))];

        fee0 = quote.fee0;
        fee1 = quote.fee1;

        if (fee0 != 0) MockERC20(token0).mint(recipient, fee0);
        if (fee1 != 0) MockERC20(token1).mint(recipient, fee1);
    }

    /// @notice Executes a mocked add-liquidity call for a pair.
    /// @dev Pulls the configured used amounts from the caller and mints mock LP shares to `to`.
    /// @param currency0 First pool currency.
    /// @param currency1 Second pool currency.
    /// @param amount0Desired Unused desired amount for `currency0`.
    /// @param amount1Desired Unused desired amount for `currency1`.
    /// @param amount0Min Unused minimum amount for `currency0`.
    /// @param amount1Min Unused minimum amount for `currency1`.
    /// @param to Recipient of the mocked LP shares.
    /// @param nativeRefundRecipient Unused native refund recipient.
    /// @param deadline Unused deadline.
    /// @return liquidity Mock LP liquidity minted to `to`.
    function addLiquidity(
        Currency currency0,
        Currency currency1,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        address to,
        address nativeRefundRecipient,
        uint256 deadline
    ) external returns (uint128 liquidity) {
        amount0Desired;
        amount1Desired;
        amount0Min;
        amount1Min;
        nativeRefundRecipient;
        deadline;

        address token0 = Currency.unwrap(currency0);
        address token1 = Currency.unwrap(currency1);
        AddLiquidityResult memory result = addLiquidityResults[_pairKey(token0, token1)];
        if (result.amount0Used != 0) IERC20(token0).safeTransferFrom(msg.sender, address(this), result.amount0Used);
        if (result.amount1Used != 0) IERC20(token1).safeTransferFrom(msg.sender, address(this), result.amount1Used);

        address liquidityToken = lpTokens[_pairKey(token0, token1)];
        if (result.liquidity != 0 && liquidityToken != address(0)) {
            MockERC20(liquidityToken).mint(to, result.liquidity);
        }
        return result.liquidity;
    }
}

contract MockLiquidProof is MockERC20 {
    uint256 public burnedAmount;

    constructor() MockERC20("POL", "POL", 18) {}

    /// @notice Burns POL from an account and records the amount.
    /// @dev Extends the mock token so tests can assert the burn side effect.
    /// @param from Account whose balance is burned.
    /// @param value Amount of POL to burn.
    function burn(address from, uint256 value) public override {
        burnedAmount += value;
        super.burn(from, value);
    }
}

contract MockOFTDispatcher {
    uint256 public composeCallCount;
    address public lastToken;
    bytes public lastMessage;

    /// @notice Records a mocked compose dispatch.
    /// @dev Stores the last token and payload for launcher fee-distribution assertions.
    /// @param _from Token address associated with the compose message.
    /// @param _guid Unused mock compose guid.
    /// @param _message Mock compose payload.
    /// @param _executor Unused mock executor address.
    /// @param _extraData Unused mock extra data.
    function lzCompose(
        address _from,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) external payable {
        _guid;
        _executor;
        _extraData;
        composeCallCount++;
        lastToken = _from;
        lastMessage = _message;
    }
}

contract TestableMemeverseLauncher is MemeverseLauncher {
    constructor(
        address _owner,
        address _localLzEndpoint,
        address _memeverseRegistrar,
        address _memeverseProxyDeployer,
        address _oftDispatcher,
        address _lzEndpointRegistry,
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
            _lzEndpointRegistry,
            _executorRewardRate,
            _oftReceiveGasLimit,
            _oftDispatcherGasLimit
        )
    {}

    /// @notice Stores mock memeverse state for a verse id.
    /// @dev Exposes direct storage writes needed by unit tests.
    /// @param verseId Verse id whose state should be set.
    /// @param verse Mock memeverse state to store.
    function setMemeverseForTest(uint256 verseId, Memeverse memory verse) external {
        memeverses[verseId] = verse;
    }

    /// @notice Stores mock genesis fund totals for a verse id.
    /// @dev Lets tests control redemption share math directly.
    /// @param verseId Verse id whose genesis totals should be set.
    /// @param totalMemecoinFunds Mock memecoin-side genesis total.
    /// @param totalLiquidProofFunds Mock liquid-proof-side genesis total.
    function setGenesisFundForTest(uint256 verseId, uint128 totalMemecoinFunds, uint128 totalLiquidProofFunds)
        external
    {
        genesisFunds[verseId] =
            GenesisFund({totalMemecoinFunds: totalMemecoinFunds, totalLiquidProofFunds: totalLiquidProofFunds});
    }

    /// @notice Stores mock user genesis data for a verse id.
    /// @dev Lets tests control redemption eligibility flags directly.
    /// @param verseId Verse id whose user state should be set.
    /// @param account Account whose genesis data should be set.
    /// @param genesisFund Mock contributed genesis amount.
    /// @param isRefunded Mock refunded flag.
    /// @param isClaimed Mock claimed flag.
    /// @param isRedeemed Mock redeemed flag.
    function setUserGenesisDataForTest(
        uint256 verseId,
        address account,
        uint256 genesisFund,
        bool isRefunded,
        bool isClaimed,
        bool isRedeemed
    ) external {
        userGenesisData[verseId][account] = GenesisData({
            genesisFund: genesisFund, isRefunded: isRefunded, isClaimed: isClaimed, isRedeemed: isRedeemed
        });
    }

    /// @notice Stores mock total POL liquidity for a verse id.
    /// @dev Used to drive POL LP redemption share math in tests.
    /// @param verseId Verse id whose total POL liquidity should be set.
    /// @param amount Mock total POL liquidity amount.
    function setTotalPolLiquidityForTest(uint256 verseId, uint256 amount) external {
        totalPolLiquidity[verseId] = amount;
    }
}

contract MemeverseLauncherPreviewFeesTest is Test {
    TestableMemeverseLauncher internal launcher;
    MockSwapRouter internal router;
    MockOFTDispatcher internal dispatcher;
    MockERC20 internal upt;
    MockERC20 internal memecoin;
    MockLiquidProof internal liquidProof;

    address internal constant REWARD_RECEIVER = address(0xBEEF);
    address internal constant ALICE = address(0xA11CE);

    /// @notice Deploys the launcher test harness and supporting mocks.
    /// @dev Wires the launcher to the mock router and mock dispatcher.
    function setUp() external {
        launcher = new TestableMemeverseLauncher(
            address(this), address(0x1), address(0x2), address(0x3), address(0x4), address(0x5), 25, 115_000, 135_000
        );
        router = new MockSwapRouter();
        dispatcher = new MockOFTDispatcher();
        upt = new MockERC20("UPT", "UPT", 18);
        memecoin = new MockERC20("MEME", "MEME", 18);
        liquidProof = new MockLiquidProof();

        launcher.setMemeverseSwapRouter(address(router));
        launcher.setOFTDispatcher(address(dispatcher));
    }

    function _setLockedVerse(uint256 verseId) internal {
        IMemeverseLauncher.Memeverse memory verse;
        verse.UPT = address(upt);
        verse.memecoin = address(memecoin);
        verse.liquidProof = address(liquidProof);
        verse.governor = address(0xCAFE);
        verse.yieldVault = address(0xD00D);
        verse.currentStage = IMemeverseLauncher.Stage.Locked;
        verse.omnichainIds = new uint32[](1);
        verse.omnichainIds[0] = uint32(block.chainid);
        launcher.setMemeverseForTest(verseId, verse);
    }

    function _setUnlockedVerse(uint256 verseId) internal {
        _setLockedVerse(verseId);
        IMemeverseLauncher.Memeverse memory verse = launcher.getMemeverseByVerseId(verseId);
        verse.currentStage = IMemeverseLauncher.Stage.Unlocked;
        launcher.setMemeverseForTest(verseId, verse);
    }

    function _approveMintInputs(address user) internal {
        vm.startPrank(user);
        upt.approve(address(launcher), type(uint256).max);
        memecoin.approve(address(launcher), type(uint256).max);
        vm.stopPrank();
    }

    /// @notice Verifies preview fee mapping preserves token ordering for both pools.
    /// @dev Ensures the launcher maps router fee0/fee1 outputs back to semantic token names.
    function testPreviewGenesisMakerFees_MapsFeesCorrectly() external {
        uint256 verseId = 1;
        _setLockedVerse(verseId);

        router.setQuote(address(memecoin), address(upt), address(launcher), 11 ether, 22 ether);
        router.setQuote(address(liquidProof), address(upt), address(launcher), 33 ether, 44 ether);

        (uint256 uptFee, uint256 memecoinFee) = launcher.previewGenesisMakerFees(verseId);

        assertEq(memecoinFee, 22 ether, "memecoin fee");
        assertEq(uptFee, 44 ether, "upt fee");
    }

    /// @notice Verifies previewing fees reverts before the locked stage.
    /// @dev The launcher must not preview LP fees during genesis.
    function testPreviewGenesisMakerFees_RevertsWhenNotLocked() external {
        uint256 verseId = 1;
        IMemeverseLauncher.Memeverse memory verse;
        verse.currentStage = IMemeverseLauncher.Stage.Genesis;
        launcher.setMemeverseForTest(verseId, verse);

        vm.expectRevert(IMemeverseLauncher.NotReachedLockedStage.selector);
        launcher.previewGenesisMakerFees(verseId);
    }

    /// @notice Verifies fee redemption reverts before the locked stage.
    /// @dev The launcher must not claim or distribute fees during genesis.
    function testRedeemAndDistributeFees_RevertsWhenNotLocked() external {
        uint256 verseId = 1;
        IMemeverseLauncher.Memeverse memory verse;
        verse.currentStage = IMemeverseLauncher.Stage.Genesis;
        launcher.setMemeverseForTest(verseId, verse);

        vm.expectRevert(IMemeverseLauncher.NotReachedLockedStage.selector);
        launcher.redeemAndDistributeFees(verseId, REWARD_RECEIVER);
    }

    /// @notice Verifies fee redemption returns zero values when no fees are claimable.
    /// @dev Confirms the early-return path does not mutate balances.
    function testRedeemAndDistributeFees_ReturnsZeroWhenNoFees() external {
        uint256 verseId = 1;
        _setLockedVerse(verseId);

        (uint256 govFee, uint256 memecoinFee, uint256 liquidProofFee, uint256 executorReward) =
            launcher.redeemAndDistributeFees(verseId, REWARD_RECEIVER);

        assertEq(govFee, 0, "govFee");
        assertEq(memecoinFee, 0, "memecoinFee");
        assertEq(liquidProofFee, 0, "liquidProofFee");
        assertEq(executorReward, 0, "executorReward");
    }

    /// @notice Verifies same-chain fee redemption claims, burns, and dispatches the expected assets.
    /// @dev Covers the restored fee distribution flow through the mock dispatcher.
    function testRedeemAndDistributeFees_SameChainClaimsAndDistributesFees() external {
        uint256 verseId = 1;
        _setLockedVerse(verseId);

        router.setClaimQuote(address(memecoin), address(upt), address(launcher), 20 ether, 7 ether);
        router.setClaimQuote(address(liquidProof), address(upt), address(launcher), 12 ether, 5 ether);

        (uint256 govFee, uint256 memecoinFee, uint256 liquidProofFee, uint256 executorReward) =
            launcher.redeemAndDistributeFees(verseId, REWARD_RECEIVER);

        assertEq(memecoinFee, 7 ether, "memecoin fee");
        assertEq(liquidProofFee, 5 ether, "liquid proof fee");
        assertEq(executorReward, 0.08 ether, "executor reward");
        assertEq(govFee, 31.92 ether, "gov fee");

        assertEq(upt.balanceOf(REWARD_RECEIVER), executorReward, "reward receiver UPT");
        assertEq(upt.balanceOf(address(dispatcher)), govFee, "dispatcher UPT");
        assertEq(memecoin.balanceOf(address(dispatcher)), memecoinFee, "dispatcher memecoin");
        assertEq(liquidProof.burnedAmount(), liquidProofFee, "burned liquid proof");
        assertEq(dispatcher.composeCallCount(), 2, "compose call count");
        assertEq(upt.balanceOf(address(launcher)), 0, "launcher UPT");
        assertEq(memecoin.balanceOf(address(launcher)), 0, "launcher memecoin");
        assertEq(liquidProof.balanceOf(address(launcher)), 0, "launcher liquid proof");
    }

    /// @notice Verifies preview fee mapping matches actual redemption fee mapping.
    /// @dev Prevents preview and claim flows from drifting on token ordering.
    function testPreviewAndRedeemShareTheSameFeeMapping() external {
        uint256 verseId = 1;
        _setLockedVerse(verseId);

        router.setPreviewQuote(address(memecoin), address(upt), address(launcher), 9 ether, 4 ether);
        router.setPreviewQuote(address(liquidProof), address(upt), address(launcher), 13 ether, 6 ether);
        router.setClaimQuote(address(memecoin), address(upt), address(launcher), 9 ether, 4 ether);
        router.setClaimQuote(address(liquidProof), address(upt), address(launcher), 13 ether, 6 ether);

        (uint256 previewUptFee, uint256 previewMemecoinFee) = launcher.previewGenesisMakerFees(verseId);
        (uint256 govFee, uint256 memecoinFee,, uint256 executorReward) =
            launcher.redeemAndDistributeFees(verseId, REWARD_RECEIVER);

        assertEq(previewMemecoinFee, memecoinFee, "memecoin mapping");
        assertEq(previewUptFee, govFee + executorReward, "UPT mapping");
    }

    /// @notice Verifies memecoin LP redemption rejects zero POL input.
    /// @dev Confirms the restored zero-input guard is active.
    function testRedeemMemecoinLiquidity_RevertsOnZeroInput() external {
        uint256 verseId = 1;
        _setUnlockedVerse(verseId);

        vm.expectRevert(IMemeverseLauncher.ZeroInput.selector);
        launcher.redeemMemecoinLiquidity(verseId, 0);
    }

    /// @notice Verifies memecoin LP redemption rejects non-unlocked verses.
    /// @dev Confirms the restored stage guard is active.
    function testRedeemMemecoinLiquidity_RevertsWhenNotUnlocked() external {
        uint256 verseId = 1;
        _setLockedVerse(verseId);

        vm.expectRevert(IMemeverseLauncher.NotUnlockedStage.selector);
        launcher.redeemMemecoinLiquidity(verseId, 1 ether);
    }

    /// @notice Verifies memecoin LP redemption burns POL and transfers pair LP shares.
    /// @dev Covers the restored router-based pair LP lookup in the happy path.
    function testRedeemMemecoinLiquidity_BurnsPOLAndTransfersMemecoinLp() external {
        uint256 verseId = 1;
        _setUnlockedVerse(verseId);

        MockERC20 memecoinLp = new MockERC20("MEME-LP", "MEME-LP", 18);
        router.setLpToken(address(memecoin), address(upt), address(memecoinLp));
        memecoinLp.mint(address(launcher), 10 ether);
        liquidProof.mint(ALICE, 10 ether);

        vm.prank(ALICE);
        uint256 amountInLP = launcher.redeemMemecoinLiquidity(verseId, 4 ether);

        assertEq(amountInLP, 4 ether, "lp amount");
        assertEq(liquidProof.burnedAmount(), 4 ether, "burned pol");
        assertEq(liquidProof.balanceOf(ALICE), 6 ether, "alice pol balance");
        assertEq(memecoinLp.balanceOf(ALICE), 4 ether, "alice memecoin lp");
        assertEq(memecoinLp.balanceOf(address(launcher)), 6 ether, "launcher memecoin lp");
    }

    /// @notice Verifies POL LP redemption rejects non-unlocked verses.
    /// @dev Confirms the restored stage guard is active for genesis-share redemption.
    function testRedeemPolLiquidity_RevertsWhenNotUnlocked() external {
        uint256 verseId = 1;
        _setLockedVerse(verseId);
        launcher.setUserGenesisDataForTest(verseId, ALICE, 1 ether, false, false, false);

        vm.prank(ALICE);
        vm.expectRevert(IMemeverseLauncher.NotUnlockedStage.selector);
        launcher.redeemPolLiquidity(verseId);
    }

    /// @notice Verifies POL LP redemption rejects accounts that already redeemed.
    /// @dev Confirms the single-claim protection is preserved.
    function testRedeemPolLiquidity_RevertsWhenAlreadyRedeemed() external {
        uint256 verseId = 1;
        _setUnlockedVerse(verseId);
        launcher.setUserGenesisDataForTest(verseId, ALICE, 1 ether, false, false, true);

        vm.prank(ALICE);
        vm.expectRevert(IMemeverseLauncher.InvalidRedeem.selector);
        launcher.redeemPolLiquidity(verseId);
    }

    /// @notice Verifies POL LP redemption transfers the caller's genesis share of POL LP.
    /// @dev Covers router-based LP lookup and redeemed-flag mutation in the happy path.
    function testRedeemPolLiquidity_TransfersPolLpByGenesisShare() external {
        uint256 verseId = 1;
        _setUnlockedVerse(verseId);

        MockERC20 polLp = new MockERC20("POL-LP", "POL-LP", 18);
        router.setLpToken(address(liquidProof), address(upt), address(polLp));
        polLp.mint(address(launcher), 60 ether);
        launcher.setGenesisFundForTest(verseId, 90 ether, 30 ether);
        launcher.setUserGenesisDataForTest(verseId, ALICE, 24 ether, false, false, false);
        launcher.setTotalPolLiquidityForTest(verseId, 60 ether);

        vm.prank(ALICE);
        uint256 amountInLP = launcher.redeemPolLiquidity(verseId);

        (, bool isRefunded, bool isClaimed, bool isRedeemed) = launcher.userGenesisData(verseId, ALICE);
        assertEq(amountInLP, 12 ether, "lp amount");
        assertEq(polLp.balanceOf(ALICE), 12 ether, "alice pol lp");
        assertEq(polLp.balanceOf(address(launcher)), 48 ether, "launcher pol lp");
        assertFalse(isRefunded, "is refunded");
        assertFalse(isClaimed, "is claimed");
        assertTrue(isRedeemed, "is redeemed");
    }

    /// @notice Verifies mintPOLToken rejects zero input budgets.
    /// @dev Confirms the restored zero-input guard is active.
    function testMintPOLToken_RevertsOnZeroInput() external {
        uint256 verseId = 1;
        _setLockedVerse(verseId);

        vm.expectRevert(IMemeverseLauncher.ZeroInput.selector);
        launcher.mintPOLToken(verseId, 0, 1 ether, 0, 0, 0, block.timestamp);
    }

    /// @notice Verifies mintPOLToken rejects verses before the locked stage.
    /// @dev Confirms the restored stage guard is active.
    function testMintPOLToken_RevertsWhenBeforeLocked() external {
        uint256 verseId = 1;
        IMemeverseLauncher.Memeverse memory verse;
        verse.currentStage = IMemeverseLauncher.Stage.Genesis;
        verse.UPT = address(upt);
        verse.memecoin = address(memecoin);
        launcher.setMemeverseForTest(verseId, verse);

        vm.expectRevert(IMemeverseLauncher.NotReachedLockedStage.selector);
        launcher.mintPOLToken(verseId, 1 ether, 1 ether, 0, 0, 0, block.timestamp);
    }

    /// @notice Verifies automatic liquidity minting refunds unused inputs and mints matching POL.
    /// @dev Covers the `amountOutDesired == 0` router path.
    function testMintPOLToken_WithAutoLiquidity_RefundsUnusedInputsAndMintsPol() external {
        uint256 verseId = 1;
        _setLockedVerse(verseId);

        MockERC20 memecoinLp = new MockERC20("MEME-LP", "MEME-LP", 18);
        router.setLpToken(address(memecoin), address(upt), address(memecoinLp));
        router.setAddLiquidityResult(address(upt), address(memecoin), 8 ether, 6 ether, 10 ether);

        upt.mint(ALICE, 9 ether);
        memecoin.mint(ALICE, 13 ether);
        _approveMintInputs(ALICE);

        vm.prank(ALICE);
        (uint256 amountInUPT, uint256 amountInMemecoin, uint256 amountOut) =
            launcher.mintPOLToken(verseId, 9 ether, 13 ether, 5 ether, 8 ether, 0, block.timestamp);

        assertEq(amountInUPT, 6 ether, "upt used");
        assertEq(amountInMemecoin, 10 ether, "memecoin used");
        assertEq(amountOut, 8 ether, "pol out");
        assertEq(upt.balanceOf(ALICE), 3 ether, "upt refund");
        assertEq(memecoin.balanceOf(ALICE), 3 ether, "memecoin refund");
        assertEq(liquidProof.balanceOf(ALICE), 8 ether, "alice pol");
        assertEq(memecoinLp.balanceOf(address(launcher)), 8 ether, "launcher lp");
    }

    /// @notice Verifies exact-liquidity minting uses the router quote and mints the requested POL.
    /// @dev Covers the `amountOutDesired != 0` router path.
    function testMintPOLToken_WithExactLiquidity_UsesRouterQuoteAndMintsRequestedPol() external {
        uint256 verseId = 1;
        _setLockedVerse(verseId);

        MockERC20 memecoinLp = new MockERC20("MEME-LP", "MEME-LP", 18);
        router.setLpToken(address(memecoin), address(upt), address(memecoinLp));
        router.setQuoteAmountsForLiquidity(address(upt), address(memecoin), 5 ether, 7 ether, 9 ether);
        router.setAddLiquidityResult(address(upt), address(memecoin), 5 ether, 7 ether, 9 ether);

        upt.mint(ALICE, 10 ether);
        memecoin.mint(ALICE, 12 ether);
        _approveMintInputs(ALICE);

        vm.prank(ALICE);
        (uint256 amountInUPT, uint256 amountInMemecoin, uint256 amountOut) =
            launcher.mintPOLToken(verseId, 10 ether, 12 ether, 0, 0, 5 ether, block.timestamp);

        assertEq(amountInUPT, 7 ether, "upt used");
        assertEq(amountInMemecoin, 9 ether, "memecoin used");
        assertEq(amountOut, 5 ether, "pol out");
        assertEq(upt.balanceOf(ALICE), 3 ether, "upt refund");
        assertEq(memecoin.balanceOf(ALICE), 3 ether, "memecoin refund");
        assertEq(liquidProof.balanceOf(ALICE), 5 ether, "alice pol");
        assertEq(memecoinLp.balanceOf(address(launcher)), 5 ether, "launcher lp");
    }

    /// @notice Verifies exact-liquidity minting reverts when the router quote exceeds the caller budget.
    /// @dev Confirms the launcher does not over-consume user inputs in exact mode.
    function testMintPOLToken_WithExactLiquidity_RevertsWhenQuoteExceedsBudget() external {
        uint256 verseId = 1;
        _setLockedVerse(verseId);

        router.setQuoteAmountsForLiquidity(address(upt), address(memecoin), 5 ether, 11 ether, 9 ether);
        upt.mint(ALICE, 10 ether);
        memecoin.mint(ALICE, 12 ether);
        _approveMintInputs(ALICE);

        vm.prank(ALICE);
        vm.expectRevert();
        launcher.mintPOLToken(verseId, 10 ether, 12 ether, 0, 0, 5 ether, block.timestamp);
    }
}
