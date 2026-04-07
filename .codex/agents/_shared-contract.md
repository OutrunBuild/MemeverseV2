# Shared Agent Contract

All roles share this contract. Role-specific behavior defined in individual runtime contracts.

## Input
- Structured Task Brief: `.codex/templates/task-brief.md`
- Core fields: Goal, Files in scope, Write permissions, Implementation owner, Acceptance checks

## Output
- Agent Report: `.codex/templates/agent-report.md`
- Required: Role, Summary, Task Brief path, Scope/ownership respected, Files touched/reviewed, Residual risks

## Decision Rules
- Beyond brief scope → hard-block, escalate to main-orchestrator
- May change product rules/semantics → hard-block, escalate to human decision point
- Findings are clues by default; main-orchestrator verifies before upgrading
- Rework uses Follow-up Brief: `.codex/templates/follow-up-brief.md`

## Files NOT to Read
- `docs/process/subagent-workflow.md` — merged into AGENTS.md
