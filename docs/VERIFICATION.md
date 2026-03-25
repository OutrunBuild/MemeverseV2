# MemeverseV2 文档系统验证指南

## 1. 目标

本指南用于持续验证以下链路一致：

- Harness / Process 契约链：`AGENTS.md` -> `docs/process/*` -> `script/process/*` -> npm scripts
- Product Truth 文档链：`docs/ARCHITECTURE.md` -> `docs/spec/*.md`（升级性主文档：`docs/spec/upgradeability.md`） -> `docs/GLOSSARY.md` -> `docs/TRACEABILITY.md` -> `docs/VERIFICATION.md` -> `docs/adr/0001-universalvault-style-harness-migration.md`
- 实现证据链：`src/**` + `test/**` + `docs/process/rule-map.json`

## 2. 规则分层校验基线

- 当前规则真源是 `docs/spec/*.md` 及其配套的 `ARCHITECTURE/GLOSSARY/TRACEABILITY/VERIFICATION/ADR`。
- `src/**` 与 `test/**` 是规则落地证据。
- `docs/memeverse-swap/*` 用于补充 swap 相关专题说明，不与当前规则并列定规。

## 3. 常规验证流程

### 3.1 Process 自检

1. `npm run process:selftest`
2. 预期：`script/process/tests/run-all.sh` 全通过，流程检查器与策略文件一致。

### 3.2 文档链检查

1. `npm run docs:check`
2. 预期：
   - 文档检查脚本可运行。
   - harness 支撑文件覆盖 `docs_contract_pattern`。

### 3.3 质量门禁

1. `npm run quality:gate`
2. 预期（按改动路径触发）：
   - `check-rule-map.sh`
   - `forge fmt --check` / `forge build` / `forge test -vvv`
   - `check-slither.sh` / `check-gas-report.sh`
   - `check-solidity-review-note.sh`
   - `npm run docs:check`

## 4. Product Truth 专项检查

用于防止文档混入非规则性标签或错误引用：

1. 旧 taxonomy 清理检查
 - `rg -n "\[PRD\]|\[代码\]|\[PRD\+代码\]" docs/spec docs/ARCHITECTURE.md docs/GLOSSARY.md docs/TRACEABILITY.md docs/VERIFICATION.md docs/adr/0001-universalvault-style-harness-migration.md`
 - 预期：不应作为当前规则标签体系。
2. Traceability 来源检查
 - `rg -n "docs/spec/|docs/ARCHITECTURE|docs/GLOSSARY|docs/TRACEABILITY|docs/VERIFICATION|docs/adr/" docs/TRACEABILITY.md`
 - 预期：`Current Rule Doc` 主要指向 `docs/spec/*.md` 与 Product Truth 支撑文档（`ARCHITECTURE/GLOSSARY/TRACEABILITY/VERIFICATION/ADR`）。
3. Upgradeability 主文档归属检查
 - `rg -n "UPG-(01|02).*(docs/spec/implementation-map\\.md)" docs/TRACEABILITY.md`
 - 预期：无命中；`UPG-*` 的 `Current Rule Doc` 主锚点应为 `docs/spec/upgradeability.md`，`implementation-map` 仅用于 surface 事实补充。
4. 规则-证据可追溯检查
 - `docs/TRACEABILITY.md` 中每条规则都应可回溯到 `src/**` 或 `test/**` 的可定位锚点。

## 5. 建议的最小回归测试集

当文档涉及权限、状态机、记账、swap 路径时，建议至少执行：

1. `forge test --match-path test/verse/MemeverseLauncherRegistration.t.sol -vvv`
2. `forge test --match-path test/verse/MemeverseLauncherConfig.t.sol -vvv`
3. `forge test --match-path test/verse/MemeverseLauncherLifecycle.t.sol -vvv`
4. `forge test --match-path test/swap/MemeverseSwapRouter.t.sol -vvv`
5. `forge test --match-path test/swap/MemeverseUniswapHookLiquidity.t.sol -vvv`
6. `forge test --match-path test/verse/YieldDispatcher.t.sol -vvv`
7. `forge test --match-path test/interoperation/OmnichainMemecoinStaker.t.sol -vvv`

## 6. 已知验证缺口管理

- `docs/process/rule-map.json` 的 `testing_gaps` 是当前受控缺口清单。
- 当某域仍在 `testing_gaps` 中，`TRACEABILITY` 状态应标记为 `GAP` 或 `PARTIAL`，不得伪造为 `PASS`。
- 缺口收敛后，需同步更新 `rule-map`、`TRACEABILITY` 与相关 spec 文档。

## 7. 失败处理与修复顺序

1. 先修复真源层定义冲突（`docs/spec/*.md`）。
2. 再修复追溯层（`docs/TRACEABILITY.md`）与架构分层说明（`docs/ARCHITECTURE.md`）。
3. 最后补齐流程证据（`docs/process/*`、测试、quality gate 产物）。
