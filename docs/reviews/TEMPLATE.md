# <YYYY-MM-DD>-<topic>-review

> 本模板用于本地可选的 review 草稿。
> review note 正文默认使用简体中文。
> 为兼容 gate，请保留下列英文 section / field key，并只填写冒号后的内容。
> source 字段采用 `role: source` 形式，表达证据来源 owner。

## Scope
- Change summary:
- Files reviewed:
- Task Brief path: docs/task-briefs/<brief>.md
- Agent Report path: docs/agent-reports/<report>.md
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
> 填写规则（二选一）：
> 有发现时填写 `High/Medium/Low`，并把 `None` 填为 `n/a`；无发现时 `High/Medium/Low` 填 `none`，`None` 填 `none`。
- High findings:
- Medium findings:
- Low findings:
- None: none
- Security review summary:
- Security residual risks:
- Open safety mismatches assessed: SAFE-UNLOCK-01: still open|resolved by <tests/changes>
- Security evidence source: security-reviewer: <agent-report-path>

## Simplification
- Candidate simplifications considered:
- Applied:
- Rejected (with reason):

## Gas
- Gas-sensitive paths reviewed:
- Gas changes applied:
- Gas snapshot/result:
- Gas residual risks:
- Gas evidence source: gas-reviewer: <agent-report-path>

## Docs
- Docs updated: <path>|none
- Why these docs:
- No-doc reason:

## Tests
> `Tests updated` / `Existing tests exercised` 由实现角色填写（`solidity-implementer`、`process-implementer`、`security-test-writer`）。
- Tests updated: <path>|none
- Existing tests exercised: <selectors or paths>
- Rule-map evidence source: verifier: <rule-id or mapped-tests>
- No-test-change reason:

## Verification
- Commands run:
- Results:
- Verification evidence source: verifier: <verification-source>

## Decision
- Ready to commit: yes/no
- Residual risks:
- Decision evidence source: main-orchestrator: <decision-source>
