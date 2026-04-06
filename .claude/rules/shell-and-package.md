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

## Required Artifacts

- Task Brief（包管理变更写明依赖变更原因与影响；hook 变更写明触发场景）
- Agent Report（`package.json` / `.githooks` 变更可简化为 inline Agent Report summary）
- 证据链：`Task Brief → Agent Report → codex review → verifier evidence → quality:gate`
