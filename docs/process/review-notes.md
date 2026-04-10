# Review Note 规范

`docs/reviews/*.md` 默认是本地 review 草稿目录。命中 `src/**/*.sol`、`script/**/*.sol` 时，本地与 CI 的 `quality:gate` 都要求至少有一份有效 review note 作为安全、简化、Gas 与验证证据。

## 1. 语言与格式

- review note 正文默认使用简体中文。
- 固定 section / field key 保持英文。
- 路径、命令、代码标识、selector 保持英文原文。
- `Behavior change`、`ABI change`、`Storage layout change`、`Config change`、`Writer dispatch confirmed`、`Evidence chain complete`、`Ready to commit` 的值只能填写 `yes` 或 `no`。
- 所有 `* evidence source` 字段都采用 `role: source` 格式。

## 2. 必填章节

- `## Scope`
- `## Impact`
- `## Findings`
- `## Simplification`
- `## Gas`
- `## Docs`
- `## Tests`
- `## Verification`
- `## Decision`

## 3. 通用必填字段

以下字段是跨仓库共享的 Harness 基线：

- `Change summary`
- `Files reviewed`
- `Task Brief path`
- `Agent Report path`
- `Implementation owner`
- `Writer dispatch confirmed`
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
- `Logic review summary`
- `Logic residual risks`
- `Security review summary`
- `Security residual risks`
- `Gas-sensitive paths reviewed`
- `Gas changes applied`
- `Gas snapshot/result`
- `Gas residual risks`
- `Docs updated`
- `Tests updated`
- `Existing tests exercised`
- `Commands run`
- `Results`
- `Logic evidence source`
- `Security evidence source`
- `Gas evidence source`
- `Verification evidence source`
- `Decision evidence source`
- `Ready to commit`
- `Residual risks`

## 4. Repo-specific 扩展字段

如果 `docs/process/policy.json`、`docs/process/rule-map.json` 或相关 gate 脚本要求额外字段，也必须填写。常见扩展示例：

- `Open safety mismatches assessed`
- `Rule-map evidence source`
- 其他仅在当前仓库策略文件中声明的字段

判断原则：

- 以 `docs/process/policy.json` 的 `review_note.*` 与 `solidity_review_note.*` 为准。
- 若仓库启用了 repo-specific 证据映射，review note 必须与其约束保持一致。

## 5. 字段职责

- `Task Brief path`、`Agent Report path`、`Implementation owner`、`Writer dispatch confirmed`
  - 默认由 `main-orchestrator` 汇总填写，用于证明该 Solidity 变更先有 brief，且 writer role 已按仓库契约派发并产出对应实现工件。
  - `Task Brief path` 默认应位于 `docs/task-briefs/`。
  - `Agent Report path` 默认应位于 `docs/agent-reports/`。
- 若 review note 用于流程面 evidence aggregation，仍应回溯到对应 `Task Brief path`、`Agent Report path` 与 verifier 结论；不得用聊天记录替代工件链。
- `Semantic dimensions reviewed`、`Source-of-truth docs checked`、`External facts checked`、`Semantic alignment summary`
  - 默认由 `main-orchestrator` 汇总 brief、review 结论与外部证据后填写。
- `Local control-flow facts checked`、`Evidence chain complete`
  - 默认由 `main-orchestrator` 在复核关键代码行、关键前提与必要外部主来源后填写。
- `Logic review summary`、`Logic residual risks`、`Logic evidence source`
  - 默认由 `logic-reviewer` 提供。
- `Security review summary`、`Security residual risks`、`Security evidence source`
  - 默认由 `security-reviewer` 提供。
- `Gas-sensitive paths reviewed`、`Gas changes applied`、`Gas snapshot/result`、`Gas residual risks`、`Gas evidence source`
  - 默认由 `gas-reviewer` 提供。
