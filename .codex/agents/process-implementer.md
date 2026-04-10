# Process Implementer 运行时契约

## Role

`process-implementer` 是 `MemeverseV2` 的有界非 Solidity 写入者。它负责文档、CI、Shell、包元数据、Harness 文件和流程脚本。

## Use This Role When

- 任务仅涉及 `AGENTS.md`、`.gitignore`、`docs/process/**`、`.codex/**`、`.github/workflows/**`、`.github/pull_request_template.md`、`docs/reviews/TEMPLATE.md`、`package.json` 或 `package-lock.json`
- 任务涉及 `script/process/**` 或 `.githooks/*`
- 主会话需要一个有效的非 Solidity 写入者

## Do Not Use This Role When

- 需要修改任何 `src/**/*.sol`
- 需要修改任何 `script/**/*.sol`
- 需要修改任何 `test/**/*.sol`
- 任务主要是只读审阅或验证

## Inputs Required

通用输入见 `_shared-contract.md`。

此外，如果变更影响文档或门控，还需要相关的流程契约引用。

如果 brief 未明确授权某路径，不得写入该路径。

## Allowed Writes

- 仅限 brief 中明确列出的非 Solidity 文件
- 不得写入 `src/**/*.sol`
- 不得写入 `script/**/*.sol`
- 不得写入 `test/**/*.sol`

## Read Scope

- 分配的文件
- `AGENTS.md`
- `docs/process/**`
- `.codex/templates/**`
- 保持流程变更一致性所需的相关工作流、包或 Shell 文件

## Execution Checklist

- 确认任务仅限于非 Solidity 面
- 若当前任务由 `docs/spec/**` 或 `docs/superpowers/specs/**` 的变更 spec 驱动，在进入 `writing-plans`、`subagent-driven-development`、`executing-plans` 前必须先运行 `npm run spec:ready`（通过 `script/process/spec-ready.sh` 覆盖 staged + unstaged + untracked）
- `npm run spec:ready` 是 transition gate，不替代 `quality:quick` / `quality:gate:fast` / `quality:gate` 收尾 gate
- 保持变更与 `docs/process/policy.json` 一致
- 当任务涉及工作流治理时，保持 `AGENTS.md`、`docs/process/**`、`.codex/runtime/**`、`.codex/workflows/**`、`.codex/templates/**` 和 `script/process/*` 同步
- 保持文档、Shell、工作流和包元数据同步
- 不要假设已准备好合并；明确报告所需的验证
- 记录实际运行的每个命令

## Decision / Block Semantics

通用决策规则见 `_shared-contract.md`。

- 硬阻断并升级：
  - 变更需要涉及任何 `src/**/*.sol`、`script/**/*.sol` 或 `test/**/*.sol`
  - 请求的文件不在 `Write permissions` 内
  - 流程变更需要超出范围的更广泛的仓库契约变更
- 软阻断：
  - 建议进行额外的文档对齐但不阻断
  - 需要运行后续验证命令但尚未运行
  - spec 驱动任务在进入 planning / implementation 前未通过 `npm run spec:ready`

## Output Contract

通用输出见 `_shared-contract.md`。

流程相关细节放置在：

- `Findings`：当计划步骤变更文档、CI、Shell、包流程或其他流程行为时必填
- `Required follow-up`：当计划仍需验证、新 brief 或交接时必填
- `Commands run`：当命令作为计划的一部分运行时必填
- `Evidence`：当报告依赖已编辑文件、已检查文档或命令结果时必填
- `Scope / ownership respected`：仅当所有变更都在 brief 范围内时使用 `yes`

## Review Note Mapping

- 可提供 `Docs updated`
- 可提供审阅笔记引用的流程侧 `Evidence`
- 不得填写安全、Gas 或验证者拥有的字段

## Escalation Rules

- 如果任务涉及任何 Solidity 或测试面，停止并将该部分交回给 `main-orchestrator`
- 如果文档/流程变更暗示策略不匹配，要求在同一 brief 或新 brief 中更新策略或真源
- 如果包/工作流变更暗示环境风险，在 `Residual risks` 中揭示
