# MemeverseV2 Traceability（当前规则 -> 证据）

## 1. 说明

- 本文档追溯的是当前规则真源（`docs/spec/*.md` 与 Product Truth 支撑文档），并按需引用 `AGENTS.md`/`docs/process/*` 的流程规则证据；不是历史 PRD 的逐条复刻。
- 状态枚举
  - `PASS`：规则与当前源码一致，且有可定位证据。
  - `PARTIAL`：源码可证，但测试/流程证据未形成闭环。
  - `GAP`：流程层已明确记录缺口。
  - `MISMATCH`：历史输入与当前规则或实现不一致。
- 置信度
  - `High`：源码直接可证。
  - `Medium`：依赖推断或缺少执行证据。
  - `Low`：存在冲突或关键证据缺失。

## 2. 追溯矩阵

| Rule ID | Current Rule Doc | Expected Surface | Expected Test / Evidence | Current Evidence | Status |
| --- | --- | --- | --- | --- | --- |
| AC-01 | `docs/spec/access-control.md`（Section 3） | launcher owner 配置边界 | `test/verse/MemeverseLauncherConfig.t.sol` + `onlyOwner` 代码路径 | `src/verse/MemeverseLauncher.sol:1127-1297`; `test/verse/MemeverseLauncherConfig.t.sol:143`, `:218` | PASS / High |
| AC-02 | `docs/spec/access-control.md`（Section 3） | `registerMemeverse` 仅 registrar | `test/verse/MemeverseLauncherRegistration.t.sol` | `src/verse/MemeverseLauncher.sol:936-947`; `test/verse/MemeverseLauncherRegistration.t.sol:176-179` | PASS / High |
| AC-03 | `docs/spec/access-control.md`（Section 3） | `setExternalInfo` 仅 governor/registrar，且增量覆盖 | `test/verse/MemeverseLauncherRegistration.t.sol` | `src/verse/MemeverseLauncher.sol:1307-1321`; `test/verse/MemeverseLauncherRegistration.t.sol:285-289`, `:324-327` | PASS / High |
| AC-04 | `docs/spec/state-machines.md`（Section 2.3） | launcher 生命周期入口 permissionless + stage guard | `test/verse/MemeverseLauncherLifecycle.t.sol` | `src/verse/MemeverseLauncher.sol:318`, `:382`, `:619`, `:671`, `:719`; `test/verse/MemeverseLauncherLifecycle.t.sol:1036`, `:1049` | PASS / Medium |
| AC-05 | `docs/spec/protocol.md`（Section 3/4）+ `docs/spec/access-control.md`（Section 3） | Router 公开入口 + Hook core 引擎 | `test/swap/MemeverseSwapRouter.t.sol`, `test/swap/MemeverseUniswapHookLiquidity.t.sol` | `src/swap/MemeverseSwapRouter.sol:31`, `:174-247`; `src/swap/MemeverseUniswapHook.sol:57`, `:440`, `:510`, `:550` | PASS / High |
| AC-06 | `docs/spec/access-control.md`（Section 3） | 外部 dispatcher / endpoint 边界 | `test/verse/MemeverseOFTDispatcher.t.sol`, `test/interoperation/OmnichainMemecoinStaker.t.sol`, `test/verse/registration/MemeverseRegistrationCenter.t.sol` | `src/verse/MemeverseOFTDispatcher.sol:46`; `src/interoperation/OmnichainMemecoinStaker.sol:39`; `src/verse/registration/MemeverseRegistrationCenter.sol:180`, `:296-297` | PASS / High |
| ACC-01 | `docs/spec/accounting.md`（Section 2） | Genesis 75/25 拆分与 preorder 入账约束 | `test/verse/*Genesis*.t.sol`, `test/verse/*Preorder*.t.sol` | `src/verse/MemeverseLauncher.sol:318-381`, `:671-713` | PASS / Medium |
| ACC-02 | `docs/spec/accounting.md`（Section 5/6） | fee 分账、治理收入与 yield 路径 | `test/verse/*Fees*.t.sol`, `test/governance/*.t.sol`, `test/yield/*.t.sol` | `src/verse/MemeverseLauncher.sol:813-935`; `src/governance/MemecoinDaoGovernorUpgradeable.sol:221`; `src/yield/MemecoinYieldVault.sol:86-154` | PARTIAL / Medium |
| UPG-01 | `docs/spec/upgradeability.md`（Section 2/3，主） | token/yield clone 初始化一次性 | `test/token/*.t.sol`, `test/yield/MemecoinYieldVault.t.sol`, `test/common/*Init*.t.sol` | `src/common/access/Initializable.sol:27-41`; `src/token/Memecoin.sol:24-33`; `src/token/MemeLiquidProof.sol:37-49`; `src/yield/MemecoinYieldVault.sol:37-50` | PASS / High |
| UPG-02 | `docs/spec/upgradeability.md`（Section 2/4，主） | governor/incentivizer 为 UUPS + governance 授权升级 | `test/governance/*.t.sol`（升级路径覆盖需确认） | `src/governance/MemecoinDaoGovernorUpgradeable.sol:42`, `:76`, `:252`; `src/governance/GovernanceCycleIncentivizerUpgradeable.sol:15`, `:83`, `:640` | PARTIAL / Medium |
| PROC-01 | `docs/VERIFICATION.md`（Section 3）+ `docs/process/change-matrix.md` | `quality:gate` 为唯一 finish gate | `script/process/quality-gate.sh` | `script/process/quality-gate.sh:192-194`; `package.json:23` | PASS / High |
| PROC-02 | `docs/VERIFICATION.md`（Section 4）+ `docs/process/policy.json` | `rule-map` + review note 证据联动 | `check-rule-map.sh` + `check-solidity-review-note.sh` | `script/process/quality-gate.sh:139`, `:177-178`; `docs/process/rule-map.json` | PASS / High |
| PROC-03 | `docs/spec/implementation-map.md`（Section 3）+ `docs/process/rule-map.json` | 非 swap/launcher 域规则映射可见性 | `testing_gaps` 应显式可见 | `docs/process/rule-map.json:140-170` | GAP / High |
| HIST-DIFF-01 | `docs/spec/protocol.md`（Section 7.1）+ `docs/spec/state-machines.md`（Section 4） | 历史输入中的 `requestSwapAttemptWithQuote(...)` 差异 | hook/router 应出现同名入口 | 当前接口与实现未发现该函数名：`src/swap/interfaces/IMemeverseUniswapHook.sol:81-199`、`src/swap/MemeverseUniswapHook.sol` | MISMATCH / High |
| HIST-DIFF-02 | `docs/spec/protocol.md`（Section 7.3）+ `docs/spec/state-machines.md`（Section 3.2） | 注册 DAY 语义一致性 | `durationDays/lockupDays` 应统一换算 | 当前实现为测试值 `DAY = 180`：`src/verse/registration/MemeverseRegistrationCenter.sol:22`; 本地 quote 仍用 `24*3600` | MISMATCH / High |

## 3. 明确未知项

- 未提供生产部署清单，无法在本仓库内确认每条链上的最终 owner / delegate / governance executor 地址。
- `UPG-02` 的“执行级”验证（实际 upgrade tx）需要集成测试与部署脚本证据；当前矩阵以源码锚点与测试存在性为主。
