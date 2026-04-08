# Agent 运行契约

`MemeverseV2` 仓库主流程契约，面向 Claude Code 与 Codex 双平台。定义角色职责、阶段流、路径触发规则、完成标准与标准化 Harness 入口。

---

## Part I: 公共契约

本部分对两个平台均适用。

### 1. Project Overview

以 Foundry 为主的 Solidity 仓库，核心包含：

- `src/`：Memeverse 协议合约（launcher、registration、swap、governance、yield、interoperation 等）
- `test/`：Foundry 测试
- `script/`：部署与运维脚本
- `script/process/`：开发流程脚本（execution-plane 验证与 gate，不是 dispatch backend）
- `docs/process/`：流程文档
- `docs/superpowers/`、`docs/task-briefs/`、`docs/agent-reports/`、`docs/reviews/`：本地工件目录
- `docs/spec/`、`docs/ARCHITECTURE.md`、`docs/GLOSSARY.md`、`docs/TRACEABILITY.md`、`docs/VERIFICATION.md`：产品真相文档
- `.codex/templates/`：Task Brief、Agent Report、Role Delta Brief、Follow-up Brief 模板（两平台共用）

### 2. Required Commands

初次设置：`git submodule update --init --recursive` → `npm install` → `npm run hooks:install`

常用命令：`forge build` | `forge test -vvv` | `forge fmt --check` | `npm run docs:check`

本地 gate：`npm run quality:quick`（快速反馈）| `npm run quality:gate:fast`（agent workflow 默认 finish gate，按变更集）| `npm run quality:gate`（全仓全量严格 gate）

`npm run quality:gate:fast` 默认启用低噪声配置：`QUALITY_GATE_ERRORS_ONLY=1`、`FORGE_TEST_VERBOSITY=-q`、`QUALITY_GATE_FAST=1`；fast 模式会先跑非 invariant，再按变更模块定向跑 `*Invariant*.t.sol`。`npm run quality:gate` 为全量严格门禁（`QUALITY_GATE_FAST=0`，运行全量 invariant）。CI 使用 `npm run quality:gate`。`gas report` 改为按需手动执行 `npm run gas:report`。

其他：`npm run process:selftest` | `npm run codex:review`（手动高风险审查）| `bash ./script/process/check-coverage.sh` | `npm run quality:profile`

### 3. Core Principles

- **单写 owner**：同一批 Solidity 文件同一时间只能有一个实现型写入者；并行只用于只读任务
- **证据先于结论**：所有可提交结论必须能追溯到 Task Brief、agent 输出、review note、gate 或 CI；subagent finding 默认不是最终结论，`main-orchestrator` 必须复核后才能升级
- **未完成证据链不得升级**：缺少本地关键前提或只依赖模式匹配 / mock / interface 时，只能标记为 hypothesis 或测试缺口
- **可读性优先于省注释**：非直观控制流、状态迁移、金额计算、权限前提与外部调用必须补充注释；禁止噪音注释
- **测试充分性优先于"有测试就行"**：高风险路径除单元测试外还必须补充 fuzz、invariant、adversarial、integration 或 upgrade tests
- **本地前提先于外部事实**：先逐行核实本地控制流与状态更新，再核验第三方行为
- **CI 不编排 agent**：CI 只验证证据与最终 gate
- **review 边界**：review 结论只输出风险、后果、证据与可选方案；改变产品规则的结论必须升级为 `需要 main-orchestrator / human 确认的决策点`

### 4. Role Model

#### 主会话

- `main-orchestrator` 是默认主会话角色，负责 intake、拆任务、划定 file ownership、汇总证据、判定 block
- 不是 product / process / config surface 的默认写入者；除 orchestration artifact（如 `docs/task-briefs/*`）与 evidence aggregation 外，不直接改仓库文件
- 不写：`src/**/*.sol`、`script/**/*.sol`、`test/**/*.sol`、`script/**/*.sh`、`script/process/**`、`AGENTS.md`、`docs/process/**`、`.claude/**`、`.codex/**`、`.github/**`、`.githooks/*`、`package.json`、`package-lock.json`
- 命中上述路径时，必须先派发对应 writer role；派发失败必须停止并请求人工决策，不能降级为直接实现者
- 自主委派仍必须遵守角色边界、单写 owner、证据链和 block 规则

#### 默认角色

