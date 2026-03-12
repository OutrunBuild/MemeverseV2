# 2026-03-12-p2-policy-and-rule-map-review

## Scope
- Change summary: Centralize process rules into machine-readable policy files and enforce an initial rule-to-test mapping for swap module changes.
- Files reviewed: AGENTS.md, docs/process/README.md, docs/process/change-matrix.md, docs/process/review-notes.md, docs/process/policy.json, docs/process/rule-map.json, script/read-process-config.js, script/check-review-note.sh, script/check-pr-body.sh, script/check-rule-map.sh, script/quality-gate.sh, script/test-process-policy.sh, script/test-rule-map-gate.sh.

## Impact
- Behavior change: yes
- ABI change: no
- Storage layout change: no
- Config change: yes

## Findings
- High findings: none.
- Medium findings: none.
- Low findings: The first rule-map layer is intentionally narrow and currently covers only `src/swap/**`.
- None: none.

## Simplification
- Candidate simplifications considered: Keep shell arrays duplicated across scripts and enforce rule-to-test mapping manually in review notes without machine-readable config.
- Applied: Added `policy.json` and `rule-map.json` as tracked process sources and reused them across the shell validators.
- Rejected (with reason): Replacing the whole shell gate with a larger framework because the repository only needed centralized configuration, not a second execution system.

## Docs
- Docs updated: AGENTS.md, docs/process/README.md, docs/process/change-matrix.md, docs/process/review-notes.md
- Why these docs: The repository process contract now has machine-readable policy sources and a rule-to-test mapping layer that must be reflected in operator-facing docs.
- No-doc reason: none.

## Tests
- Tests updated: script/test-process-policy.sh, script/test-rule-map-gate.sh
- Existing tests exercised: bash ./script/test-process-policy.sh; bash ./script/test-rule-map-gate.sh; npm run quality:gate
- No-test-change reason: none.

## Verification
- Commands run: bash ./script/test-process-policy.sh; bash ./script/test-rule-map-gate.sh; bash -n script/check-review-note.sh script/check-pr-body.sh script/check-rule-map.sh script/quality-gate.sh script/test-process-policy.sh script/test-rule-map-gate.sh .githooks/pre-commit; npm run quality:gate
- Results: Policy self-test confirms review-note and PR validators read overridden policy data; rule-map self-test confirms swap changes fail without mapped test evidence and pass with it; shell syntax checks pass; the staged P2 change set passes the local quality gate.

## Decision
- Ready to commit: yes
- Residual risks: The rule-map currently covers only a small set of high-value modules, so broader repository coverage still needs incremental follow-up.
