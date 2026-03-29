# Agent Operating Contract

本文件是 `MemeverseV2` 仓库的主流程契约，面向开发者与 Codex / subagent 工作流。它定义角色职责、阶段流、路径触发规则、完成标准，以及当前仓库采用的标准化 Solidity Harness 入口。

## 1. Project Overview

这是一个以 Foundry 为主的 Solidity 仓库，核心包含：

- `src/`：Memeverse 协议合约（launcher、registration、swap、governance、yield、interoperation 等）
- `test/`：Foundry 测试
- `script/`：部署与运维脚本
- `script/process/`：开发流程脚本
- `docs/process/`：Harness / Process 文档与机器真源
- `docs/plans/`：本地设计文档、实现计划、阶段方案、拆分草案
- `docs/task-briefs/`：本地 `Task Brief` 工件
- `docs/agent-reports/`：本地 `Agent Report` 工件
- `docs/reviews/`：本地 review 草稿模板与草稿
- `docs/spec/`、`docs/ARCHITECTURE.md`、`docs/GLOSSARY.md`、`docs/TRACEABILITY.md`、`docs/VERIFICATION.md`：产品真相与支撑文档
- `.codex/agents/`：项目级 subagent manifest（`*.toml`）与运行时契约（`*.md`）
- `.codex/runtime/`：subagent runtime 入口索引
- `.codex/templates/`：`Task Brief` 与 `Agent Report` 模板

## 1.5 Subagent Runtime Entry

- 标准 runtime 索引：`.codex/runtime/subagent-runtime.json`
- 标准 dispatch helpers：`script/process/prepare-agent-brief.sh`、`script/process/resolve-agent-dispatch.js`、`script/process/dispatch-agent.sh`
- 该文件只负责声明项目入口、角色集合、工件位置与默认写入 ownership，不承载机器规则细节
- 机器规则真源仍是 `AGENTS.md`、`docs/process/policy.json`、`script/process/*` 与 `.codex/agents/*.md`

## 2. Required Commands

- 初次 clone 后执行：`git submodule update --init --recursive`
- 每个工作副本只需执行一次：`npm install`
- 每个工作副本只需执行一次：`npm run hooks:install`
- 流程脚本自测：`npm run process:selftest`
- 日常本地快速反馈：`npm run quality:quick`
- 任意准备提交的变更，唯一 finish gate：`npm run quality:gate`
- 文档链检查：`npm run docs:check`

常用命令：

- 构建：`forge build`
- 测试：`forge test -vvv`
- 覆盖率检查：`bash ./script/process/check-coverage.sh`
- 格式检查：`forge fmt --check`
- 文档检查：`npm run docs:check`
- 本地 gate：`npm run quality:quick`、`npm run quality:gate`
- `check-coverage.sh` 默认使用 `forge coverage --ir-minimum`，用于绕过 coverage 模式下的 `stack too deep` 编译阻塞；其 source mapping 精度可能低于默认 coverage 模式

## 3. Role Model

### Main Session

- `main-orchestrator` 是默认主会话角色
- `main-orchestrator` 负责 intake、拆任务、划定 file ownership、汇总证据、判定 block
- `main-orchestrator` 不写 `src/**/*.sol`
- `main-orchestrator` 不写 `test/**/*.sol`
- `main-orchestrator` 不写 `script/**/*.sh`
- 命中 `src/**/*.sol`、`test/**/*.sol`、`script/**/*.sh` 时，必须先派发对应 writer role
- 若 writer role 未成功派发，主会话必须停止并请求人工决策，不能降级为直接实现者
- 主会话被长期授权可按 `AGENTS.md` 自主使用 subagents
- 主会话可自行决定何时委派、并行执行、等待结果与回收 agent，无需每次单独向用户请求许可
- 自主委派仍必须遵守本文件的角色边界、单写 owner、证据链和 block 规则

### Default Roles

- `solidity-implementer`
  - Solidity surface 的唯一默认写入者
  - 负责 `src/**/*.sol`、适量的方法内注释与与风险匹配的测试
