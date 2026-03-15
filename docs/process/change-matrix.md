# 变更触发矩阵

本矩阵描述“改哪些路径，必须补什么证据，必须跑什么命令”。

## `src/**/*.sol`

必须满足：

- `forge fmt --check`
- `bash ./script/process/check-natspec.sh`
- `forge build`
- `forge test -vvv`
- 代码编写完成后先执行 `Code Simplifier`
- 然后执行 `Solidity Security`，并在该步骤内同时完成安全检查与 Gas 优化审查
- 命中该路径时，agent/workflow 优先调用 `skills/solidity-post-coding-flow/SKILL.md` 串行执行上述后编码流程
- 一旦实现已完成并进入 review、收尾、准备 `git add` / commit，或准备运行 `npm run quality:gate`，必须把 `skills/solidity-post-coding-flow/SKILL.md` 视为必选步骤；如果此前已执行过，但之后又继续修改任意 `src/**/*.sol`，则必须基于最新 diff 重新执行
- `bash ./script/process/check-slither.sh`
- `bash ./script/process/check-gas-report.sh`
- `quality:gate` 在本地与 CI 下都会执行 `bash ./script/process/check-solidity-review-note.sh`
- `npm run docs:check`

## `src/**/*.sol` 关键场景测试映射

如果命中 `docs/process/rule-map.json` 中的正式规则：

- 当前阶段同时校验该规则的 `change_requirement`
- `check-solidity-review-note.sh` 会在本地与 CI 下基于同一批命中规则校验 `evidence_requirement`
- `change_requirement.mode = any` 表示变更集中必须至少包含 1 个映射测试文件
- `change_requirement.mode = all` 表示变更集中必须包含全部映射测试文件
- `change_requirement.mode = none` 表示当前 gate 不要求同时修改测试文件
- `evidence_requirement.mode = any` 表示 review note 的 `Existing tests exercised` 必须至少引用 1 个映射测试
- `evidence_requirement.mode = all` 表示 review note 的 `Existing tests exercised` 必须覆盖全部映射测试
- `evidence_requirement.mode = none` 表示 review note 不要求额外引用映射测试
- `testing_gaps` 只用于记录测试治理缺口，不参与 gate 失败

## `test/**/*.t.sol`

必须满足：

- `forge fmt --check`
- `forge build`
- `forge test -vvv`

## `script/**/*.sh` 或 `.githooks/*`

必须满足：

- `bash -n`

## Pull Request

必须满足：

- PR body 包含：
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

- 当前根仓库工具链为 Foundry-only。
- 变更触发和 PR sections 的机器可读真源是 `docs/process/policy.json`。
- 关键行为场景到测试证据映射的机器可读真源是 `docs/process/rule-map.json`。
- 仓库提供 `.github/pull_request_template.md` 作为标准 PR 模板，但当前机械校验的是 section 标题是否存在。
- 如果以后新增 gate，优先更新 `docs/process/policy.json` 或 `docs/process/rule-map.json`，再同步人类可读文档与脚本。
