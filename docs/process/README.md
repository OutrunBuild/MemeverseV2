# 开发流程规则总览

本目录存放仓库开发流程的可审阅真源。

使用原则：

- `AGENTS.md` 只保留高杠杆、短规则、失败条件和入口命令。
- 本目录解释这些规则为什么存在、触发范围是什么、哪些脚本负责执行。
- 如果规则影响 hook、CI 或提交门禁，文档变更必须和脚本变更一起提交。

当前 P0 范围：

- 将仓库根目录 `AGENTS.md` 纳入版本控制。
- 用路径触发矩阵约束 `src/**/*.sol` 变更。
- 用结构化 review note 取代“只有标题的审计记录”。
- 用 `npm run docs:check` 验证生成文档流程，而不是把生成文档当作提交产物。

详细规则见：

- `docs/process/change-matrix.md`
- `docs/process/review-notes.md`