- `security-reviewer`
  - 只读安全审阅
  - 负责 high / medium / low findings 与必补测试建议
- `gas-reviewer`
  - 只读 Gas 基线、diff、优化建议与残余风险
- `verifier`
  - 只读验证执行与失败归因

### On-Demand Roles

- `solidity-explorer`
  - 复杂改动前的影响面侦察与任务拆分建议
- `process-implementer`
  - 流程、文档、CI、shell、package metadata 与 Harness 文件的受限写入者
  - 对非 Solidity surface 变更默认启用；在 Solidity-centric 任务中按需启用
- `security-test-writer`
  - 高风险改动后的 fuzz / invariant / adversarial tests 补强

### Required Review Order (Harness / Process Tasks)

对于 `AGENTS.md`、`docs/process/**`、`docs/reviews/TEMPLATE.md`、`.codex/**`、`script/process/**` 这类流程面变更，默认评审顺序为：

`main-orchestrator` -> `verifier`

## 4. Core Principles

- 默认单写 owner：同一批 Solidity 文件在同一时间只能有一个实现型写入者
- 并行优先用于只读任务：exploration、security review、Gas review、verification triage
- 证据先于结论：所有可提交结论都必须能追溯到 `Task Brief`、agent 输出、review note、gate 或 CI
- 可读性优先于省注释：对非直观控制流、状态迁移、金额计算、权限前提与外部调用，必须补充适量的方法内注释；禁止把显而易见的逐行语句翻译成噪音注释
- 测试充分性优先于“有测试就行”：测试必须能证明行为与风险边界，不能只停留在 happy path；涉及会计、状态机、权限、资金流、升级或外部集成的高风险路径时，除单元测试外还必须补充适用的 fuzz、invariant、adversarial、integration 或 upgrade tests，并明确覆盖范围与剩余缺口
- 本地前提先于外部事实：任何结论都必须先逐行核实本地关键控制流、状态更新与入口条件，再去核验第三方协议或外部系统行为
- 未完成证据链，不得升级为已确认 finding：缺少本地关键前提、缺少上游主来源、或只依赖模式匹配 / mock / interface / wrapper 命名时，只能标记为 `hypothesis`、`needs verification` 或测试缺口
- subagent finding 默认不是最终结论：`main-orchestrator` 必须复核关键代码行、关键前提和外部来源后，才能把 subagent 输出升级为仓库级结论
- CI 不负责编排 agent：CI 只验证证据与最终 gate
- review 结论只允许输出风险、后果、证据与可选方案；不得擅自修改产品需求，也不得把审阅建议直接固化为新的仓库规则
- 若 review 结论会改变业务语义、权限边界、资金流约束、可领取条件、费用规则、流动性规则或其他产品规则，必须升级为 `需要 main-orchestrator / human 确认的决策点`，在确认前不得默认实现

## 5. Workflow Summary

- `npm run quality:gate` 是唯一 finish gate；`npm run quality:quick` 只用于本地快速反馈
- 工件目录约定：
  - `docs/plans/` 只放 design / plan / draft
  - `docs/task-briefs/` 只放 `Task Brief`
  - `docs/agent-reports/` 只放 `Agent Report`
  - `docs/reviews/` 放本地 review note / 模板
- 结构化阶段流、通信模型、证据链、block 规则，统一以 [docs/process/subagent-workflow.md](/home/azkrale/Web3Project/MemeverseV2/docs/process/subagent-workflow.md) 为准
- 在新建任何文档前，必须先校验目标目录是否符合本仓库约定；路径未校验视为流程错误

## 6. Change Surfaces

- 路径触发规则、默认角色、必跑命令与 gate 约束，以 [docs/process/change-matrix.md](/home/azkrale/Web3Project/MemeverseV2/docs/process/change-matrix.md) 为准
- 机器可读真源以 [docs/process/policy.json](/home/azkrale/Web3Project/MemeverseV2/docs/process/policy.json) 与 `script/process/*` 为准
- `MemeverseV2` 的 `rule-map` 是 repo-specific 扩展，不被通用 Harness 文案替代

