# UniversalVault 文档与 Harness 迁移设计

## 背景

`MemeverseV2` 当前已经有一套可工作的流程脚本、`review note` 与 `rule-map`，但仓库内仍缺少两类关键真源：

- 以 `AGENTS.md + .codex/agents + docs/process/subagent-workflow.md` 为核心的仓内 subagent Harness
- 以 `docs/spec/*` 为核心的产品规则与系统边界真源

`UniversalVault` 已经把这两层组织成统一体系：主流程契约、角色化 subagent 模型、结构化证据链、产品规格层、实现映射层、可追溯性与验证入口之间边界清晰。目标是把这套结构迁移到 `MemeverseV2`，同时保留 `MemeverseV2` 现有的高价值特性，如 `rule-map.json`、流程自测和 Foundry 生成文档链路。

## 目标

- 让 `MemeverseV2` 采用 `UniversalVault` 风格的仓内 Harness，统一主流程契约、subagent 角色模型和证据链
- 把 `MemeverseV2` 的产品文档从 `PRD + 生成文档 + 零散流程说明` 收敛为 `docs/spec/*` 主真源
- 保留 `rule-map.json`、流程脚本自测、`docs:check` 等 Memeverse 特有机制，并挂到新的 Harness 下面

## 非目标

- 不改动 `src/**/*.sol`、`test/**/*.sol` 的业务逻辑
- 不把 `docs/spec/*` 写成源码逐文件说明书
- 不继续把 `skills/solidity-post-coding-flow/SKILL.md` 作为仓库主流程真源

## 方案比较

### 方案 A：保守拼接

只把 `UniversalVault` 的 `docs/spec/*` 和 `.codex/` 搬进来，保留 `MemeverseV2` 现有 `AGENTS.md`、`docs/process/*` 和 `script/process/*` 主结构。

优点：

- 改动最少
- 风险较低

缺点：

- 会形成两套真源
- 主流程契约和 subagent 契约会互相冲突
- 后续维护成本高

### 方案 B：`UniversalVault` 骨架优先，按 Memeverse 回填特性

以 `UniversalVault` 的 `AGENTS.md`、`.codex/agents`、templates、`docs/process/*`、`docs/process/subagent-workflow.md` 作为新主骨架，再把 `MemeverseV2` 已验证有效的特性回填进去。

优点：

- 主契约、角色模型、证据链、产品文档分层都统一
- 能保留 `rule-map.json`、流程自测
- 最适合长期维护

缺点：

- 需要重写的文档和脚本较多

### 方案 C：近乎完全照抄 `UniversalVault`

尽量按 `UniversalVault` 原样迁移，只替换协议名和少量路径。

优点：

- 结构最整齐
- 迁移速度快

缺点：

- 会丢失 `MemeverseV2` 特有的测试治理和流程资产
- 对现有仓库不够贴合

## 结论

采用方案 B：`UniversalVault-style harness + Memeverse-specific product/spec overlay`。

## 目标架构

迁移完成后，`MemeverseV2` 的仓内真源分为四层。

### 1. 总入口层

- `README.md`
  - 仓库概览
  - 快速开始
  - 文档入口与阅读顺序

### 2. 主流程契约层

- `AGENTS.md`
  - 主会话角色
  - 默认 / 按需 subagent 角色
  - 变更矩阵摘要
  - finish gate
  - block 规则
  - source of truth

### 3. Subagent Runtime 层

- `.codex/agents/*.toml`
- `.codex/agents/*.md`
- `.codex/templates/task-brief.md`
- `.codex/templates/agent-report.md`
- `docs/process/subagent-workflow.md`

这一层负责：

- 明确角色职责
- 明确输入契约和输出契约
- 明确读写边界
- 明确证据链
- 明确 hard-block / soft-block 语义

### 4. 文档真源层

产品真源：

- `docs/spec/*`

流程与证据真源：

- `docs/process/*`
- `docs/reviews/*`
- `docs/ARCHITECTURE.md`
- `docs/GLOSSARY.md`
- `docs/TRACEABILITY.md`
- `docs/VERIFICATION.md`
- `docs/adr/*`

明确排除：

- `out/`、`cache/`、脚本输出、测试辅助件不属于产品文档真源

## 文件级迁移映射

### A. 直接引入 `UniversalVault` 骨架并按仓库名/路径改写

以下文件的结构可直接继承 `UniversalVault`：

- `.codex/templates/task-brief.md`
- `.codex/templates/agent-report.md`
- `.codex/agents/README.md`
- `.codex/agents/main-orchestrator.toml`
- `.codex/agents/main-orchestrator.md`
- `.codex/agents/process-implementer.toml`
- `.codex/agents/process-implementer.md`
- `.codex/agents/solidity-implementer.toml`
- `.codex/agents/solidity-implementer.md`
- `.codex/agents/security-reviewer.toml`
- `.codex/agents/security-reviewer.md`
- `.codex/agents/gas-reviewer.toml`
- `.codex/agents/gas-reviewer.md`
- `.codex/agents/security-test-writer.toml`
- `.codex/agents/security-test-writer.md`
- `.codex/agents/solidity-explorer.toml`
- `.codex/agents/solidity-explorer.md`
- `.codex/agents/verifier.toml`
- `.codex/agents/verifier.md`

