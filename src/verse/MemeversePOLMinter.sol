// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {TokenHelper} from "../common/token/TokenHelper.sol";
import {IPol} from "../token/interfaces/IPol.sol";
import {IMemeverseSwapRouter} from "../swap/interfaces/IMemeverseSwapRouter.sol";
import {IMemeverseUniswapHook} from "../swap/interfaces/IMemeverseUniswapHook.sol";
import {IMemeverseLauncher} from "./interfaces/IMemeverseLauncher.sol";
import {MemeverseLauncherStorage} from "./interfaces/IMemeverseLauncherStorage.sol";
import {IMemeversePOLMinter} from "./interfaces/IMemeversePOLMinter.sol";

/// @title MemeversePOLMinter
/// @notice Delegatecall-only sibling holding the POL minting chain (Locked-stage user add-liquidity + POL mint)
///         relocated from MemeverseLauncher. Binds the SAME ERC-7201 slot so under delegatecall it operates on
///         the proxy's MemeverseLauncherStorage. No Initializable, no own storage, empty constructor.
/// @dev The facade performs outer validation (verseId / pause / input non-zero / stage >= Locked) and reads
///      verse.uAsset / verse.memecoin / verse.pol before delegating. This sibling owns the full side-effect
///      block (transfer-in -> approve -> router liquidity -> POL mint -> refund) so `_transferOut` refund and
///      all token movement share one delegatecall boundary. `swapRouter` is self-read from
///      `memeverseLauncherStorage.memeverseSwapRouter`. Delegatecall-only by construction, not by a runtime
///      guard: the sibling's own storage is permanently uninitialized, so a direct (non-delegatecall) call reads
///      `memeverseSwapRouter` as address(0) and the router external call reverts on empty returndata decode; a
///      `msg.sender` guard would be wrong here — under delegatecall msg.sender is the facade's caller.
contract MemeversePOLMinter layout at erc7201("outrun.storage.MemeverseLauncher") is TokenHelper, IMemeversePOLMinter {
    MemeverseLauncherStorage private memeverseLauncherStorage;

    constructor() {}

    // === relocated POL minting chain (from MemeverseLauncher) ===
    //
    // Nested types / cross-interface errors are qualified (this sibling does not inherit IMemeverseLauncher /
    // IMemeverseSwapRouter / IMemeverseUniswapHook): IMemeverseLauncher.InvalidLength,
    // IMemeverseSwapRouter.InputAmountExceedsMaximum, IMemeverseUniswapHook.TooMuchSlippage.

    /// @inheritdoc IMemeversePOLMinter
    function mintPOLToken(
        address uAsset,
        address memecoin,
        address pol,
        uint256 amountInUAssetDesired,
        uint256 amountInMemecoinDesired,
        uint256 amountInUAssetMin,
        uint256 amountInMemecoinMin,
        uint256 amountOutDesired,
        uint256 deadline
    ) external override returns (uint256 amountInUAsset, uint256 amountInMemecoin, uint256 amountOut) {
        address swapRouter = memeverseLauncherStorage.memeverseSwapRouter;
        _transferIn(uAsset, msg.sender, amountInUAssetDesired);
        _transferIn(memecoin, msg.sender, amountInMemecoinDesired);
        _safeApprove(uAsset, swapRouter, amountInUAssetDesired);
        _safeApprove(memecoin, swapRouter, amountInMemecoinDesired);
        (amountInUAsset, amountInMemecoin, amountOut) = _executeMintPOLTokenLiquidity(
            uAsset,
            memecoin,
            amountInUAssetDesired,
            amountInMemecoinDesired,
            amountInUAssetMin,
            amountInMemecoinMin,
            amountOutDesired,
            deadline
        );

        IPol(pol).mint(msg.sender, amountOut);
        _refundMintPOLTokenInputs(
            uAsset, memecoin, amountInUAssetDesired, amountInMemecoinDesired, amountInUAsset, amountInMemecoin
        );
    }

    function _executeMintPOLTokenLiquidity(
        address uAsset,
        address memecoin,
        uint256 amountInUAssetDesired,
        uint256 amountInMemecoinDesired,
        uint256 amountInUAssetMin,
        uint256 amountInMemecoinMin,
        uint256 amountOutDesired,
        uint256 deadline
    ) internal returns (uint256 amountInUAsset, uint256 amountInMemecoin, uint256 amountOut) {
        if (amountOutDesired == 0) {
            return _mintPOLTokenWithAutoLiquidity(
                uAsset,
                memecoin,
                amountInUAssetDesired,
                amountInMemecoinDesired,
                amountInUAssetMin,
                amountInMemecoinMin,
                deadline
            );
        }

        return _mintPOLTokenWithExactLiquidity(
            uAsset, memecoin, amountInUAssetDesired, amountInMemecoinDesired, amountOutDesired, deadline
        );
    }

    function _mintPOLTokenWithAutoLiquidity(
        address uAsset,
        address memecoin,
        uint256 amountInUAssetDesired,
        uint256 amountInMemecoinDesired,
        uint256 amountInUAssetMin,
        uint256 amountInMemecoinMin,
        uint256 deadline
    ) internal returns (uint256 amountInUAsset, uint256 amountInMemecoin, uint256 amountOut) {
        (amountOut, amountInUAsset, amountInMemecoin) = IMemeverseSwapRouter(
                memeverseLauncherStorage.memeverseSwapRouter
            )
            .addLiquidityDetailed(
                Currency.wrap(uAsset),
                Currency.wrap(memecoin),
                amountInUAssetDesired,
                amountInMemecoinDesired,
                amountInUAssetMin,
                amountInMemecoinMin,
                address(this),
                deadline
            );
    }

    function _mintPOLTokenWithExactLiquidity(
        address uAsset,
        address memecoin,
        uint256 amountInUAssetDesired,
        uint256 amountInMemecoinDesired,
        uint256 amountOutDesired,
        uint256 deadline
    ) internal returns (uint256 amountInUAsset, uint256 amountInMemecoin, uint256 amountOut) {
        require(amountOutDesired <= type(uint128).max, IMemeverseLauncher.InvalidLength());
        // Quote the smallest router-side budgets that should mint the requested LP amount at the current pool price.
        (uint256 quotedUAsset, uint256 quotedMemecoin) = IMemeverseSwapRouter(
                memeverseLauncherStorage.memeverseSwapRouter
            ).quoteExactAmountsForLiquidity(uAsset, memecoin, uint128(amountOutDesired));
        if (quotedUAsset > amountInUAssetDesired) {
            revert IMemeverseSwapRouter.InputAmountExceedsMaximum(quotedUAsset, amountInUAssetDesired);
        }
        if (quotedMemecoin > amountInMemecoinDesired) {
            revert IMemeverseSwapRouter.InputAmountExceedsMaximum(quotedMemecoin, amountInMemecoinDesired);
        }
        // Reuse the exact quote as the desired budget so any price move that under-mints reverts instead of silently
        // minting less POL than requested.
        (amountOut, amountInUAsset, amountInMemecoin) = IMemeverseSwapRouter(
                memeverseLauncherStorage.memeverseSwapRouter
            )
            .addLiquidityDetailed(
                Currency.wrap(uAsset),
                Currency.wrap(memecoin),
                quotedUAsset,
                quotedMemecoin,
                0,
                0,
                address(this),
                deadline
            );
        if (amountOut < amountOutDesired) revert IMemeverseUniswapHook.TooMuchSlippage();
    }

    function _refundMintPOLTokenInputs(
        address uAsset,
        address memecoin,
        uint256 amountInUAssetDesired,
        uint256 amountInMemecoinDesired,
        uint256 amountInUAsset,
        uint256 amountInMemecoin
    ) internal {
        uint256 uAssetRefund = amountInUAssetDesired - amountInUAsset;
        uint256 memecoinRefund = amountInMemecoinDesired - amountInMemecoin;
        if (uAssetRefund > 0) _transferOut(uAsset, msg.sender, uAssetRefund);
        if (memecoinRefund > 0) _transferOut(memecoin, msg.sender, memecoinRefund);
    }
}
