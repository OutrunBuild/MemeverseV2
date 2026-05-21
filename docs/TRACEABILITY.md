# MemeverseV2 Traceability

- Machine truth: .harness/policy.json
- Session contract: .harness/runtime/main-session-contract.md
- Policy schema: .harness/schemas/policy.schema.json
- Claude agents: .claude/agents/*
- Codex agents: .codex/agents/*
- Enforcement entrypoint: script/harness/gate.sh
- CI gate entrypoint: script/harness/ci-gate-entrypoint.sh

Mixed `harness_control` + Solidity changed-file sets are legal. The gate reports phase fields for `harness_writer_roles`, `spec_review_required`, `code_writer_roles`, and `code_review_roles`.

For `prod-semantic` work, classification precedes dispatch. The main session dispatches each phase from those emitted fields.
