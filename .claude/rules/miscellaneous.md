---
paths:
  - "foundry.toml"
  - "remappings.txt"
  - "README.md"
  - ".github/**"
  - ".gitignore"
---

# Miscellaneous Surface Rules

## Writer

- Default writer: `process-implementer`
- 不得修改任何 `src/**/*.sol`、`script/**/*.sol`、`test/**/*.sol`

## Required Review Order

- `process-implementer` → `codex review` → `verifier`

## Required Commands

- `foundry.toml`：`forge build` + `forge test -vvv`
- `.github/`：无本地命令（PR verify 由 CI 执行）
- `npm run quality:gate`

## Required Artifacts

- Task Brief（简要即可，写明变更动机与影响面）
- Agent Report
- 证据链：`Task Brief → Agent Report → codex review → verifier evidence → quality:gate`