改写要求：

- 把仓库名替换为 `MemeverseV2`
- 在 `process-implementer`、`verifier`、`policy.json` 相关说明中显式保留 `rule-map.json`、`script/process/tests/*`、`docs:check`
- 允许 `process-implementer` 修改 Harness、流程、文档相关非 Solidity 文件

### B. 按 `UniversalVault` 结构重写，但内容按 Memeverse 语义重写

- `README.md`
- `AGENTS.md`
- `docs/ARCHITECTURE.md`
- `docs/TRACEABILITY.md`
- `docs/VERIFICATION.md`
- `docs/GLOSSARY.md`
- `docs/process/change-matrix.md`
- `docs/process/review-notes.md`
- `docs/process/policy.json`
- `docs/process/subagent-workflow.md`
- `docs/reviews/TEMPLATE.md`
- `docs/reviews/README.md`

重写目标：

- 用 `main-orchestrator + role-based subagents` 取代“以 skill 为主”的仓库主契约
- 在 `policy.json` 中补齐 review note field owner、agents 目录、默认角色、docs contract pattern
- 把 `TRACEABILITY.md` 写成“规则 -> 文档源 -> 预期实现面 -> 预期测试面 -> 当前证据 -> 状态”的矩阵
- 把 `ARCHITECTURE.md` 写成产品模块地图、资金流、文档分层和阅读顺序，而不是代码目录总览

### C. 保留并接入 Memeverse 特有机制

以下内容不删除，但要挂到新骨架下：

- `docs/process/rule-map.json`
- `script/process/check-rule-map.sh`
- `script/process/tests/*`
- `script/process/tools/install-repo-skill.sh`
- `script/process/check-pr-body.sh`
- `package.json` 中 `docs:check`、`process:selftest`

接入原则：

- `rule-map.json` 继续作为“关键行为到测试证据”的机器可读真源
- `policy.json`、`AGENTS.md`、`change-matrix.md`、`review-notes.md` 必须显式引用 `rule-map.json`
- `process:selftest` 继续保留，作为流程脚本质量保障

### D. 新增产品文档真源目录

建议新增：

- `docs/spec/protocol.md`
- `docs/spec/state-machines.md`
- `docs/spec/accounting.md`
- `docs/spec/invariants.md`
- `docs/spec/access-control.md`
- `docs/spec/upgradeability.md`
- `docs/spec/config-matrix.md`
- `docs/spec/events.md`
- `docs/spec/operations.md`
- `docs/spec/deployment.md`
- `docs/spec/implementation-map.md`
- `docs/spec/integrations/layerzero-oapp-oft.md`
- `docs/spec/integrations/uniswap-v4.md`
- `docs/spec/integrations/permit2.md`
- `docs/adr/0001-universalvault-style-harness-migration.md`

如确有需要，再补充其他 ADR 和 integration spec。

## 产品文档分层

### `docs/spec/protocol.md`

回答：

- Memeverse 的系统目标
- 当前版本边界
- 模块矩阵
- 用户可见主路径
- 非目标

### `docs/spec/state-machines.md`

回答：

- `Genesis -> Refund / Locked -> Unlocked`
- `flashGenesis` 语义
- 注册和跨链注册状态边界
- anti-snipe 窗口内外的状态差异

### `docs/spec/accounting.md`

回答：

- Genesis 资金拆分
- memecoin / POL / LP / fee 的数量关系
- executor reward、treasury fee、yield fee 的记账口径
- `redeemMemecoinLiquidity` 与 `redeemPolLiquidity` 的份额规则

### `docs/spec/invariants.md`

回答：

- verseId、memecoin、liquidProof 的映射一致性
- Genesis 用户累计资金和全局总资金的一致性
- POL claim / mint / burn 与 LP 存量关系
- fee 分发路径互斥性
- 注册和跨链元数据唯一性约束

### `docs/spec/access-control.md`

回答：

- owner
- registrar
- governor
- permissionless caller
- dispatcher / endpoint / deployer 边界

### `docs/spec/upgradeability.md`

回答：

- 哪些合约是可升级 surface
- 初始化约束
- proxy / deployer 对系统行为的前提

### `docs/spec/config-matrix.md`

回答：

- fund metadata
- executorRewardRate
- anti-snipe duration
- LayerZero / gas 配置
- router / deployer / dispatcher / registrar / endpoint registry 注入项

### `docs/spec/events.md`

回答：

- 外部索引器与运维可依赖的事件
- 不应凭空假设的隐式状态

### `docs/spec/operations.md`

回答：

- 阶段推进
- fee 分发
- 异链报价与发送
- 常见失败面与人工干预点

### `docs/spec/deployment.md`

回答：

- 当前仓库能确认的部署拓扑、装配关系与环境边界
- 不能确认的部署事实

### `docs/spec/implementation-map.md`

回答：

- 当前真实源码 surface
- 各 surface 的职责、权限、升级模型、证据来源和 implementation status

## 迁移执行顺序

### Phase 1：建立新骨架

- 新增 `.codex/agents/*`
- 新增 `.codex/templates/*`
- 新增 `docs/process/subagent-workflow.md`
- 重写 `README.md`
- 重写 `AGENTS.md`

### Phase 2：重构流程真源

- 重写 `docs/process/change-matrix.md`
- 重写 `docs/process/review-notes.md`
- 重写 `docs/process/policy.json`
- 调整 `docs/reviews/TEMPLATE.md`
- 调整 `docs/reviews/README.md`
- 保留并接入 `docs/process/rule-map.json`

### Phase 3：对齐脚本与命令

- 调整 `script/process/check-docs.sh`
- 调整 `script/process/quality-quick.sh`
- 调整 `script/process/quality-gate.sh`
- 必要时调整 `script/process/read-process-config.js`
- 必要时调整 `check-solidity-review-note.sh` 与 `check-rule-map.sh` 的读取逻辑
- 对齐 `package.json`

### Phase 4：建立产品文档真源

优先新增和回填：

- `docs/spec/protocol.md`
- `docs/spec/state-machines.md`
- `docs/spec/accounting.md`
- `docs/spec/access-control.md`
- `docs/spec/implementation-map.md`

然后补齐：

- `docs/spec/invariants.md`
- `docs/spec/upgradeability.md`
- `docs/spec/config-matrix.md`
- `docs/spec/events.md`
- `docs/spec/operations.md`
- `docs/spec/deployment.md`
- `docs/spec/integrations/*`
- `docs/ARCHITECTURE.md`
- `docs/GLOSSARY.md`
- `docs/TRACEABILITY.md`
- `docs/VERIFICATION.md`
- `docs/adr/*`

### Phase 5：验证与收尾

至少验证：

- `npm run docs:check`
- `npm run process:selftest`

按改动面补充：

- `bash -n` 覆盖被改动的 shell
- 必要时补一份样例 `review note`

## 风险

### 1. 流程真源冲突

如果 `AGENTS.md`、`.codex/agents` 和 `skills/solidity-post-coding-flow/SKILL.md` 继续并列作为主契约，后续会出现两套编排真源。

处理：

- 仓库主契约以 `AGENTS.md + .codex + docs/process/subagent-workflow.md` 为准
- `skills/solidity-post-coding-flow/SKILL.md` 降为兼容辅助入口

### 2. `policy.json` 与脚本脱节

如果只重写文档，不同步脚本，`quality:quick` / `quality:gate` 会和新契约不一致。

处理：

- `policy.json` 与流程脚本必须同批提交
- 完成后跑 `process:selftest`

### 3. `rule-map.json` 被边缘化

如果迁移只复刻 `UniversalVault` 而不正式接入 `rule-map.json`，会削弱 `MemeverseV2` 现有测试治理。

处理：

- 在 `AGENTS.md`、`change-matrix.md`、`review-notes.md`、`policy.json` 中显式接入 `rule-map.json`

### 4. `docs/spec/*` 退化成代码目录注释

如果按目录逐文件解释，就会失去产品真源意义。

处理：

- `protocol / state-machines / accounting / invariants / access-control / implementation-map` 严格分工
- 纯内部 helper 不写入 spec 主文档

### 5. 过渡期阅读入口混乱

补充专题文档、旧流程说明和新 `docs/spec/*` 会短期并存。

处理：

- 在 `README.md`、`AGENTS.md`、`docs/ARCHITECTURE.md` 中明确阅读顺序
- 把补充专题文档降级为背景资料，不再作为当前真源

## 验收标准

- 仓库内存在完整的 `.codex/agents` 与 `.codex/templates` 结构
- `AGENTS.md` 成为唯一主流程契约，并明确 subagent role model
- `docs/process/subagent-workflow.md`、`docs/process/policy.json`、`docs/process/change-matrix.md`、`docs/process/review-notes.md` 语义一致
- `rule-map.json` 被明确纳入新的 Harness
- 新增 `docs/spec/*` 主骨架，并至少覆盖 `protocol`、`state-machines`、`accounting`、`access-control`、`implementation-map`
- `npm run docs:check` 与 `npm run process:selftest` 能验证新骨架

## 最终建议

采用“`UniversalVault` 骨架覆盖 + `Memeverse` 特性回填”的迁移方式。这样可以同时获得：

- 统一的仓内 Harness
- 明确的 subagent 角色体系
- 成体系的产品文档真源
- 对 `MemeverseV2` 现有流程资产的最大保留
