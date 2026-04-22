# MemeverseV2 Verification

- Verification entrypoint: script/harness/gate.sh
- Quick local profile: npm run gate:fast
- Full local profile: npm run gate
- CI profile: npm run gate:ci
- gate:fast is for fast blocking checks on the current change set.
- gate is the local release gate and uses the full profile.
- gate:ci is the CI-facing path and requires changed-files input from CI.
- changed-files mode for Solidity paths requires diff evidence via `CHANGE_CLASSIFIER_DIFF_FILE` or `GATE_DIFF_BASE`; without it, semantic classification is blocked.
- `fast` is the default local verdict for current work and should be run against the exact changed file set.
- `full` is the merge or release gate and runs the repository-wide verification profile.
- harness-only and docs-only changes still require a fresh gate verdict from the matching profile before claiming completion.
- mock-heavy unit tests do not replace semantic or integration coverage when the claim depends on upstream protocol behavior.
- Completion or pass claims require fresh output from the exact gate profile used for the verdict.
