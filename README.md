# MemeverseV2

Foundry-only workspace.

Project commands:

- `npm run lint`
- `npm run build`
- `npm run test`
- `npm run gas:report`

Harness commands:

- `npm run gate:fast` - rapid local feedback: fmt, lint, build, and changed/mapped tests
- `npm run gate` - default local gate, same as `gate:fast`
- `npm run gate:full` - release-like local gate
- `npm run gate:ci` - CI gate; CI must pass explicit changed-file input

`script/harness/gate.sh --classify-only` emits policy-derived orchestration fields without running verification commands.

## How The Gate Works

1. **Classify surfaces** - every changed file is matched against `.harness/policy.json`.
2. **Classify change class** - Solidity diffs are parsed for semantic changes while ignoring comments, whitespace, and punctuation-only lines.
3. **Select orchestration** - gate emits `orchestration_profile`, `harness_writer_roles`, `code_writer_roles`, and `code_review_roles`.
4. **Run verification** - normal gate profiles run commands selected by profile and changed-file scope.
5. **Emit run record** - when `RUN_RECORD_PATH` is set, the gate writes classification, orchestration, command results, and final verdict.

Change classes: `no-op` | `non-semantic` | `test-semantic` | `prod-semantic`.

Orchestration profiles:

| Profile | Meaning |
|---|---|
| `direct` | main session edits; no writer/reviewer dispatch |
| `direct-review` | main session edits; selected reviewers run |
| `delegated` | policy-selected writer handles docs/process/control changes |
| `full-review` | policy-selected writer plus full review matrix |
| `full-subagent` | full review plus independent verifier |
| `blocked` | stop before editing |
| `no-op` | no classified changes |

Production Solidity semantic changes never downgrade by static allowlist and never escalate by static keyword denylist alone. Small localized production Solidity changes may use `direct-review` only after a main-session Risk Analysis Record. If analysis is incomplete or uncertain, use at least `full-review`.

## Verification Commands

| Command | fast | full / ci | Condition |
|---|---|---|---|
| `forge fmt --check` | yes | yes | changed Solidity files |
| `npx solhint` | yes | yes | changed Solidity files |
| `forge build` | yes | yes | always |
| `forge test --match-path` | yes | no | changed/mapped targeted tests |
| `forge test -vvv` | no | yes | full / ci |
| `forge coverage` | no | yes | `change_class=prod-semantic` and `surface_sensitivity=sensitive` |
| `slither` | no | yes | same as coverage, only when changed production Solidity includes `src/**/*.sol` |
| `bash -n` | yes | yes | changed shell files |
| `node --check` | yes | yes | changed JavaScript files |
| `npm ci` | yes | yes | package manifest or lockfile changed |

## Test Mapping

When production Solidity changes, `gate:fast` resolves targeted tests from `policy.json -> test_mapping`. Each rule maps source paths to `change_tests` and `evidence_tests`.

## Git Hooks

`.githooks/` calls the same gate entrypoints when enabled with `core.hooksPath=.githooks`.

## How To Deploy

### Swap Hook Subsystem

`script/DeployMemeverseHookProxy.s.sol` deploys the MemeverseUniswapHook and MemeverseDynamicFeeEngine via CREATE3 (OutrunDeployer). Each deployment produces 4 deterministic addresses scoped by `(deployer, nonce)`:

1. MemeverseDynamicFeeEngine implementation
2. MemeverseDynamicFeeEngine ERC1967 proxy
3. MemeverseUniswapHook implementation
4. MemeverseUniswapHook ERC1967 proxy (address carries Uniswap v4 hook flags)

Required environment variables (see `.env.example`):

| Variable | Meaning |
|---|---|
| `PRIVATE_KEY` | Deployer private key (Foundry `--broadcast`) |
| `OUTRUN_DEPLOYER` | OutrunDeployer (CREATE3 deployer) address on the target chain |
| `POOL_MANAGER` | Uniswap v4 PoolManager address on the target chain |
| `HOOK_OWNER` | Owner address for the hook proxy |
| `HOOK_TREASURY` | Treasury address that receives protocol fees |
| `DEPLOYMENT_NONCE` | Version nonce for CREATE3 salts. Use `0` for first deploy, increment by 1 per upgrade. |

Deploy command:

```bash
cp .env.example .env   # fill in real values
forge script script/DeployMemeverseHookProxy.s.sol:DeployMemeverseHookProxy \
  --broadcast --verify --rpc-url <RPC_URL>
```

Re-running with the same nonce is idempotent — if the full set of 4 contracts already exists with matching configuration, the script returns the existing addresses without re-deploying.

Repository layout:

- `src/{common,governance,interoperation,swap,token,verse,yield}`
- `test/{common,governance,interoperation,swap,token,verse,yield}`
- `script/**/*.sol` plus shell deployment scripts
