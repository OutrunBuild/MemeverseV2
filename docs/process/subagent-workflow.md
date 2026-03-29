# Solidity Subagent Workflow

本文件定义当前仓库的默认 subagent Harness，用于把 `AGENTS.md` 中的主契约拆成可执行阶段、角色职责、通信模型与 block 规则。

本文件是 subagent 相关的总说明入口；角色级 runtime contract 位于 `.codex/agents/*.md`。

## 1. Agent File Model

`.codex/agents/` 采用同名双文件：

- `*.toml`
  - Codex 原生 manifest / 入口层
  - 只承载最小角色元数据与入口级 `developer_instructions`
- `*.md`
  - 仓库运行时契约 / 行为真源
  - 定义输入契约、读写边界、执行清单、block 语义、输出契约与升级规则

如果同名 `*.toml` 与 `*.md` 之间出现冲突，以 `*.md` 为准。

运行约束：

- 所有下游 subagent 都必须消费结构化 `Task Brief`
- 所有下游 subagent 都必须返回标准化 `Agent Report`
- `main-orchestrator` 负责 brief、ownership、block 决策与证据汇总
- 默认保持单写 owner，不让多个实现型 agent 并行修改同一批 Solidity 文件

## 2. Subagent Runtime Entry

- 标准 runtime 索引：`.codex/runtime/subagent-runtime.json`
- dispatch helpers：`script/process/prepare-agent-brief.sh`、`script/process/resolve-agent-dispatch.js`、`script/process/dispatch-agent.sh`
- 该文件只保留项目入口、角色集合、工件位置与默认写入 ownership
- reviewer、verifier 与 explorer 的触发范围仍以 `AGENTS.md`、`docs/process/change-matrix.md` 与 `docs/process/policy.json` 为准
- 具体规则、路径匹配、命令要求与 gate 语义仍以 `AGENTS.md`、`docs/process/policy.json`、`script/process/*` 与 `.codex/agents/*.md` 为准

## 3. 目标

- 让 Solidity 开发默认具备安全、Gas、验证三条并行只读检查线
- 保持默认单写 owner，避免多个实现型 agent 并行修改同一批 Solidity 文件
- 让 `review note` 成为统一证据汇总面
- 让本地 `quality:gate` 与 CI 共享同一条最终证明链
- 让 review 只输出风险、后果、证据与可选方案，不越权改写产品需求或沉淀新的产品规则

## 4. 角色

### 默认角色

- `main-orchestrator`
  - 主会话角色
  - 负责 intake、任务拆分、ownership、block 判定、证据汇总
  - 不写 `src/**/*.sol`、`test/**/*.sol`、`script/**/*.sh`
- `solidity-implementer`
  - 唯一默认写入者
  - 负责 Solidity surface 的实现代码、适量的方法内注释与足以证明行为的测试
- `security-reviewer`
  - 只读安全审阅
  - 输出 findings、required tests、residual risks
- `gas-reviewer`
  - 只读 Gas 基线、diff、优化建议与残余风险
- `verifier`
  - 只读验证命令执行与失败归因

### 按需角色

- `solidity-explorer`
  - 复杂改动前的影响面侦察与任务拆分建议
- `process-implementer`
  - 流程、文档、CI、shell、package metadata 与 Harness 文件的受限写入者
  - 对非 Solidity surface 变更默认启用；在 Solidity-centric 任务中按需启用
- `security-test-writer`
  - 高风险改动后的 fuzz、invariant、adversarial test 补强

角色级细则见 `.codex/agents/*.md`。

## 5. 阶段流

### Phase 1: Intake / Scoping

- `main-orchestrator` 创建 `Task Brief`
- 对语义敏感改动，`Task Brief` 必须显式写出 `Semantic review dimensions`、`Source-of-truth docs`、`External sources required` 与 `Critical assumptions to prove or reject`
- 命中 `src/**/*.sol` 或 `test/**/*.sol` 的任务，`Task Brief` 必须先明确 `Default writer role` 与 `Write permissions`
- 如影响面不清、跨模块、涉及 ABI、storage、config、access control、external call，可按需启用 `solidity-explorer`

### Phase 2: Baseline Analysis

- `src/**/*.sol` 变更默认启用 `security-reviewer`
- `src/**/*.sol` 变更默认启用 `gas-reviewer`
- 输出安全重点、Gas 热点与 review note 影响面

### Phase 3: Implementation

- `solidity-implementer` 在明确 ownership 下修改实现，补充非直观方法的适量方法内注释，并完成足以证明行为的测试
- `test/**/*.sol` helper / support surface 只有在 brief 显式授权时才允许被实现型角色写入
- 非 Solidity 的 process、docs、CI、shell、package metadata、Harness 变更由 `process-implementer` 在明确 ownership 下修改
- 命中 `src/**/*.sol`、`test/**/*.sol`、`script/**/*.sh` 时，必须先派发对应 writer role
- `main-orchestrator` 不得降级为 `src/**/*.sol`、`test/**/*.sol`、`script/**/*.sh` 的直接实现者；writer role 派发失败时只能停止并请求人工决策
- 不得未经派发扩大文件边界

