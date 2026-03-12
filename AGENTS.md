# Agent Operating Contract

本文件只保留高杠杆、可机械验证的规则。解释性细节下沉到 `docs/process/`。

## 1. Required Commands
- 初次 clone 后执行：`git submodule update --init --recursive`
- 每个工作副本只需执行一次：`npm run hooks:install`
- 任意准备提交的变更，唯一 finish gate：`npm run quality:gate`
- 不要把单独的 `forge build`、`forge test`、`npm run docs:check` 视为 finish gate 替代品

## 2. Change Matrix
- `src/**/*.sol`
  - 必须通过 Solidity gate：`forge fmt --check`、`forge build`、`forge test -vvv`
  - 必须通过 NatSpec gate：`bash ./script/process/check-natspec.sh`
  - 必须通过 docs gate：`npm run docs:check`
- `src/swap/**/*.sol`
  - 如果命中 `docs/process/rule-map.json` 中的模块规则，变更集中必须同时包含至少 1 个匹配的测试文件
- `test/**/*.t.sol`
  - 必须通过：`forge fmt --check`、`forge build`、`forge test -vvv`
- `script/**/*.sh` 或 `.githooks/*`
  - 必须通过：`bash -n`

## 3. Pull Request Contract
- 仓库提供标准模板：`.github/pull_request_template.md`
- 当前机械校验的是 PR body 必须包含以下标题：
  - `## Summary`
  - `## Impact`
  - `## Docs`
  - `## Tests`
  - `## Verification`
  - `## Risks`

## 4. Review Note Contract
- 模板文件：`docs/reviews/TEMPLATE.md`
- `docs/reviews/*.md` 为本地可选草稿，不再是提交 gate
- 以下固定字段不能为空、不能写 `TBD`、不能保留模板占位：
  - `Change summary`
  - `Files reviewed`
  - `Behavior change`
  - `ABI change`
  - `Storage layout change`
  - `Config change`
  - `Docs updated`
  - `Tests updated`
  - `Existing tests exercised`
  - `Commands run`
  - `Results`
  - `Residual risks`
- `Ready to commit` 只能填写 `yes` 或 `no`
- `Findings`、`Simplification` 及其子字段保留在模板中作为建议补充，但当前 gate 不单独校验其具体内容

## 5. Generated Docs Policy
- `docs/contracts/` 是生成产物，不手工编辑，不提交到 git
- `npm run docs:check` 的职责是验证生成流程可运行且输出结构符合预期
- `docs/plans/` 仅用于本地规划，不提交到 git
- `docs/reviews/` 默认作为本地 review 草稿目录，不提交到 git

## 6. Documentation Language
- 新增的自然语言文档默认使用简体中文
- `docs/reviews/*.md` 如果本地使用，固定 section / field key 与 `yes`、`no` 取值保持英文，其余说明与正文使用简体中文
- 命令、路径、代码标识、协议名、库名保持英文原文

## 7. References
- 规则说明：`docs/process/README.md`
- 路径与 gate 细则：`docs/process/change-matrix.md`
- Review note 规范：`docs/process/review-notes.md`
- 机器可读策略源：`docs/process/policy.json`
- 规则到测试映射：`docs/process/rule-map.json`
