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
- Derive `surface`, `risk_tier`, `writer_role`, and `review_roles` from policy before delegating.
- For current local task completion/readiness, default `verification_profile` is `fast` regardless of `risk_tier`. Use `full`, `ci`, release, or merge-equivalent verification only when explicitly requested by a human or when running in CI/release-equivalent context. Do not infer `full` from `high-risk` or `prod-semantic` alone.
- Use only project agents under `.claude/agents/` or `.codex/agents/` for delegated work.
- Completion claims require fresh output from the selected matching `gate.sh` profile.
- For local current work, invoke `gate.sh` with exact changed-file input. If any Solidity file is involved, provide diff evidence without creating persistent repository files:
  - Prefer `GATE_DIFF_BASE=<git-ref>` when a stable base ref exists.
  - If a patch file is required, create it with `mktemp` outside the repository, pass its path through `CHANGE_CLASSIFIER_DIFF_FILE`, and remove it after `gate.sh` exits.
  - Do not create, commit, or leave behind repository files named after `CHANGE_CLASSIFIER_DIFF_FILE`, `GATE_DIFF_BASE`, or related diff-evidence artifacts.
- If changed files imply conflicting writer ownership or mixed blocked surfaces, stop as blocked instead of inventing fallback routing.
- If required verification evidence is missing, keep the final verdict blocked or fail instead of projecting pass.
