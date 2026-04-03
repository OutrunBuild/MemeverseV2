---
paths:
  - "script/process/**"
  - "docs/process/**"
  - ".codex/**"
  - ".claude/**"
  - "AGENTS.md"
  - "CLAUDE.md"
---

# Process Surface Rules

## Writer

- Default writer: `process-implementer`
- 不得修改任何 `src/**/*.sol`、`script/**/*.sol`、`test/**/*.sol`

## Required Review Order

- `process-implementer` → `codex review` → `verifier`

## Required Commands

- `npm run docs:check`
- 命中 runtime / policy / template / agent contract / workflow index / process script 时：`npm run process:selftest`
- `npm run quality:gate`

## Required Artifacts

- Task Brief
- Agent Report
- Evidence chain: `Task Brief → Agent Report → codex review → verifier evidence → docs:check / process:selftest`

## Notes

- 命中 `script/process/**`、`docs/process/policy.json`、`package.json`、`package-lock.json` 或 `.codex/runtime/**` 时，gate 会自动补跑 `process:selftest`
- 命中 `script/process/**/*.js` 时，gate 会执行 `node --check` 作为 JS 语法检查
