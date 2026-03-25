# Agent Operating Contract

本文件是 `MemeverseV2` 的主流程契约，面向开发者与 Codex / subagent 工作流。它定义主会话角色、协作阶段、路径触发规则、完成标准与证据链。

## 1. Project Overview

这是一个以 Foundry 为主的 Solidity 仓库，核心包含：

- `src/`：Memeverse 协议合约（launcher、registration、swap、governance、yield、interoperation 等）
- `test/`：Foundry 测试
- `script/`：部署脚本与流程脚本
- `docs/process/`：流程契约与机器可读规则
- `docs/contracts/`：自动生成的合约文档产物
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
- 生成文档：`npm run docs:gen`
- 流程自测：`npm run process:selftest`

## 3. Role Model

### Main Session

- 主会话默认角色是 `main-orchestrator`
- `main-orchestrator` 负责 intake、任务拆分、ownership 分配、证据汇总、block 判定
- `main-orchestrator` 默认不写 `src/**/*.sol`、`test/**/*.sol`、`script/**/*.sh`

### Default Roles

- `solidity-implementer`：Solidity 面默认写入者
- `process-implementer`：非 Solidity 面默认写入者
- `security-reviewer`：只读安全审阅
- `gas-reviewer`：只读 Gas 审阅
- `verifier`：只读验证与失败归因

### On-Demand Roles

- `solidity-explorer`：复杂改动前影响面侦察
- `security-test-writer`：高风险测试补强

### Required Review Order (Harness / Process 任务)

对于 `.codex/**`、`AGENTS.md`、`README.md`、`docs/process/subagent-workflow.md`、`script/process/**` 这类流程面变更，默认评审顺序为：

`main-orchestrator`（范围与契约复核） -> `verifier`

## 4. Workflow Model

### Phase 1: Intake / Scoping

- `main-orchestrator` 产出结构化 `Task Brief`
- 识别路径、风险、required roles、write ownership
- scope 不清时可先启用 `solidity-explorer`

### Phase 2: Baseline Analysis

- `src/**/*.sol` 变更默认并行启用 `security-reviewer` + `gas-reviewer`
- 非 Solidity 变更默认进入 `process-implementer`

### Phase 3: Implementation

- Solidity 面由 `solidity-implementer` 在授权边界内写入
- 非 Solidity 面由 `process-implementer` 在授权边界内写入
- 未重派发不得扩展到 ownership 外路径

### Phase 4: Specialist Review

- Solidity 任务：`security-reviewer` / `gas-reviewer` 给出只读结论
- Harness/process 任务：由 `main-orchestrator` 复核契约一致性与角色边界
- 任何会改变产品规则的建议升级为待决策点，不默认实现

### Phase 5: Test Hardening

- 仅在高风险或安全审阅指出缺口时启用 `security-test-writer`

### Phase 6: Verification

- `verifier` 运行或汇总 required checks
- Harness/process 任务在评审后由 `verifier` 收敛最终验证结论

### Phase 7: Decision

- `main-orchestrator` 汇总 `Task Brief`、`Agent Report`、review note（如适用）、gate/CI 证据
- 证据链完整后才可进入 `quality:gate` / CI

## 5. Change Matrix Summary

- `src/**/*.sol`
  - 进入 review/收尾/commit 前必须按仓库约定执行 post-coding 流程
  - 优先使用 `skills/solidity-post-coding-flow/SKILL.md`
  - required checks 参考 `docs/process/change-matrix.md` 与 `docs/process/policy.json`
  - `rule-map` 证据映射以 `docs/process/rule-map.json` 为准
- `test/**/*.t.sol`
  - 必须通过 Solidity 相关基础检查（fmt/build/test）
- `script/**/*.sh` 或 `.githooks/*`
  - 必须通过 `bash -n`
- `AGENTS.md`、`README.md`、`docs/process/subagent-workflow.md`、`.codex/**`、`script/process/check-docs.sh`
  - 默认由 `process-implementer` 修改
  - 至少通过 `npm run docs:check`
- `docs/contracts/**`
  - 仅生成产物，不手工编辑，不作为产品或 Harness 真源

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

## 8. Generated Docs and Local-Only Files

- `docs/contracts/**` 是生成文档输出，来源链为：
  - `script/process/generate-docs.sh` -> `docs/contracts/**`
- `docs/contracts/**` 不属于产品或 Harness source of truth
- `docs/plans/` 默认本地规划目录
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

### Generated Docs Chain

- 生成入口：`script/process/generate-docs.sh`
- 生成输出：`docs/contracts/**`
- 结论：`docs/contracts/**` 仅为生成产物，不作为产品规则或 Harness 规则真源

## 12. Recommended Reading Order

1. `AGENTS.md`（协作边界、角色与流程契约）
2. `docs/ARCHITECTURE.md`（架构层次与边界）
3. `docs/spec/*`（产品真相核心规则；先读 `protocol`/`state-machines`/`accounting`/`access-control`/`upgradeability`）
4. `docs/GLOSSARY.md`（术语与定义基线）
5. `docs/TRACEABILITY.md` + `docs/VERIFICATION.md`（规则追溯与验证路径）
6. `docs/adr/0001-universalvault-style-harness-migration.md`（文档治理决策背景）
7. `docs/process/subagent-workflow.md` + `docs/process/*`（Harness/Process 执行细则）
8. `docs/contracts/**`（生成文档输出，仅用于参考，不作为真源）
