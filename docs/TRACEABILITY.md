# MemeverseV2 Traceability

- Machine truth: .harness/policy.json
- Session contract: .harness/runtime/main-session-contract.md
- Policy schema: .harness/schemas/policy.schema.json
- Claude agents: .claude/agents/*
- Codex agents: .codex/agents/*
- Enforcement entrypoint: script/harness/gate.sh
- CI gate entrypoint: script/harness/ci-gate-entrypoint.sh

Mixed `harness_control` + Solidity changed-file sets are legal. The gate reports the highest risk tier across the set, review roles are the union of matched policy roles, and writer may be `mixed`. Spec readiness remains a pre-implementation gate for `prod-semantic` and `high-risk` sets, and spec document changes still require explicit human confirmation before implementation proceeds.

For `prod-semantic` Solidity, the intended flow is two-step:

1. run the required spec/document workflow
2. classify code changes separately

For code-only classification, the `spec-readiness-doc-update` block may clear when all mapped required docs are already present in the current diff scope. The same diff-scope exception also applies to mixed docs+code `prod-semantic` sets, but only when that diff scope already contains the full mapped required-doc set for the code under review. This exception clears only the residual `spec-readiness-doc-update` block; it does not bypass the two-step spec-readiness flow or lower mixed docs+code `prod-semantic` sets below the existing `full-review` minimum.
