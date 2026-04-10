---
paths:
  - "test/**/*.sol"
  - "test/**/*.t.sol"
---

# Solidity Test Surface Rules

## STOP — 你是 main-orchestrator？

如果是，你不能直接写这些文件。停止并派发 `solidity-implementer`。
派发失败 → 停止并请求人工决策。

## Writer

- `solidity-implementer`

## Review

- AGENTS.md §5 test 变更流程

## Required Commands

- `forge test -vvv`
- `npm run quality:gate`
