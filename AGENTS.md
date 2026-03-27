# Agent Operating Contract

本文件是 `MemeverseV2` 的主流程契约，面向开发者与 Codex / subagent 工作流。它定义主会话角色、协作阶段、路径触发规则、完成标准与证据链。

## 1. Project Overview

这是一个以 Foundry 为主的 Solidity 仓库，核心包含：

- `src/`：Memeverse 协议合约（launcher、registration、swap、governance、yield、interoperation 等）
- `test/`：Foundry 测试
- `script/`：部署脚本与流程脚本
- `docs/process/`：流程契约与机器可读规则
- `docs/plans/`：设计文档、实现计划、阶段方案、拆分草案
- `docs/task-briefs/`：本地 `Task Brief` 工件
- `docs/agent-reports/`：本地 `Agent Report` 工件
- `.codex/agents/`：角色 manifest（`*.toml`）与运行时契约（`*.md`）
- `.codex/templates/`：`Task Brief` 与 `Agent Report` 模板

## 2. Required Commands

- 初次 clone：`git submodule update --init --recursive`
- 每个工作副本一次：`npm install`
- 每个工作副本一次：`npm run hooks:install`
- 流程脚本自测：`npm run process:selftest`
- 日常快速反馈：`npm run quality:quick`
- 唯一 finish gate：`npm run quality:gate`
- 文档链检查：`npm run docs:check`

常用命令：

- 构建：`forge build`
- 测试：`forge test -vvv`
- 格式：`forge fmt --check`
- 流程自测：`npm run process:selftest`

## 3. Role Model

### Main Session

- 主会话默认角色是 `main-orchestrator`
- `main-orchestrator` 只负责 intake、任务拆分、ownership 分配、证据汇总、block 判定
- `main-orchestrator` 不得直接写 `src/**/*.sol`、`test/**/*.sol`、`script/**/*.sh`
- 命中上述路径时，必须先派发对应 writer role；未成功派发前不得开始实现
- 若 writer role 未成功派发，主会话必须停止并请求人工决策，不能降级为直接实现者
- 主会话直接写入上述路径视为流程违规，不得进入 verification / decision / finish

### Default Roles

- `solidity-implementer`：Solidity 面默认写入者
- `process-implementer`：非 Solidity 面默认写入者
- `security-reviewer`：只读安全审阅
- `gas-reviewer`：只读 Gas 审阅
- `verifier`：只读验证与失败归因

### On-Demand Roles

- `solidity-explorer`：复杂改动前影响面侦察
- `security-test-writer`：测试补强与覆盖率加固（fuzz / invariant / adversarial 等）

### Required Review Order (Harness / Process 任务)

对于 `.codex/**`、`AGENTS.md`、`README.md`、`docs/process/subagent-workflow.md`、`script/process/**` 这类流程面变更，默认评审顺序为：

`main-orchestrator`（范围与契约复核） -> `verifier`

### Evidence Rules

- 证据先于结论：可提交结论必须能回溯到 `Task Brief`、agent 输出、review note、gate 或 CI
- 本地前提先于外部事实：任何已确认结论都必须先核实本地关键控制流、状态更新、金额计算、索引推进与权限检查，再核验第三方语义
- subagent finding 默认不是最终结论：`main-orchestrator` 复核关键代码行、关键前提和必要的外部主来源后，才能升级为仓库级 confirmed finding
- 缺少本地前提证据、外部主来源证据，或只依赖 interface / mock / wrapper / 命名模式时，只能写成 `hypothesis`、`needs verification` 或测试缺口

## 4. Workflow Model

### Phase 1: Intake / Scoping

- `main-orchestrator` 产出结构化 `Task Brief`
- 对语义敏感改动，`Task Brief` 必须显式声明 `Semantic review dimensions`、`Source-of-truth docs`、`External sources required` 与 `Critical assumptions to prove or reject`
- 识别路径、风险、required roles、write ownership
- scope 不清时可先启用 `solidity-explorer`

### Phase 2: Baseline Analysis

- `src/**/*.sol` 变更默认并行启用 `security-reviewer` + `gas-reviewer`
- 非 Solidity 变更默认进入 `process-implementer`

