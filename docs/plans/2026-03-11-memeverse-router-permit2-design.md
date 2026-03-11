# Memeverse Router Permit2 Design

**Date:** 2026-03-11

## Goal

Unify liquidity bootstrap through `MemeverseSwapRouter`, then add optional Permit2-based user entrypoints that improve wallet-direct UX without breaking the existing ERC20 approval flow.

## Decision Summary

- `MemeverseLauncher._deployLiquidity()` should stop using `PoolBootstrapLib` as the primary bootstrap path and instead call `IMemeverseSwapRouter.createPoolAndAddLiquidity(...)`.
- `MemeverseSwapRouter` should keep its current ERC20 approval flow unchanged.
- Permit2 should be added as an optional parallel path on the router, not as a replacement.
- The first Permit2 version should use `SignatureTransfer`, not `AllowanceTransfer`.
- Permit2 support is for end-user wallet flows. Protocol-internal callers should continue to use normal ERC20 approvals.

## Why This Design

`PoolBootstrapLib` currently mixes two responsibilities:

- a legacy no-hook bootstrap path built around `positionManager` and `permit2`
- a hook path that directly calls hook core liquidity functions

`MemeverseSwapRouter` is already the intended user-facing entrypoint for quote, swap, LP, fee claim, and hook-backed bootstrap. Keeping bootstrap in `MemeverseLauncher` on a separate library path creates duplicated logic and drifts away from the router-centric architecture.

For user approvals, current market practice is mixed rather than exclusive: ordinary approvals remain the compatibility fallback, while permit-style flows are layered on top for better UX. Permit2 fits that model, but it should not become the only way to fund router actions.

## Scope

### In Scope

- Migrate `MemeverseLauncher._deployLiquidity()` to the router interface.
- Extend `IMemeverseSwapRouter` with optional Permit2 entrypoints.
- Implement Permit2 funding on router paths that pull ERC20s from the user:
  - swap
  - add liquidity
  - remove liquidity
  - create pool and add liquidity
- Add tests for Permit2 success, validation failure, and regression coverage.

### Out of Scope

- Permit2-only routing
- changing the anti-snipe model
- changing hook accounting
- front-end implementation
- removing `PoolBootstrapLib` in the same change

## Architecture

### Phase 1: Launcher Migration

`MemeverseLauncher._deployLiquidity()` will call `IMemeverseSwapRouter(memeverseSwapRouter).createPoolAndAddLiquidity(...)` twice:

- once for `memecoin / UPT`
- once for `POL / UPT`

This removes the launcher's direct dependency on `PoolBootstrapLib`, `positionManager`, and the library bootstrap flow for the main protocol path.

### Phase 2: Router Permit2 Entry Layer

`MemeverseSwapRouter` will gain parallel Permit2 entrypoints:

- `swapWithPermit2(...)`
- `addLiquidityWithPermit2(...)`
- `removeLiquidityWithPermit2(...)`
- `createPoolAndAddLiquidityWithPermit2(...)`

These functions will prepare funds with Permit2 and then reuse the same core execution logic as the current functions. The existing `swap`, `addLiquidity`, `removeLiquidity`, and `createPoolAndAddLiquidity` functions remain unchanged.

## Permit2 Model

### Chosen Primitive

Use `IPermit2` with `ISignatureTransfer` flow as the first implementation target.

### Why SignatureTransfer

- Better fit for wallet-direct single-action UX.
- No router-side long-lived Permit2 allowance is required.
- Easier to explain as a one-signature funding action.
- Safer default for swap and LP actions than shifting standing allowance management into the router.

### Why Not AllowanceTransfer First

`AllowanceTransfer` is useful when the product explicitly wants a reusable Permit2 allowance model. That is more stateful, less minimal, and not required for the first end-user UX improvement.

## Router API Shape

### New State

- add immutable `permit2`

### New Interface Types

Add compact Permit2 parameter wrappers to `IMemeverseSwapRouter`:

- `Permit2SingleParams`
- `Permit2BatchParams`

Each wrapper should hold the signed Permit2 payload plus the signature bytes. The router should infer the spender action and force the transfer recipient to be `address(this)`.

### New Entry Points

- `swapWithPermit2(...)`
- `addLiquidityWithPermit2(...)`
- `removeLiquidityWithPermit2(...)`
- `createPoolAndAddLiquidityWithPermit2(...)`

## Data Flow

### Existing Path

1. User approves router.
2. Router pulls ERC20 from `msg.sender`.
3. Router approves hook if needed.
4. Router executes existing swap or LP path.

### Permit2 Path

1. User signs Permit2 payload off-chain.
2. Router consumes the signature and pulls ERC20 into itself through Permit2.
3. Router approves hook if needed.
4. Router executes the same existing swap or LP path.

The business logic should not diverge after funding succeeds.

## Witness Binding

Permit2 entrypoints should use `permitWitnessTransferFrom`, not bare `permitTransferFrom`.

The witness should bind a signature to the specific router action so that a valid signature for one function cannot be reused for a different function. Separate witness hashes should be defined for:

- swap
- add liquidity
- remove liquidity
- create pool and add liquidity

## Validation and Error Handling

Keep new router-side validation minimal and local to Permit2 payload shape:

- invalid token order
- invalid token count for batch funding
- Permit2 funding requested for a native-only action

Permit2-native failures such as expired signatures, used nonces, or insufficient permitted amounts should bubble up from Permit2 instead of being wrapped in router-specific errors.

## Security Notes

- Do not remove the standard ERC20 approval path.
- Force Permit2-funded transfers to `address(this)`.
- Bind signatures to concrete router actions with witness data.
- Keep native-asset handling outside Permit2 and preserve the existing `nativeRefundRecipient` protections.
- Reuse current slippage and deadline checks after funding succeeds.

## Testing Strategy

### Launcher Migration Tests

- launcher bootstrap compiles against `IMemeverseSwapRouter`
- launcher still records `poolId`, minted liquidity, and `totalClaimablePOL` correctly

### Router Permit2 Tests

- `swapWithPermit2` exact-input success
- `swapWithPermit2` soft-fail refund path
- `swapWithPermit2` exact-output funding cap handling
- `addLiquidityWithPermit2` with two ERC20 inputs
- `addLiquidityWithPermit2` with one ERC20 plus native
- `removeLiquidityWithPermit2` with LP token funding
- `createPoolAndAddLiquidityWithPermit2` bootstrap success
- invalid batch length or token mismatch reverts
- expired or replayed signature reverts via Permit2

### Regression Tests

- existing non-Permit2 router tests stay green
- existing launcher bootstrap behavior stays green after router migration

## Follow-Up After Implementation

- decide whether `PoolBootstrapLib` should be reduced to a no-hook helper or removed later
- decide whether a later phase should add `AllowanceTransfer` support for repeat traders
