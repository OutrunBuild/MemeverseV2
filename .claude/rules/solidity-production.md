---
paths:
  - "src/**/*.sol"
  - "script/**/*.sol"
---

# Solidity Production Surface Rules

## Writer

- `solidity-implementer`

## Review

- `npm run classify:change` → AGENTS.md §5 对应流程

## Required Commands

- `forge build`
- `forge test -vvv`
- `forge fmt --check`
- `npm run quality:gate`
