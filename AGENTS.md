# Agent Operating Contract

本文件只保留高杠杆、可机械验证的规则。解释性细节下沉到 `docs/process/`。

## 1. Required Commands
- 初次 clone 后执行：`git submodule update --init --recursive`
- 每个工作副本只需执行一次：`npm run hooks:install`
- 任意准备提交的变更，唯一 finish gate：`npm run quality:gate`
- 不要把单独的 `forge build`、`forge test`、`npm run docs:check` 视为 finish gate 替代品

## 2. Change Matrix
- `src/**/*.sol`
  - 必须提交至少 1 个 `docs/reviews/*.md`
  - 必须通过 Solidity gate：`forge fmt --check`、`forge build`、`forge test -vvv`
  - 必须通过 NatSpec gate：`bash ./script/check-natspec.sh`
  - 必须通过 docs gate：`npm run docs:check`
  - review note 中必须声明：
    - `Behavior change: yes/no`
    - `ABI change: yes/no`
    - `Storage layout change: yes/no`
    - `Config change: yes/no`
    - `Docs updated: <path>|none`
    - `Tests updated: <path>|none`
    - `Existing tests exercised: <selectors or paths>`
    - `Ready to commit: yes/no`
  - 如果 `Behavior change: yes`，本次变更必须同时包含至少 1 个非生成文档：
    - 匹配：`docs/**/*.md`
    - 排除：`docs/contracts/**`、`docs/plans/**`、`docs/reviews/**`
- `src/swap/**/*.sol`
  - 如果 `Behavior change: yes`，默认还必须更新 `docs/memeverse-swap/*.md`
- `test/**/*.t.sol`
  - 必须通过：`forge fmt --check`、`forge build`、`forge test -vvv`
- `script/*.sh` 或 `.githooks/*`
  - 必须通过：`bash -n`

## 3. Pull Request Contract
- PR 必须使用 `.github/pull_request_template.md`
- PR body 必须包含以下标题：
  - `## Summary`
  - `## Impact`
  - `## Docs`
  - `## Tests`
  - `## Verification`
  - `## Risks`

## 4. Review Note Contract
- 模板文件：`docs/reviews/TEMPLATE.md`
- `src/**/*.sol` 变更时，review note 必须与代码一起提交
- 以下内容不能为空、不能写 `TBD`、不能保留模板占位：
  - `Change summary`
  - `Files reviewed`
  - `Findings`
  - `Candidate simplifications considered`
  - `Commands run`
  - `Results`
  - `Residual risks`
- 如果没有发现问题，`Findings` 必须明确写 `None`
- `Ready to commit` 只能填写 `yes` 或 `no`

## 5. Generated Docs Policy
- `docs/contracts/` 是生成产物，不手工编辑，不提交到 git
- `npm run docs:check` 的职责是验证生成流程可运行且输出结构符合预期
- `docs/plans/` 仅用于本地规划，不提交到 git
- `docs/reviews/` 是必须提交的审计证据

## 6. Documentation Language
- 新增的人写文档默认使用简体中文
- 命令、路径、代码标识、协议名、库名保持英文原文

## 7. References
- 规则说明：`docs/process/README.md`
- 路径与 gate 细则：`docs/process/change-matrix.md`
- Review note 规范：`docs/process/review-notes.md`
