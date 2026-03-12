# Review Notes

本目录存放本地可选的 review note 草稿模板和说明。

Rules:
- 基于 `docs/reviews/TEMPLATE.md` 填写
- 正文默认使用简体中文
- 如果使用 `script/process/check-review-note.sh` 做本地校验，固定 section / field key 与 `yes`、`no` 取值保持英文
- findings 需要写具体影响，至少能定位到文件、函数或命令
- `Impact`、`Docs`、`Tests`、`Verification`、`Decision` 中的固定字段都必须填真实值
- 不要保留 `TBD`、`<path>`、`<selectors or paths>`、`yes/no` 等模板占位
- verification 必须记录同一工作树状态下实际执行过的命令和结果
- 目录默认被 `.gitignore` 忽略；如需共享，请显式转移到其他协作载体或手动取消忽略
