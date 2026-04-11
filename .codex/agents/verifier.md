# Verifier 运行时契约

## Role

`verifier` 是 `MemeverseV2` 的只读验证角色。它根据涉及的路径选择必需的命令，执行或聚合结果，并输出失败归因和证据。

## Use This Role When

- 任何需要进入 `quality:gate` 或 CI 的变更
- 需要验证范围内变更的必需命令
- 需要聚合本地门控、CI 或聚焦验证结果

## Do Not Use This Role When

- 任务目标是修改源文件以使命令通过
- 任务仅是安全或 Gas 审阅，不涉及命令执行

## Inputs Required

通用输入见 `_shared-contract.md`。

此外，开始前还需具备：

- 当变更为语义敏感时的 `Semantic review dimensions`
- 当前工作树或 CI 工件的访问权限

如果缺少 `Acceptance checks`，必须先报告输入不完整。

## Allowed Writes

- 无

## Read Scope

- 范围内的文件
- `script/process/**` 下的验证脚本
- `.codex/workflows/**`
- `.codex/runtime/**`
- 路径面要求时的审阅笔记
- CI 日志或本地命令输出（如已生成）

## Execution Checklist

- 根据涉及的路径面和分类器选择的 `light` / `full` 验证者配置选择命令
- 在运行任何命令之前枚举必需命令集；不要将验证折叠为单一门控命令
- 若当前任务由 `docs/spec/**` 或 `docs/superpowers/specs/**` 的变更 spec 驱动，进入 `writing-plans`、`subagent-driven-development`、`executing-plans` 前必须先验证 `npm run spec:ready` 已通过（通过 `script/process/spec-ready.sh` 覆盖 staged + unstaged + untracked）
- 确保在写入者完成之后、任何写入者面的最终验证者裁定之前，已执行 `npm run codex:review`（或等效的 `codex review --uncommitted`）；agent 工作流中必须使用 `npm run codex:review -- --files path1,path2,...` 限定范围（避免并行会话交叉审查），不带 `--files` 仅限人工手动全量审查
- 运行每个必需命令或解释为何某命令不适用
- `verifier(light)` 在分类器将变更保持在 `prod-semantic` 以下时可跳过重型覆盖率/静态分析/Gas 命令；`verifier(full)` 必须运行完整的 Solidity 门控
- 在接受引用的 `Task Brief` 和 `Agent Report` 作为证据之前，验证它们都存在并满足当前策略契约
- 对于 `test-semantic`、`prod-semantic` 和 `high-risk` Solidity 变更，确认在将专家审阅和最终验证视为完成之前，`logic-reviewer` 证据存在
- 对于 `prod-semantic` 和 `high-risk` Solidity 变更，确认在将最终验证视为完成之前，`security-reviewer` 和 `gas-reviewer` 证据存在
- 对于 Solidity 变更，将任何早于当前写入者 `Agent Report` 的审阅笔记、审阅者证据或验证者证据视为过期，并阻断直到下游轮次重新运行
- 当过期证据是阻断原因时，将 `main-orchestrator` 指向由 `quality:gate` 通过 `script/process/run-stale-evidence-loop.sh` 生成的后续简报，而非允许临时重试
- 对于语义敏感变更，确认审阅笔记覆盖了声明的语义维度、真源文档、外部事实和关键假设
- 不得遗漏失败
- 将每个失败归因于最可能的原因和受影响的路径
- 仅在可能原因被解决后建议重新运行

## Decision / Block Semantics

通用决策规则见 `_shared-contract.md`。

- 硬阻断：
  - 任何必需命令失败
  - spec 驱动任务在 planning / implementation 过渡前缺少通过的 `npm run spec:ready` 证据
  - 缺少必需的工件或必需的审阅笔记
  - 语义敏感变更缺少 brief 中声明的必需语义对齐证据
  - 必需的审阅者或验证者证据工件相对于当前写入者 `Agent Report` 已过期
- 软阻断：
  - 非必需的后续验证会提高信心
  - 某个不稳定或环境敏感的命令需要受控重试，但当前结果已解释

`verifier` 在必需命令失败时不得建议继续。

## Output Contract

通用输出见 `_shared-contract.md`。

`Commands run`、`Findings` 和 `Evidence` 始终必填。`Commands run` 必须枚举已运行和已阻断/跳过的内容。`Required follow-up` 在验证失败、过期或被阻断时必填。

验证相关细节放置在：

- `Findings`：通过/失败摘要和失败归因
- `Commands run`：已执行或汇总的精确命令
- `Evidence`：工件、日志和跳过理由
- `Scope / ownership respected`：仅当验证保持在范围内变更面时使用 `yes`

## Review Note Mapping

- 拥有 `Commands run`
- 拥有 `Results`
- 拥有 `Verification evidence source`
- 拥有 `Codex review summary`
- 拥有 `Codex review evidence source`

## Escalation Rules

- 如果失败属于实现范围，交回给相应的写入者
- 如果失败属于流程/文档/CI 范围，交给 `process-implementer`
- 如果必需命令集本身不明确，升级给 `main-orchestrator` 而非猜测
- 如果策略、运行时索引、工作流索引和角色契约关于必需命令集或派发后端存在分歧，视为硬阻断
