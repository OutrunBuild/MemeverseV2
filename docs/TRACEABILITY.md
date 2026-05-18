# MemeverseV2 Traceability

- Machine truth: .harness/policy.json
- Session contract: .harness/runtime/main-session-contract.md
- Policy schema: .harness/schemas/policy.schema.json
- Claude agents: .claude/agents/*
- Codex agents: .codex/agents/*
- Enforcement entrypoint: script/harness/gate.sh
- CI gate entrypoint: script/harness/ci-gate-entrypoint.sh

Mixed `harness_control` + Solidity changed-file sets are legal. The gate reports the highest risk tier across the set, review roles are the union of matched policy roles, and writer may be `mixed`. Spec readiness remains a pre-implementation gate for `prod-semantic` and `high-risk` sets, and spec document changes still require explicit human confirmation before implementation proceeds.
