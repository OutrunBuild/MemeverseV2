# MemeverseV2 Traceability

- Shared control contract: `solidity-subagent-harness`
- Repo machine truth: `.harness/policy.json`
- Runtime entrypoint: `script/harness/gate.sh`
- Durable trace artifact: run-record JSON emitted to `.harness/.runs/` or an explicit `--emit-run-record` path
- Each run record must capture changed files, surface, risk tier, writer role, review roles, verification profile, commands run, command results, blocking findings, residual risks, and final verdict
- CI supplies the changed-file list to `npm run gate:ci`; local runs derive the staged set unless `--changed-files` is provided
- Deleted legacy roots from policy remain unsupported and must stay absent
