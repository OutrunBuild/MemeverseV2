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
- Derive `surface`, `risk_tier`, `writer_role`, `review_roles`, and `verification_profile` from policy before delegating.
- Use only project agents under `.claude/agents/` or `.codex/agents/` for delegated work.
- Completion claims require the latest matching `gate.sh` output.
- If changed files imply conflicting writer ownership or mixed blocked surfaces, stop as blocked instead of inventing fallback routing.
- If required verification evidence is missing, keep the final verdict blocked or fail instead of projecting pass.
