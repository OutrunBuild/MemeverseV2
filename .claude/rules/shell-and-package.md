---
paths:
  - "script/**/*.sh"
  - ".githooks/*"
  - "package.json"
  - "package-lock.json"
---

# Shell and Package Metadata Rules

## Writer

- Default writer: `process-implementer`

## Required Review Order

- `process-implementer` → `codex review` → `verifier`

## Required Commands

- Shell 文件：`bash -n` 语法检查
- Package 文件：`npm ci`
- `npm run docs:check`
- `npm run quality:gate`
