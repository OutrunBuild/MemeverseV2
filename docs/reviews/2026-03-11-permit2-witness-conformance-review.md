# 2026-03-11-permit2-witness-conformance-review

## Scope
- Change summary:
  - Fixed router Permit2 witness generation to use canonical typed witness hashes and canonical witness type strings for all four Permit2 entrypoints (`swap`, `addLiquidity`, `removeLiquidity`, `createPoolAndAddLiquidity`).
  - Added Permit2 signature conformance tests that validate canonical EIP-712 witness signing across all four Permit2 entrypoints.
  - Fixed quality-gate generated-doc path mismatch (`docs/src` -> `docs/contracts`) so src Solidity changes can complete pre-commit flow.
  - Updated product integration/PRD docs with Permit2 witness-signing constraints.
- Files reviewed:
  - `src/swap/MemeverseSwapRouter.sol`
  - `test/MemeverseSwapRouterPermit2.t.sol`
  - `script/quality-gate.sh`
  - `docs/memeverse-swap/memeverse-swap-integration.md`
  - `docs/memeverse-swap/memeverse-swap-prd.md`

## Findings
- `High`:
  - None.
- `Medium`:
  - None.
- `Low`:
  - `script/quality-gate.sh` previously staged/checked `docs/src`, but docs generation now writes to `docs/contracts`. This would break pre-commit on `src/**/*.sol` changes. Fixed in this change set.
  - Local staged mode attempted `git add docs/contracts`; when docs output is ignored, this fails and blocks commit. Added ignore-aware staging guard.
- `None` if no findings:
  - N/A.

## Simplification
- Candidate simplifications considered:
  - Collapsing all witness builders into one generic helper.
  - Removing the strict Permit2 signature harness and keeping only old mock-based tests.
- Applied:
  - Extracted router witness typehash/type-string constants to avoid repeated literals and reduce drift risk.
  - Kept witness hash construction explicit per flow for auditability.
- Rejected (with reason):
  - Generic witness builder helper was rejected because each flow has different typed fields; explicit encodings are easier to audit for signature-critical logic.
  - Mock-only test strategy was rejected because it cannot detect spender/witness typehash/signature conformance failures.

## Verification
- Commands run:
  - `forge test --match-path test/MemeverseSwapRouterPermit2.t.sol --match-test "test(SwapWithPermit2_RealPermit2CanonicalWitnessExecutes|AddLiquidityWithPermit2_RealPermit2CanonicalBatchWitnessExecutes)" -vvv`
  - `forge test --match-path test/MemeverseSwapRouterPermit2.t.sol --match-test "RealPermit2Canonical" -vvv`
  - `forge test --match-path test/MemeverseSwapRouterPermit2.t.sol -vvv`
  - `forge test -vvv`
  - `QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST=<tmp> bash ./script/quality-gate.sh`
- Results:
  - First targeted conformance run failed on old router implementation with `InvalidSigner` (expected RED).
  - After router witness fix, targeted conformance tests passed.
  - Full Permit2 test suite passed.
  - Full Forge test suite passed (`62 passed, 0 failed`).
  - Quality gate first failed due missing review note (expected).
  - After adding review note, quality gate passed.

## Decision
- Ready to commit: `yes`
- Residual risks:
  - Conformance harness in tests replicates Permit2 SignatureTransfer witness verification semantics because repository compiler pin (`solc 0.8.30`) cannot directly compile upstream `Permit2.sol (=0.8.17)` in this workspace.
  - Runtime parity risk is low for covered paths (spender binding, typed witness hash, witness type string, nonce usage, signature verification), but direct upstream bytecode execution is not part of this test environment.
