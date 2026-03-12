# Review Notes

本目录存放 `src/**/*.sol` 变更必须附带的 review note。

Rules:
- staged files 包含 `src/**/*.sol` 时，至少同时提交 1 个 `docs/reviews/*.md`
- 基于 `docs/reviews/TEMPLATE.md` 填写
- 正文默认使用简体中文
- 为兼容现有 gate，固定 section / field key 与 `yes`、`no` 取值保持英文
- findings 需要写具体影响，至少能定位到文件、函数或命令
- `Impact`、`Docs`、`Tests`、`Verification`、`Decision` 中的固定字段都必须填真实值
- 不要保留 `TBD`、`<path>`、`<selectors or paths>`、`yes/no` 等模板占位
- verification 必须记录同一工作树状态下实际执行过的命令和结果
