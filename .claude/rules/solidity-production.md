---
paths:
  - "src/**/*.sol"
  - "script/**/*.sol"
---

# Solidity Production Surface Rules

## Writer

- Default writer: `solidity-implementer`
- 单写 owner：同一批 Solidity 文件在同一时间只能有一个实现型写入者

## Required Review Order

按变更分类选择审阅流程：

- `non-semantic`：`solidity-implementer` → `codex review` → `verifier(light)`
- `test-semantic`：`solidity-implementer` → `logic-reviewer` → `codex review` → `verifier(light)`
- `prod-semantic`：`solidity-implementer` → `logic-reviewer` → `security-reviewer` → `gas-reviewer` → `codex review` → `verifier(full)`
- `high-risk`：同 `prod-semantic`，优先考虑 `security-test-writer` 补强测试

## Required Commands

- `forge build`
- `forge test -vvv`
- `forge fmt --check`
- `npm run quality:gate`（唯一 finish gate）

## Required Artifacts

- Task Brief（含 `Change classification`、`Files in scope`、`Write permissions`）
- Agent Report
- Review note（命中 `src/**/*.sol` 或 `script/**/*.sol` 时必须）
- Evidence chain: `Task Brief → Agent Report → codex review → review note → verifier evidence → quality:gate`

## Verifier Profiles

- `light`：用于 `non-semantic` 和 `test-semantic`，可跳过重度 coverage/static-analysis/gas gate
- `full`：用于 `prod-semantic` 和 `high-risk`，必须跑完整 Solidity gate

## Optional Roles

- `solidity-explorer`：复杂改动前的影响面侦察
- `security-test-writer`：高风险改动后的 fuzz / invariant / adversarial tests 补强
