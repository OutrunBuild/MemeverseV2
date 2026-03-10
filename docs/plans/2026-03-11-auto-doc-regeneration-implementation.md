# Auto Documentation Regeneration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement repository-backed contract doc regeneration with local hook automation and CI freshness checks.

**Architecture:** Track `docs/src/**` in git, regenerate it from `forge doc`, and enforce freshness with a `pre-commit` hook plus a dedicated CI job. Keep hand-written files in `docs/plans/**` out of the auto-staging path.

**Tech Stack:** Foundry, Git hooks, GitHub Actions, npm scripts, Bash

---

### Task 1: Define tracked docs boundaries

**Files:**
- Modify: `.gitignore`
- Reference: `docs/.gitignore`

**Step 1: Update ignore rules**

Remove the root-level `docs/` ignore so git can track docs sources and generated markdown. Keep only built book output ignored.

**Step 2: Verify scope**

Confirm the repository now treats `docs/src/**` as trackable and leaves `docs/book/` ignored.

### Task 2: Add local docs commands and validation

**Files:**
- Modify: `package.json`
- Create: `script/check-docs.sh`

**Step 1: Add docs scripts**

Add:

- `hooks:install`
- `docs:gen`
- `docs:watch`
- `docs:check`

**Step 2: Implement the docs check script**

Write a shell script that:

1. Runs `forge doc`
2. Fails if tracked files under `docs/src` changed
3. Fails if untracked generated files appear under `docs/src`

### Task 3: Add hook automation

**Files:**
- Create: `.githooks/pre-commit`

**Step 1: Detect staged Solidity changes**

Read staged file paths and exit early unless a file under `src/**/*.sol` is part of the commit.

**Step 2: Regenerate and re-stage docs**

Run `npm run docs:gen` and then `git add docs/src`.

### Task 4: Add CI enforcement

**Files:**
- Modify: `.github/workflows/test.yml`

**Step 1: Add a dedicated docs job**

Create a separate `docs` job that checks out the repository, installs Foundry, and runs the docs freshness check.

**Step 2: Keep failure mode explicit**

The job should fail when docs generation fails or when generated docs differ from tracked contents.

### Task 5: Align repository guidance

**Files:**
- Modify: `AGENTS.md`
- Create: `docs/plans/2026-03-11-auto-doc-regeneration-design.md`

**Step 1: Update workflow documentation**

Rewrite the `Auto Documentation Regeneration` section so it describes `docs/src/`, hook behavior, and CI enforcement accurately.

**Step 2: Preserve hand-written plan boundaries**

Make sure the guidance does not imply `docs/plans/**` is auto-generated.