- `Commands run`、`Results`、`Verification evidence source`
  - 默认由 `verifier` 提供。
  - `verifier` 仍负责 `Commands run`、`Results` 中的验证 verdict，以及相关证据链；writer 侧字段轻量化不会减轻 `verifier` 的证据责任。
  - `Results` 必须包含 required commands 的通过/失败结论与 failure attribution，不能只写“已跑 gate”。
- `Codex review summary`、`Codex review evidence source`
  - 默认由 `verifier` 提供，用于记录 writer 完成后的一次独立 Codex 审查与 findings 收口。
  - 仅在 classification 要求本地 `codex:review`，或 review note 显式记录该审查证据时才需要填写并参与校验。
- `Ready to commit`、`Decision evidence source`
  - 只能由 `main-orchestrator` 最终判定。

## 6. Spec Surface 特例

- 以下规则描述 spec surface 的当前契约；`spec-reviewer` evidence、stale remediation 与 selftest coverage 已接入当前 execution-plane。
- `docs/spec/**`、`docs/superpowers/specs/**`、或后续 brief 接入后声明 `Artifact type: spec` 的变更，不以 review note 作为 spec review 的主证据。
- spec review evidence 作为这类 surface 的 reviewer artifact。
- writer 再次写入同一 spec scope 后，旧的 spec review evidence 视为 stale，不能复用；自动化 stale remediation 会生成新的 follow-up brief 和 rerun order。
- 当前顺序是 `process-implementer → spec-reviewer → verifier`。
- `docs/reviews/*.md` 若存在，只作为后续汇总或补充证据，不替代 spec review evidence。

## 7. 防误报与证据链规则

通用证据链定义与 hard-block / soft-block 规则见 AGENTS.md §10。以下为 review note 层面的补充约束：

- `Local control-flow facts checked` 必须写清结论依赖的本地关键前提，例如状态更新顺序、条件分支、金额处理、索引推进、返回值处理或权限检查。
- 若结论依赖第三方协议、外部合约、SDK、API 或系统行为，`External facts checked` 必须写明主来源；没有主来源时只能写成 `needs verification`、假设或待确认决策点。
- `Evidence chain complete` 只有在"本地前提已复核"且"必要时外部主来源已核验"同时满足时才允许填写 `yes`。
- 若某条结论只来自 subagent 摘要而主会话未复核关键代码行，该条结论不得在 review note 中写成已确认 finding。
- 对 `src/**/*.sol`、`script/**/*.sol` 写面，`Logic evidence source`、`Security evidence source`、`Gas evidence source`、`Verification evidence source` 必须指向可落盘、可回溯的具体 artifact path；不能只写命令名、聊天结论或模糊描述。
- 当某个 reviewer 没有被 classifier 选中时，对应 review-note 字段应保留 owner-prefixed 说明，例如 `security-reviewer: skipped by classifier (non-semantic)`；不得伪造不存在的 reviewer artifact path。

## 8. 禁止内容

以下内容会被脚本视为无效或高风险信号：

- 空字段
- `TBD`
- `<path>`
- `<path>|none`
- `<selectors or paths>`
- `yes/no`
- 其他仍保留在模板状态、不能形成证据的占位值

## 9. 使用方式

- 需要本地记录审阅结论时，可基于 `docs/reviews/TEMPLATE.md` 新建草稿。
- 命中 `src/**/*.sol`、`script/**/*.sol` 变更且准备运行本地或 CI `quality:gate` 时，必须先准备好一份可通过校验的 review note。
- 仅检查草稿结构可运行：`bash ./script/process/check-review-note.sh <review-note>`
- 需要在 Solidity gate 中联动检查时，可运行：`bash ./script/process/check-solidity-review-note.sh`
- 若未显式设置 `QUALITY_GATE_REVIEW_NOTE`，Solidity gate 只会自动选择一份 `Files reviewed` 能唯一覆盖当前变更 production Solidity path set 的 review note；若存在歧义或没有匹配，必须显式指定。
- 若仓库跟踪了特定 review note 文件（例如 `docs/reviews/CI_REVIEW_NOTE.md`），它也必须与当前改动、当前 gate 语义保持一致。