### Phase 4: Specialist Review

- `security-reviewer` 与 `gas-reviewer` 输出只读结论
- 对命中外部依赖、权限边界、会计、状态机、升级或资金流语义的改动，review 需要显式处理 brief 中声明的语义维度与关键假设
- review 必须先核本地前提：关键控制流、状态更新、索引推进、金额处理、权限检查等本地事实未逐行确认前，不得把问题升级为 confirmed finding
- 若结论依赖第三方行为，review 必须在本地前提成立后再核验 upstream 主来源
- `main-orchestrator` 在采纳 subagent finding 前，必须复核关键代码行、关键前提和必要主来源；subagent finding 默认只是线索，不是最终结论
- 当 review 结论会改变产品规则、权限边界、资金流约束或其他业务语义时，必须升级为 `需要 main-orchestrator / human 确认的决策点`

### Phase 5: Test Hardening

- 仅在高风险变更或 `security-reviewer` 指出测试缺口时启用 `security-test-writer`
- `security-test-writer` 只修改测试，不修改生产逻辑
- `security-test-writer` 需要围绕缺口补齐 fuzz、invariant、adversarial tests，并交代覆盖了哪些风险边界

### Phase 6: Verification

- `verifier` 运行或汇总验证命令
- 对语义敏感改动，`verifier` 还要确认 review note 中的语义对齐字段、外部事实与关键假设结论已经落盘
- 命中 `src/**/*.sol` 或 `test/**/*.sol` 时，`verifier` 还要确认 coverage 与其他 required checks 已收敛
- required command 失败时必须记录失败归因

### Phase 7: Decision

- `main-orchestrator` 汇总 `Task Brief`、`Agent Report`、review note、gate 与 CI 结果
- 仅在证据链完整时允许进入 finish gate

## 6. 通信模型

采用 `hub-and-spoke`：

- 所有 subagent 只和 `main-orchestrator` 通信
- agent 之间不直接 peer-to-peer 协商
- 结构化 handoff 通过 `.codex/templates/task-brief.md` 与 `.codex/templates/agent-report.md` 统一字段
- role instantiation 通过 `.codex/agents/*.toml`，具体行为通过同名 `.md` 契约约束

## 7. 证据链

统一证据链为：

`Task Brief` -> `Agent Report` -> `review note` -> `quality:gate` -> `CI`

规则如下：

- `review note` 是唯一统一审阅记录
- `quality:gate` 是唯一 finish gate
- CI 只负责验证，不负责编排 agent
- 命中 `src/**/*.sol` 或 `test/**/*.sol` 时，`review note` 必须能回溯到 `Task Brief path`、`Agent Report path`、`Implementation owner` 与 `Writer dispatch confirmed`
- `Task Brief` 默认放在 `docs/task-briefs/`
- `Agent Report` 默认放在 `docs/agent-reports/`；`docs/plans/` 只保留 design、plan、draft 文档
- 已确认结论必须同时具备本地前提证据与必要的外部主来源证据；缺少任一项时只能维持为假设、待验证项或测试缺口
- 若仓库启用了 repo-specific 证据映射，review note 也必须同步满足其要求

## 8. Block 规则

### Hard-block

- `verifier` 任一 required command fail
- `main-orchestrator` 直接写入 `src/**/*.sol`、`test/**/*.sol` 或 `script/**/*.sh`
- 命中受限路径但未成功派发对应 writer role
- 缺少 `Task Brief` 就开始 `src/**/*.sol` / `test/**/*.sol` 实现
- `security-reviewer` 存在未关闭的 `high` finding
- Solidity 变更但缺 `security-reviewer` 或 `gas-reviewer` 结论
- 命中 `src/**/*.sol` 或 `test/**/*.sol` 时，coverage 或其他 required checks 未达标
- 任一已确认 finding 缺少本地前提证据，或依赖外部语义却缺少主来源证据
- review note 缺字段、缺 writer ownership / `Agent Report` 工件链证据，或仍为占位值

### Soft-block

- 可解释的中低优先级 Gas 回退
- 可延期的简化建议
- 不影响正确性与安全性的文档补充项
- 已识别到会改变产品规则的 review 建议，但尚未获得 `main-orchestrator` 或 human 决策

## 9. 与仓库文件的关系

- 主契约：`AGENTS.md`
- 变更矩阵：`docs/process/change-matrix.md`
- review note 规则：`docs/process/review-notes.md`
- 机器可读策略：`docs/process/policy.json`
- 质量门禁脚本：`script/process/*`
- 项目级 agent manifest：`.codex/agents/*.toml`
- 项目级 agent 运行时契约：`.codex/agents/*.md`
