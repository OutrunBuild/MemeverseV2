# Memeverse Swap Router Interface Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a minimal user-facing `IMemeverseSwapRouter` interface with router-owned structs, custom errors, and NatSpec, then bind `MemeverseSwapRouter` to it and verify compilation.

**Architecture:** Keep the interface scoped to the router's intended public entrypoints rather than inherited callback plumbing. Use a compile-oriented Foundry test to prove the interface exists and its selectors match the router contract.

**Tech Stack:** Solidity 0.8.28, Foundry, Uniswap v4 core/periphery types.

---

### Task 1: Add the failing compile-oriented test

**Files:**
- Create: `test/MemeverseSwapRouterInterface.t.sol`

**Step 1: Write the failing test**

Create a test that imports `IMemeverseSwapRouter`, references all expected selectors, and compares them to `MemeverseSwapRouter`.

**Step 2: Run test to verify it fails**

Run: `forge test --match-path test/MemeverseSwapRouterInterface.t.sol -vvv`
Expected: compile failure because `src/swap/interfaces/IMemeverseSwapRouter.sol` does not exist yet.

### Task 2: Implement the interface

**Files:**
- Create: `src/swap/interfaces/IMemeverseSwapRouter.sol`

**Step 1: Write minimal implementation**

Define the router-facing structs, custom errors, and external function signatures with required NatSpec.

**Step 2: Bind the router to the interface**

Modify `src/swap/MemeverseSwapRouter.sol` to import `IMemeverseSwapRouter`, inherit it, and mark implemented members with `override`.

**Step 3: Run test to verify it passes**

Run: `forge test --match-path test/MemeverseSwapRouterInterface.t.sol -vvv`
Expected: the targeted test compiles and passes.

### Task 3: Verify no integration breakage

**Files:**
- Modify: `src/swap/MemeverseSwapRouter.sol`
- Test: `test/MemeverseSwapRouterInterface.t.sol`

**Step 1: Run a focused compile/test command**

Run: `forge test --match-contract MemeverseSwapRouterTest --match-test testQuoteSwap -vvv`
Expected: an existing router test compiles and passes with the interface changes in place.
