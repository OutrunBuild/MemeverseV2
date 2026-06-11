// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.30;

import {IERC20} from "../common/token/OutrunERC20Init.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";

import {OutrunSafeERC20} from "../yield/libraries/OutrunSafeERC20.sol";
import {ReentrancyGuard} from "../common/access/ReentrancyGuard.sol";
import {IPOLend} from "./interfaces/IPOLend.sol";
import {IPOLSplitter} from "./interfaces/IPOLSplitter.sol";
import {PrincipalToken} from "./tokens/PrincipalToken.sol";
import {YieldToken} from "./tokens/YieldToken.sol";
import {IMemeverseLauncher} from "../verse/interfaces/IMemeverseLauncher.sol";

contract POLSplitter is Initializable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuard, IPOLSplitter {
    using OutrunSafeERC20 for IERC20;
    using Clones for address;

    /// @custom:storage-location erc7201:outrun.storage.POLSplitter
    struct POLSplitterStorage {
        mapping(uint256 verseId => SplitInfo) splitInfos;
        mapping(uint256 verseId => PreRedeemedState state) preRedeemedStates;
        address launcher;
        address polend;
        address principalTokenImplementation;
        address yieldTokenImplementation;
    }

    // keccak256(abi.encode(uint256(keccak256("outrun.storage.POLSplitter")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant POL_SPLITTER_STORAGE_LOCATION =
        0xab504a6dee30096d32ccac13a30a002829c5eeb4c38a0196ed16a6c4e9faca00;

    function _getPOLSplitterStorage() private pure returns (POLSplitterStorage storage $) {
        assembly {
            $.slot := POL_SPLITTER_STORAGE_LOCATION
        }
    }

    function splitInfos(uint256 verseId)
        external
        view
        returns (
            address pt,
            address yt,
            address pol,
            address memecoin,
            address uAsset,
            uint256 totalPOLCollateral,
            uint256 settlementUAsset,
            uint256 settlementMemecoin,
            uint256 ptBackingNumerator,
            uint256 ptBackingDenominator,
            bool settled
        )
    {
        SplitInfo storage info = _getPOLSplitterStorage().splitInfos[verseId];
        pt = info.pt;
        yt = info.yt;
        pol = info.pol;
        memecoin = info.memecoin;
        uAsset = info.uAsset;
        totalPOLCollateral = info.totalPOLCollateral;
        settlementUAsset = info.settlementUAsset;
        settlementMemecoin = info.settlementMemecoin;
        ptBackingNumerator = info.ptBackingNumerator;
        ptBackingDenominator = info.ptBackingDenominator;
        settled = info.settled;
    }

    function preRedeemedStates(uint256 verseId) external view returns (uint256 ptAmount, uint256 uAssetBacking) {
        PreRedeemedState storage state = _getPOLSplitterStorage().preRedeemedStates[verseId];
        return (state.ptAmount, state.uAssetBacking);
    }

    function preRedeemedPT(uint256 verseId) external view returns (uint256) {
        return _getPOLSplitterStorage().preRedeemedStates[verseId].ptAmount;
    }

    function ptBackingRatios(uint256 verseId) external view returns (uint256 numerator, uint256 denominator) {
        SplitInfo storage info = _getPOLSplitterStorage().splitInfos[verseId];
        return (info.ptBackingNumerator, info.ptBackingDenominator);
    }

    function getPT(uint256 verseId) external view returns (address pt) {
        pt = _getPOLSplitterStorage().splitInfos[verseId].pt;
    }

    function getYT(uint256 verseId) external view returns (address yt) {
        yt = _getPOLSplitterStorage().splitInfos[verseId].yt;
    }

    function getMemecoin(uint256 verseId) external view returns (address memecoin) {
        memecoin = _getPOLSplitterStorage().splitInfos[verseId].memecoin;
    }

    function getPTAndYT(uint256 verseId) external view returns (address pt, address yt) {
        SplitInfo storage info = _getPOLSplitterStorage().splitInfos[verseId];
        pt = info.pt;
        yt = info.yt;
    }

    function getPTSettlementState(uint256 verseId) external view returns (address pt, bool settled) {
        SplitInfo storage info = _getPOLSplitterStorage().splitInfos[verseId];
        pt = info.pt;
        settled = info.settled;
    }

    function getPOLAndMemecoin(uint256 verseId) external view returns (address pol, address memecoin) {
        SplitInfo storage info = _getPOLSplitterStorage().splitInfos[verseId];
        pol = info.pol;
        memecoin = info.memecoin;
    }

    function launcher() external view returns (address) {
        return _getPOLSplitterStorage().launcher;
    }

    function polend() external view returns (address) {
        return _getPOLSplitterStorage().polend;
    }

    function principalTokenImplementation() external view returns (address) {
        return _getPOLSplitterStorage().principalTokenImplementation;
    }

    function yieldTokenImplementation() external view returns (address) {
        return _getPOLSplitterStorage().yieldTokenImplementation;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    modifier onlyLauncher() {
        if (msg.sender != _getPOLSplitterStorage().launcher) revert PermissionDenied();
        _;
    }

    modifier onlyPOLend() {
        if (msg.sender != _getPOLSplitterStorage().polend) revert PermissionDenied();
        _;
    }

    function initialize(address initialOwner, address _launcher) external initializer {
        if (_launcher == address(0)) revert ZeroInput();

        __Ownable_init(initialOwner);

        POLSplitterStorage storage $ = _getPOLSplitterStorage();
        $.launcher = _launcher;
        $.polend = IMemeverseLauncher(_launcher).polend();
        $.principalTokenImplementation = address(new PrincipalToken());
        $.yieldTokenImplementation = address(new YieldToken());
    }

    function initializeVerse(
        uint256 verseId,
        address pol,
        address memecoin,
        address uAsset,
        string calldata name,
        string calldata symbol
    ) external onlyLauncher returns (address pt, address yt) {
        POLSplitterStorage storage $ = _getPOLSplitterStorage();
        if ($.splitInfos[verseId].pt != address(0)) revert AlreadyDeployed();

        pt = $.principalTokenImplementation.cloneDeterministic(bytes32(verseId));
        yt = $.yieldTokenImplementation.cloneDeterministic(bytes32(verseId));

        PrincipalToken(pt).initialize(string.concat("PT-", name), string.concat("PT-", symbol), address(this));
        YieldToken(yt).initialize(string.concat("YT-", name), string.concat("YT-", symbol), address(this));

        $.splitInfos[verseId] = SplitInfo({
            pt: pt,
            yt: yt,
            pol: pol,
            memecoin: memecoin,
            uAsset: uAsset,
            totalPOLCollateral: 0,
            settlementUAsset: 0,
            settlementMemecoin: 0,
            ptBackingNumerator: 0,
            ptBackingDenominator: 0,
            settled: false
        });

        return (pt, yt);
    }

    function split(uint256 verseId, uint256 polAmount)
        external
        nonReentrant
        returns (uint256 ptAmount, uint256 ytAmount)
    {
        if (polAmount == 0) revert ZeroInput();
        SplitInfo storage info = _getPOLSplitterStorage().splitInfos[verseId];
        if (_isUnlocked(verseId) || info.settled) revert AlreadyUnlocked();
        _requirePTBackingRatio(info);

        IERC20(info.pol).safeTransferFrom(msg.sender, address(this), polAmount);
        info.totalPOLCollateral += polAmount;
        PrincipalToken(info.pt).mint(msg.sender, polAmount);
        YieldToken(info.yt).mint(msg.sender, polAmount);

        return (polAmount, polAmount);
    }

    function merge(uint256 verseId, uint256 amount) external nonReentrant returns (uint256 polAmount) {
        if (amount == 0) revert ZeroInput();
        SplitInfo storage info = _getPOLSplitterStorage().splitInfos[verseId];
        if (_isUnlocked(verseId) || info.settled) revert AlreadyUnlocked();
        _requirePTBackingRatio(info);

        info.totalPOLCollateral -= amount;
        PrincipalToken(info.pt).burn(msg.sender, amount);
        YieldToken(info.yt).burn(msg.sender, amount);
        IERC20(info.pol).safeTransfer(msg.sender, amount);

        return amount;
    }

    function settle(uint256 verseId)
        external
        onlyLauncher
        returns (uint256 settlementUAsset, uint256 settlementMemecoin)
    {
        POLSplitterStorage storage $ = _getPOLSplitterStorage();
        SplitInfo storage info = $.splitInfos[verseId];
        if (info.settled) revert AlreadySettled();
        if (!_isUnlocked(verseId)) revert NotUnlocked();

        // Effects: set re-entry guard before external calls
        info.settled = true;

        // Interactions
        (settlementUAsset, settlementMemecoin) = _settlePOLCollateral(verseId, info);
        PreRedeemedState storage state = $.preRedeemedStates[verseId];
        uint256 preRedeemedUAssetBacking = state.uAssetBacking;
        if (settlementUAsset < preRedeemedUAssetBacking) revert InvalidClaim();
        settlementUAsset -= preRedeemedUAssetBacking;
        if (settlementUAsset < _ptToUAsset(info, IERC20(info.pt).totalSupply())) revert InvalidClaim();
        if (preRedeemedUAssetBacking != 0) {
            address _polend = $.polend;
            IERC20(info.uAsset).approve(_polend, preRedeemedUAssetBacking);
            IPOLend(_polend).burnPreRedeemedBacking(verseId, preRedeemedUAssetBacking);
            delete $.preRedeemedStates[verseId];
        }

        // Effects: write post-interaction state
        info.totalPOLCollateral = 0;
        info.settlementUAsset = settlementUAsset;
        info.settlementMemecoin = settlementMemecoin;
    }

    function recordPTBackingRatio(uint256 verseId, uint256 numerator, uint256 denominator) external onlyLauncher {
        if (numerator == 0 || denominator == 0) revert ZeroInput();
        POLSplitterStorage storage $ = _getPOLSplitterStorage();
        SplitInfo storage info = $.splitInfos[verseId];
        if (info.pt == address(0)) revert InvalidClaim();
        if (info.settled) revert AlreadySettled();
        if (info.totalPOLCollateral != 0) revert InvalidClaim();
        if (info.ptBackingNumerator != 0 || info.ptBackingDenominator != 0) revert InvalidClaim();

        info.ptBackingNumerator = numerator;
        info.ptBackingDenominator = denominator;
    }

    function previewPTToUAsset(uint256 verseId, uint256 ptAmount) external view returns (uint256 uAssetAmount) {
        if (ptAmount == 0) return 0;
        SplitInfo storage info = _getPOLSplitterStorage().splitInfos[verseId];
        return _ptToUAsset(info, ptAmount);
    }

    function preRedeemPTFee(uint256 verseId, uint256 ptAmount) external onlyPOLend returns (uint256 uAssetBacking) {
        POLSplitterStorage storage $ = _getPOLSplitterStorage();
        SplitInfo storage info = $.splitInfos[verseId];
        if (info.settled) revert AlreadySettled();

        uAssetBacking = _ptToUAsset(info, ptAmount);
        if (uAssetBacking == 0) revert InvalidClaim();
        PrincipalToken(info.pt).burn($.launcher, ptAmount);
        PreRedeemedState storage state = $.preRedeemedStates[verseId];
        state.ptAmount += ptAmount;
        state.uAssetBacking += uAssetBacking;
    }

    function redeemPT(uint256 verseId, uint256 ptAmount, address to)
        external
        nonReentrant
        returns (uint256 uAssetAmount)
    {
        if (ptAmount == 0) revert ZeroInput();
        SplitInfo storage info = _getPOLSplitterStorage().splitInfos[verseId];
        if (!info.settled) revert NotSettled();
        if (to == address(0)) revert ZeroInput();
        uAssetAmount = _ptToUAsset(info, ptAmount);
        if (uAssetAmount == 0) revert InvalidClaim();
        uint256 settlementUAsset = info.settlementUAsset;
        if (settlementUAsset < uAssetAmount) revert InvalidClaim();

        PrincipalToken(info.pt).burn(msg.sender, ptAmount);
        info.settlementUAsset = settlementUAsset - uAssetAmount;
        IERC20(info.uAsset).safeTransfer(to, uAssetAmount);
        emit RedeemPT(verseId, msg.sender, to, ptAmount);

        return uAssetAmount;
    }

    function redeemYT(uint256 verseId, uint256 ytAmount, address to)
        external
        nonReentrant
        returns (uint256 uAssetAmount, uint256 memecoinAmount)
    {
        if (ytAmount == 0) revert ZeroInput();
        SplitInfo storage info = _getPOLSplitterStorage().splitInfos[verseId];
        if (!info.settled) revert NotSettled();
        if (to == address(0)) revert ZeroInput();

        uint256 outstandingYT = IERC20(info.yt).totalSupply();
        if (outstandingYT == 0) revert InvalidClaim();
        uint256 settlementUAsset = info.settlementUAsset;
        uint256 reservedUAssetForPT = _ptToUAsset(info, IERC20(info.pt).totalSupply());
        uint256 ytRedeemableUAssetPool = settlementUAsset - reservedUAssetForPT;

        uAssetAmount = Math.mulDiv(ytRedeemableUAssetPool, ytAmount, outstandingYT);
        memecoinAmount = Math.mulDiv(info.settlementMemecoin, ytAmount, outstandingYT);
        if (uAssetAmount == 0 && memecoinAmount == 0) revert InvalidClaim();

        YieldToken(info.yt).burn(msg.sender, ytAmount);
        info.settlementUAsset -= uAssetAmount;
        info.settlementMemecoin -= memecoinAmount;

        IERC20(info.uAsset).safeTransfer(to, uAssetAmount);
        IERC20(info.memecoin).safeTransfer(to, memecoinAmount);
        emit RedeemYT(verseId, msg.sender, to, ytAmount, uAssetAmount, memecoinAmount);
    }

    function previewRedeemYTUAsset(uint256 verseId, uint256 ytAmount) external view returns (uint256 uAssetAmount) {
        SplitInfo storage info = _getPOLSplitterStorage().splitInfos[verseId];
        uint256 outstandingYT = IERC20(info.yt).totalSupply();
        if (outstandingYT == 0) return 0;

        uint256 settlementUAsset = info.settlementUAsset;
        uint256 reservedUAssetForPT = _ptToUAsset(info, IERC20(info.pt).totalSupply());
        uint256 ytRedeemableUAssetPool = settlementUAsset - reservedUAssetForPT;
        return Math.mulDiv(ytRedeemableUAssetPool, ytAmount, outstandingYT);
    }

    function _isUnlocked(uint256 verseId) internal view returns (bool) {
        return IMemeverseLauncher(_getPOLSplitterStorage().launcher).getStageByVerseId(verseId)
            == IMemeverseLauncher.Stage.Unlocked;
    }

    function _settlePOLCollateral(uint256 verseId, SplitInfo storage info)
        internal
        returns (uint256 settlementUAsset, uint256 settlementMemecoin)
    {
        uint256 polAmount = info.totalPOLCollateral;
        address memecoin = info.memecoin;
        uint256 beforeUAsset = IERC20(info.uAsset).balanceOf(address(this));
        uint256 beforeMemecoin = IERC20(memecoin).balanceOf(address(this));

        IERC20(info.pol).approve(_getPOLSplitterStorage().launcher, polAmount);
        IMemeverseLauncher(_getPOLSplitterStorage().launcher).redeemMemecoinLiquidity(verseId, polAmount, true);

        settlementUAsset = IERC20(info.uAsset).balanceOf(address(this)) - beforeUAsset;
        settlementMemecoin = IERC20(memecoin).balanceOf(address(this)) - beforeMemecoin;
    }

    function _ptToUAsset(SplitInfo storage info, uint256 ptAmount) internal view returns (uint256 uAssetAmount) {
        uint256 numerator = info.ptBackingNumerator;
        uint256 denominator = info.ptBackingDenominator;
        if (numerator == 0 || denominator == 0) revert InvalidClaim();
        return FullMath.mulDiv(ptAmount, numerator, denominator);
    }

    function _requirePTBackingRatio(SplitInfo storage info) internal view {
        uint256 numerator = info.ptBackingNumerator;
        uint256 denominator = info.ptBackingDenominator;
        if (numerator == 0 || denominator == 0) revert InvalidClaim();
    }

    function _authorizeUpgrade(address) internal view override onlyOwner {}
}
