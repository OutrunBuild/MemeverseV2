# 开发流程产物说明

`AGENTS.md` 是仓库的主要操作入口。本目录存放与开发流程相关的补充文档、机器可读策略源以及脚本所依赖的结构定义。

使用原则：

- `AGENTS.md` 负责日常操作契约、入口命令、完成定义和关键上下文。
- 本目录负责保存细化规则、Review note 结构说明以及机器可读配置。
- 如果规则影响脚本、CI 或提交门禁，文档变更必须和脚本变更一起提交。
- `docs/process/policy.json` 是当前流程规则的机器可读真源。
- `docs/process/rule-map.json` 是关键行为场景到测试证据的机器可读映射，同时记录测试联动要求与测试治理缺口。

详细规则见：

- `docs/process/change-matrix.md`
- `docs/process/review-notes.md`
- `docs/process/policy.json`
- `docs/process/rule-map.json`
