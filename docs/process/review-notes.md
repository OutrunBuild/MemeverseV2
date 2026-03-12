# Review Note 规范

`docs/reviews/*.md` 是 `src/**/*.sol` 变更的强制审计证据。

## 语言约束

- review note 正文默认使用简体中文
- 为兼容 `script/check-review-note.sh`，固定 section / field key 保持英文
- `Behavior change`、`ABI change`、`Storage layout change`、`Config change`、`Ready to commit` 的值仍然只能填写 `yes` 或 `no`
- 路径、命令、代码标识、selector 保持英文原文

## 必填目标

每份 review note 都必须让脚本能够回答这几个问题：

1. 这次改了什么，审了哪些文件？
2. 是否改变了行为、ABI、存储布局或配置？
3. 有没有发现问题？如果没有，要明确写 `none`。
4. 有没有评估过更简单的实现？
5. 更新了哪些文档和测试？
6. 运行了哪些命令，结果是什么？
7. 当前是否允许提交？剩余风险是什么？

PR template 会复用同一套 `Impact / Docs / Tests / Verification / Risks` 语言，但 review note 仍然是本地提交门禁的强约束真源。

## 结构要求

必须包含以下章节：

- `## Scope`
- `## Impact`
- `## Findings`
- `## Simplification`
- `## Docs`
- `## Tests`
- `## Verification`
- `## Decision`

必须包含以下固定字段：

- `Behavior change: yes/no`
- `ABI change: yes/no`
- `Storage layout change: yes/no`
- `Config change: yes/no`
- `Docs updated: <path>|none`
- `Tests updated: <path>|none`
- `Existing tests exercised: ...`
- `Ready to commit: yes/no`

## 禁止内容

以下内容会被脚本视为无效：

- 空字段
- `TBD`
- `<path>`
- `<selectors or paths>`
- `yes/no`
- 模板占位没有替换

## 行为变更联动

如果 `Behavior change: yes`：

- 必须更新至少 1 个非生成文档
- 如果改动位于 `src/swap/**/*.sol`，还必须更新 `docs/memeverse-swap/*.md`

模板见 `docs/reviews/TEMPLATE.md`。
