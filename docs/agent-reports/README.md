# Agent Reports

本目录只存放 `Agent Report` 工件。

Rules:

- 使用 `.codex/templates/agent-report.md` 作为模板
- 命中需要落盘 report 的流程时，`Agent Report path` 必须指向本目录下的实际文件
- 按 `.codex/templates/agent-report.md`，核心 6 个 `required` fields 是 `Role`、`Summary`、`Task Brief path`、`Scope / ownership respected`、`Files touched/reviewed`、`Residual risks`
- 按 `.codex/templates/agent-report.md`，核心 4 个 `conditional` fields 是 `Findings`、`Required follow-up`、`Commands run`、`Evidence`
- `conditional` 字段可以省略，但如果某个角色的结论依赖它，就必须填写
- 文件名建议包含日期、角色与主题，例如 `2026-03-27-process-implementer-three-directory-split.md`
