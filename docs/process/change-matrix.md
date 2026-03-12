# 变更触发矩阵

本矩阵描述“改哪些路径，必须补什么证据，必须跑什么命令”。

## `src/**/*.sol`

必须满足：

- `forge fmt --check`
- `bash ./script/process/check-natspec.sh`
- `forge build`
- `forge test -vvv`
- `npm run docs:check`

## `src/swap/**/*.sol`

如果命中 `docs/process/rule-map.json` 中的模块规则，则必须同时修改至少 1 个匹配的测试文件。

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

## 说明

- 当前根仓库工具链为 Foundry-only。
- 变更触发和 PR sections 的机器可读真源是 `docs/process/policy.json`。
- 关键模块测试证据映射的机器可读真源是 `docs/process/rule-map.json`。
- 仓库提供 `.github/pull_request_template.md` 作为标准 PR 模板，但当前机械校验的是 section 标题是否存在。
- 如果以后新增 gate，优先更新 `docs/process/policy.json` 或 `docs/process/rule-map.json`，再同步人类可读文档与脚本。
