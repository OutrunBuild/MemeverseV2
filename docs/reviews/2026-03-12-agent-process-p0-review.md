# 2026-03-12-agent-process-p0-review

## Scope
- Change summary: Harden repository process rules by tracking AGENTS.md, adding tracked process docs, and enforcing structured review-note validation in the quality gate.
- Files reviewed: .gitignore, AGENTS.md, docs/process/README.md, docs/process/change-matrix.md, docs/process/review-notes.md, docs/reviews/README.md, docs/reviews/TEMPLATE.md, script/check-review-note.sh, script/quality-gate.sh.

## Impact
- Behavior change: yes
- ABI change: no
- Storage layout change: no
- Config change: yes

## Findings
- High findings: none.
- Medium findings: none.
- Low findings: The P0 gate still relies on explicit review-note declarations and does not yet lint NatSpec or validate PR-side metadata.
- None: none.

## Simplification
- Candidate simplifications considered: Keep all process guidance inside AGENTS.md and preserve heading-only review-note validation.
- Applied: Moved detailed process rules into tracked docs/process files and centralized review-note validation in a dedicated shell script.
- Rejected (with reason): Adding a heavier parser for markdown because stable line-oriented fields are sufficient for the P0 contract.

## Docs
- Docs updated: AGENTS.md, docs/process/README.md, docs/process/change-matrix.md, docs/process/review-notes.md, docs/reviews/README.md, docs/reviews/TEMPLATE.md
- Why these docs: The repository process contract and its supporting references changed together and must stay aligned with the new gate behavior.
- No-doc reason: none.

## Tests
- Tests updated: none
- Existing tests exercised: bash -n script/check-review-note.sh script/quality-gate.sh .githooks/pre-commit; bash ./script/check-review-note.sh docs/reviews/TEMPLATE.md; QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST=<tmp> bash ./script/quality-gate.sh; npm run quality:gate
- No-test-change reason: This change modifies workflow enforcement rather than contract logic.

## Verification
- Commands run: bash -n script/check-review-note.sh script/quality-gate.sh .githooks/pre-commit; bash ./script/check-review-note.sh docs/reviews/TEMPLATE.md; QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST=<tmp> bash ./script/quality-gate.sh; npm run quality:gate
- Results: shell syntax checks passed; the template file failed validation as intended; simulated quality-gate scenarios covered pass and fail branches; the staged real change set passed npm run quality:gate.

## Decision
- Ready to commit: yes
- Residual risks: NatSpec lint and PR-side enforcement remain outside the P0 scope.
