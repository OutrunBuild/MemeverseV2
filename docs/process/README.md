# 开发流程规则总览

本目录存放仓库开发流程的可审阅真源。

使用原则：

- `AGENTS.md` 只保留高杠杆、短规则、失败条件和入口命令。
- 本目录解释这些规则为什么存在、触发范围是什么、哪些脚本负责执行。
- 如果规则影响 hook、CI 或提交门禁，文档变更必须和脚本变更一起提交。
- `docs/process/policy.json` 是当前流程规则的机器可读真源。
- `docs/process/rule-map.json` 是关键模块规则到测试证据的机器可读映射。

当前已落地范围：

- 将仓库根目录 `AGENTS.md` 纳入版本控制。
- 用路径触发矩阵约束 `src/**/*.sol` 变更。
- 用结构化 review note 取代“只有标题的审计记录”。
- 用 `npm run docs:check` 验证生成文档流程，而不是把生成文档当作提交产物。
- 用 `script/check-natspec.sh` 对变更过的 `src/**/*.sol` 做最小 NatSpec lint。
- 用 PR template 和 PR body 结构检查约束 GitHub 合并入口。

文档语言约定：

- 仓库内新增的自然语言文档默认使用简体中文
- `docs/reviews/*.md` 为兼容现有 gate，固定 section / field key 保持英文，其余说明与正文使用简体中文
- 命令、路径、代码标识、协议名、库名保持英文原文

详细规则见：

- `docs/process/change-matrix.md`
- `docs/process/review-notes.md`
- `docs/process/policy.json`
- `docs/process/rule-map.json`
