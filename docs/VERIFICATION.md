# MemeverseV2 Verification

- Machine truth: `.harness/policy.json`
- Enforcement entrypoint: `script/harness/gate.sh`
- Local quick gate: `npm run gate:fast`
- Local full gate: `npm run gate`
- CI gate: `npm run gate:ci`
- Direct project checks: `npm run lint`, `npm run build`, `npm run test`, `npm run gas:report`
- Default run records land in `.harness/.runs/`; CI may override with `RUN_RECORD_PATH`
- Completion claims require fresh output from the exact gate profile used for the verdict
