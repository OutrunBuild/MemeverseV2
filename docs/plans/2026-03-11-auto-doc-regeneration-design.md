# Auto Documentation Regeneration Design

**Goal:** Keep generated contract docs synchronized with Solidity NatSpec while isolating generated output from hand-written plans.

## Problem

The repository guidance described a `pre-commit`-driven docs refresh workflow, but the repository did not implement it. Root `.gitignore` ignored the entire `docs/` tree, `package.json` did not expose the documented scripts, and `.githooks/` was empty.

## Decision

Track generated contract docs under `docs/src/**` in git and treat them as repository artifacts that must stay in sync with `src/**/*.sol`.

Treat the following as hand-maintained files:

- `docs/plans/**`
- `docs/book.toml`
- `docs/book.css`
- `docs/solidity.min.js`
- `docs/.gitignore`

Treat the following as generated files:

- `docs/src/**`

## Workflow

1. Developers write and update NatSpec in `src/**/*.sol`.
2. `npm run docs:gen` runs `forge doc` to refresh generated docs.
3. A `pre-commit` hook detects staged Solidity changes, regenerates docs, and re-stages only `docs/src`.
4. CI runs a docs freshness check that regenerates docs and fails if `docs/src` differs from git or contains untracked generated files.

## Repository Changes

- Stop ignoring the whole `docs/` directory.
- Keep only built book output ignored via `docs/book/`.
- Add repository scripts for hook installation and docs commands.
- Add a shell script for docs freshness checks so local and CI verification use the same logic.
- Add a tracked `.githooks/pre-commit`.
- Extend CI with a dedicated docs job.
- Update `AGENTS.md` to describe the implemented behavior precisely.

## Verification

Primary verification for this workflow is command-based:

- `npm run docs:gen`
- `npm run docs:check`

The current workspace has an existing Solidity compile error in `src/verse/MemeverseLauncher.sol`, so full docs regeneration is expected to fail until contract changes are fixed. The automation should still be implemented now so the repository workflow is ready once the source tree is buildable.
