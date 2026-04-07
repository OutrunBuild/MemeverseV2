# Agent Detail Reference

本文件是 AGENTS.md §8 和 §9 的完整展开版，供 main-orchestrator 和按需加载使用。

---

## §A: Shared Agent Contract（完整版）

所有角色的通用输入、输出与决策规则。各角色 runtime contract 只需定义角色特有行为，不需要重复本节。

#### 通用输入

- 结构化 Task Brief（分级模板见 `.codex/templates/task-brief.md`）
- 核心字段：`Goal`、`Files in scope`、`Write permissions`、`Implementation owner`、`Writer dispatch backend`、`Acceptance checks`、`Required verifier commands`
- 语义敏感改动需额外：`Semantic review dimensions`、`Source-of-truth docs`、`External sources required`、`Critical assumptions to prove or reject`

#### 通用输出

标准化 Agent Report（模板见 `.codex/templates/agent-report.md`）：
- Required：`Role`、`Summary`、`Task Brief path`、`Scope / ownership respected`、`Files touched/reviewed`、`Residual risks`
- Conditional：`Findings`、`Required follow-up`、`Commands run`、`Evidence`

#### 通用决策规则

- 超出 brief scope 的写入 → hard-block，升级给 main-orchestrator
- 产品规则 / 业务语义可能被改变 → hard-block，升级为需要 human 确认的决策点
- reviewer / verifier finding 默认只是线索，main-orchestrator 必须复核关键代码行与前提后才能升级
- 回修轮次改用 Follow-up Brief（`.codex/templates/follow-up-brief.md`），明确 remediation scope、已失效 evidence 与 rerun order

## §B: Workflow Phases（完整版）

#### Phase 1: 接收 / 划定范围

- `main-orchestrator` 创建 Task Brief（必须让未继承主会话历史的下游角色也能独立理解目标、边界与阻断条件）
- 对语义敏感改动，Task Brief 必须显式写出语义维度、真源文档、外部来源与关键假设
- 如影响面不清、跨模块，可按需启用 `solidity-explorer`

#### Phase 2: 基线分析

- 运行 `npm run classify:change` 判定 `non-semantic` / `test-semantic` / `prod-semantic` / `high-risk`
- Task Brief 必须同步写出 Change classification、rationale 与 Verifier profile

#### Phase 3: 实现

- writer 在明确 ownership 下修改实现、补充注释与测试
- `main-orchestrator` 不得降级为直接实现者；派发失败只能停止并请求人工决策
- 不得未经派发扩大文件边界

#### Phase 4: 逻辑审阅（`test-semantic`+）

- `logic-reviewer` 做只读逻辑审阅，覆盖控制流、状态迁移、边界条件
- 若 writer 再次改写同一 scope，上一轮证据自动失效，必须重跑

#### Phase 5: 专家审阅（`prod-semantic`+）

- `security-reviewer` 与 `gas-reviewer` 输出只读结论
- review 必须先核本地前提（关键控制流、状态更新、金额处理、权限检查），再核验外部来源

#### Phase 6: 测试加固（`high-risk` 或 security-reviewer 指出缺口）

- `security-test-writer` 只修改测试，不修改生产逻辑

#### Phase 7: 验证

- `verifier` 按 light / full 两档执行验证命令
- 必须独立检查 Task Brief、Agent Report、review note 与 failure attribution
- stale evidence（早于当前 writer Agent Report）必须阻断
- stale evidence 被 gate 检出时，自动生成 follow-up brief，`main-orchestrator` 按 rerun order 重新派发

#### Phase 8: 决策

- `main-orchestrator` 汇总全部证据，仅在证据链完整时允许进入 finish gate
