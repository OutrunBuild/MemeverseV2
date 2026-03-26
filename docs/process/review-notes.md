# Review Note 契约（UniversalVault 风格 + Memeverse 扩展）

`docs/reviews/*.md` 默认是本地 review 草稿目录。命中 `src/**/*.sol` 时，`quality:gate` 在本地和 CI 下都要求至少 1 份有效 review note。

本契约分为两层：

- gate 强校验层：`required_headings`、`required_fields`、`boolean_fields`、`placeholder_values`
- 角色语义层：`field_owners`、`owner_prefixed_source_fields`

机器可读真源统一在 `docs/process/policy.json`。

## 语言与格式

- 自然语言说明默认使用简体中文
- 固定 section / field key 保持英文
- 路径、命令、代码标识、selector 保持英文
- `Behavior change`、`ABI change`、`Storage layout change`、`Config change`、`Ready to commit` 只能填 `yes` 或 `no`

## 必填章节（`review_note.required_headings`）

- `## Scope`
- `## Impact`
- `## Findings`
- `## Simplification`
- `## Gas`
- `## Docs`
- `## Tests`
- `## Verification`
- `## Decision`

## 必填字段（`review_note.required_fields`）

- `Change summary`
- `Files reviewed`
- `Semantic dimensions reviewed`
- `Source-of-truth docs checked`
- `External facts checked`
- `Local control-flow facts checked`
- `Evidence chain complete`
- `Semantic alignment summary`
- `Behavior change`
- `ABI change`
- `Storage layout change`
- `Config change`
- `Security review summary`
- `Security residual risks`
- `Open safety mismatches assessed`
- `Gas-sensitive paths reviewed`
- `Gas changes applied`
- `Gas snapshot/result`
- `Gas residual risks`
- `Docs updated`
- `Tests updated`
- `Existing tests exercised`
- `Commands run`
- `Results`
- `Ready to commit`
- `Residual risks`

## 布尔字段（`review_note.boolean_fields`）

- `Behavior change`
- `ABI change`
- `Storage layout change`
- `Config change`
- `Ready to commit`

## 字段 owner 语义（`review_note.field_owners`）

默认 owner 语义：

- `Semantic dimensions reviewed`、`Source-of-truth docs checked`、`External facts checked`、`Semantic alignment summary` 由 `main-orchestrator` 汇总填写
- `Local control-flow facts checked`、`Evidence chain complete` 由 `main-orchestrator` 在复核关键代码行、关键前提和必要的外部主来源后填写
- 安全字段（`Security review summary`、`Security residual risks`）由 `security-reviewer` 提供
- `Open safety mismatches assessed` 用于显式记录是否审阅了当前已知开放安全缺口（例如 `SAFE-UNLOCK-01`），默认由 `security-reviewer`、`verifier` 或 `main-orchestrator` 维护
- Gas 字段（`Gas-*`）由 `gas-reviewer` 提供
- 验证字段（`Commands run`、`Results`）由 `verifier` 提供
- 决策字段（`Ready to commit`）由 `main-orchestrator` 最终确认
- `Docs updated` 由实现角色（`solidity-implementer` 或 `process-implementer`）维护
- `Tests updated` / `Existing tests exercised` 由实现角色（`solidity-implementer`、`process-implementer`、`security-test-writer`）维护
- `Rule-map evidence source` 由 `verifier` 汇总

owner 语义以 `policy.json` 为机器可读真源。

## 证据来源字段语义（`review_note.owner_prefixed_source_fields`）

以下字段采用 `role: source` 形式，表达“结论由谁给出、证据来自哪里”：

- `Security evidence source`
- `Gas evidence source`
- `Verification evidence source`
- `Decision evidence source`
- `Rule-map evidence source`

示例：

- `Security evidence source: security-reviewer: docs/reviews/2026-03-25-security-pass.md`
- `Gas evidence source: gas-reviewer: docs/reviews/2026-03-25-gas-pass.md`
- `Verification evidence source: verifier: forge test -vvv`
- `Decision evidence source: main-orchestrator: task brief decision summary`

## Memeverse 专属 rule-map 证据规则

`docs/process/rule-map.json` 是 Memeverse 专属映射真源，不被通用 harness 替代。命中正式规则时：

- `check-rule-map.sh` 依据 `change_requirement` 校验改动集
- `check-solidity-review-note.sh` 依据 `evidence_requirement` 校验 `Existing tests exercised`
- `mode = any`：至少引用 1 个映射测试
- `mode = all`：必须覆盖全部映射测试
- `mode = none`：不要求额外映射测试

`Rule-map evidence source` 用于记录对应 rule id / 测试路径来源，便于追溯；当前 gate 仍以 `Existing tests exercised` 为硬校验入口。

## 防误报 / 证据链规则

- `Local control-flow facts checked` 必须写清该结论依赖的本地关键前提，例如状态更新顺序、条件分支、金额截断、索引推进、返回值处理或权限检查
- 若结论依赖第三方协议、外部合约、SDK、API 或系统行为，`External facts checked` 必须写明主来源；没有主来源时只能写成 `needs verification` 或假设，不能写成已确认事实
- `Evidence chain complete` 只有在“本地前提已复核”且“必要时外部主来源已核验”同时满足时才允许填写 `yes`
- 若某条结论只来自 subagent 摘要而主会话未复核关键代码行，该条结论不得在 review note 中写成已确认 finding

## 开放安全缺口填写约定

当改动触达 launcher / router / hook / unlock 语义时：

- `Open safety mismatches assessed` 不得省略
- 至少应显式写出：
  - `SAFE-UNLOCK-01: still open`
  - 或 `SAFE-UNLOCK-01: resolved by <tests/changes>`
- 若 review note 声称该缺口已解决，`Existing tests exercised` 必须同时包含与 unlock protection 相关的映射测试
- 若缺口仍未解决，`Security residual risks` 或 `Residual risks` 中应保留对应风险说明

## Findings 填写约定

`Findings` 采用二选一：

- 有发现：填写 `High findings` / `Medium findings` / `Low findings`，并把 `None` 设为 `n/a`
- 无发现：`High findings` / `Medium findings` / `Low findings` 填 `none`，`None` 保持 `none`

## 禁止值

以下占位值会被视为无效：

- 空值
- `TBD`
- `<path>`
- `<path>|none`
- `<selectors or paths>`
- `<agent-report-path>`
- `<verification-source>`
- `<decision-source>`
- `<rule-id or mapped-tests>`
- `yes/no`

## 使用方式

- 以 `docs/reviews/TEMPLATE.md` 新建 review note
- 仅校验结构可运行：`bash ./script/process/check-review-note.sh <review-note>`
- 需要联动 `rule-map` 证据时运行：`bash ./script/process/check-solidity-review-note.sh`
