# MemeverseV2

Foundry-only workspace.

Project commands:

- `npm run lint`
- `npm run build`
- `npm run test`
- `npm run gas:report`

Harness commands:

- `npm run gate:fast`
- `npm run gate`
- `npm run gate:ci`

Harness machine truth is `.harness/policy.json`. Enforcement runs through `script/harness/gate.sh`. Local hooks in `.githooks/` call the same gate entrypoints when enabled.

Repository layout:

- `src/{common,governance,interoperation,swap,token,verse,yield}`
- `test/{common,governance,interoperation,swap,token,verse,yield}`
- `script/**/*.sol` plus `script/deploy.sh`
