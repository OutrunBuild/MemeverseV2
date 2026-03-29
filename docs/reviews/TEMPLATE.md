# Review Note Template

> 本模板用于本地可选的 review 草稿。
> review note 正文默认使用简体中文。
> 为兼容 gate，请保留下列英文 section / field key，并只填写冒号后的内容。
> 所有 `* evidence source` 字段采用 `role: source` 形式。

## Scope
- Change summary:
- Files reviewed:
- Task Brief path:
- Agent Report path:
- Implementation owner:
- Writer dispatch confirmed: yes/no
- Semantic dimensions reviewed:
- Source-of-truth docs checked:
- External facts checked:
- Local control-flow facts checked:
- Evidence chain complete: yes/no
- Semantic alignment summary:

## Impact
- Behavior change: yes/no
- ABI change: yes/no
- Storage layout change: yes/no
- Config change: yes/no

## Findings
- High findings:
- Medium findings:
- Low findings:
- None: none
- Security review summary:
- Security residual risks:
- Security evidence source:

## Simplification
- Simplification:
- Follow-up simplifications:
- Gas-sensitive paths reviewed:
- Gas changes applied:
- Gas snapshot/result:
- Gas residual risks:
- Gas evidence source:

## Docs
- Docs updated:
- No-doc reason:

## Tests
> 在这里写明本次覆盖的 test type（如 unit、fuzz、invariant、integration、upgrade、adversarial）与关键风险边界；如果没有补测，要说明为什么现有覆盖已足够。
- Tests updated:
- Existing tests exercised:
- No-test-change reason:

## Verification
> 在这里写明实际运行过的命令、结果，以及是否达到当前仓库 finish gate。
- Commands run:
- Results:
- Verification evidence source:

## Decision
- Ready to commit: yes/no
- Residual risks:
- Decision evidence source:

## Repo-specific Extensions
> 仅当 `docs/process/policy.json`、`docs/process/rule-map.json` 或相关 gate 脚本要求时填写。
- Open safety mismatches assessed:
- Rule-map evidence source:
