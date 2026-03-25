# ADR 0001: 采用 UniversalVault 风格的 Harness + Product-Truth 文档分层

- 状态：Accepted
- 日期：2026-03-25
- 决策范围：`MemeverseV2` 文档治理与验证链路（不改变链上合约逻辑）

## 背景

当前仓库同时存在三类信息：

1. 产品补充文档（`docs/memeverse-swap/*`）
2. 实现真相（`src/**`）
3. 流程/证据真源（`AGENTS.md`、`docs/process/*`）

历史上这些层次容易混在一起，导致：

- PRD 叙事与代码语义出现漂移时，读者难以快速判断“以哪个为准”
- 审阅、测试、运维难形成统一证据入口
- 生成文档产物与规则真源边界不清晰

## 决策

采用 UniversalVault 风格分层，明确“产品真相层”作为中间层：

1. **Intent Layer（意图层）**
 - 保留 PRD 与功能叙事，允许表达产品目标与历史设计。
2. **Product-Truth Core Layer（产品真相核心层）**
 - 在 `docs/spec/*` 输出当前可执行规则：
   - 协议总览、状态机、记账、权限、升级性
   - 配置矩阵、事件面、运维语义、部署事实、外部集成边界
   - 跨模块不变量
3. **Product-Truth Support Layer（产品真相支撑层）**
 - `docs/ARCHITECTURE.md` + `docs/GLOSSARY.md` + `docs/TRACEABILITY.md` + `docs/VERIFICATION.md` + `docs/adr/*`
 - 用于规则边界、术语、追溯矩阵与验证基线的持续维护
4. **Harness / Process Layer（流程契约层）**
 - `AGENTS.md` + `docs/process/*` + `script/process/*`
 - 定义协作流程、门禁与机器可执行检查逻辑
5. **Implementation Evidence Layer（实现证据层）**
 - `src/**` + `test/**`
 - 作为 Product-Truth 规则的可验证实现证据

同时明确：

- 执行语义以代码与 product-truth 文档为准

## 备选方案与取舍

### 方案 A：只维护 PRD + 代码（不设 product-truth 层）

- 优点：维护文件更少
- 缺点：PRD/代码漂移时，审计与运维成本高，证据链不稳定

### 方案 B：直接把实现细节写进 PRD

- 优点：单文档集中
- 缺点：PRD丢失“产品意图”角色，读写冲突大，变更噪声高

### 方案 C：当前决策（推荐）

- 优点：意图、真相、证据三层职责清晰；利于持续审计与回归
- 成本：需要维护一组 spec 文档并保持与代码同步

## 影响

### 正向影响

- 代码审阅与测试设计可直接引用 `docs/spec/*` 的规则语句
- 运营与集成方可读取“当前语义”，减少 PRD 历史叙事干扰
- 变更评估可通过 traceability/verification 更快闭环

### 负向影响

- 文档维护量增加
- 需要在每次行为变更后同步更新 spec 与 traceability

## 实施约束

- 新增自然语言文档默认简体中文；命令、路径、代码标识保持英文。
- 明确标注“代码已证 / 未知”边界，避免推测性表述。
- 文档中不得使用占位式待办标记。

## 非目标

- 本 ADR 不变更合约访问控制、经济模型或跨链协议参数。
- 本 ADR 不替代测试与代码审计本身，只定义文档治理骨架。
