// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

import {IERC20} from "../common/token/OutrunERC20Init.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {OutrunSafeERC20} from "../yield/libraries/OutrunSafeERC20.sol";
import {ReentrancyGuard} from "../common/access/ReentrancyGuard.sol";
import {IPOLend} from "./interfaces/IPOLend.sol";
import {IPOLSplitter} from "./interfaces/IPOLSplitter.sol";
import {IUniversalAssets} from "./interfaces/IUniversalAssets.sol";
import {IMemeverseLauncher} from "../verse/interfaces/IMemeverseLauncher.sol";

contract POLend layout at erc7201("outrun.storage.POLend")
    is
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    PausableUpgradeable,
    ReentrancyGuard,
    IPOLend
{
    using OutrunSafeERC20 for IERC20;

    uint8 internal constant CLAIM_REFUND = 1 << 0;
    uint8 internal constant CLAIM_LEVERAGED_YT = 1 << 1;
    uint8 internal constant CLAIM_RESIDUAL = 1 << 2;
    uint256 internal constant MIN_LEVERAGED_DEBT_PRODUCT = 1e36;
    uint256 internal constant MAX_SUPPORTED_TOTAL_GENESIS_FUNDS = type(uint128).max;
    uint256 internal constant MAX_LEVERAGED_DEBT_FACTOR = uint256(type(uint128).max) * 1e18;

    /// @custom:storage-location erc7201:outrun.storage.POLend
    struct POLendStorage {
        uint256 defaultInterestRate;
        uint256 leveragedDebtFactor;
        address treasury;
        address launcher;
        address splitter;
        mapping(uint256 => LendMarket) lendMarkets;
        mapping(uint256 => mapping(address => uint256)) leveragedInterestPaid;
        mapping(uint256 => ResidualState) residualStates;
        mapping(address => uint256) globalDebtByUAsset;
        mapping(address uAsset => SettlementDustState state) settlementDustStates;
        mapping(uint256 => mapping(address => uint8)) claimFlags;
    }

    POLendStorage private polendStorage;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    modifier onlyLauncher() {
        if (msg.sender != polendStorage.launcher) revert PermissionDenied();
        _;
    }

    modifier onlySplitter() {
        if (msg.sender != polendStorage.splitter) revert PermissionDenied();
        _;
    }

    function initialize(
        address initialOwner,
        uint256 interestRate_,
        uint256 leveragedDebtFactor_,
        address treasury_,
        address launcher_,
        address splitter_
    ) external initializer {
        if (interestRate_ == 0) revert ZeroInput();
        if (interestRate_ > 1e18) revert InvalidConfig();
        if (treasury_ == address(0) || launcher_ == address(0) || splitter_ == address(0)) revert ZeroInput();
        _validateLeverageConfig(interestRate_, leveragedDebtFactor_);

        __Ownable_init(initialOwner);
        __Pausable_init();

        polendStorage.defaultInterestRate = interestRate_;
        polendStorage.leveragedDebtFactor = leveragedDebtFactor_;
        polendStorage.treasury = treasury_;
        polendStorage.launcher = launcher_;
        polendStorage.splitter = splitter_;
    }

    function setProtocolTreasury(address newTreasury) external onlyOwner {
        if (newTreasury == address(0)) revert ZeroInput();

        address oldTreasury = polendStorage.treasury;
        polendStorage.treasury = newTreasury;
        emit ProtocolTreasuryChanged(oldTreasury, newTreasury);
    }

    function setDefaultInterestRate(uint256 newRate) external onlyOwner {
        if (newRate == 0) revert ZeroInput();
        if (newRate > 1e18) revert InvalidConfig();

        _validateLeverageConfig(newRate, polendStorage.leveragedDebtFactor);
        uint256 oldRate = polendStorage.defaultInterestRate;
        polendStorage.defaultInterestRate = newRate;
        emit DefaultInterestRateChanged(oldRate, newRate);
    }

    function setLeveragedDebtFactor(uint256 newFactor) external onlyOwner {
        _validateLeverageConfig(polendStorage.defaultInterestRate, newFactor);
        uint256 oldFactor = polendStorage.leveragedDebtFactor;
        polendStorage.leveragedDebtFactor = newFactor;
        emit LeveragedDebtFactorChanged(oldFactor, newFactor);
    }

    function setMaxSettlementDustReserve(address uAsset, uint128 maxReserve) external onlyOwner {
        if (uAsset == address(0) || maxReserve == 0) revert ZeroInput();

        SettlementDustState storage state = polendStorage.settlementDustStates[uAsset];
        if (state.reserve > maxReserve) revert InvalidConfig();
        uint128 oldMaxReserve = state.maxReserve;
        state.maxReserve = maxReserve;
        emit SettlementDustReserveConfigured(uAsset, oldMaxReserve, maxReserve);
    }

    function registerLendMarket(uint256 verseId) external onlyLauncher {
        if (polendStorage.lendMarkets[verseId].uAsset != address(0)) revert InvalidState();
        _validateLeverageConfig(polendStorage.defaultInterestRate, polendStorage.leveragedDebtFactor);
        address uAsset = IMemeverseLauncher(polendStorage.launcher).getUAssetByVerseId(verseId);
        if (uAsset == address(0)) revert ZeroInput();
        if (polendStorage.settlementDustStates[uAsset].maxReserve == 0) revert InvalidConfig();
        polendStorage.lendMarkets[verseId] = LendMarket({
            uAsset: uAsset,
            yt: address(0),
            interestRate: polendStorage.defaultInterestRate,
            totalLeveragedInterest: 0,
            totalLeveragedYT: 0,
            state: MarketState.None
        });
    }

    function leveragedGenesis(uint256 verseId, uint256 interestAmount)
        external
        whenNotPaused
        returns (uint256 borrowedAmount)
    {
        if (interestAmount == 0) revert ZeroInput();

        LendMarket storage market = polendStorage.lendMarkets[verseId];
        if (market.interestRate == 0) revert InvalidState();
        if (market.state != MarketState.None && market.state != MarketState.Genesis) revert InvalidState();
        address marketUAsset = market.uAsset;
        if (IMemeverseLauncher(polendStorage.launcher).getStageByVerseId(verseId) != IMemeverseLauncher.Stage.Genesis) {
            revert InvalidState();
        }
        uint256 actualNormalFunds = IMemeverseLauncher(polendStorage.launcher).totalNormalFunds(verseId);
        if (actualNormalFunds > MAX_SUPPORTED_TOTAL_GENESIS_FUNDS) revert InvalidConfig();

        uint256 nextTotalInterest = market.totalLeveragedInterest + interestAmount;
        uint256 previewTotalDebt = Math.mulDiv(nextTotalInterest, 1e18, market.interestRate);
        // Aggregate genesis funds include all leveraged debt already accumulated for the verse.
        if (previewTotalDebt > MAX_SUPPORTED_TOTAL_GENESIS_FUNDS - actualNormalFunds) revert InvalidConfig();
        if (previewTotalDebt > _debtCap(verseId)) revert DebtCapExceeded();

        borrowedAmount = Math.mulDiv(interestAmount, 1e18, market.interestRate);
        polendStorage.leveragedInterestPaid[verseId][msg.sender] += interestAmount;
        market.totalLeveragedInterest = nextTotalInterest;
        if (market.state == MarketState.None) market.state = MarketState.Genesis;
        IERC20(marketUAsset).safeTransferFrom(msg.sender, address(this), interestAmount);
        emit LeveragedGenesis(verseId, msg.sender, interestAmount);
    }

    function markRefundable(uint256 verseId) external onlyLauncher {
        LendMarket storage market = polendStorage.lendMarkets[verseId];
        if (market.state != MarketState.Genesis) revert InvalidState();
        market.state = MarketState.Refund;
    }

    function finalizeLeveragedGenesis(uint256 verseId) external onlyLauncher {
        LendMarket storage market = polendStorage.lendMarkets[verseId];
        if (market.state != MarketState.Genesis) revert InvalidState();
        uint256 debt = _totalLeveragedDebt(market);
        if (debt == 0) revert InvalidState();

        address marketUAsset = market.uAsset;
        uint256 totalLeveragedInterest = market.totalLeveragedInterest;
        (uint256 credited, uint256 treasuryInterest, uint256 reserveAfter) =
            _creditSettlementDustReserve(marketUAsset, totalLeveragedInterest);

        market.state = MarketState.Locked;
        polendStorage.globalDebtByUAsset[marketUAsset] += debt;

        IUniversalAssets(marketUAsset).mint(polendStorage.launcher, debt);
        if (treasuryInterest != 0) IERC20(marketUAsset).safeTransfer(polendStorage.treasury, treasuryInterest);
        emit SettlementDustReservedFromInterest(
            verseId, marketUAsset, totalLeveragedInterest, credited, treasuryInterest, reserveAfter
        );
    }

    function recordLeveragedYT(uint256 verseId, address yt, uint256 totalLeveragedYT) external onlyLauncher {
        LendMarket storage market = polendStorage.lendMarkets[verseId];
        if (market.state != MarketState.Locked || market.yt != address(0)) revert InvalidState();
        if (yt == address(0) || totalLeveragedYT == 0) revert ZeroInput();
        market.yt = yt;
        market.totalLeveragedYT = totalLeveragedYT;
    }

    function executeGlobalSettlement(uint256 verseId) external onlyLauncher nonReentrant {
        LendMarket storage market = polendStorage.lendMarkets[verseId];
        if (market.state != MarketState.Locked) revert InvalidState();
        address marketUAsset = market.uAsset;

        (uint256 polAmount, uint256 ptAmount, uint256 lpUAsset) =
            IMemeverseLauncher(polendStorage.launcher).settleLeveragedAuxiliaryLiquidity(verseId);
        (uint256 burnedPolUAsset, uint256 burnedPolMemecoin) = _burnSettledPol(verseId, polAmount);
        uint256 redeemedPtUAsset;
        if (ptAmount != 0) {
            redeemedPtUAsset = IPOLSplitter(polendStorage.splitter).redeemPT(verseId, ptAmount, address(this));
        }

        uint256 totalRecoveredUAsset = lpUAsset + burnedPolUAsset + redeemedPtUAsset;
        uint256 debt = _totalLeveragedDebt(market);
        SettlementDustState storage dustState = polendStorage.settlementDustStates[marketUAsset];
        uint256 reserveBeforeSettlement = dustState.reserve;
        uint256 reserveAfterSettlement = reserveBeforeSettlement;
        uint256 consumedSettlementDustReserve;
        uint256 residualUAsset;

        if (totalRecoveredUAsset >= debt) {
            residualUAsset = totalRecoveredUAsset - debt;
        } else {
            uint256 deficit = debt - totalRecoveredUAsset;
            if (deficit > reserveBeforeSettlement) revert SettlementDustInsufficient(deficit, reserveBeforeSettlement);
            consumedSettlementDustReserve = deficit;
            reserveAfterSettlement = reserveBeforeSettlement - deficit;
            dustState.reserve = uint128(reserveAfterSettlement);
            emit SettlementDustReserveConsumed(verseId, marketUAsset, deficit, reserveAfterSettlement);
        }

        polendStorage.residualStates[verseId] =
            ResidualState({residualUAsset: residualUAsset, residualMemecoin: burnedPolMemecoin});
        market.state = MarketState.Settled;
        if (debt != 0) polendStorage.globalDebtByUAsset[marketUAsset] -= debt;

        if (debt != 0) IUniversalAssets(marketUAsset).repay(address(this), debt);

        emit GlobalSettlementExecuted(
            verseId,
            marketUAsset,
            debt,
            totalRecoveredUAsset,
            consumedSettlementDustReserve,
            reserveAfterSettlement,
            residualUAsset,
            burnedPolMemecoin
        );
    }

    function fundSettlementDustReserve(address uAsset, uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroInput();

        SettlementDustState storage state = polendStorage.settlementDustStates[uAsset];
        uint256 maxReserve = state.maxReserve;
        if (maxReserve == 0) revert InvalidConfig();

        uint256 reserve = state.reserve;
        uint256 capacity = maxReserve - reserve;
        bool fromLauncher = msg.sender == polendStorage.launcher;
        if (!fromLauncher && amount > capacity) revert SettlementDustReserveExceeded(amount, capacity);

        IERC20(uAsset).safeTransferFrom(msg.sender, address(this), amount);
        uint256 credited = Math.min(amount, capacity);
        uint256 excess = amount - credited;
        state.reserve = uint128(reserve + credited);
        if (excess != 0) IERC20(uAsset).safeTransfer(polendStorage.treasury, excess);
        emit SettlementDustReserveFunded(uAsset, msg.sender, amount, credited, excess);
    }

    function preRedeemPTFee(uint256 verseId, uint256 ptAmount, address mintTo)
        external
        onlyLauncher
        returns (uint256 uAssetBacking)
    {
        if (ptAmount == 0 || mintTo == address(0)) revert ZeroInput();

        LendMarket storage market = polendStorage.lendMarkets[verseId];
        if (market.state != MarketState.Locked) revert InvalidState();

        uAssetBacking = IPOLSplitter(polendStorage.splitter).preRedeemPTFee(verseId, ptAmount);
        polendStorage.globalDebtByUAsset[market.uAsset] += uAssetBacking;
        IUniversalAssets(market.uAsset).mint(mintTo, uAssetBacking);
        emit PreRedeemPTFee(verseId, market.uAsset, ptAmount, uAssetBacking, mintTo);
    }

    function burnPreRedeemedBacking(uint256 verseId, uint256 amount) external onlySplitter {
        if (amount == 0) revert ZeroInput();

        address marketUAsset = polendStorage.lendMarkets[verseId].uAsset;
        polendStorage.globalDebtByUAsset[marketUAsset] -= amount;
        IUniversalAssets(marketUAsset).repay(polendStorage.splitter, amount);
    }

    function claimRefund(uint256 verseId, address to) external nonReentrant returns (uint256 refundedAmount) {
        if (to == address(0)) revert ZeroInput();

        LendMarket storage market = polendStorage.lendMarkets[verseId];
        if (market.state != MarketState.Refund) revert InvalidState();

        refundedAmount = polendStorage.leveragedInterestPaid[verseId][msg.sender];
        if (refundedAmount == 0) revert InvalidClaim();

        _consumeClaimFlag(verseId, msg.sender, CLAIM_REFUND);
        IERC20(market.uAsset).safeTransfer(to, refundedAmount);
        emit ClaimRefund(verseId, msg.sender, to, refundedAmount);
    }

    function claimLeveragedYT(uint256 verseId, address to) external nonReentrant returns (uint256 amount) {
        if (to == address(0)) revert ZeroInput();

        LendMarket storage market = polendStorage.lendMarkets[verseId];
        if (market.state != MarketState.Locked && market.state != MarketState.Settled) revert InvalidState();

        uint256 interestPaid = polendStorage.leveragedInterestPaid[verseId][msg.sender];
        uint256 totalLeveragedInterest = market.totalLeveragedInterest;
        if (interestPaid == 0 || totalLeveragedInterest == 0) revert InvalidClaim();

        _consumeClaimFlag(verseId, msg.sender, CLAIM_LEVERAGED_YT);
        amount = Math.mulDiv(market.totalLeveragedYT, interestPaid, totalLeveragedInterest);
        IERC20(market.yt).safeTransfer(to, amount);
        emit ClaimLeveragedYT(verseId, msg.sender, to, amount);
    }

    function claimResidual(uint256 verseId, address to)
        external
        nonReentrant
        returns (uint256 uAssetAmount, uint256 memecoinAmount)
    {
        if (to == address(0)) revert ZeroInput();

        LendMarket storage market = polendStorage.lendMarkets[verseId];
        if (market.state != MarketState.Settled) revert InvalidState();

        uint256 interestPaid = polendStorage.leveragedInterestPaid[verseId][msg.sender];
        uint256 totalLeveragedInterest = market.totalLeveragedInterest;
        if (interestPaid == 0 || totalLeveragedInterest == 0) revert InvalidClaim();

        _consumeClaimFlag(verseId, msg.sender, CLAIM_RESIDUAL);

        ResidualState storage residual = polendStorage.residualStates[verseId];
        uAssetAmount = Math.mulDiv(residual.residualUAsset, interestPaid, totalLeveragedInterest);
        memecoinAmount = Math.mulDiv(residual.residualMemecoin, interestPaid, totalLeveragedInterest);

        if (uAssetAmount != 0) IERC20(market.uAsset).safeTransfer(to, uAssetAmount);
        if (memecoinAmount != 0) {
            address memecoin = IPOLSplitter(polendStorage.splitter).getMemecoin(verseId);
            IERC20(memecoin).safeTransfer(to, memecoinAmount);
        }
        emit ClaimResidual(verseId, msg.sender, to, uAssetAmount, memecoinAmount);
    }

    // --- View functions (replacing auto-generated public getters) ---

    function defaultInterestRate() external view returns (uint256) {
        return polendStorage.defaultInterestRate;
    }

    function leveragedDebtFactor() external view returns (uint256) {
        return polendStorage.leveragedDebtFactor;
    }

    function treasury() external view returns (address) {
        return polendStorage.treasury;
    }

    function launcher() external view returns (address) {
        return polendStorage.launcher;
    }

    function splitter() external view returns (address) {
        return polendStorage.splitter;
    }

    function lendMarkets(uint256 verseId) external view returns (LendMarket memory) {
        return polendStorage.lendMarkets[verseId];
    }

    function leveragedInterestPaid(uint256 verseId, address user) external view returns (uint256) {
        return polendStorage.leveragedInterestPaid[verseId][user];
    }

    function residualStates(uint256 verseId) external view returns (uint256 residualUAsset, uint256 residualMemecoin) {
        ResidualState storage r = polendStorage.residualStates[verseId];
        residualUAsset = r.residualUAsset;
        residualMemecoin = r.residualMemecoin;
    }

    function globalDebtByUAsset(address uAsset) external view returns (uint256) {
        return polendStorage.globalDebtByUAsset[uAsset];
    }

    function settlementDustStates(address uAsset) external view returns (uint128 reserve, uint128 maxReserve) {
        SettlementDustState storage state = polendStorage.settlementDustStates[uAsset];
        return (state.reserve, state.maxReserve);
    }

    // --- External view helpers ---

    function getTotalLeveragedDebt(uint256 verseId) external view returns (uint256) {
        return _totalLeveragedDebt(polendStorage.lendMarkets[verseId]);
    }

    function getUserLeveragedDebt(uint256 verseId, address user) external view returns (uint256) {
        if (user == address(0)) revert ZeroInput();

        LendMarket storage market = polendStorage.lendMarkets[verseId];
        if (market.interestRate == 0) revert InvalidState();
        return Math.mulDiv(polendStorage.leveragedInterestPaid[verseId][user], 1e18, market.interestRate);
    }

    function getTotalDebtByUAsset(address uAsset) external view returns (uint256) {
        if (uAsset == address(0)) revert ZeroInput();
        return polendStorage.globalDebtByUAsset[uAsset];
    }

    function getLeveragedDebtInfo(uint256 verseId) external view returns (LeveragedDebtInfo memory info) {
        LendMarket storage market = polendStorage.lendMarkets[verseId];
        if (market.interestRate == 0) revert InvalidState();

        info.totalLeveragedInterest = market.totalLeveragedInterest;
        info.totalLeveragedDebt = _totalLeveragedDebt(market);
        info.interestRate = market.interestRate;
        (info.debtCap, info.remainingAdditionalInterest) = _debtCapacity(verseId, market);
    }

    function getTotalLeveragedInterest(uint256 verseId) external view returns (uint256) {
        return polendStorage.lendMarkets[verseId].totalLeveragedInterest;
    }

    function getLendMarket(uint256 verseId) external view returns (LendMarket memory market) {
        return polendStorage.lendMarkets[verseId];
    }

    // --- Internal ---

    function _totalLeveragedDebt(LendMarket storage market) internal view returns (uint256) {
        if (market.interestRate == 0) revert InvalidState();
        return Math.mulDiv(market.totalLeveragedInterest, 1e18, market.interestRate);
    }

    function _debtCapacity(uint256 verseId, LendMarket storage market)
        internal
        view
        returns (uint256 debtCap, uint256 remainingAdditionalInterest)
    {
        if (market.state != MarketState.None && market.state != MarketState.Genesis) return (0, 0);
        if (polendStorage.settlementDustStates[market.uAsset].maxReserve == 0) return (0, 0);
        if (IMemeverseLauncher(polendStorage.launcher).getStageByVerseId(verseId) != IMemeverseLauncher.Stage.Genesis) {
            return (0, 0);
        }

        debtCap = _debtCap(verseId);
        uint256 actualNormalFunds = IMemeverseLauncher(polendStorage.launcher).totalNormalFunds(verseId);
        if (actualNormalFunds >= MAX_SUPPORTED_TOTAL_GENESIS_FUNDS) return (0, 0);
        uint256 aggregateDebtCap = MAX_SUPPORTED_TOTAL_GENESIS_FUNDS - actualNormalFunds;
        if (debtCap > aggregateDebtCap) debtCap = aggregateDebtCap;
        uint256 maxTotalInterest;
        if (debtCap == type(uint256).max) {
            uint256 q = type(uint256).max / 1e18;
            uint256 r = type(uint256).max % 1e18;
            maxTotalInterest =
                q * market.interestRate + Math.mulDiv(r + 1, market.interestRate, 1e18, Math.Rounding.Ceil) - 1;
        } else {
            maxTotalInterest = Math.mulDiv(debtCap + 1, market.interestRate, 1e18, Math.Rounding.Ceil) - 1;
        }
        uint256 totalInterest = market.totalLeveragedInterest;
        if (maxTotalInterest > totalInterest) remainingAdditionalInterest = maxTotalInterest - totalInterest;
    }

    function _validateLeverageConfig(uint256 interestRate, uint256 debtFactor) internal pure {
        if (debtFactor == 0) revert ZeroInput();
        if (debtFactor > MAX_LEVERAGED_DEBT_FACTOR) revert InvalidConfig();

        uint256 minDebtFactor = Math.mulDiv(MIN_LEVERAGED_DEBT_PRODUCT, 1, interestRate, Math.Rounding.Ceil);
        if (debtFactor < minDebtFactor) revert InvalidConfig();
    }

    function _debtCap(uint256 verseId) internal view returns (uint256) {
        uint256 capBase = IMemeverseLauncher(polendStorage.launcher).getDebtCapBaseByVerseId(verseId);
        return _mulDiv1e18Saturating(polendStorage.leveragedDebtFactor, capBase);
    }

    function _mulDiv1e18Saturating(uint256 a, uint256 b) internal pure returns (uint256 result) {
        unchecked {
            uint256 prod0;
            uint256 prod1;
            assembly ("memory-safe") {
                let mm := mulmod(a, b, not(0))
                prod0 := mul(a, b)
                prod1 := sub(sub(mm, prod0), lt(mm, prod0))
            }

            // Saturate when floor(a * b / 1e18) would be >= type(uint256).max.
            // (2^256 - 1) * 1e18 = (1e18 - 1) * 2^256 + (2^256 - 1e18)
            if (prod1 > 1e18 - 1) return type(uint256).max;
            if (prod1 == 1e18 - 1 && prod0 >= type(uint256).max - (1e18 - 1)) return type(uint256).max;

            return Math.mulDiv(a, b, 1e18);
        }
    }

    function _creditSettlementDustReserve(address uAsset, uint256 amount)
        internal
        returns (uint256 credited, uint256 excess, uint256 reserveAfter)
    {
        SettlementDustState storage state = polendStorage.settlementDustStates[uAsset];
        uint256 maxReserve = state.maxReserve;
        if (maxReserve == 0) revert InvalidConfig();

        uint256 reserve = state.reserve;
        uint256 capacity = maxReserve - reserve;
        credited = Math.min(amount, capacity);
        excess = amount - credited;
        reserveAfter = reserve + credited;
        state.reserve = uint128(reserveAfter);
    }

    function _consumeClaimFlag(uint256 verseId, address account, uint8 mask) internal {
        uint8 flags = polendStorage.claimFlags[verseId][account];
        if (flags & mask != 0) revert InvalidClaim();
        polendStorage.claimFlags[verseId][account] = flags | mask;
    }

    function _burnSettledPol(uint256 verseId, uint256 polAmount)
        internal
        returns (uint256 uAssetAmount, uint256 memecoinAmount)
    {
        if (polAmount == 0) return (0, 0);

        LendMarket storage market = polendStorage.lendMarkets[verseId];
        (address pol, address memecoin) = IPOLSplitter(polendStorage.splitter).getPOLAndMemecoin(verseId);
        uint256 beforeUAsset = IERC20(market.uAsset).balanceOf(address(this));
        uint256 beforeMemecoin = IERC20(memecoin).balanceOf(address(this));

        IERC20(pol).approve(polendStorage.launcher, polAmount);
        IMemeverseLauncher(polendStorage.launcher).redeemMemecoinLiquidity(verseId, polAmount, true);

        uAssetAmount = IERC20(market.uAsset).balanceOf(address(this)) - beforeUAsset;
        memecoinAmount = IERC20(memecoin).balanceOf(address(this)) - beforeMemecoin;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function _authorizeUpgrade(address) internal view override onlyOwner {}
}