### Phase 3: Implementation

- Solidity 面由 `solidity-implementer` 在授权边界内写入
- 非 Solidity 面由 `process-implementer` 在授权边界内写入
- 命中 `src/**/*.sol` 或 `test/**/*.sol` 的任务，必须先有 `Task Brief`，且其中明确 `Default writer` 与 `Write permissions`
- 未完成 role dispatch，不得开始 Solidity 实现
- 复杂分支、状态迁移、资金/权限判断、关键外部调用、非直观数学等实现必须补充适当的方法内注释，说明意图、前置条件或安全假设；禁止噪音式逐行注释
- 未重派发不得扩展到 ownership 外路径

### Phase 4: Specialist Review

- Solidity 任务：`security-reviewer` / `gas-reviewer` 给出只读结论
- 命中外部依赖、用户资金流、权限边界、registration / settlement / liquidity / yield / omnichain 语义的改动，review 必须显式处理 brief 中声明的语义维度与关键假设
- review 必须先核实本地前提；关键控制流、状态变化、金额处理、权限检查与触发路径未逐行确认前，不得把问题升级为 confirmed finding
- 若结论依赖第三方协议、外部合约、SDK、API 或系统行为，必须在本地前提成立后再核验主来源
- Harness/process 任务：由 `main-orchestrator` 复核契约一致性与角色边界
- 任何会改变产品规则的建议升级为待决策点，不默认实现

### Phase 5: Test Hardening

- Solidity 改动默认需要完善测试，不得只停留在最小回归或 happy path
- 测试至少覆盖 unit tests，并按风险与状态复杂度补充 fuzz / invariant / adversarial / integration tests，使变更路径保持足够高覆盖率；若仍有测试盲区，必须显式记录
- 高风险路径或覆盖缺口明显时启用 `security-test-writer`

### Phase 6: Verification

- `verifier` 运行或汇总 required checks
- 对语义敏感改动，`verifier` 还需确认 review note 已填写语义对齐字段，且 brief 要求的外部来源/关键假设已收敛为结论或决策点
- Harness/process 任务在评审后由 `verifier` 收敛最终验证结论

### Phase 7: Decision

- `main-orchestrator` 汇总 `Task Brief`、`Agent Report`、review note（如适用）、gate/CI 证据
- 对 confirmed finding，`main-orchestrator` 至少复核关键代码行、关键前提和必要的外部主来源，不能只转述 subagent 摘要
- 证据链完整后才可进入 `quality:gate` / CI

## 5. Change Matrix Summary

- `src/**/*.sol`
  - 进入 review/收尾/commit 前必须按仓库约定执行 post-coding 流程
  - 优先使用 `skills/solidity-post-coding-flow/SKILL.md`
  - required checks 参考 `docs/process/change-matrix.md` 与 `docs/process/policy.json`
  - `rule-map` 证据映射以 `docs/process/rule-map.json` 为准
  - 复杂实现必须有适当的方法内注释，解释关键意图与安全假设
  - 测试必须覆盖 unit tests，并按适用性补 fuzz / invariant / adversarial / integration tests；变更面应保持足够高覆盖率，不能留下未解释的明显盲区
  - 语义敏感改动还必须补齐 semantic-alignment / evidence-chain 字段，不能把外部语义留在隐含前提里
- `test/**/*.t.sol`
  - 必须通过 Solidity 相关基础检查（fmt/build/test）
  - 测试至少覆盖正常路径、边界条件和失败路径；高风险状态路径应补 fuzz / invariant / adversarial tests，并追求足够高覆盖率
- `script/**/*.sh` 或 `.githooks/*`
  - 必须通过 `bash -n`
- `AGENTS.md`、`README.md`、`docs/process/subagent-workflow.md`、`.codex/**`、`script/process/check-docs.sh`
  - 默认由 `process-implementer` 修改
  - 至少通过 `npm run docs:check`

## 6. Pull Request Contract

- 标准模板：`.github/pull_request_template.md`
- PR body 必须包含：
  - `## Summary`
  - `## Impact`
  - `## Docs`
  - `## Tests`
  - `## Verification`
  - `## Risks`
  - `## Security`
  - `## Simplification`
  - `## Gas`

