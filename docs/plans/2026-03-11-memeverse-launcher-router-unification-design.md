# Memeverse Launcher Router Unification Design

**Date:** 2026-03-11

## Goal

Unify `MemeverseLauncher` so it exposes and uses a single router address named `memeverseSwapRouter`, removing the legacy `liquidityRouter` naming from the launcher ABI.

## Decision Summary

- Remove `liquidityRouter` from `MemeverseLauncher`.
- Keep a single router state variable: `memeverseSwapRouter`.
- Rename the launcher owner setter to `setMemeverseSwapRouter(address)`.
- Rename the launcher event to `SetMemeverseSwapRouter(address)`.
- Keep runtime behavior unchanged: launcher bootstrap still routes through `IMemeverseSwapRouter.createPoolAndAddLiquidity(...)`.

## Why This Design

The launcher already treats bootstrap liquidity creation as a `MemeverseSwapRouter` responsibility. Keeping both `liquidityRouter` and `memeverseSwapRouter` in the same contract creates duplicate configuration surface and unclear integration semantics. Renaming the remaining router field to the actual contract role makes the ABI and implementation line up.

## Scope

### In Scope

- `MemeverseLauncher` state variable rename and field removal.
- `IMemeverseLauncher` setter and event rename.
- Internal launcher call sites, comments, and NatSpec updates.
- Related plan docs that still describe the old launcher ABI.

### Out of Scope

- Changes to `IMemeverseSwapRouter`.
- Permit2 flow changes.
- Broad deployment environment variable cleanup beyond files directly coupled to the launcher ABI.

## Architecture

`MemeverseLauncher` will expose a single router address:

- `address public memeverseSwapRouter;`

All liquidity bootstrap calls will use:

`IMemeverseSwapRouter(memeverseSwapRouter).createPoolAndAddLiquidity(...)`

The owner configuration path will become:

- `setMemeverseSwapRouter(address _memeverseSwapRouter)`
- `emit SetMemeverseSwapRouter(_memeverseSwapRouter)`

## ABI Impact

This is an intentional ABI change:

- remove getter `liquidityRouter()`
- add getter `memeverseSwapRouter()`
- remove `setLiquidityRouter(address)`
- add `setMemeverseSwapRouter(address)`
- remove `SetLiquidityRouter(address)`
- add `SetMemeverseSwapRouter(address)`

Any external caller, script, or test still using the old launcher ABI must be updated in the same change.

## Security Notes

- Access control remains `onlyOwner` on router configuration.
- Zero-address validation remains required.
- No change to liquidity bootstrap amounts, recipient handling, or pool accounting.

## Testing Strategy

- Add or update a launcher-focused regression test that verifies the new setter stores `memeverseSwapRouter`.
- Verify bootstrap call sites compile against the renamed field.
- Run interface and build checks to catch stale ABI references.