| 角色 | 权限 | 职责 | 启用条件 |
|---|---|---|---|
| `solidity-implementer` | 可写 | Solidity surface 唯一默认写入者，负责 `src/**/*.sol`、`script/**/*.sol`、方法内注释与风险匹配的测试 | 始终 |
| `process-implementer` | 可写 | 非 Solidity surface 默认写入者，负责流程、文档、CI、`script/process/**`、shell、`.githooks/*`、package metadata 与 Harness 文件 | 始终 |
| `logic-reviewer` | 只读 | 控制流、状态迁移、边界条件、语义偏差与可简化点 | `test-semantic`+ |
| `security-reviewer` | 只读 | findings、测试缺口与残余风险 | `prod-semantic`+ |
| `gas-reviewer` | 只读 | 热路径、Gas diff、优化建议与残余风险 | `prod-semantic`+ |
| `verifier` | 只读 | 验证执行与失败归因（`light` / `full` 两档） | 始终 |

#### 按需角色

- `solidity-explorer`：复杂改动前的影响面侦察与任务拆分建议
- `security-test-writer`：高风险改动后的 fuzz / invariant / adversarial tests 补强

### 5. Review Order

按变更分类选择审阅流程（对 `src/**/*.sol` / `script/**/*.sol` 变更，必须先运行 `npm run classify:change`）：

- `non-semantic`：solidity-implementer → codex review → verifier(light)
- `test-semantic`：solidity-implementer → logic-reviewer → codex review → verifier(light)
- `prod-semantic`：solidity-implementer → logic-reviewer → security-reviewer → gas-reviewer → codex review → verifier(full)
- `high-risk`：同 `prod-semantic`，优先考虑 `security-test-writer`

测试变更（`test/**/*.sol` / `test/**/*.t.sol`）：solidity-implementer → logic-reviewer → codex review → verifier；高风险可选加 security-reviewer

流程面变更（`AGENTS.md`、`docs/process/**`、`.claude/**`、`.codex/**`、`script/process/**`）：process-implementer → codex review → verifier

### 6. Change Surfaces

- 路径触发规则、默认角色、必跑命令与 gate 约束以 `docs/process/change-matrix.md` 为准
- 路径触发规则同时已在 `.claude/rules/` 中以 `paths:` frontmatter rule 文件落地
- `MemeverseV2` 的 `rule-map`（`docs/process/rule-map.json`）是 repo-specific 扩展

### 7. PR / Review Note Contract

PR 模板：`.github/pull_request_template.md`，必须包含：`## Summary`、`## Impact`、`## Docs`、`## Tests`、`## Verification`、`## Risks`、`## Security`、`## Simplification`、`## Gas`

Review note 规则：`docs/process/review-notes.md`。命中 `src/**/*.sol`、`script/**/*.sol` 变更时必须有有效 review note。

### 8. Shared Agent Contract

所有角色的通用输入、输出与决策规则。完整定义见 `docs/process/agents-detail.md §A`。
各角色 runtime contract 只需定义角色特有行为，不需要重复通用契约。
回修轮次统一使用 Follow-up Brief（`.codex/templates/follow-up-brief.md`）。

### 9. Workflow Phases

Phase 1: 接收 / 划定范围 → Phase 2: 基线分析 → Phase 3: 实现 → Phase 4: 逻辑审阅 → Phase 5: 专家审阅 → Phase 6: 测试加固 → Phase 7: 验证 → Phase 8: 决策。
各 Phase 完整准入/准出条件与角色职责见 `docs/process/agents-detail.md §B`。
关键约束：Phase 3 中 main-orchestrator 不得降级为直接实现者；Phase 7 中 stale evidence 必须阻断。

### 10. 证据链与阻断规则

#### 证据链

- Solidity：`Task Brief → Agent Report → codex review → review note → verifier evidence → quality:gate → CI`
- Process：`Task Brief → Agent Report → codex review → verifier evidence → docs:check / process:selftest`

`review note` 是唯一统一审阅记录。`quality:gate` 是唯一 finish gate。CI 只验证不编排。

#### Hard-block（硬阻断）

- verifier 任一 required command fail
- `main-orchestrator` 直接写入受限路径
- 缺少 Task Brief 就开始 Solidity 实现
- 流程面改动缺少 Task Brief、Agent Report 或 required command 证据
- `security-reviewer` 存在未关闭的 `high` finding
- Solidity 变更但缺对应 reviewer 结论
- coverage 或 required checks 未达标
- finding 缺少本地前提证据或外部主来源证据
- review note 或 evidence 早于当前 writer Agent Report
- review note 缺字段、缺 ownership / Agent Report 工件链，或仍为占位值

#### Soft-block（软阻断）

- 可解释的中低优先级 Gas 回退
- 可延期的简化建议
- 不影响正确性与安全性的文档补充
- 已识别会改变产品规则但尚未获得决策的 review 建议

### 11. 真源层级

#### 人类 / Agent 可读

`AGENTS.md` → `.claude/rules/*.md`（CC）→ `.claude/agents/*.md`（CC）→ `.codex/agents/*.md`（Codex）→ `docs/process/change-matrix.md` → `docs/process/review-notes.md`

#### 脚本专用（agent 不需要直接读）

