# Repository Guidelines

## Project Structure & Module Organization
- `src/` contains core Solidity code, grouped by domain: `common/`, `token/`, `verse/`, `governance/`, `interoperation/`, `yield/`, and `libraries/`.
- `test/` stores Foundry tests (`*.t.sol`), including simulation-style tests.
- `script/` contains Foundry scripts (`*.s.sol`) and helper shell scripts like `deploy.sh`.
- `lib/` holds external dependencies and git submodules (LayerZero, OpenZeppelin, Uniswap v4, etc.).
- Generated outputs live in `out/`, `artifacts/`, and `cache/`; treat these as build artifacts, not source.

## Build, Test, and Development Commands
- `git submodule update --init --recursive`: initialize pinned dependency submodules.
- `forge fmt --check`: formatting check used by CI.
- `forge build --sizes`: compile contracts and show bytecode sizes.
- `forge test -vvv`: run Solidity tests with verbose logs.
- `npm run quality:gate`: run mandatory local quality gate (format/build/test/docs + review note checks for staged changes).
- `npm run compile`: runs `forge build` and `hardhat compile`.
- `npm run test`: runs Forge and Hardhat test commands.
- `npm run lint`: runs ESLint/Prettier and Solidity lint checks.
- `npm run clean`: removes local build/cache outputs.

## Coding Style & Naming Conventions
- Follow Foundry formatting (`forge fmt`) and keep Solidity style consistent (4-space indentation, explicit visibility, SPDX + pragma headers).
- Use PascalCase for contracts/libraries (`MemeverseLauncher.sol`), `I` prefix for interfaces (`IMemecoin.sol`), and descriptive module names.
- Use `.t.sol` suffix for tests and `.s.sol` suffix for scripts.
- Keep changes minimal and scoped to one concern per PR.

## Solidity Documentation Standards
- Write NatSpec as part of development, not as a final step.
- For every `public`/`external` function, include `@notice`, `@dev`, `@param`, `@return` (if any), and `@custom:security` when risk exists.
- Document permission boundaries clearly: `owner`, roles, multisig, timelock, and their allowed actions.
- Keep state and invariant notes explicit (critical state variables, state transitions, must-always-hold assumptions).
- Document failure semantics with custom errors and trigger conditions.
- Define event semantics and indexed fields for off-chain consumers.
- For upgradeable contracts, document storage layout assumptions, initializer order, and upgrade risks.
- Keep docs-to-tests mapping: each core rule should have at least one deterministic test case.

## Documentation Language
- Unless explicitly requested otherwise, write newly created repository documents in Simplified Chinese.
- Keep code identifiers, commands, and protocol/library names in their canonical English form.

## Product / Design Consistency
- For any requested change that affects product semantics, business rules, user-visible behavior, interface meaning, fund flow, permission boundaries, or configuration assumptions anywhere in the project, do not treat it as a code-only change.
- First review the relevant design / product / integration documentation.
- If the requested change changes intended behavior, update the relevant documentation first.
- Then update the implementation.
- Before finishing, ensure documentation, tests, and code are consistent.
- This is a project-wide rule and applies to all modules, not only specific contracts.

## Auto Documentation Regeneration
- Contract docs are generated locally from Solidity NatSpec via `npm run docs:gen`.
- Generated output is written to `docs/contracts/` and is not committed.
- Generation rewrites the default nested path so docs are stored directly under `docs/contracts/`.
- Contract doc generation is checked by a git `pre-commit` hook.
- One-time setup: run `npm run hooks:install` to set `core.hooksPath` to `.githooks`.
- On each commit, run `npm run quality:gate`. If staged files include `src/**/*.sol`, the gate runs `npm run docs:gen`.
- `docs/plans/` is local planning content and is not committed.
- CI runs `npm run quality:gate` in CI mode with PR/Push changed-file scope, and enforces the same finish gate rules as local commits.
- Optional live workflow during editing: `npm run docs:watch`.

## Testing Guidelines
- Primary framework is Foundry (`forge-std/Test.sol`); Hardhat tests may be used for JS/TS workflows.
- Place tests in `test/` and name them by feature or behavior (example: `MemeverseDynamicFeeSimulation.t.sol`).
- Prefer deterministic tests and isolate chain-specific behavior behind configuration.
- For any staged `src/**/*.sol` or `test/**/*.t.sol` change, run `npm run quality:gate` before commit.
- Do not rely on mock-only tests for external protocol integrations (Permit2/Uniswap/LayerZero/etc.). Keep fast mock tests, but add at least one conformance/integration test path that validates real protocol semantics (signature/hash/witness/nonce/deadline or equivalent boundary rules).
- Every core rule and external integration assumption must map to at least one deterministic test.

## Mandatory Finish Gate (Before Commit)
- This gate is required for any commit touching `src/**/*.sol`.
- Step 1: Perform code review of changed logic and record concrete findings in a staged file under `docs/reviews/*.md`.
- Step 2: Explicitly assess simplification opportunities and record whether each candidate is applied or intentionally rejected.
- Step 3: Record verification evidence (commands + pass/fail summary) in the same review note.
- Step 4: Run `npm run quality:gate` and ensure it passes.
- Commit is not allowed if these checks are missing.

## Commit & Pull Request Guidelines
- Current git history is minimal (`Init commit`), so adopt concise imperative commit subjects (example: `feat(verse): add registrar validation`).
- Include clear PR context: what changed, why, and affected paths/modules.
- Attach verification evidence (commands run and results), especially for contract logic or deployment script changes.
- Note any ABI, storage-layout, or network-config impact explicitly.
- Keep `docs/plans/` as local planning content (do not commit).

## Security & Configuration Tips
- Keep secrets in `.env` only (`MNEMONIC`, `PRIVATE_KEY`, RPC URLs, explorer keys); never commit credentials.
- Validate network/environment variables in `foundry.toml` and `hardhat.config.ts` before deployment runs.
