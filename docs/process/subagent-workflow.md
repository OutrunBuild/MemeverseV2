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
- `security-test-writer`：测试补强与覆盖率加固

### Harness / Process 任务评审顺序

当任务主要触达 `.codex/**`、`AGENTS.md`、`README.md`、`docs/process/subagent-workflow.md`、`script/process/**` 时，required review order 为：

`main-orchestrator`（范围与契约复核） -> `verifier`

### 证据规则

- 先核本地前提，再核外部事实；不能把第三方语义事实留在隐式前提里
- subagent finding 默认只是线索，不是最终 confirmed finding
- 缺少本地关键控制流证据或必要的外部主来源证据时，只能输出 `hypothesis`、`needs verification` 或测试缺口

## 3. 阶段流

### Phase 1: Intake / Scoping

- `main-orchestrator` 产出 `Task Brief`
- 明确 `Files in scope`、`Write permissions`、`Required roles`
- 对语义敏感改动，`Task Brief` 还必须显式写出 `Semantic review dimensions`、`Source-of-truth docs`、`External sources required` 与 `Critical assumptions to prove or reject`

### Phase 2: Baseline Analysis

- Solidity 任务默认启用 `security-reviewer` + `gas-reviewer`
- 复杂 Solidity 任务可先启用 `solidity-explorer`

### Phase 3: Implementation

- Solidity 写入仅由 `solidity-implementer`（单写 owner）
- 非 Solidity 写入仅由 `process-implementer`
- 命中 `src/**/*.sol` 或 `test/**/*.sol` 的任务，必须先有 `Task Brief`，且其中明确 `Default writer` 与 `Write permissions`
- 未完成对应 writer role 派发前，不得开始 Solidity 实现
- `main-orchestrator` 不得降级为 Solidity 直接实现者；writer role 派发失败时只能停止并请求人工决策
- 复杂分支、状态迁移、资金/权限判断、关键外部调用、非直观数学等实现必须补充适当的方法内注释，说明意图、前置条件或安全假设
- 未重派发不得扩写路径

### Phase 4: Specialist Review

- Solidity 任务：安全与 Gas 并行只读审阅
- 对外部依赖、claim / registration / settlement / liquidity / yield / omnichain / 权限边界等语义敏感改动，review 必须显式处理 brief 中声明的语义维度与关键假设
- review 必须先核本地前提；关键控制流、状态更新、金额处理、权限检查和触发路径未确认前，不得升级为 confirmed finding
- 若结论依赖第三方行为，review 必须核验主来源，而不能只依赖本地 mock、interface、wrapper 或命名模式
- Harness/process 任务：由 `main-orchestrator` 复核契约一致性与角色边界

### Phase 5: Test Hardening

- Solidity 改动默认需要完善测试，至少覆盖 unit tests
- 按风险与状态复杂度补 fuzz / invariant / adversarial / integration tests，使变更面保持足够高覆盖率；未覆盖盲区要在证据里说明
- 高风险路径或覆盖缺口明显时启用 `security-test-writer`

### Phase 6: Verification

- `verifier` 执行/汇总 required commands
- 对语义敏感改动，`verifier` 还要确认 review note 中的语义对齐字段、外部事实、关键假设和本地控制流事实已经落盘
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
- `Semantic review dimensions`
- `Source-of-truth docs`
- `External sources required`
- `Critical assumptions to prove or reject`
- `Required output fields`
- `Review note impact`

模板路径：`.codex/templates/task-brief.md`
工件目录：`docs/briefs/`

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
工件目录：`docs/agent-reports/`

## 5. 证据链

统一证据链：

`Task Brief` -> `Agent Report` -> `review note`（如适用） -> `docs:check / quality:gate` -> `CI`

规则：

- `quality:gate` 是唯一 finish gate
- CI 只验证证据，不编排 agent
- `review note` 在命中 `src/**/*.sol` 时是必需证据
- `docs/plans/` 只保留 design / implementation plan / stage draft；`Task Brief` 与 `Agent Report` 不得再与其混放
- `Task Brief path` 应回溯到 `docs/briefs/` 下的实际 brief；`Agent Report path` 应回溯到 `docs/agent-reports/` 下的实际 report
- 已确认结论必须同时具备本地前提证据与必要的外部主来源证据
- `Task Brief`、`Agent Report`、`review note` 的语义敏感字段必须能互相回溯，不能只有一处声明

## 6. Block 规则

### Hard-block

- `verifier` 任一 required command 失败
- `main-orchestrator` 直接写入 `src/**/*.sol` 或 `test/**/*.sol`
- 命中受限 ownership 路径但未成功派发对应 writer role
- 缺少 `Task Brief` 就开始 Solidity 实现
- Solidity 任务缺失 `security-reviewer` 或 `gas-reviewer` 结论
- 存在未关闭 `high` 安全 finding
- required artifact 缺失（含 required review note）
- 未经授权写入 scope 外路径
- 语义敏感改动缺失 semantic-alignment / evidence-chain 必填字段
- 已确认 finding 缺少本地前提证据或必要的外部主来源证据

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
