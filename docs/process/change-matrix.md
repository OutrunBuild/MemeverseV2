# 变更触发矩阵

本矩阵描述“改哪些路径，默认触发哪些角色，必须补什么证据，必须跑什么命令”。主会话角色与阶段模型以 `AGENTS.md`、`.codex/agents/*`、`docs/process/subagent-workflow.md` 为准。

## 快速反馈命令

- `npm run quality:quick` 只用于本地高频反馈，不是 finish gate
- `npm run quality:quick` 不能替代 `npm run quality:gate`
- `npm run quality:quick` 会先执行全量 `npm run lint:sol`，再对 Solidity 变更做轻量检查与定向测试；不执行 `slither`、gas report、review note 校验、`docs:check`、全量 `forge test -vvv`

## Solidity Lint 策略

- `npm run lint:sol` 由 `solhint.config.js`（`src/**/*.sol`）与 `solhint-test.config.js`（`test/**/*.sol`）组成；`quality:quick` 与 `quality:gate` 都会先执行它。
- `src/**/*.sol` 当前已启用并要求全仓阻塞通过的规则，优先覆盖低噪音且有明确收益的项：`state-visibility`、`const-name-snakecase`、`interface-starts-with-i`、`compiler-version`、`func-visibility`（`ignoreConstructors: true`）、`gas-custom-errors`、`gas-multitoken1155`，以及 `avoid-low-level-calls`、`check-send-result`、`multiple-sends`。
- `avoid-low-level-calls`、`check-send-result`、`multiple-sends` 在 `src/**/*.sol` 中允许基于协议语义或兼容性需求做局部 `solhint-disable-next-line` 豁免；新增豁免时应在代码旁直接说明原因。
- `gas-custom-errors` 在 `src/**/*.sol` 中默认开启；如果某些字符串 revert 需要保持外部兼容语义，应就地写局部豁免并说明原因，而不是全局关闭。
- `test/**/*.sol` 采用 Foundry 兼容口径，额外关闭 `no-console`、`one-contract-per-file`、`avoid-low-level-calls`、`check-send-result`、`multiple-sends`、`gas-custom-errors`，避免测试辅助代码和多合约测试文件成为默认噪音。
- 当前仍全局关闭的规则主要是三类：命名/风格遗留（如 `var-name-mixedcase`、`func-name-mixedcase`）、Foundry 或仓库模式兼容项（如 `no-empty-blocks`、`no-inline-assembly`、`import-path-check`、`max-states-count`）、以及暂未纳入门禁的其余 gas / NatSpec 项（如 `gas-indexed-events`、`gas-small-strings`、`use-natspec`）。
- 若继续收紧 `solhint`，默认原则是先收 `src/**/*.sol`、先挑低命中低噪音规则、先修真实问题再上 gate，不一次性把历史命名或测试习惯全部拉入阻塞面。

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

- `npm run lint:sol`
- `forge fmt --check`
- `bash ./script/process/check-natspec.sh <changed-src-solidity-files>`
- `forge build`
- `forge test -vvv`
- `bash ./script/process/check-slither.sh`
- `bash ./script/process/check-gas-report.sh`
- `bash ./script/process/check-solidity-review-note.sh`
- `npm run docs:check`

流程约束：

- `skills/solidity-post-coding-flow/SKILL.md` 可作为兼容辅助入口，用于组织 Solidity 后编码检查步骤
- Harness 主契约仍以 `AGENTS.md`、`docs/process/subagent-workflow.md`、`docs/process/policy.json` 与 `script/process/*` 为准；若继续修改 `src/**/*.sol`，按这些主契约重新完成对应检查
- 复杂分支、状态迁移、资金/权限判断、关键外部调用、非直观数学等实现必须补充适当的方法内注释，说明意图、前置条件或安全假设；禁止噪音式逐行注释
- 测试不得只停留在 happy path 或最小回归；至少覆盖 unit tests，并按风险补充 fuzz / invariant / adversarial / integration tests，使变更路径保持足够高覆盖率；未覆盖部分需在交付证据中说明
- 对外部依赖、用户资金流、权限边界、registration / settlement / liquidity / yield / omnichain 语义敏感改动，`Task Brief` 必须写明 `Semantic review dimensions`、`Source-of-truth docs`、`External sources required` 与 `Critical assumptions to prove or reject`
- review note 必须补齐 `Semantic dimensions reviewed`、`Source-of-truth docs checked`、`External facts checked`、`Local control-flow facts checked`、`Evidence chain complete`、`Semantic alignment summary`
- confirmed finding 必须同时具备本地前提证据与必要的外部主来源证据；缺少任一项时只能维持为假设、待验证项或测试缺口

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

- `npm run lint:sol`
- `forge fmt --check`
- `forge build`
- `forge test -vvv`

流程约束：

- 测试至少覆盖正常路径、边界条件和失败路径，不能只验证单一主流程
- 涉及状态机、权限、资金流、跨链、价格/数学等高风险面时，应补 fuzz / invariant / adversarial 等测试，并尽量提高相关变更面的覆盖率

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
- `quality:gate` 已接入 coverage gate：默认对命中 `src/**/*.sol` 改动的目录执行 `line / function / branch` 三指标硬门禁，阈值与分层规则由 `docs/process/policy.json -> quality_gate.coverage` 控制
- `quality:quick` 使用轻量 coverage：仅对命中目录校验 `line / function`（默认不校验 `branch`），指标集合由 `quality_gate.coverage.quick_metrics` 控制
- 若新增 gate 语义，先更新 `policy.json` / `rule-map.json`，再同步人类文档与脚本
