# MemeverseV2

Foundry-only workspace.

Project commands:

- `npm run lint`
- `npm run build`
- `npm run test`
- `npm run gas:report`

Harness commands:

- `npm run gate:fast` — rapid feedback: fmt + lint + build + changed/mapped tests only
- `npm run gate` — local final gate: full test suite + coverage + Slither (when risk tier requires)
- `npm run gate:ci` — same scope as `gate`, emits a timestamped run record to `.harness/.runs/`

Which commands actually run depends on what changed. The gate classifies diffs, determines risk, and selects a verification profile — it does not blindly run everything every time.

## How the gate works

`script/harness/gate.sh` reads `.harness/policy.json` and executes this pipeline:

1. **Classify surfaces** — every changed file is matched against surface patterns:
   - `solidity_prod` → `src/**/*.sol`, `script/**/*.sol`, `lib/**`
   - `solidity_test` → `test/**/*.sol`
   - `harness_control` → `AGENTS.md`, `README.md`, `CLAUDE.md`, `package.json`, `.githooks/*`, `script/harness/*`, `.harness/*`, docs, CI config, etc.
2. **Enforce hard blocks** — mixed `harness_control` + `solidity_*` in one diff is blocked. Multiple writer roles in one diff is blocked.
3. **Classify risk tier** — diffs are parsed for semantic changes (skipping comments, whitespace, punctuation-only lines):
   - `none` — no Solidity files
   - `non-semantic` — Solidity files changed but only comments/whitespace
   - `test-semantic` — only test files have semantic changes
   - `prod-semantic` — production Solidity has semantic changes
   - `high-risk` — production changes touch `src/` paths or contain dangerous tokens (`delegatecall`, `assembly`, etc.)
4. **Run verification** — commands selected by profile + risk tier (see table below)
5. **Emit run record** — JSON artifact with surface, risk tier, writer role, review roles, command results, and final verdict

Verdicts: `pass` | `fail` (verification failed) | `blocked` (policy violation) | `no-op` (nothing staged).

## Verification by profile and risk tier

| Command | fast | full / ci | Condition |
|---|---|---|---|
| `forge fmt --check` (changed `.sol`) | yes | yes | Solidity files in diff |
| `npx solhint` (changed `.sol`) | yes | yes | Solidity files in diff |
| `forge build` | yes | yes | always |
| `forge test --match-path` (changed + mapped tests) | yes | — | fast profile only |
| `forge test -vvv` (full suite) | — | yes | full / ci |
| `forge coverage` | — | yes | risk = `prod-semantic` or `high-risk` |
| `slither` | — | yes | risk = `prod-semantic` or `high-risk` |
| `bash -n` (changed `.sh`) | yes | yes | shell files in diff |
| `node --check` (changed `.js`) | yes | yes | JS files in diff |
| `npm ci` | yes | yes | `package.json` / lockfile changed |

## Review roles by risk tier

| Risk tier | Required reviewers |
|---|---|
| `non-semantic` | none |
| `test-semantic` | logic-reviewer |
| `prod-semantic` | logic-reviewer, security-reviewer, gas-reviewer |
| `high-risk` | logic-reviewer, security-reviewer, gas-reviewer |

## Test mapping

When a production file changes, `gate:fast` resolves required tests from `policy.json → test_mapping`. Each rule maps source paths to `change_tests` (must pass) and `evidence_tests` (broader coverage). See `.harness/policy.json` for the full mapping table.

## Git hooks

`.githooks/` calls the same gate entrypoints when enabled (`core.hooksPath = .githooks`).

Repository layout:

- `src/{common,governance,interoperation,swap,token,verse,yield}`
- `test/{common,governance,interoperation,swap,token,verse,yield}`
- `script/**/*.sol` plus `script/deploy.sh`
