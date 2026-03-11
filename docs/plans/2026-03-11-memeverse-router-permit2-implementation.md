# Memeverse Router Permit2 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Migrate launcher liquidity bootstrap to `IMemeverseSwapRouter`, then add optional Permit2-powered router entrypoints without breaking the existing approval flow.

**Architecture:** Keep the current ERC20 approval path untouched and add Permit2 as a parallel funding layer on the router. Execute the work in two stages: first route launcher bootstrap through the router, then extend the router interface and implementation with SignatureTransfer-based Permit2 entrypoints that reuse the same post-funding swap and LP logic.

**Tech Stack:** Solidity 0.8.28, Foundry, Uniswap v4 core/periphery, Permit2 (`IPermit2`, `ISignatureTransfer`).

---

### Task 1: Migrate Launcher Bootstrap To The Router

**Files:**
- Create: `test/MemeverseLauncherLiquidityRouter.t.sol`
- Modify: `src/verse/MemeverseLauncher.sol`
- Modify: `src/verse/interfaces/IMemeverseLauncher.sol`

**Step 1: Write the failing test**

Create a focused launcher harness test that exposes `_deployLiquidity(...)` and uses a mock router to prove:
- the launcher calls `createPoolAndAddLiquidity(...)` twice
- the first call uses `memecoin/UPT` budgets
- the second call uses `POL/UPT` budgets
- `setPoolId`, `mint`, `totalPolLiquidity`, and `totalClaimablePOL` are updated from router return values

```solidity
function testDeployLiquidity_UsesSwapRouterForBothPools() external {
    harness.exposedDeployLiquidity(verseId, UPT, memecoin, pol, totalMemecoinFunds, totalLiquidProofFunds);

    assertEq(mockRouter.callCount(), 2);
    assertEq(liquidProof.poolId(), expectedPoolId);
    assertEq(harness.totalPolLiquidity(verseId), expectedPolLiquidity);
    assertEq(harness.totalClaimablePOL(verseId), expectedMemecoinLiquidity - expectedDeployedPol);
}
```

**Step 2: Run test to verify it fails**

Run: `forge test --match-path test/MemeverseLauncherLiquidityRouter.t.sol -vvv`
Expected: FAIL because `MemeverseLauncher` still uses `PoolBootstrapLib` directly and does not call `memeverseSwapRouter`.

**Step 3: Write minimal implementation**

Update `MemeverseLauncher` to:
- import `IMemeverseSwapRouter`
- stop calling `PoolBootstrapLib.createPoolAndAddLiquidity(...)` inside `_deployLiquidity(...)`
- call `IMemeverseSwapRouter(memeverseSwapRouter).createPoolAndAddLiquidity(...)` for both bootstrap legs
- preserve the current bookkeeping after each returned `(liquidity, poolKey)`

```solidity
(uint128 memecoinLiquidity, PoolKey memory poolKey) =
    IMemeverseSwapRouter(memeverseSwapRouter).createPoolAndAddLiquidity(params);
```

**Step 4: Run test to verify it passes**

Run: `forge test --match-path test/MemeverseLauncherLiquidityRouter.t.sol -vvv`
Expected: PASS

**Step 5: Commit**

```bash
git add test/MemeverseLauncherLiquidityRouter.t.sol src/verse/MemeverseLauncher.sol
git commit -m "refactor(launcher): route liquidity bootstrap through swap router"
```

### Task 2: Extend The Router Interface For Permit2

**Files:**
- Modify: `src/swap/interfaces/IMemeverseSwapRouter.sol`
- Modify: `test/MemeverseSwapRouterInterface.t.sol`

**Step 1: Write the failing test**

Extend the interface selector test to require:
- `permit2()`
- `swapWithPermit2(...)`
- `addLiquidityWithPermit2(...)`
- `removeLiquidityWithPermit2(...)`
- `createPoolAndAddLiquidityWithPermit2(...)`

```solidity
function testPermit2SelectorsMatchRouter() external pure {
    assertEq(IMemeverseSwapRouter.permit2.selector, bytes4(keccak256("permit2()")));
    assertEq(IMemeverseSwapRouter.swapWithPermit2.selector, bytes4(keccak256("swapWithPermit2(...)")));
}
```

**Step 2: Run test to verify it fails**

Run: `forge test --match-path test/MemeverseSwapRouterInterface.t.sol -vvv`
Expected: FAIL because the interface does not yet define Permit2 structs or selectors.

**Step 3: Write minimal implementation**

Add to `IMemeverseSwapRouter`:
- `Permit2SingleParams`
- `Permit2BatchParams`
- `permit2()` getter
- the four Permit2 entrypoints with concise NatSpec

Prefer `IPermit2` import from:
`lib/v4-periphery/lib/permit2/src/interfaces/IPermit2.sol`

**Step 4: Run test to verify it passes**

Run: `forge test --match-path test/MemeverseSwapRouterInterface.t.sol -vvv`
Expected: PASS

**Step 5: Commit**

```bash
git add src/swap/interfaces/IMemeverseSwapRouter.sol test/MemeverseSwapRouterInterface.t.sol
git commit -m "feat(router): extend interface with permit2 entrypoints"
```

### Task 3: Add Router Permit2 State And Single-Token Funding

**Files:**
- Create: `test/MemeverseSwapRouterPermit2.t.sol`
- Modify: `src/swap/MemeverseSwapRouter.sol`
- Modify: `src/swap/interfaces/IMemeverseSwapRouter.sol`

