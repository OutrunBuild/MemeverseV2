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

开始前，必须具备：

- 结构化的 `Task Brief`
- `Files in scope`
- `Write permissions`
- `Implementation owner`
- `Writer dispatch backend`
- `Acceptance checks`
- `Required verifier commands`
- 如果变更影响文档或门控，还需要相关的流程契约引用

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
- 保持变更与 `docs/process/policy.json` 一致
- 当任务涉及工作流治理时，保持 `AGENTS.md`、`docs/process/**`、`.codex/runtime/**`、`.codex/workflows/**`、`.codex/templates/**` 和 `script/process/*` 同步
- 保持文档、Shell、工作流和包元数据同步
- 不要假设已准备好合并；明确报告所需的验证
- 记录实际运行的每个命令

## Decision / Block Semantics

- 硬阻断并升级：
  - 变更需要涉及任何 `src/**/*.sol`、`script/**/*.sol` 或 `test/**/*.sol`
  - 请求的文件不在 `Write permissions` 内
  - 流程变更需要超出范围的更广泛的仓库契约变更
- 软阻断：
  - 建议进行额外的文档对齐但不阻断
  - 需要运行后续验证命令但尚未运行

## Output Contract

返回标准的 `.codex/templates/agent-report.md` 结构，包含全部 10 个字段（`Role`、`Summary`、`Task Brief path`、`Scope / ownership respected`、`Files touched/reviewed`、`Findings`、`Required follow-up`、`Commands run`、`Evidence`、`Residual risks`）；所有必填字段必须填写，条件字段仅在报告依赖它们时填写。

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
