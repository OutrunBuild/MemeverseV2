# 2026-03-12-hardhat-removal-review

## Scope
- Change summary: Remove the repository root Hardhat integration so compile and test entrypoints are Foundry-only.
- Files reviewed: package.json, AGENTS.md, docs/process/change-matrix.md, docs/reviews/2026-03-12-agent-process-p0-review.md.

## Impact
- Behavior change: yes
- ABI change: no
- Storage layout change: no
- Config change: yes

## Findings
- High findings: none.
- Medium findings: none.
- Low findings: README still mentions Hardhat only as generic ecosystem comparison text; it is no longer part of the active root workflow.
- None: none.

## Simplification
- Candidate simplifications considered: Leave dormant Hardhat scripts and config in place and merely stop documenting them.
- Applied: Removed the root Hardhat entrypoints, config, and TypeScript support entirely.
- Rejected (with reason): Editing vendor files under lib/** because that would couple repository workflow cleanup to upstream dependency maintenance.

## Docs
- Docs updated: docs/process/change-matrix.md, docs/reviews/2026-03-12-agent-process-p0-review.md
- Why these docs: The process contract and its recorded residual risks must match the new Foundry-only root toolchain.
- No-doc reason: none.

## Tests
- Tests updated: none
- Existing tests exercised: npm run compile; npm run test; npm run quality:gate; rg -n "compile:hardhat|test:hardhat|hardhat" . --glob '!lib/**' --glob '!node_modules/**'
- No-test-change reason: This change removes repository tooling integration rather than contract logic.

## Verification
- Commands run: npm run compile; npm run test; npm run quality:gate; rg -n "compile:hardhat|test:hardhat|hardhat" . --glob '!lib/**' --glob '!node_modules/**'
- Results: Root compile and test entrypoints run through Forge only; quality gate passes for the staged change set; remaining root-owned Hardhat references are limited to intentional non-operational text.

## Decision
- Ready to commit: yes
- Residual risks: If the repository later needs a second EVM toolchain, it should be reintroduced explicitly with matching scripts, docs, and gate rules instead of reviving ad hoc local Hardhat usage.