## 7. Review Note Contract

- 模板：`docs/reviews/TEMPLATE.md`
- 命中 `src/**/*.sol` 时，本地与 CI 的 `quality:gate` 必须能找到有效 review note
- 必填字段与占位规则以 `docs/process/review-notes.md` 与 `docs/process/policy.json` 为准
- `Behavior change`、`ABI change`、`Storage layout change`、`Config change`、`Ready to commit` 仅允许 `yes` 或 `no`
- 对语义敏感改动，review note 还必须补齐：
  - `Semantic dimensions reviewed`
  - `Source-of-truth docs checked`
  - `External facts checked`
  - `Local control-flow facts checked`
  - `Evidence chain complete`
  - `Semantic alignment summary`

## 8. Local-Only Files

- `docs/plans/` 默认本地规划目录，仅放设计文档、实现计划、阶段方案、拆分草案
- `docs/task-briefs/` 默认本地 `Task Brief` 目录
- `docs/agent-reports/` 默认本地 `Agent Report` 目录
- `docs/reviews/` 默认本地 review 草稿目录（是否提交由团队策略决定）

## 9. Documentation Language

- 新增自然语言文档默认使用简体中文
- 固定字段 key、命令、路径、代码标识、协议名、库名保持英文
- review note 的固定 key 与 `yes`/`no` 取值保持英文

## 10. High-Level Architecture

### 10.1 Verse 启动与生命周期

- 入口：`src/verse/MemeverseLauncher.sol`
- 负责 verse 创建、阶段推进、Genesis 相关状态、POL 与外围模块装配

### 10.2 注册与跨链注册

- 目录：`src/verse/registration/`
- 入口与状态中心：`MemeverseRegistrationCenter.sol`
- 本地注册与跨链注册由不同 registrar 协作完成

### 10.3 Swap 与流动性

- 目录：`src/swap/`
- 用户入口：`MemeverseSwapRouter.sol`
- Hook 扩展：`MemeverseUniswapHook.sol`

### 10.4 Token / Yield / Governance

- `src/token/`：`Memecoin.sol`、`MemeLiquidProof.sol`
- `src/yield/`：`MemecoinYieldVault.sol`
- `src/governance/`：治理与激励合约

### 10.5 Omnichain Interoperation

- 目录：`src/interoperation/`
- 负责跨链 staking、治理链侧承接、与 launcher/OFT/endpoint 配置联动

### 10.6 Common 基础层

- 目录：`src/common/`
- 提供 omnichain 封装、token 基类、访问控制和密码学组件

## 11. Source of Truth

### Product Truth Core Source of Truth

- `docs/spec/*`
- 升级性规则主文档：`docs/spec/upgradeability.md`
- `docs/spec/implementation-map.md` 的升级性列用于记录各 surface 的代码事实，不替代升级性规则主文档

### Product Truth Support Source of Truth

- `docs/ARCHITECTURE.md`
- `docs/GLOSSARY.md`
- `docs/TRACEABILITY.md`
- `docs/VERIFICATION.md`
- `docs/adr/0001-universalvault-style-harness-migration.md`

### Harness Source of Truth

- `AGENTS.md`
- `.codex/**`
- `docs/process/subagent-workflow.md`

### Process and Policy Source of Truth

- `docs/process/policy.json`
- `docs/process/rule-map.json`
- `docs/process/change-matrix.md`
- `docs/process/review-notes.md`
- `script/process/*`（含 `process:selftest` 与 gate 脚本）

## 12. Recommended Reading Order

1. `AGENTS.md`（协作边界、角色与流程契约）
2. `docs/ARCHITECTURE.md`（架构层次与边界）
3. `docs/spec/*`（产品真相核心规则；先读 `protocol`/`state-machines`/`accounting`/`access-control`/`upgradeability`）
4. `docs/GLOSSARY.md`（术语与定义基线）
5. `docs/TRACEABILITY.md` + `docs/VERIFICATION.md`（规则追溯与验证路径）
6. `docs/adr/0001-universalvault-style-harness-migration.md`（文档治理决策背景）
7. `docs/process/subagent-workflow.md` + `docs/process/*`（Harness/Process 执行细则）