`docs/process/policy.json` → `script/process/*` → `docs/process/rule-map.json`（若存在）

---

## Part II: Claude Code 工作流（Codex 请忽略）

### CC-1. 派发机制

- 使用 Agent tool，`name` 匹配角色名（如 `solidity-implementer`）
- Agent 定义：`.claude/agents/*.md`（YAML frontmatter 含 name, model, tools）
- 路径触发规则：`.claude/rules/*.md`（`paths:` frontmatter，编辑匹配路径时自动加载）
- 主会话 = main-orchestrator（不是 dispatched agent）

### CC-2. Agent 映射

| 角色 | Agent 文件 | 类型 |
|---|---|---|
| `solidity-implementer` | `.claude/agents/solidity-implementer.md` | 可写 |
| `process-implementer` | `.claude/agents/process-implementer.md` | 可写 |
| `logic-reviewer` | `.claude/agents/logic-reviewer.md` | 只读 |
| `security-reviewer` | `.claude/agents/security-reviewer.md` | 只读 |
| `gas-reviewer` | `.claude/agents/gas-reviewer.md` | 只读 |
| `verifier` | `.claude/agents/verifier.md` | 只读 |
| `solidity-explorer` | `.claude/agents/solidity-explorer.md` | 按需只读 |
| `security-test-writer` | `.claude/agents/security-test-writer.md` | 按需可写 |

### CC-3. 主会话规则

- 不写的路径清单见 Part I §4 Main Session
- 必须先 dispatch，派发失败必须停止
- 自主委派仍必须遵守角色边界、单写 owner、证据链和 block 规则

---

## Part III: Codex 工作流（Claude Code 请忽略）

### CX-1. 派发机制

- 原生 subagent 派发 + `.codex/agents/*.toml`
- 双文件模型：`*.toml`（manifest / 入口层，只承载最小角色元数据）+ `*.md`（runtime contract / 行为真源）
- 同名 `*.toml` 与 `*.md` 冲突时以 `*.md` 为准

### CX-2. Agent 映射

| 角色 | Manifest | Runtime Contract |

|---|---|---|
| `solidity-implementer` | `.codex/agents/solidity-implementer.toml` | `.codex/agents/solidity-implementer.md` |
| `process-implementer` | `.codex/agents/process-implementer.toml` | `.codex/agents/process-implementer.md` |
| `logic-reviewer` | `.codex/agents/logic-reviewer.toml` | `.codex/agents/logic-reviewer.md` |
| `security-reviewer` | `.codex/agents/security-reviewer.toml` | `.codex/agents/security-reviewer.md` |
| `gas-reviewer` | `.codex/agents/gas-reviewer.toml` | `.codex/agents/gas-reviewer.md` |
| `verifier` | `.codex/agents/verifier.toml` | `.codex/agents/verifier.md` |
| `solidity-explorer` | `.codex/agents/solidity-explorer.toml` | `.codex/agents/solidity-explorer.md` |
| `security-test-writer` | `.codex/agents/security-test-writer.toml` | `.codex/agents/security-test-writer.md` |

### CX-3. 索引文件

- Workflow index：`.codex/workflows/solidity-subagent-workflow.json`
- Runtime index：`.codex/runtime/subagent-runtime.json`
- 两者定义 surfaces、角色集合、工件位置与 path-triggered defaults，不承载行为规则（行为规则在 `*.md` runtime contract 和本文档中）

---

## Part IV: 项目特定配置

### 模块目录

Launcher（`src/verse/MemeverseLauncher.sol`）、Registration（`src/verse/registration/`）、Swap（`src/swap/`）、Token（`src/token/`）、Yield（`src/yield/`）、Governance（`src/governance/`）、Interoperation（`src/interoperation/`）

### 产品真相文档

- Core：`docs/spec/*`、`docs/spec/upgradeability.md`、`src/**`、`test/**`、`script/**`
- Support：`docs/ARCHITECTURE.md`、`docs/GLOSSARY.md`、`docs/TRACEABILITY.md`、`docs/VERIFICATION.md`、`docs/reviews/TEMPLATE.md`

### 本地专用目录

`docs/superpowers/specs/`（规范）、`docs/superpowers/plans/`（设计）、`docs/task-briefs/`（Task Brief）、`docs/agent-reports/`（Agent Report）、`docs/reviews/`（review 草稿）。新建文档前必须先校验目标目录是否符合仓库约定。

### 语言

与用户交流始终以及新增自然语言文档始终使用简体中文；固定字段 key、命令、路径、标识保持英文。

### 建议阅读顺序

1. `AGENTS.md` → 2. `docs/spec/*` → 3. `src/verse/`、`src/swap/`、`src/token/` → 4. `src/yield/`、`src/governance/`、`src/interoperation/` → 5. `test/`、`script/` → 6. `docs/process/*`
