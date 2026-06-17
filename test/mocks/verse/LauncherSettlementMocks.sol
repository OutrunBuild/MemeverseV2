// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta, toBalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";

import {IMemeverseUniswapHook} from "../../../src/swap/interfaces/IMemeverseUniswapHook.sol";

/// @notice Universal asset mock that also supports a repay() path used by settlement tests.
contract UniversalAssetForPOLendSettlementInvariant is MockERC20 {
    uint256 public repaidAmount;

    constructor() MockERC20("UASSET", "UASSET", 18) {}

    function mint(address to, uint256 amount) public override {
        _mint(to, amount);
    }

    function repay(address account, uint256 amount) external {
        if (account != msg.sender) {
            uint256 allowed = allowance[account][msg.sender];
            require(allowed >= amount, "insufficient allowance");
            allowance[account][msg.sender] = allowed - amount;
        }
        repaidAmount += amount;
        _burn(account, amount);
    }
}

contract LPTokenForPOLendSettlementInvariant is MockERC20 {
    constructor(string memory name_, string memory symbol_) MockERC20(name_, symbol_, 18) {}

    function mint(address to, uint256 amount) public override {
        _mint(to, amount);
    }
}

contract HookForPOLendSettlementInvariant {
    address public immutable launcher;
    address public poolInitializer;
    mapping(bytes32 => uint40) public publicSwapResumeTimes;
    mapping(bytes32 => FeeQuote) internal claimQuotes;

    struct FeeQuote {
        uint256 fee0;
        uint256 fee1;
    }

    constructor(address launcher_) {
        launcher = launcher_;
    }

    function setClaimQuote(address tokenA, address tokenB, uint256 tokenAFee, uint256 tokenBFee) external {
        (uint256 fee0, uint256 fee1) = tokenA < tokenB ? (tokenAFee, tokenBFee) : (tokenBFee, tokenAFee);
        claimQuotes[_pairKey(tokenA, tokenB)] = FeeQuote({fee0: fee0, fee1: fee1});
    }

    function setPoolInitializer(address poolInitializer_) external {
        poolInitializer = poolInitializer_;
    }

    function setPublicSwapResumeTime(address tokenA, address tokenB, uint40 resumeTime) external {
        require(msg.sender == launcher, "not launcher");
        publicSwapResumeTimes[_pairKey(tokenA, tokenB)] = resumeTime;
    }

    function claimableFees(PoolKey calldata key, address)
        external
        view
        returns (uint256 fee0Amount, uint256 fee1Amount)
    {
        FeeQuote memory quote = claimQuotes[_pairKey(Currency.unwrap(key.currency0), Currency.unwrap(key.currency1))];
        return (quote.fee0, quote.fee1);
    }

    function claimFeesCore(IMemeverseUniswapHook.ClaimFeesCoreParams calldata params)
        external
        returns (uint256 fee0Amount, uint256 fee1Amount)
    {
        address token0 = Currency.unwrap(params.key.currency0);
        address token1 = Currency.unwrap(params.key.currency1);
        FeeQuote memory quote = claimQuotes[_pairKey(token0, token1)];
        fee0Amount = quote.fee0;
        fee1Amount = quote.fee1;
        delete claimQuotes[_pairKey(token0, token1)];

        if (fee0Amount != 0) _pay(token0, params.recipient, fee0Amount);
        if (fee1Amount != 0) _pay(token1, params.recipient, fee1Amount);
    }

    function _pay(address token, address recipient, uint256 amount) internal {
        if (MockERC20(token).balanceOf(address(this)) >= amount) {
            require(MockERC20(token).transfer(recipient, amount), "transfer failed");
        } else {
            UniversalAssetForPOLendSettlementInvariant(token).mint(recipient, amount);
        }
    }

    function _pairKey(address tokenA, address tokenB) internal pure returns (bytes32) {
        return keccak256(abi.encode(tokenA < tokenB ? tokenA : tokenB, tokenA < tokenB ? tokenB : tokenA));
    }
}

