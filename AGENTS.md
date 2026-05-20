# AGENTS Contract

## Goal

Route repository work through the harness without violating policy, ownership, review, or verification rules.

## Success Criteria

A task is complete only when:

- the intended changed-file set is known, or the task is reported blocked
- every edited path is classified by `gate.sh --classify-only` before editing
- every edited path matches `.harness/policy.json`
- writer, reviewer, and verifier routing follows policy and gate evidence
- fresh matching `gate.sh` output supports the final verdict

## Session Entry

- AGENTS.md is the session entry for MemeverseV2.
- Load only the files needed for the current task. When multiple control files are needed, read order is fixed:
  1. AGENTS.md
  2. .harness/policy.json
  3. .harness/runtime/main-session-contract.md
  4. docs/TRACEABILITY.md when you need control-file or artifact locations
  5. docs/VERIFICATION.md when you need verification profile or verdict rules
  6. script/harness/gate.sh when you need enforcement details or emitted evidence

## Truth Precedence

1. explicit human instruction for task intent and requested scope
2. .harness/policy.json
3. script/harness/gate.sh results
4. AGENTS.md and .harness/runtime/main-session-contract.md
5. other repository docs

Human instruction does not override safety, filesystem, policy, gate, or verification constraints.
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

## High-Priority Beginner-Readable Code

- This section is high-priority. Optimize for code a beginner can read top to bottom.
- Favor beginner-readable names over protocol jargon, abbreviations, or internal shorthand.
- If a specialized term must stay, explain it at first use in a short local comment.
- Add short implementation comments for non-obvious business logic, invariants, or cross-step reasoning. NatSpec alone is not enough.
- Many tiny single-use helpers make code harder to follow because readers must jump around.
- Extract a helper only when it clearly improves readability, naming, reuse, or testability.
- Inline trivial single-use logic unless extraction clearly improves comprehension.

## Ownership And Concurrent-Write Guard

- Before editing any dirty target file, run an ownership check with `git status --short` plus a path-scoped `git diff --name-only` or equivalent.
- If a target file contains changes not made by the current main session or current assigned writer, do not delete, revert, or overwrite those changes.
- If concurrent or foreign edits affect the same target files, stop writing and establish ownership or merge strategy before any further edits.
- Treat out-of-scope existing changes as foreign-owned by default: report them or request direction. Only remove out-of-scope changes introduced by the current session or assigned writer.
- Maintain one active writer per file set. Reviewers stay read-only; if review requires changes, route back to the assigned writer or explicitly transfer ownership before editing.
- Gate or review failures do not authorize overwriting foreign edits. First determine whether the failure comes from owned changes or foreign changes.

## Context Scope

- Use the minimum repository context needed to classify, route, edit, review, and verify the task.
- Do not read Solidity code for harness/docs-only work unless a policy rule or requested change depends on Solidity surface classification.
- Do not read `script/harness/gate.sh` when policy, runtime, or verification docs already answer the routing question.
- If tool output is empty, partial, or suspicious, retry once with a different command before treating it as evidence.

## Verification Contract

- gate.sh is the enforcement entrypoint.
- Completion, readiness, or pass claims require fresh output from the selected matching gate profile.
- For local current work, invoke `gate.sh` with the exact changed-file set. If any Solidity file is involved, also provide diff evidence via `CHANGE_CLASSIFIER_DIFF_FILE` or `GATE_DIFF_BASE`.
- See docs/VERIFICATION.md for profile meanings and command entrypoints.

## Harness Dispatch Procedure

When `.harness/policy.json` exists and the task modifies repository files, follow this procedure.

### Mandatory Pre-condition

After the intended changed-file set is known and before the first edit, run `bash script/harness/gate.sh --classify-only --changed-files <path>` with exact existing paths and intended-created paths. If the changed-file set is not knowable yet, inspect only enough context to identify candidate paths, then classify before editing.

Do not use stale mental classification.

### Surface Completeness

Every file that will be modified or created must match a surface pattern in policy.json. Unknown paths are blocked until policy is updated.

### Flow Source

Follow the `orchestration_profile`, writer roles, review roles, verifier requirement, and blockers emitted by policy and gate evidence. Use `.harness/runtime/main-session-contract.md` for detailed flow rules.

Production Solidity semantic changes without structural escalation require a Risk Analysis Record before selecting `direct-review`. If analysis is incomplete or uncertain, use at least `full-review`.

README.md editorial-only direct changes require a Doc Editorial Attestation. README workflow, gate, verification, policy, command, CI, or repository-truth semantics are `delegated`.

## Retry Routing

- surface=solidity_prod/test -> route back to `solidity-implementer`
- surface=harness_control -> route back to `process-implementer`
- spec readiness gate failure -> route to `process-implementer` for doc update
- For code-only classification, the `spec-readiness-doc-update` block may be cleared when the mapped required docs are already present in the current diff scope after the spec/document workflow has been handled separately.

## When Not To Trigger Harness

- User asks a question without requesting code changes
- User requests exploration only
- Task is purely conversational

## Repository Truth

- .harness/policy.json is the machine truth for ownership, classification, review routing, verification profiles, and hard blocks.
- docs/TRACEABILITY.md lists control files and artifact locations.
- Other repository docs are context only unless policy or gate evidence explicitly points to them.

## Completion Loop

Before final response, check:

- all requested files or items are handled, or marked blocked
- no edited path is outside the classified surface
- validation command and result are fresh
- final answer reports only completed work, validation, and blockers

## Escalation Boundaries

Escalate instead of deciding locally when a change would alter product semantics, fund flow, permission semantics, security assumptions, upgrade behavior, or acceptance thresholds for residual risk.
