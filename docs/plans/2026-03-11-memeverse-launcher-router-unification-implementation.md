# Memeverse Launcher Router Unification Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rename the launcher router ABI from `liquidityRouter` to `memeverseSwapRouter` and remove the duplicate launcher router field.

**Architecture:** The launcher keeps one router address, `memeverseSwapRouter`, and all bootstrap liquidity calls use that field via `IMemeverseSwapRouter`. The interface and event surface are renamed to match, while runtime liquidity behavior stays unchanged.

**Tech Stack:** Solidity 0.8.28, Foundry, forge tests, NatSpec docs

---

### Task 1: Add launcher ABI regression coverage

**Files:**
- Create: `test/MemeverseLauncherRouterConfig.t.sol`
- Modify: `src/verse/interfaces/IMemeverseLauncher.sol`
- Modify: `src/verse/MemeverseLauncher.sol`

**Step 1: Write the failing test**

```solidity
function testSetMemeverseSwapRouterStoresAddress() external {
    launcher.setMemeverseSwapRouter(address(router));
    assertEq(launcher.memeverseSwapRouter(), address(router));
}
```

**Step 2: Run test to verify it fails**

Run: `forge test --match-path test/MemeverseLauncherRouterConfig.t.sol -vvv`
Expected: FAIL because the launcher ABI still exposes `setLiquidityRouter` and does not expose `memeverseSwapRouter()` as the only router getter.

**Step 3: Write minimal implementation**

```solidity
address public memeverseSwapRouter;

function setMemeverseSwapRouter(address _memeverseSwapRouter) external onlyOwner {
    require(_memeverseSwapRouter != address(0), ZeroInput());
    memeverseSwapRouter = _memeverseSwapRouter;
    emit SetMemeverseSwapRouter(_memeverseSwapRouter);
}
```

**Step 4: Run test to verify it passes**

Run: `forge test --match-path test/MemeverseLauncherRouterConfig.t.sol -vvv`
Expected: PASS

### Task 2: Replace launcher internal references

**Files:**
- Modify: `src/verse/MemeverseLauncher.sol`
- Modify: `docs/plans/2026-03-11-memeverse-router-permit2-design.md`
- Modify: `docs/plans/2026-03-11-memeverse-router-permit2-implementation.md`

**Step 1: Write the failing compile expectation**

Use the new test and build command after renaming the ABI so stale `liquidityRouter` references fail compilation.

**Step 2: Run the targeted command to surface stale references**

Run: `forge test --match-path test/MemeverseLauncherRouterConfig.t.sol -vvv`
Expected: FAIL or compile error while `MemeverseLauncher` still references `liquidityRouter`.

**Step 3: Write minimal implementation**

```solidity
IMemeverseSwapRouter(memeverseSwapRouter).createPoolAndAddLiquidity(param);
```

Also update comments, NatSpec, and plan docs that still mention `liquidityRouter` as the launcher field name.

**Step 4: Run test to verify it passes**

Run: `forge test --match-path test/MemeverseLauncherRouterConfig.t.sol -vvv`
Expected: PASS

### Task 3: Verify interface and compilation consistency

**Files:**
- Modify: `src/verse/interfaces/IMemeverseLauncher.sol`
- Modify: `src/verse/MemeverseLauncher.sol`
- Create or update: generated docs only if the source tree is buildable

**Step 1: Run interface-level verification**

Run: `forge build`
Expected: PASS if no stale launcher ABI references remain in source files.

**Step 2: Run focused regression tests**

Run: `forge test --match-path test/MemeverseLauncherRouterConfig.t.sol -vvv`
Expected: PASS

**Step 3: Run broader router interface test if buildable**

Run: `forge test --match-path test/MemeverseSwapRouterInterface.t.sol -vvv`
Expected: PASS

**Step 4: Refresh generated docs if compilation succeeds**

Run: `npm run docs:gen`
Expected: PASS and regenerated `docs/src/` for launcher interface changes.
