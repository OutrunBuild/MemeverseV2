# 开发流程产物说明

`AGENTS.md` 是仓库的主要操作入口。本目录存放与开发流程相关的补充文档、机器可读策略源以及脚本所依赖的结构定义。

使用原则：

- `AGENTS.md` 负责日常操作契约、入口命令、完成定义和关键上下文。
- 本目录负责保存细化规则、review note 结构说明以及机器可读配置。
- 如果规则影响脚本、CI 或提交门禁，文档变更必须和脚本变更一起收敛。
- 代码可读性、测试完备性、writer ownership、review note 责任分工等叙述性规则，以 `AGENTS.md`、`docs/process/change-matrix.md`、`docs/process/review-notes.md` 与 `.codex/agents/*.md` 的一致表述为准。
- `docs/process/policy.json` 是当前流程规则的机器可读真源。
- 若仓库启用了 repo-specific 扩展（例如 `docs/process/rule-map.json`），它同样属于本目录的机器真源，不会被通用 Harness 文案替代。
- `script/process/` 顶层保留正式流程入口；`script/process/tests/` 保留这些流程脚本的自测，可通过 `npm run process:selftest` 统一执行。

详细规则见：

- `docs/process/change-matrix.md`
- `docs/process/review-notes.md`
- `docs/process/policy.json`
- 若存在：`docs/process/rule-map.json`
