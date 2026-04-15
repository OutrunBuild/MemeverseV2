# MemeverseV2 Verification

- Verification entrypoint: script/harness/gate.sh
- Quick local profile: npm run gate:fast
- Full local profile: npm run gate
- CI profile: npm run gate:ci
- gate:fast is for fast blocking checks on the current change set.
- gate is the local release gate and uses the full profile.
- gate:ci is the CI-facing path and may receive changed files from CI.
- Completion or pass claims require fresh output from the exact gate profile used for the verdict.
