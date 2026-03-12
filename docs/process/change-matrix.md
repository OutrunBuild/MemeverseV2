# 变更触发矩阵

本矩阵描述“改哪些路径，必须补什么证据，必须跑什么命令”。

## `src/**/*.sol`

必须满足：

- 变更集中至少包含 1 个 `docs/reviews/*.md`
- 所有相关 review note 通过 `script/check-review-note.sh`
- `forge fmt --check`
- `bash ./script/check-natspec.sh`
- `forge build`
- `forge test -vvv`
- `npm run docs:check`

额外联动：

- 如果任一 review note 声明 `Behavior change: yes`
  - 变更集中必须包含至少 1 个非生成文档：
    - 匹配：`docs/**/*.md`
    - 排除：`docs/contracts/**`、`docs/plans/**`、`docs/reviews/**`

## `src/swap/**/*.sol`

如果任一 review note 声明 `Behavior change: yes`，则必须同时更新：

- `docs/memeverse-swap/*.md`

## `test/**/*.t.sol`

必须满足：

- `forge fmt --check`
- `forge build`
- `forge test -vvv`

## `script/*.sh` 或 `.githooks/*`

必须满足：

- `bash -n`

## Pull Request

必须满足：

- 使用 `.github/pull_request_template.md`
- PR body 包含：
  - `## Summary`
  - `## Impact`
  - `## Docs`
  - `## Tests`
  - `## Verification`
  - `## Risks`

## 说明

- 当前根仓库工具链为 Foundry-only。
- P1 已补齐最小 NatSpec lint 和 PR body 结构校验。
- 如果以后新增 gate，优先更新本文件，再更新脚本和 `AGENTS.md`。
