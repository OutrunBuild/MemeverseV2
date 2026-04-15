# AGENTS Contract

## Session Entry

- AGENTS.md is the session entry for MemeverseV2.
- Read order is fixed:
  1. AGENTS.md
  2. .harness/policy.json
  3. .harness/runtime/main-session-contract.md
  4. docs/TRACEABILITY.md when you need control-file or artifact locations
  5. docs/VERIFICATION.md when you need verification profile or verdict rules
  6. script/harness/gate.sh when you need enforcement details or emitted evidence

## Truth Precedence

1. explicit human instruction
2. .harness/policy.json
3. script/harness/gate.sh results
4. AGENTS.md and .harness/runtime/main-session-contract.md
5. other repository docs

Do not override policy or gate evidence with natural-language guesses.

## Main-Session Rules

- main-orchestrator stays in the primary session and is never a project agent file.
- Derive surface, risk_tier, writer_role, review_roles, and verification_profile from policy before delegating.
- review_roles remain reviewer-only; do not place verifier or security-test-writer inside review_roles.
- Project agent files under .claude/agents/ and .codex/agents/ are execution files. They do not define policy or verdict rules.
- Do not create a parallel control plane outside policy, gate, and project agent files.

## Verification Contract

- gate.sh is the enforcement entrypoint.
- Completion, readiness, or “pass” claims require fresh output from the matching gate profile.
- See docs/VERIFICATION.md for profile meanings and command entrypoints.

## Harness Dispatch Procedure

When `.harness/policy.json` exists AND the task involves writing or modifying code, follow this procedure:

### Mandatory Pre-condition

Even when the user gives a direct instruction to modify files, you MUST follow this dispatch procedure. Do not modify files directly in the main session. Every code modification must go through classify → dispatch → review → verify.

### Surface Completeness

Every file that will be modified or created must match a surface pattern in policy.json. If a target file does not match any surface, the surface configuration is incomplete — stop and add the missing pattern to policy.json before proceeding. New files are classified by their intended path against existing surface patterns.

### Flow

1. **Classify** — Read `.harness/policy.json`. Determine surface, risk_tier, writer_role, review_roles, verification_profile.
2. **Explore** (optional) — If surface/risk unclear, dispatch `solidity-explorer`. Use structured findings to re-classify.
3. **Implement** — Dispatch the appropriate writer:
   - surface=solidity → `solidity-implementer`
   - surface=harness_control → `process-implementer`
   - Mixed surface → hard block, ask user to split.
4. **Review** (parallel) — Dispatch reviewers by risk_tier:
   - non-semantic → skip review
   - test-semantic → `logic-reviewer`
   - prod-semantic → `logic-reviewer` + `gas-reviewer` + `security-reviewer`
   - high-risk → `logic-reviewer` + `gas-reviewer` + `security-reviewer`
   - If review_triggers match (spec file changes) → also dispatch `spec-reviewer`.
5. **Remediation cycle** — max 5 rounds (from remediation_policy.max_cycles):
   - All findings info/minor → continue to step 6.
   - Severity ≥ major → forward reviewer's raw output to the appropriate writer → re-review.
   - Severity = critical → block, present findings to user for decision.
   - User override critical → record residual risk, continue.
   - Reviewer conflict → resolve by conflict_priority order (security-reviewer > gas-reviewer > logic-reviewer).
6. **Security tests** — If risk_tier=high-risk AND security_test_writer_trigger matches, dispatch `security-test-writer`.
7. **Verify** — Dispatch `verifier` to run `bash script/harness/gate.sh --profile <profile>`. Report exit code + stdout.
8. **Conclude** — Report final verdict based on latest gate output. Do not claim completion without fresh gate evidence.

### Retry routing

- surface=solidity_prod/test → route back to `solidity-implementer`
- surface=harness_control → route back to `process-implementer`
- security test fixes → route back to `security-test-writer`

### When NOT to trigger harness

- User asks a question without requesting code changes
- User requests exploration only
- Task is purely conversational

## Repository Truth

- .harness/policy.json is the machine truth for ownership, classification, review routing, verification profiles, and hard blocks.
- docs/TRACEABILITY.md lists control files and artifact locations.
- Other repository docs are context only unless policy or gate evidence explicitly points to them.

## Upgrade Boundaries

Escalate instead of deciding locally when a change would:
- alter product semantics, fund flow, permission semantics, security assumptions, or upgrade behavior
- change the acceptance threshold for residual risk
- cross the current task scope into unrelated restructuring or product changes

## Repo Focus

High-sensitivity areas in this repo:
- lifecycle and stage transitions
- fund routing and fee distribution
- swap and hook boundaries
- cross-chain registration, dispatch, and interoperation semantics
- initializer, proxy, and governance upgrade correctness
