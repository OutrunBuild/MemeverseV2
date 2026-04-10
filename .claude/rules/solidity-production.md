---
paths:
  - "src/**/*.sol"
  - "script/**/*.sol"
---

# Solidity Production Surface Rules

## STOP — 你是 main-orchestrator？

如果是，你不能直接写这些文件。停止并派发 `solidity-implementer`。
派发失败 → 停止并请求人工决策。

## Writer

- `solidity-implementer`

## Review

- `npm run classify:change` → AGENTS.md §5 对应流程

## Required Commands

- `forge build`
- `forge test -vvv`
- `forge fmt --check`
- `npm run quality:gate`

## Prerequisites

- 必须有有效 Task Brief（AGENTS.md §10 hard-block）
