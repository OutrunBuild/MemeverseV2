# 变更触发矩阵

本矩阵描述“改哪些路径，默认触发哪些角色，必须补什么证据，必须跑什么命令”。主会话角色与阶段模型以 `AGENTS.md`、`.codex/agents/*`、`docs/process/subagent-workflow.md` 为准。

## 快速反馈命令

- `npm run quality:quick` 只用于本地高频反馈，不是 finish gate
- `npm run quality:quick` 不能替代 `npm run quality:gate`
- `npm run quality:quick` 对 Solidity 变更只做轻量检查与定向测试，不执行 `slither`、gas report、review note 校验、`docs:check`、全量 `forge test -vvv`

## `src/**/*.sol`

默认角色：

- `solidity-implementer`
- `security-reviewer`
- `gas-reviewer`
- `verifier`

按需角色：

- `solidity-explorer`
- `security-test-writer`

必须满足：

- `forge fmt --check`
- `bash ./script/process/check-natspec.sh`
- `forge build`
- `forge test -vvv`
- `bash ./script/process/check-slither.sh`
- `bash ./script/process/check-gas-report.sh`
- `bash ./script/process/check-solidity-review-note.sh`
- `npm run docs:check`

流程约束：

- `skills/solidity-post-coding-flow/SKILL.md` 可作为兼容辅助入口，用于组织 Solidity 后编码检查步骤
- Harness 主契约仍以 `AGENTS.md`、`docs/process/subagent-workflow.md`、`docs/process/policy.json` 与 `script/process/*` 为准；若继续修改 `src/**/*.sol`，按这些主契约重新完成对应检查

## `src/**/*.sol` 与 `rule-map.json` 证据映射

`docs/process/rule-map.json` 是 Memeverse 专属流程面真源，用于“源码变更 -> 测试文件 -> review note 证据”映射。命中正式规则时：

- `check-rule-map.sh` 校验 `change_requirement`
- `check-solidity-review-note.sh` 校验 `evidence_requirement`
- `change_requirement.mode = any|all|none` 决定是否要求同时修改映射测试
- `evidence_requirement.mode = any|all|none` 决定 `Existing tests exercised` 的覆盖要求
- `testing_gaps` 仅用于记录测试治理缺口，不直接触发 gate 失败
- 当命中 launcher/router/hook 的 unlock 相关规则时，review note 还应显式填写 `Open safety mismatches assessed`，说明 `SAFE-UNLOCK-01` 是仍然开放还是已被本次改动关闭

## `test/**/*.sol`

默认角色：

- `solidity-implementer`
- `verifier`

按需角色：

- `security-reviewer`
- `gas-reviewer`

必须满足：

- `forge fmt --check`
- `forge build`
- `forge test -vvv`

## `script/**/*.sh` 或 `.githooks/*`

默认角色：

- `process-implementer`
- `verifier`

必须满足：

- `bash -n`

## `package.json` 或 `package-lock.json`

默认角色：

- `process-implementer`
- `verifier`

必须满足：

- `npm ci`
- `npm run docs:check`

## Harness / Process 表面

命中 `AGENTS.md`、`README.md`、`docs/process/**`、`docs/reviews/TEMPLATE.md`、`docs/reviews/README.md`、`.github/pull_request_template.md`、`.codex/**` 时：

- 默认写入角色：`process-implementer`
- 默认验证角色：`verifier`
- 评审顺序遵循 Harness 契约：`main-orchestrator` -> `verifier`
- 至少执行：`npm run docs:check`

## Pull Request

PR body 必须包含：

- `## Summary`
- `## Impact`
- `## Docs`
- `## Tests`
- `## Verification`
- `## Risks`
- `## Security`
- `## Simplification`
- `## Gas`

## 说明

- 变更触发、review note 字段和 PR sections 的机器可读真源是 `docs/process/policy.json`
- `rule-map.json` 是 Memeverse 特有的机器可读规则映射，不被 UniversalVault 通用骨架替代
- 若新增 gate 语义，先更新 `policy.json` / `rule-map.json`，再同步人类文档与脚本
