---
paths:
  - "test/**/*.sol"
  - "test/**/*.t.sol"
---

# Solidity Test Surface Rules

## Writer

- Default writer: `solidity-implementer`
- `security-test-writer` 仅在 `security-reviewer` 明确要求或高风险路径时按需启用

## Required Review Order

- `solidity-implementer` → `logic-reviewer` → `codex review` → `verifier`
- 高风险测试变更可选加 `security-reviewer`

## Required Commands

- `forge test -vvv`
- `npm run quality:gate`

## Required Artifacts

- Task Brief
- Agent Report
