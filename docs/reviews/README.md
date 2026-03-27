# Review Notes

本目录存放 review note 模板与使用说明。契约真源在 `docs/process/review-notes.md` 与 `docs/process/policy.json`。

Rules:
- 统一基于 `docs/reviews/TEMPLATE.md` 填写
- 正文默认使用简体中文，固定 section / field key 保持英文
- `Behavior change`、`ABI change`、`Storage layout change`、`Config change`、`Ready to commit` 只能填写 `yes` 或 `no`
- 当改动命中 `src/**/*.sol` 且准备运行 `quality:gate` 时，必须提供一份可通过校验的 review note
- `Task Brief path` 必须指向 `docs/task-briefs/` 下的实际 brief
- `Agent Report path` 必须指向 `docs/agent-reports/` 下的实际 report
- `docs/plans/` 只保留设计/计划/阶段草案，不得混放 `Task Brief` 或 `Agent Report`
- `Existing tests exercised` 必须真实记录已执行测试；命中 `rule-map.json` 正式规则时必须满足 `evidence_requirement`
- `Tests updated` / `Existing tests exercised` 由实现角色填写（`solidity-implementer`、`process-implementer`、`security-test-writer`）
- `Open safety mismatches assessed` 必须显式记录是否审阅了当前开放安全缺口；命中 launcher/router/hook/unlock 语义时，不得省略 `SAFE-UNLOCK-01`
- `Security evidence source`、`Gas evidence source`、`Verification evidence source`、`Decision evidence source`、`Rule-map evidence source` 采用 `role: source` 格式
- source 字段 owner 语义以 `policy.json -> review_note.field_owners` 与 `owner_prefixed_source_fields` 为准
- Findings 二选一：有发现时填写 `High/Medium/Low` 且 `None: n/a`；无发现时 `High/Medium/Low: none` 且 `None: none`
- 不要保留 `TBD`、`<path>`、`<path>|none`、`<selectors or paths>`、`<agent-report-path>`、`<verification-source>`、`<decision-source>`、`<rule-id or mapped-tests>`、`yes/no` 等占位
- verification 必须记录同一工作树状态下实际执行过的命令和结果
- 目录默认被 `.gitignore` 忽略；如需共享请显式转移到协作载体或手动取消忽略
- `docs/reviews/CI_REVIEW_NOTE.md` 是 CI 使用的可跟踪 review note，命中 `src/**/*.sol` 的 PR 需确保它与当前改动保持一致
