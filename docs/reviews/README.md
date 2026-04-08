# Review Notes

本目录存放 review note 模板与使用说明。契约真源在 `docs/process/review-notes.md` 与 `docs/process/policy.json`。

Rules:

- 统一基于 `docs/reviews/TEMPLATE.md` 填写。
- 正文默认使用简体中文，固定 section / field key 保持英文。
- `Behavior change`、`ABI change`、`Storage layout change`、`Config change`、`Writer dispatch confirmed`、`Evidence chain complete`、`Ready to commit` 只能填写 `yes` 或 `no`。
- 当改动命中 `src/**/*.sol` 且准备运行 `quality:gate` 时，必须提供一份可通过校验的 review note。
- `Task Brief path` 必须指向 `docs/task-briefs/` 下的实际 brief。
- `Agent Report path` 必须指向 `docs/agent-reports/` 下的实际 report。
- `Existing tests exercised` 必须真实记录已执行测试；若仓库启用了 repo-specific 证据映射，也必须满足该映射约束。
- `Security evidence source`、`Gas evidence source`、`Verification evidence source`、`Decision evidence source` 采用 `role: source` 格式。
- `Commands run`、`Results`、`Verification evidence source` 仍归 `verifier` 负责；writer 侧字段轻量化不会减轻 `verifier` 对验证命令、验证 verdict 和相关证据的责任。
- 不要保留 `TBD`、`<path>`、`<path>|none`、`<selectors or paths>`、`yes/no` 等占位值。
- verification 必须记录同一工作树状态下实际执行过的命令和结果。
- 目录默认被 `.gitignore` 忽略；如需共享，请显式转移到协作载体或手动取消忽略。
- 若仓库跟踪了特定 review note 文件，也必须让它与当前 gate 语义保持一致。
