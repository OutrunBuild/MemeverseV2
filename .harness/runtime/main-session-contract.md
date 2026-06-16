# Main Session Contract

## Read Order

1. `AGENTS.md`
2. `.harness/policy.json`
3. this file
4. `docs/TRACEABILITY.md` when you need control-file or artifact locations
5. `docs/VERIFICATION.md` when you need verification profile or verdict rules
6. `script/harness/gate.sh` when you need enforcement details or emitted evidence

## Truth Precedence

1. explicit human instruction
2. `.harness/policy.json`
3. `script/harness/gate.sh` results
4. `AGENTS.md` and this file
5. other repository docs

## Main-Session Rules

- `main-orchestrator` stays in the primary session and is never a project agent file.
- Every repository modification must go through `gate.sh --classify-only --planned-files <path> [<path> ...]` before editing.
- Dispatch and review are selected by policy-derived `orchestration_profile`.
- Derive `change_class`, `surface_sensitivity`, `orchestration_profile`, `harness_writer_roles`, `code_writer_roles`, and `code_review_roles` from policy/gate evidence before delegating.
- For `prod-semantic` work, the main session decides whether spec/docs or other harness-control changes are needed before dispatching `harness_writer_roles`, `code_writer_roles`, or `code_review_roles`.
- If the main session decides spec/docs changes are required, complete that spec/doc writing round first and dispatch `spec-reviewer` immediately after the spec/doc changes are ready, before any code writer is dispatched.
- `spec-reviewer` dispatch is a main-session orchestration hook, not a `gate.sh` output field. Separately, `requires_human_confirmation` remains a policy signal for spec/doc paths and does not itself decide reviewer dispatch.
- Main session may directly modify files only for `direct` and `direct-review`.
- Main session must not author `delegated`, `full-review`, or `full-subagent` changes except to integrate approved subagent output.
- Do not dispatch writer or reviewer agents for `direct`.
- Use only project agents under `.claude/agents/` or `.codex/agents/` for delegated work.
- Do not bypass `process-implementer`, `spec-reviewer`, or human confirmation for docs/spec changes.
- Production Solidity semantic changes without structural escalation require a main-session Risk Analysis Record before using `direct-review`; otherwise use `full-review`.
- README.md editorial-only direct changes require a Doc Editorial Attestation; otherwise use `delegated`.
- `direct-review` reviewer roles come from `orchestration_review_roles`, not `full_review_matrix`.
- Dispatch consumes resolved `harness_writer_roles`, `code_writer_roles`, and `code_review_roles`.
- For pre-edit routing, invoke `gate.sh --classify-only` with exact planned-file input through `--planned-files`. Planned Solidity files are conservatively classified as semantic because no diff exists yet.
- For local current-work verification on tracked or intended-to-commit repository changes, invoke `gate.sh` with exact changed-file input through `--changed-files`. If any Solidity file is involved, provide diff evidence without creating persistent repository files:
  - Prefer `GATE_DIFF_BASE=<git-ref>` when a stable base ref exists.
  - If a patch file is required, create it with `mktemp` outside the repository, pass its path through `CHANGE_CLASSIFIER_DIFF_FILE`, and remove it after `gate.sh` exits.
  - Do not create, commit, or leave behind repository files named after `CHANGE_CLASSIFIER_DIFF_FILE`, `GATE_DIFF_BASE`, or related diff-evidence artifacts.
- Ignored/local scratch artifacts are outside repository readiness. Do not use ignored scratch paths as `gate.sh` changed-file input for a repository PASS/BLOCKED verdict. Verify them with artifact-specific checks, report that result separately, and mark repository gate as not applicable.
- If an ignored/local artifact is intended to become a formal deliverable, first move it into a policy-classified tracked path or update policy so the path is classified; then run the matching gate before claiming repository readiness.
- If changed files imply multiple writer roles, route each touched surface to its configured writer; only stop as blocked when policy or gate evidence emits a hard block.
- Completion claims require fresh output from the selected matching `gate.sh` profile.
- If required verification evidence is missing, keep the final verdict blocked or fail instead of projecting pass.
- If Solidity surface or risk is unclear, inspect the related contracts, imports/inheritance, existing tests, and mapped spec documents before classifying. Do not rely on a separate explorer agent for this step.
