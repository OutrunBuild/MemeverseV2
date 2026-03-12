# Review Note 规范

`docs/reviews/*.md` 现在是本地可选的 review 草稿，不再是提交 gate。

## 语言约束

- review note 正文默认使用简体中文
- 如果使用 `script/process/check-review-note.sh` 做本地自检，固定 section / field key 保持英文
- `Behavior change`、`ABI change`、`Storage layout change`、`Config change`、`Ready to commit` 的值仍然只能填写 `yes` 或 `no`
- 路径、命令、代码标识、selector 保持英文原文

## 必填目标

每份 review note 都必须让脚本能够回答这几个问题：

1. 这次改了什么，审了哪些文件？
2. 是否改变了行为、ABI、存储布局或配置？
3. 更新了哪些文档和测试？
4. 运行了哪些命令，结果是什么？
5. 当前是否允许提交？剩余风险是什么？

`Findings` 和 `Simplification` 仍然保留在模板中，作为建议补充的审计上下文，但当前 gate 不会逐项校验它们的子字段。

PR template 会复用同一套 `Impact / Docs / Tests / Verification / Risks` 语言；review note 只作为本地辅助材料，不再参与 `quality:gate`。

固定字段与占位值的机器可读定义见 `docs/process/policy.json`。

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

门禁必填字段：

- `Behavior change: yes/no`
- `ABI change: yes/no`
- `Storage layout change: yes/no`
- `Config change: yes/no`
- `Change summary: ...`
- `Files reviewed: ...`
- `Docs updated: <path>|none`
- `Tests updated: <path>|none`
- `Existing tests exercised: ...`
- `Commands run: ...`
- `Results: ...`
- `Ready to commit: yes/no`
- `Residual risks: ...`

建议补充字段：

- `High findings: ...`
- `Medium findings: ...`
- `Low findings: ...`
- `None: none`
- `Candidate simplifications considered: ...`
- `Applied: ...`
- `Rejected (with reason): ...`
- `Why these docs: ...`
- `No-doc reason: ...`
- `No-test-change reason: ...`

## 禁止内容

以下内容会被脚本视为无效：

- 空字段
- `TBD`
- `<path>`
- `<selectors or paths>`
- `yes/no`
- 模板占位没有替换

## 使用方式

- 需要本地记录审阅结论时，可基于 `docs/reviews/TEMPLATE.md` 新建草稿
- 需要检查草稿格式时，可手动运行 `bash ./script/process/check-review-note.sh <review-note>`
- 是否保留、分享或转移到其他协作系统，由团队自行决定
