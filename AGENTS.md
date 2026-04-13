# AGENTS Contract

## Role

- 本文件是 `MemeverseV2` 的仓库级 agent operating contract。
- 它定义 repo-local 行为边界、真源层级、升级边界与完成口径。
- 它不是机器真源；结构化策略与执行结果以 `.harness/policy.json` 和 `script/harness/gate.sh` 为准。

## Control Stack

- Machine policy: `.harness/policy.json`
- Enforcement entrypoint: `script/harness/gate.sh`
- Repo-local agent contract: `AGENTS.md`

适用顺序：

1. 人工明确指令
2. `solidity-subagent-harness`
3. `.harness/policy.json` 的结构化策略
4. `script/harness/gate.sh` 的执行结果
5. `AGENTS.md` 的 repo-local 边界与真源说明
6. 设计稿、计划稿、专题文档

若 `AGENTS.md` 与 machine truth 冲突，以 machine truth 为准；不要用自然语言覆盖 policy 或 gate。

## Handoff Rules

- 新会话必须先读 `AGENTS.md`，再进入 `solidity-subagent-harness`，再读 `.harness/policy.json`；不要先根据 `package.json` 或 `script/harness/gate.sh` 自行脑补 runtime 语义。
- `main-orchestrator` 只能留在主会话，不能作为 subagent 派发。
- `review_roles` 只允许包含 reviewer；不得把 `verifier` 或 `security-test-writer` 塞进 `review_roles`。
- 平台差异只允许存在于 `solidity-subagent-harness` 的 adapter；不得为了适配 Claude Code 或 Codex，在仓库内重新长出平行控制面。

## Agent Rules

- 只要仓库存在 `.harness/policy.json`，主会话就必须使用 `solidity-subagent-harness`，不得自行发明 repo-local harness flow。
- 不得绕开 `gate.sh` 直接给出“完成”“可提交”“已通过”结论。
- 默认优先依赖当前实现和可复验证据，而不是历史流程、历史工件或惯性做法。
- 只能在当前任务 scope 内解释和行动，不得顺手扩大为无关重构、无关流程改造或无关产品修正。
- 遇到工作树中与当前任务无关的现有改动，默认视为外部改动，不得重写、清理、吸收或借机整理，除非任务明确要求。
- 不得建立与 `solidity-subagent-harness`、policy、gate 相冲突的平行控制面。
- 不得为了适配流程、脚本、gate 或验证便利，反向修改产品或安全语义。

## Upgrade Boundaries

以下事项必须升级，不能自行决定：

- 任何改写产品语义、资金语义、权限语义、安全语义或升级语义的决定
- 任何改变系统外部可观察行为的决定
- 任何改变 residual risk 接受标准的决定
- 任何跨越当前任务 scope 的结构性改写

## Execution Contract

- `npm run gate:fast` 是快速阻断入口。
- `npm run gate` 是本地最终放行入口。
- `npm run gate:ci` 与本地 `gate` 同级，不是弱化路径。
- completion claim 必须基于与本次 verdict 对应的最新 gate 输出。

## Repository Truth

产品真源优先看：

- `docs/spec/protocol.md`
- `docs/spec/state-machines.md`
- `docs/spec/accounting.md`
- `docs/spec/access-control.md`
- `docs/spec/upgradeability.md`
- `docs/spec/lifecycle-details.md`
- `docs/spec/registration-details.md`
- `docs/spec/governance-yield-details.md`
- `docs/spec/interoperation-details.md`
- `docs/spec/common-foundations.md`

支撑性真源：

- `docs/ARCHITECTURE.md`
- `docs/GLOSSARY.md`
- `docs/TRACEABILITY.md`
- `docs/VERIFICATION.md`
- `docs/SECURITY_AND_APPROVALS.md`

实现证据面：

- `src/**`
- `test/**`
- `script/**/*.sol`
- `script/deploy.sh`

专题或设计文档只提供背景，不单独定义当前规则：

- `docs/memeverse-swap/*`
- `docs/superpowers/specs/*`
- `docs/superpowers/plans/*`

若文档与实现冲突，以当前实现与可复验测试能证明的行为为准，并把冲突显式升级。

## Repo Focus

本仓库高敏感问题类型：

- lifecycle / stage transition
- 资金分配与 fee routing
- swap / hook 边界
- cross-chain registration / dispatch / interoperation 语义
- initializer / proxy / governance upgrade 正确性
