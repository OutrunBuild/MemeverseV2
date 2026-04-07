---
paths:
  - "script/**/*.sh"
  - ".githooks/*"
  - "package.json"
  - "package-lock.json"
---

# Shell and Package Metadata Rules

## Writer

- `process-implementer`

## Review

- AGENTS.md §5 流程面变更流程

## Required Commands

- `bash -n <changed>.sh`
- `npm ci`
- `npm run quality:gate`
