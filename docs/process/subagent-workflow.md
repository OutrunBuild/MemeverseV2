# Subagent Workflow

本文件定义 `MemeverseV2` 的默认 subagent Harness，把 `AGENTS.md` 的主契约拆成可执行阶段、角色职责、输入输出结构与 block 规则。

## 0. Harness 真源与边界

规范性真源以 `AGENTS.md` 的 `Source of Truth` 章节为准。本文件只展开 subagent 执行模型（角色、阶段、输入输出、证据链与 block 语义）。

为避免双重真源，本文件不重复改写 `rule-map.json`、`process:selftest` 与 generated-docs chain 的规范表述；需要时直接引用 `AGENTS.md`。

## 1. Agent File Model

`.codex/agents/` 使用同名双文件：

- `*.toml`：manifest / 入口层
- `*.md`：运行时契约 / 行为真源

若冲突，以同名 `*.md` 为准。

## 2. 角色模型

### 默认角色

- `main-orchestrator`：主会话编排，负责 intake、ownership、block、证据汇总
- `solidity-implementer`：Solidity 默认写入者
- `process-implementer`：非 Solidity 默认写入者
- `security-reviewer`：只读安全审阅
- `gas-reviewer`：只读 Gas 审阅
- `verifier`：只读验证与失败归因

### 按需角色

- `solidity-explorer`：预实现影响面侦察
- `security-test-writer`：安全测试补强

### Harness / Process 任务评审顺序

当任务主要触达 `.codex/**`、`AGENTS.md`、`README.md`、`docs/process/subagent-workflow.md`、`script/process/**` 时，required review order 为：

`main-orchestrator`（范围与契约复核） -> `verifier`

## 3. 阶段流

### Phase 1: Intake / Scoping

- `main-orchestrator` 产出 `Task Brief`
- 明确 `Files in scope`、`Write permissions`、`Required roles`

### Phase 2: Baseline Analysis

- Solidity 任务默认启用 `security-reviewer` + `gas-reviewer`
- 复杂 Solidity 任务可先启用 `solidity-explorer`

### Phase 3: Implementation

- Solidity 写入仅由 `solidity-implementer`（单写 owner）
- 非 Solidity 写入仅由 `process-implementer`
- 未重派发不得扩写路径

### Phase 4: Specialist Review

- Solidity 任务：安全与 Gas 并行只读审阅
- Harness/process 任务：由 `main-orchestrator` 复核契约一致性与角色边界

### Phase 5: Test Hardening

- 仅在高风险或安全审阅要求时启用 `security-test-writer`

### Phase 6: Verification

- `verifier` 执行/汇总 required commands
- required commands 任一失败即 hard-block

### Phase 7: Decision

- `main-orchestrator` 汇总证据并决定是否进入 `quality:gate` / CI

## 4. Task Brief / Agent Report 要求

### Task Brief 最少字段

- `Goal`
- `Change type`
- `Files in scope`
- `Risks to check`
- `Required roles`
- `Optional roles`
- `Default writer`
- `Write permissions`
- `Non-goals`
- `Acceptance checks`
- `Required output fields`
- `Review note impact`

模板路径：`.codex/templates/task-brief.md`

### Agent Report 最少字段

- `Role`
- `Summary`
- `Files touched/reviewed`
- `Findings`
- `Required follow-up`
- `Commands run`
- `Evidence`
- `Residual risks`

模板路径：`.codex/templates/agent-report.md`

## 5. 证据链

统一证据链：

`Task Brief` -> `Agent Report` -> `review note`（如适用） -> `docs:check / quality:gate` -> `CI`

规则：

- `quality:gate` 是唯一 finish gate
- CI 只验证证据，不编排 agent
- `review note` 在命中 `src/**/*.sol` 时是必需证据
- `docs/contracts/**` 仅提供生成输出，不作为证据链中的规则真源

## 6. Block 规则

### Hard-block

- `verifier` 任一 required command 失败
- Solidity 任务缺失 `security-reviewer` 或 `gas-reviewer` 结论
- 存在未关闭 `high` 安全 finding
- required artifact 缺失（含 required review note）
- 未经授权写入 scope 外路径

### Soft-block

- 可解释的非关键 Gas 回退
- 可延期的简化建议
- 不影响正确性与安全性的补充文档项
- 需要 human/main-orchestrator 决策的产品规则变更建议

## 7. 与现有流程文件的关系

- 变更触发矩阵：`docs/process/change-matrix.md`
- review note 规范：`docs/process/review-notes.md`
- 机器可读策略：`docs/process/policy.json`
- 规则到测试映射：`docs/process/rule-map.json`
- gate / 校验脚本：`script/process/*`
