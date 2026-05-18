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
- Derive `change_class`, `surface_sensitivity`, `orchestration_profile`, `selected_writer_roles`, and `selected_review_roles` from policy/gate evidence before delegating.
- Current local task completion defaults to `gate:fast`. Use `full`, `ci`, release, or merge-equivalent verification only when explicitly requested or running in that context.
- Current Solidity contracts are pre-deployment development artifacts unless a human explicitly says deployed compatibility must be preserved.
- Review roles remain reviewer-only; do not place verifier inside review roles.
- Project agent files under .claude/agents/ and .codex/agents/ are execution files. They do not define policy or verdict rules.
- Do not create a parallel control plane outside policy, gate, and project agent files.
- Deleting untracked files from the current git working tree requires explicit human confirmation.

## Verification Contract

- gate.sh is the enforcement entrypoint.
- Completion, readiness, or pass claims require fresh output from the selected matching gate profile.
- For local current work, invoke `gate.sh` with the exact changed-file set. If any Solidity file is involved, also provide diff evidence via `CHANGE_CLASSIFIER_DIFF_FILE` or `GATE_DIFF_BASE`.
- See docs/VERIFICATION.md for profile meanings and command entrypoints.

## Harness Dispatch Procedure

When `.harness/policy.json` exists and the task modifies repository files, follow this procedure.

### Mandatory Pre-condition

Run `bash script/harness/gate.sh --classify-only --changed-files <path>` before editing. Do not use stale mental classification.

### Surface Completeness

Every file that will be modified or created must match a surface pattern in policy.json. Unknown paths are blocked until policy is updated.

### Flow

1. **Classify** - run `gate.sh --classify-only` with exact changed files and Solidity diff evidence when needed.
2. **Docs/spec readiness** - if spec docs or spec-readiness updates are required, dispatch `process-implementer`, require `spec-reviewer`, then obtain human confirmation before code implementation.
3. **Direct** - main session may edit; no writer/reviewer dispatch; run `gate:fast`.
4. **Direct-review** - main session may edit; dispatch `selected_review_roles`; run `gate:fast` after review.
5. **Delegated** - dispatch `selected_writer_roles`; dispatch `selected_review_roles` from `delegated_review_rules`; main session runs `gate:fast` after integration.
6. **Full-review** - dispatch `selected_writer_roles`; dispatch reviewers from `full_review_matrix[change_class]`; main session runs `gate:fast` after integration.
7. **Full-subagent** - dispatch writer, reviewers, and verifier; verifier runs the selected gate profile and reports output.
8. **Blocked** - stop before editing.

Production Solidity semantic changes without structural escalation require a Risk Analysis Record before selecting `direct-review`. If analysis is incomplete or uncertain, use at least `full-review`.

README.md editorial-only direct changes require a Doc Editorial Attestation. README workflow, gate, verification, policy, command, CI, or repository-truth semantics are `delegated`.

## Retry Routing

- surface=solidity_prod/test -> route back to `solidity-implementer`
- surface=harness_control -> route back to `process-implementer`
- spec readiness gate failure -> route to `process-implementer` for doc update

## When Not To Trigger Harness

- User asks a question without requesting code changes
- User requests exploration only
- Task is purely conversational

## Repository Truth

- .harness/policy.json is the machine truth for ownership, classification, review routing, verification profiles, and hard blocks.
- docs/TRACEABILITY.md lists control files and artifact locations.
- Other repository docs are context only unless policy or gate evidence explicitly points to them.

## Escalation Boundaries

Escalate instead of deciding locally when a change would alter product semantics, fund flow, permission semantics, security assumptions, upgrade behavior, or acceptance thresholds for residual risk.