contract RouterForPOLendSettlementInvariant {
    address internal immutable hookAddress;
    uint128 internal createLiquidityResult;
    uint128 internal defaultAddLiquidityResult;
    mapping(bytes32 => address) internal lpTokens;
    mapping(bytes32 => uint128) internal pairCreateLiquidityResults;
    mapping(bytes32 => uint128) internal pairAddLiquidityResults;
    mapping(bytes32 => PairSpend) internal pairCreateSpends;
    mapping(bytes32 => mapping(address => uint256)) internal pairTokenPulled;
    mapping(bytes32 => PairQuote) internal exactLiquidityQuotes;
    mapping(bytes32 => PairOutputRate) internal outputRates;

    struct PairOutputRate {
        uint256 amount0PerLp;
        uint256 amount1PerLp;
    }

    struct PairQuote {
        uint256 amount0Required;
        uint256 amount1Required;
    }

    struct PairSpend {
        bool enabled;
        uint256 amount0Used;
        uint256 amount1Used;
    }

    constructor(address hookAddress_) {
        hookAddress = hookAddress_;
    }

    function hook() external view returns (address) {
        return hookAddress;
    }

    function setCreateLiquidityResult(uint128 liquidity) external {
        createLiquidityResult = liquidity;
    }

    function setPairCreateLiquidityResult(address tokenA, address tokenB, uint128 liquidity) external {
        pairCreateLiquidityResults[_pairKey(tokenA, tokenB)] = liquidity;
    }

    function setPairAddLiquidityResult(address tokenA, address tokenB, uint128 liquidity) external {
        pairAddLiquidityResults[_pairKey(tokenA, tokenB)] = liquidity;
    }

    function setPairCreateSpend(address tokenA, address tokenB, uint256 tokenAUsed, uint256 tokenBUsed) external {
        (uint256 amount0Used, uint256 amount1Used) =
            tokenA < tokenB ? (tokenAUsed, tokenBUsed) : (tokenBUsed, tokenAUsed);
        pairCreateSpends[_pairKey(tokenA, tokenB)] =
            PairSpend({enabled: true, amount0Used: amount0Used, amount1Used: amount1Used});
    }

    function pulledForPair(address tokenA, address tokenB, address token) external view returns (uint256) {
        return pairTokenPulled[_pairKey(tokenA, tokenB)][token];
    }

    function setExactLiquidityQuote(address tokenA, address tokenB, uint256 tokenARequired, uint256 tokenBRequired)
        external
    {
        (uint256 amount0Required, uint256 amount1Required) =
            tokenA < tokenB ? (tokenARequired, tokenBRequired) : (tokenBRequired, tokenARequired);
        exactLiquidityQuotes[_pairKey(tokenA, tokenB)] =
            PairQuote({amount0Required: amount0Required, amount1Required: amount1Required});
    }

    function setDefaultAddLiquidityResult(uint128 liquidity) external {
        defaultAddLiquidityResult = liquidity;
    }

    function setLpToken(address tokenA, address tokenB, address liquidityToken) external {
        lpTokens[_pairKey(tokenA, tokenB)] = liquidityToken;
    }

    function lpToken(address tokenA, address tokenB) external view returns (address liquidityToken) {
        return lpTokens[_pairKey(tokenA, tokenB)];
    }

    function setPairOutputPerLp(address tokenA, address tokenB, uint256 tokenAOutPerLp, uint256 tokenBOutPerLp)
        external
    {
        (uint256 amount0PerLp, uint256 amount1PerLp) =
            tokenA < tokenB ? (tokenAOutPerLp, tokenBOutPerLp) : (tokenBOutPerLp, tokenAOutPerLp);
        outputRates[_pairKey(tokenA, tokenB)] = PairOutputRate({amount0PerLp: amount0PerLp, amount1PerLp: amount1PerLp});
    }

    function createPoolAndAddLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint160,
        address to,
        uint256
    ) external returns (uint128 liquidity, PoolKey memory poolKey, uint256 amountAUsed, uint256 amountBUsed) {
        (amountAUsed, amountBUsed) = _createSpendForPair(tokenA, tokenB, amountADesired, amountBDesired);
        _pull(tokenA, amountAUsed);
        _pull(tokenB, amountBUsed);
        pairTokenPulled[_pairKey(tokenA, tokenB)][tokenA] += amountAUsed;
        pairTokenPulled[_pairKey(tokenA, tokenB)][tokenB] += amountBUsed;
        liquidity = _createLiquidityForPair(tokenA, tokenB);
        LPTokenForPOLendSettlementInvariant(_lpTokenOrCreate(tokenA, tokenB)).mint(to, liquidity);
        poolKey = PoolKey({
            currency0: Currency.wrap(tokenA < tokenB ? tokenA : tokenB),
            currency1: Currency.wrap(tokenA < tokenB ? tokenB : tokenA),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 200,
            hooks: IHooks(hookAddress)
        });
    }

    function addLiquidity(
        Currency currency0,
        Currency currency1,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256,
        uint256,
        address to,
        uint256
    ) external returns (uint128 liquidity) {
        address token0 = Currency.unwrap(currency0);
        address token1 = Currency.unwrap(currency1);
        _pull(token0, amount0Desired);
        _pull(token1, amount1Desired);
        liquidity = defaultAddLiquidityResult;
        LPTokenForPOLendSettlementInvariant(_lpTokenOrCreate(token0, token1)).mint(to, liquidity);
    }

    function quoteExactAmountsForLiquidity(address tokenA, address tokenB, uint128)
        external
        view
        returns (uint256 amountARequired, uint256 amountBRequired)
    {
        PairQuote memory quote = exactLiquidityQuotes[_pairKey(tokenA, tokenB)];
        if (tokenA < tokenB) return (quote.amount0Required, quote.amount1Required);
        return (quote.amount1Required, quote.amount0Required);
    }

    function addLiquidityDetailed(
        Currency currency0,
        Currency currency1,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        address to,
        uint256
    ) external returns (uint128 liquidity, uint256 amount0Used, uint256 amount1Used) {
        require(amount0Desired >= amount0Min, "amount0 below min");
        require(amount1Desired >= amount1Min, "amount1 below min");
        address token0 = Currency.unwrap(currency0);
        address token1 = Currency.unwrap(currency1);
        _pull(token0, amount0Desired);
        _pull(token1, amount1Desired);
        liquidity = pairAddLiquidityResults[_pairKey(token0, token1)];
        if (liquidity == 0) liquidity = defaultAddLiquidityResult;
        LPTokenForPOLendSettlementInvariant(_lpTokenOrCreate(token0, token1)).mint(to, liquidity);
        return (liquidity, amount0Desired, amount1Desired);
    }

    function removeLiquidity(
        Currency currency0,
        Currency currency1,
        uint128 liquidity,
        uint256,
        uint256,
        address to,
        uint256
    ) external returns (BalanceDelta delta) {
        address tokenA = Currency.unwrap(currency0);
        address tokenB = Currency.unwrap(currency1);
        bytes32 pairKey = _pairKey(tokenA, tokenB);
        require(MockERC20(lpTokens[pairKey]).transferFrom(msg.sender, address(this), liquidity), "transfer failed");

        PairOutputRate memory rate = outputRates[pairKey];
        uint256 amount0Out = uint256(liquidity) * rate.amount0PerLp / 1 ether;
        uint256 amount1Out = uint256(liquidity) * rate.amount1PerLp / 1 ether;
        address token0 = tokenA < tokenB ? tokenA : tokenB;
        address token1 = tokenA < tokenB ? tokenB : tokenA;
        if (amount0Out != 0) _pay(token0, to, amount0Out);
        if (amount1Out != 0) _pay(token1, to, amount1Out);
        return toBalanceDelta(int128(uint128(amount0Out)), int128(uint128(amount1Out)));
    }

    function _pull(address token, uint256 amount) internal {
        if (amount != 0) require(MockERC20(token).transferFrom(msg.sender, address(this), amount), "transfer failed");
    }

    function _lpTokenOrCreate(address tokenA, address tokenB) internal returns (address liquidityToken) {
        bytes32 pairKey = _pairKey(tokenA, tokenB);
        liquidityToken = lpTokens[pairKey];
        if (liquidityToken == address(0)) {
            liquidityToken = address(new LPTokenForPOLendSettlementInvariant("AUTO-LP", "AUTO-LP"));
            lpTokens[pairKey] = liquidityToken;
        }
    }

    function _createLiquidityForPair(address tokenA, address tokenB) internal view returns (uint128 liquidity) {
        liquidity = pairCreateLiquidityResults[_pairKey(tokenA, tokenB)];
        if (liquidity != 0) return liquidity;
        if (defaultAddLiquidityResult != 0) return defaultAddLiquidityResult;
        return createLiquidityResult;
    }

    function _pay(address token, address to, uint256 amount) internal {
        if (MockERC20(token).balanceOf(address(this)) >= amount) {
            require(MockERC20(token).transfer(to, amount), "transfer failed");
        } else {
            UniversalAssetForPOLendSettlementInvariant(token).mint(to, amount);
        }
    }

    function _createSpendForPair(address tokenA, address tokenB, uint256 amountADesired, uint256 amountBDesired)
        internal
        view
        returns (uint256 amountAUsed, uint256 amountBUsed)
    {
        PairSpend memory spend = pairCreateSpends[_pairKey(tokenA, tokenB)];
        if (!spend.enabled) return (amountADesired, amountBDesired);
        if (tokenA < tokenB) return (spend.amount0Used, spend.amount1Used);
        return (spend.amount1Used, spend.amount0Used);
    }

    function _pairKey(address tokenA, address tokenB) internal pure returns (bytes32) {
        return keccak256(abi.encode(tokenA < tokenB ? tokenA : tokenB, tokenA < tokenB ? tokenB : tokenA));
    }
}
