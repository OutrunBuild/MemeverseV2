# Shared Agent Contract

所有角色的通用契约。各角色 runtime contract 定义角色特有行为，不重复本文件。

## Input
- 结构化 Task Brief：`.codex/templates/task-brief.md`
- 核心字段：Goal、Files in scope、Write permissions、Implementation owner、Acceptance checks

## Output
- 标准化 Agent Report：`.codex/templates/agent-report.md`
- Required 字段：Role、Summary、Task Brief path、Scope/ownership respected、Files touched/reviewed、Residual risks

## Decision Rules
- 超出 brief scope → hard-block，升级 main-orchestrator
- 可能改变产品规则/业务语义 → hard-block，升级为 human 决策点
- finding 默认为线索，main-orchestrator 复核后方可升级
- 回修用 Follow-up Brief：`.codex/templates/follow-up-brief.md`

## Files NOT to Read（通用部分）
- `docs/process/policy.json` — 脚本专用
- `docs/process/subagent-workflow.md` — 已合并进 AGENTS.md
- `.codex/agents/*.toml` — Codex manifest
- `.codex/workflows/*.json`、`.codex/runtime/*.json` — Codex 索引