**Step 1: Write the failing test**

Create a Permit2-focused router test with:
- a mock Permit2 contract implementing the minimal `permitWitnessTransferFrom(...)` single-token path
- a test for `swapWithPermit2(...)` success
- a test for `swapWithPermit2(...)` soft-fail refund behavior

```solidity
function testSwapWithPermit2_TransfersInputAndExecutes() external {
    vm.prank(alice);
    router.swapWithPermit2(singlePermit, key, params, alice, alice, deadline, minOut, maxIn, hookData);

    assertEq(mockPermit2.lastOwner(), alice);
    assertEq(mockPermit2.lastRecipient(), address(router));
}
```

**Step 2: Run test to verify it fails**

Run: `forge test --match-path test/MemeverseSwapRouterPermit2.t.sol --match-test testSwapWithPermit2_TransfersInputAndExecutes -vvv`
Expected: FAIL because the router has no Permit2 state or `swapWithPermit2(...)`.

**Step 3: Write minimal implementation**

Update `MemeverseSwapRouter` to:
- accept `IPermit2 _permit2` in the constructor
- expose `permit2`
- add minimal single-token witness-based funding helper
- implement `swapWithPermit2(...)` by funding through Permit2, then reusing existing swap execution logic

```solidity
function _pullCurrencyWithPermit2(
    Permit2SingleParams calldata permitParams,
    address owner,
    address token,
    uint256 amount,
    bytes32 witness,
    string memory witnessTypeString
) internal;
```

**Step 4: Run test to verify it passes**

Run: `forge test --match-path test/MemeverseSwapRouterPermit2.t.sol --match-test testSwapWithPermit2_TransfersInputAndExecutes -vvv`
Expected: PASS

**Step 5: Commit**

```bash
git add test/MemeverseSwapRouterPermit2.t.sol src/swap/MemeverseSwapRouter.sol src/swap/interfaces/IMemeverseSwapRouter.sol
git commit -m "feat(router): add permit2 swap entrypoint"
```

### Task 4: Add Batch Permit2 Funding For LP And Bootstrap Paths

**Files:**
- Modify: `test/MemeverseSwapRouterPermit2.t.sol`
- Modify: `src/swap/MemeverseSwapRouter.sol`
- Modify: `src/swap/interfaces/IMemeverseSwapRouter.sol`

**Step 1: Write the failing tests**

Add focused tests for:
- `addLiquidityWithPermit2(...)` with two ERC20 inputs
- `addLiquidityWithPermit2(...)` with one ERC20 plus native
- `removeLiquidityWithPermit2(...)`
- `createPoolAndAddLiquidityWithPermit2(...)`
- invalid batch length and token mismatch reverts

```solidity
function testCreatePoolAndAddLiquidityWithPermit2_InvalidBatchLengthReverts() external {
    vm.expectRevert(MemeverseSwapRouter.InvalidPermit2Length.selector);
    router.createPoolAndAddLiquidityWithPermit2(batchPermit, params);
}
```

**Step 2: Run tests to verify they fail**

Run: `forge test --match-path test/MemeverseSwapRouterPermit2.t.sol -vvv`
Expected: FAIL because batch Permit2 helpers and LP/bootstrap entrypoints are missing.

**Step 3: Write minimal implementation**

Implement:
- router-side Permit2 validation errors
- batch funding helper for 1-or-2 ERC20 transfers
- `addLiquidityWithPermit2(...)`
- `removeLiquidityWithPermit2(...)`
- `createPoolAndAddLiquidityWithPermit2(...)`

Keep the existing non-Permit2 logic as the shared execution path after funding.

**Step 4: Run tests to verify they pass**

Run: `forge test --match-path test/MemeverseSwapRouterPermit2.t.sol -vvv`
Expected: PASS

**Step 5: Commit**

```bash
git add test/MemeverseSwapRouterPermit2.t.sol src/swap/MemeverseSwapRouter.sol src/swap/interfaces/IMemeverseSwapRouter.sol
git commit -m "feat(router): add permit2 liquidity and bootstrap entrypoints"
```

### Task 5: Verify Regressions And Integration

**Files:**
- Modify: `test/MemeverseSwapRouter.t.sol`
- Modify: `test/MemeverseSwapRouterInterface.t.sol`
- Modify: `test/MemeverseLauncherLiquidityRouter.t.sol`

**Step 1: Run focused regression commands**

Run: `forge test --match-path test/MemeverseSwapRouter.t.sol --match-test testQuoteSwap_WhenEmergencyFlagEnabled_ReturnsBaseFee -vvv`
Expected: PASS

Run: `forge test --match-path test/MemeverseSwapRouter.t.sol --match-test testSwapPass_RecordsAttemptAndExecutes -vvv`
Expected: PASS

Run: `forge test --match-path test/MemeverseSwapRouterInterface.t.sol -vvv`
Expected: PASS

Run: `forge test --match-path test/MemeverseLauncherLiquidityRouter.t.sol -vvv`
Expected: PASS

**Step 2: Run broader verification**

Run: `forge test -vvv`
Expected: PASS, or identify exact failing suites before proceeding.

**Step 3: Commit**

```bash
git add test/MemeverseSwapRouter.t.sol test/MemeverseSwapRouterInterface.t.sol test/MemeverseLauncherLiquidityRouter.t.sol
git commit -m "test(router): verify permit2 and launcher bootstrap integration"
```