## 7. Pull Request Contract

- 仓库提供标准模板：`.github/pull_request_template.md`
- PR body 必须包含以下标题：
  - `## Summary`
  - `## Impact`
  - `## Docs`
  - `## Tests`
  - `## Verification`
  - `## Risks`
  - `## Security`
  - `## Simplification`
  - `## Gas`

## 8. Review Note Contract

- 模板文件：`docs/reviews/TEMPLATE.md`
- 当命中 `src/**/*.sol` 变更时，本地与 CI 的 `quality:gate` 都必须能找到一份有效 review note
- 字段、布尔值约束、owner-prefixed source 规则与 artifact 路径要求，以 [docs/process/review-notes.md](/home/azkrale/Web3Project/MemeverseV2/docs/process/review-notes.md) 和 [docs/process/policy.json](/home/azkrale/Web3Project/MemeverseV2/docs/process/policy.json) 为准
- 若仓库启用了 repo-specific 证据映射或额外 gate 字段，review note 也必须同步满足

## 9. Local-Only Files

- `docs/plans/` 默认本地规划目录，仅放设计文档、实现计划、阶段方案、拆分草案
- `docs/task-briefs/` 默认本地 `Task Brief` 目录
- `docs/agent-reports/` 默认本地 `Agent Report` 目录
- `docs/reviews/` 默认本地 review 草稿目录（是否提交由团队策略决定）

## 10. Documentation Language

- 新增自然语言文档默认使用简体中文
- 固定字段 key、命令、路径、代码标识、协议名、库名保持英文
- review note 的固定 key 与 `yes` / `no` 取值保持英文

## 11. Repository Architecture Snapshot

### 11.1 Launcher 与生命周期

- 入口：`src/verse/MemeverseLauncher.sol`
- 负责 verse 创建、阶段推进、Genesis / Refund / Locked / Unlocked 相关状态与资金主编排

### 11.2 Registration 与跨链注册

- 目录：`src/verse/registration/`
- 负责参数校验、symbol 占用、local / remote fan-out，以及对 launcher 的落库调用

### 11.3 Swap 与流动性

- 目录：`src/swap/`
- 用户入口：`src/swap/MemeverseSwapRouter.sol`
- Hook 引擎：`src/swap/MemeverseUniswapHook.sol`

### 11.4 Token / Yield / Governance

- `src/token/`：memecoin 与 POL 资产层
- `src/yield/`：收益相关合约
- `src/governance/`：治理与激励合约

### 11.5 Interoperation

- 目录：`src/interoperation/`
- 负责跨链 staking、治理链侧承接，以及与 launcher / OFT / endpoint 配置联动

## 12. Source of Truth And Reading Order

### Harness / Process Truth

- `AGENTS.md`
- `docs/process/change-matrix.md`
- `docs/process/review-notes.md`
- `docs/process/policy.json`
- 若存在：`docs/process/rule-map.json`
- `script/process/*`
- `.codex/agents/*.md`
- `.codex/agents/*.toml`

### Product Truth Core Source of Truth

- `docs/spec/*`
- 升级性规则主文档：`docs/spec/upgradeability.md`
- `docs/spec/implementation-map.md` 的升级性列用于记录各 surface 的代码事实，不替代升级性规则主文档

### Product Truth Support Source of Truth

- `docs/ARCHITECTURE.md`
- `docs/GLOSSARY.md`
- `docs/TRACEABILITY.md`
- `docs/VERIFICATION.md`
- `docs/SECURITY_AND_APPROVALS.md`
- `docs/adr/0001-universalvault-style-harness-migration.md`

### Recommended Reading Order

1. `AGENTS.md`
2. `docs/ARCHITECTURE.md`
3. `docs/spec/*`
4. `docs/GLOSSARY.md`
5. `docs/TRACEABILITY.md` + `docs/VERIFICATION.md`
6. `docs/process/subagent-workflow.md` + `docs/process/*`
