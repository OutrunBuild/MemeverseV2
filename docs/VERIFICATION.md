# MemeverseV2 Verification

- Verification entrypoint: `script/harness/gate.sh`
- Classification-only entrypoint: `bash script/harness/gate.sh --classify-only --changed-files <path> [<path> ...]`
- Default local profile: `npm run gate` (`fast`)
- Fast local profile: `npm run gate:fast`
- Full local profile: `npm run gate:full`
- CI profile: `npm run gate:ci`
- CI entrypoint wrapper: `bash script/harness/ci-gate-entrypoint.sh`

`fast` is the default local verdict for current work. Use `full`, `ci`, release, or merge-equivalent verification only when explicitly requested or running in that context.

Gate output controls:

- `--quiet`: suppresses successful `pass`, `no-op`, or `classified` text stdout. Failures and blocked verdicts still print an error summary.
- `--log-level error|warn|info|debug`: defaults to `info`. `error` prints only error-oriented output, `warn` prints warnings/errors without success summaries, and `debug` includes the structured gate record in text mode.
- `--output text|json`: defaults to JSON for `--classify-only` and text for normal verification. `json` prints the structured classification or final record to stdout and takes precedence over `--quiet`.

`--changed-files` accepts one or more repo-relative paths. Every positional argument after `--changed-files` is treated as a changed file until the next option. The old "path to a changed-files manifest" form is removed.

Local current-work gate invocations must use exact changed-file input. Solidity changed-files mode requires diff evidence via `CHANGE_CLASSIFIER_DIFF_FILE` or `GATE_DIFF_BASE`; without it, semantic classification is blocked.

Gate verifies classification and command outcomes. Spec/document impact is decided before doc writers, `spec-reviewer`, code writers, or code reviewers are dispatched, not by gate.

For `fast` verification, `targeted_tests` still starts from the exact file set selected by `test_mapping`, but the gate now tries to compress that file set into a single `forge test --match-contract <regex>` run. The gate builds the regex from `forge test --list --match-path <file>` results, validates that `forge test --list --match-contract <regex>` resolves to the same test-contract set, and only then runs the compressed command. If extraction or validation fails, the gate falls back to the original per-file `forge test --match-path <file>` loop.

CI uses two entry paths:

- When a reliable diff base exists, `script/harness/ci-gate-entrypoint.sh` computes changed files plus diff evidence and invokes `gate:ci -- --changed-files <path> [<path> ...]`.
- For `workflow_dispatch`, zero-base, or empty-diff events, the CI entrypoint invokes `gate:ci -- --all` instead of passing an empty changed-files list.

Diff evidence must not be created as persistent repository files. Prefer `GATE_DIFF_BASE=<git-ref>`; when `CHANGE_CLASSIFIER_DIFF_FILE` is needed, point it at a `mktemp` file outside the repository and remove it after `gate.sh` exits.

`full` and `ci` command gates:

| Command | Condition |
|---|---|
| `forge coverage` | `change_class=prod-semantic` and `surface_sensitivity=sensitive` |
| `slither` | same as coverage, only when changed production Solidity includes `src/**/*.sol` |

`full-subagent` is an orchestration profile, not a gate profile. It means an independent verifier is required; the verifier runs the selected `fast`, `full`, or `ci` profile.

Completion or pass claims require fresh output from the exact gate profile used for the verdict. Harness-only and docs-only changes still require a fresh gate verdict before claiming completion.
