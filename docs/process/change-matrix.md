# 变更触发矩阵

本矩阵描述“改哪些路径，默认触发哪些角色，必须补什么证据，必须跑什么命令”。详细 gate 逻辑与脚本消费字段以 `docs/process/policy.json` 和 `script/process/*` 为机器可读真源。

## 快速反馈与 finish gate

- `npm run quality:quick` 只用于本地高频快速反馈，不是 finish gate。
- `npm run quality:quick` 不能替代 `npm run quality:gate`。
- `npm run quality:gate` 是唯一 finish gate。
- 如果仓库启用了额外流程真源（例如 `docs/process/rule-map.json`），`quality:quick` / `quality:gate` 的证据要求也要一并满足。

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

- 命中 `src/**/*.sol` 的任务，必须先有 `Task Brief`，且其中明确 `Default writer role` 与 `Write permissions`。
- 主会话必须先派发对应 writer role；writer role 未成功派发时不得继续实现。
- 复杂或非直观方法必须补充适量的方法内注释，重点解释状态迁移、金额计算、权限前提与外部调用意图。
- 测试不能只停留在 happy path；至少覆盖正常路径、失败路径与关键边界，高风险路径补齐适用的 fuzz、invariant、adversarial、integration 或 upgrade tests。
- 命中 `src/**/*.sol` 后，准备 review、收尾、`git add` / commit 或运行 finish gate 前，必须补齐 review note。
- 需要通过当前仓库 `quality:gate` 所要求的全部检查；精确命令与阈值以 `docs/process/policy.json`、`script/process/*` 与 `AGENTS.md` 为准。

额外说明：

- 若仓库启用了 `docs/process/rule-map.json` 之类的 repo-specific 证据映射，则 `Existing tests exercised` 等字段必须满足对应规则。
- 若改动命中外部依赖、权限边界、会计、状态机、升级或资金流，不能跳过 source-of-truth、external facts 与 critical assumptions 收敛。

## `test/**/*.sol`

默认角色：

- `solidity-implementer`
- `verifier`

按需角色：

- `security-reviewer`
- `security-test-writer`

必须满足：

- `test/**/*.sol` helper / support surface 仍属于测试面；只有在 brief 显式授权时，实现型角色才可写入。
- 命中 `test/**/*.sol` 的任务同样必须先有 `Task Brief`，并明确 writer ownership。
- 新增或修改测试时，必须说明本次覆盖了哪些 test type 与哪些风险边界。
- 需要通过当前仓库对测试面要求的基础检查与 coverage 门禁。

## `script/**/*.sh`、`.githooks/*` 或其他流程脚本

默认角色：

- `process-implementer`
- `verifier`

必须满足：

- `bash -n <changed-shell-scripts>`
- `npm run docs:check`
- 如改动影响流程脚本入口或策略解析，按需执行 `npm run process:selftest`

## `package.json`、`package-lock.json`、CI 与工具链入口

默认角色：

- `process-implementer`
- `verifier`

必须满足：

- `npm ci`
- `npm run docs:check`
- 如改动影响流程脚本、自定义 gate 或 subagent runtime 入口，按需执行 `npm run process:selftest`

## Harness / Process 文档与配置

命中以下表面时：

- `AGENTS.md`
- `docs/process/**`
- `docs/reviews/TEMPLATE.md`
- `docs/reviews/README.md`
- `docs/task-briefs/README.md`
- `docs/agent-reports/README.md`
- `docs/SECURITY_AND_APPROVALS.md`
- `.github/pull_request_template.md`
- `.github/workflows/**`
- `.codex/**`

默认角色：

- `process-implementer`
- `verifier`

必须满足：

- `npm run docs:check`

说明：

- 这类改动默认不允许把 product-specific 规则偷偷沉淀进 Harness 文档。
- 如果文档改动同时改变了脚本、CI 或 gate 语义，人类文档、机器真源与脚本必须同批收敛。

## 本地工件目录约束

- `docs/plans/` 只保留 design doc、implementation plan、stage draft、split draft 等规划材料。
- `docs/task-briefs/` 只存放 `Task Brief`。
- `docs/agent-reports/` 只存放 `Agent Report`。
- `docs/reviews/` 默认是本地 review 草稿目录；若仓库跟踪了特定 review note 文件，也必须与当前 gate 语义保持一致。

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

- 变更触发、PR sections、review note 字段 owner 与布尔字段约束，以 `docs/process/policy.json` 为机器可读真源。
- 如果仓库启用了额外流程真源（例如 `docs/process/rule-map.json`），它属于仓库专属扩展，不会被通用 Harness 文案抹平。
