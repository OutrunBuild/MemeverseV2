# MemeverseV2 架构总览

## 1. 模块地图

### 1.1 启动与生命周期核心

- `src/verse/MemeverseLauncher.sol`
- 负责 verse 生命周期状态机与资金主编排（Genesis/Refund/Locked/Unlocked）。

### 1.2 注册与跨链注册

- `src/verse/registration/MemeverseRegistrationCenter.sol`
- `src/verse/registration/MemeverseRegistrarAtLocal.sol`
- `src/verse/registration/MemeverseRegistrarOmnichain.sol`
- 负责参数校验、symbol 占用、local/remote fan-out，以及对 launcher 的落库调用。

### 1.3 交易与流动性

- `src/swap/MemeverseSwapRouter.sol`
- `src/swap/MemeverseUniswapHook.sol`
- `src/swap/libraries/MemeverseHookLib.sol`
- 负责 swap、加减流动性、LP fee claim、启动期费用语义与 launch settlement 通道。
- `MemeverseHookLib` 是从 Hook 合约提取的 internal library，承载动态费率报价、swap 后状态更新、LP/协议费收取与资产结算逻辑，以降低 Hook 合约字节码体积。

#### MemeverseHookLib 导出函数

**费率报价**

| 函数 | 作用 |
|---|---|
| `quoteSwap` | 完整报价：先通过 `_quoteDynamicFee` 计算动态费率，取动态费率与 launch fee 的较大值作为 effective fee，再拆分为 LP fee 与 protocol fee，按 exact-input / exact-output 两种方向估算用户实际输入输出。 |
| `quoteSwapQuickReturn` | 轻量报价（流动性为零时快速返回）：仅使用 launch fee 或 base fee，不做动态费率计算，也不估算 output 金额。exact-output 方向直接 revert。 |
| `quoteSwapBaseFee` | 仅基于 launch fee 或 base fee 的报价（跳过动态费率）：估算 swap 流向并拆分 LP / protocol fee，用于不启用动态费率的场景。 |
| `quoteLaunchFeeBps` | 根据指数衰减公式计算当前 launch fee bps：从 `startFeeBps` 按经过时间衰减到 `minFeeBps`，衰减形状由 `LAUNCH_FEE_EXP_SHAPE_WAD` 控制。 |

**动态费率与状态更新**

| 函数 | 作用 |
|---|---|
| `updateDynamicStateAfterSwap` | swap 后更新 per-pool EWVWAP 状态与 per-address batch 累积：维护指数加权成交量 `weightedVolume0`、加权价格成交量 `weightedPriceVolume0`、EWVWAP `ewVWAPX18`，同时衰减并累加短期冲击 `shortImpactPpm`、更新波动率偏差累加器 `volDeviationAccumulator`、以及更新 per-address 的 `batchAccumPpm`（3 秒窗口内的累积 PIF，用于 adverse 防拆单）。 |
| `refreshVolatilityAnchorAndCarry` | swap 前刷新波动率锚定价格与携带量：当距上次锚定移动超过 `VOL_FILTER_PERIOD_SEC` 时，将当前价格设为新锚定价格，并对 `volDeviationAccumulator` 按衰减因子折算为 `volCarryAccumulator`；超过 `VOL_DECAY_PERIOD_SEC` 则清零。 |

**Launch settlement**

| 函数 | 作用 |
|---|---|
| `quoteLaunchSettlement` | 给定 gross input 金额和 LP/protocol fee bps，计算 launch settlement 中各方应得的 input 份额。 |
| `handleLaunchSettlementCallback` | 执行 launch settlement swap（调用 `PoolManager.swap`），并在 `protocolFeeOnInput == false` 时从 output 侧扣除 protocol fee，返回原始 delta 和调整后 delta。 |
| `collectLaunchSettlementInputFees` | 从 payer 拉取 input 侧的 LP fee 和 protocol fee：LP fee 通过 `creditLpFee` 记入 per-share 累计，protocol fee 直接转给 treasury。 |

**LP 费收取与 claim**

| 函数 | 作用 |
|---|---|
| `creditLpFee` | 将一笔 LP fee 按 `totalSupply` 换算为 per-share 增量，累加到 `pool.fee0PerShare` 或 `pool.fee1PerShare`，并触发 `LPFeeCollected` 事件。 |
| `collectLpFee` | 从 PoolManager take 出 LP fee 金额到 Hook 合约，再调用 `creditLpFee` 入账。 |
| `updateUserSnapshot` | 根据 LP token 余额和 per-share 累计值，将用户自上次快照以来的可 claim fee 累加到 `pendingFee0` / `pendingFee1`，并更新 offset。 |
| `claimableFeesView` | view 函数：返回用户当前可 claim 的 fee0 / fee1，包含已记录 pending 和尚未 snapshot 的增量。 |
| `claimFeesImpl` | 执行 LP fee claim：先 `updateUserSnapshot`，再将 pending fee 通过 `transferCurrency` 发送给 recipient，清零 pending 并触发 `FeesClaimed` 事件。 |

**协议费收取**

| 函数 | 作用 |
|---|---|
| `collectProtocolFee` | 从 PoolManager take 出 protocol fee 到 treasury，触发 `ProtocolFeeCollected` 事件。 |

**资产结算与转账**

| 函数 | 作用 |
|---|---|
| `settleDeltas` | 向 PoolManager settle 负 delta（用户欠池子的资金）。在 swap 栈语义下仅处理 ERC20/ERC20 pair；任一侧为 `address(0)` 直接 `revert NativeCurrencyUnsupported`。 |
| `takeDeltas` | 从 PoolManager take 正 delta（池子欠用户的资金）到 recipient。 |
| `transferCurrency` | 通用转账 helper。common 层可处理 native 与 ERC20，但 swap 栈文义上只允许 ERC20 结算。 |

### 1.4 资产层

- `src/token/Memecoin.sol`
- `src/token/MemePol.sol`
- 负责 memecoin 与 POL 的铸造/销毁权限边界。

### 1.5 收益与治理

- `src/yield/MemecoinYieldVault.sol`
- `src/governance/MemecoinDaoGovernorUpgradeable.sol`
- `src/governance/GovernanceCycleIncentivizerUpgradeable.sol`
- 负责收益份额、国库接收、投票周期奖励。

### 1.6 跨链互操作

- `src/verse/YieldDispatcher.sol`
- `src/interoperation/MemeverseOmnichainInteroperation.sol`
- `src/interoperation/OmnichainMemecoinStaker.sol`
- 负责治理收益跨链投递与 memecoin 跨链 staking。

## 2. 文档分层

1. Harness Contract 层
   - `AGENTS.md`
   - `CLAUDE.md`
   - `.harness/policy.json`
   - `script/harness/gate.sh`
   - `README.md`
   - `.github/workflows/test.yml`
   - `.githooks/*`
   - `.claude/settings.json`
2. Product Truth 层（当前规则真源）
   - `docs/spec/protocol.md`
   - `docs/spec/state-machines.md`
   - `docs/spec/accounting.md`
   - `docs/spec/access-control.md`
   - `docs/spec/upgradeability.md`
   - `docs/spec/lifecycle-details.md`
   - `docs/spec/registration-details.md`
   - `docs/spec/governance-yield-details.md`
   - `docs/spec/interoperation-details.md`
   - `docs/spec/common-foundations.md`
   - `docs/spec/implementation-map.md`
   - `docs/ARCHITECTURE.md`
   - `docs/GLOSSARY.md`
   - `docs/TRACEABILITY.md`
   - `docs/VERIFICATION.md`
   - `docs/SECURITY_AND_APPROVALS.md`
3. Implementation Evidence 层（规则落地证据）
   - `src/**`
   - `test/**`
4. Topic Guides 层（设计稿与专题补充，不是当前规则真源）
   - `docs/memeverse-swap/*`
   - `docs/superpowers/specs/*`
   - `docs/superpowers/plans/*`

冲突处理顺序：

- 当前规则判断以 Product Truth 层为准，并用 Implementation Evidence 层核验。
- Topic Guides 层用于补充模块说明，不单独定义当前规则。
- 若 `docs/spec/*.md` 与 `src/**` 冲突，以 `src/**` 为准。

## 3. 推荐阅读顺序

1. `CLAUDE.md`
2. `docs/ARCHITECTURE.md`
3. `docs/GLOSSARY.md`
4. `docs/spec/protocol.md`
5. `docs/spec/state-machines.md`
6. `docs/spec/accounting.md`
7. `docs/spec/access-control.md`
8. `docs/spec/upgradeability.md`
9. `docs/TRACEABILITY.md` + `docs/VERIFICATION.md`

## 4. Transient Storage (EIP-1153) 在 Hook Swap 流程中的使用

### 4.1 问题背景

Uniswap V4 的 hook 回调将一次 swap 拆分为 `_beforeSwap` 和 `_afterSwap` 两个独立的外部调用帧。两者之间无法通过内存（memory）或调用栈传递状态。传统方案是将中间状态写入持久化 storage，但这会带来不必要的 SSTORE 开销（即使后续立即覆盖）。

EIP-1153 引入的 transient storage 通过 `TSTORE`（写入）和 `TLOAD`（读取）opcode 解决了这一问题：写入的数据在当前交易结束时自动清除，不产生持久化 storage 开销，且 gas 成本远低于 SSTORE。

### 4.2 封装层：MemeverseTransientState

`src/swap/libraries/MemeverseTransientState.sol` 将底层 `tstore`/`tload` 操作封装为类型安全的 library 函数，与 hook 业务逻辑解耦。

**存储槽位设计**：每个槽位通过 `keccak256("memeverse.transient.<key>") - 1` 推导，避免与持久化 storage 布局冲突，同时保持确定性寻址。

**导出函数**：

| 函数 | 方向 | 作用 |
|---|---|---|
| `storeSwapContext(feeBps, preSqrtPriceX96)` | 写入 | 一次性写入两个核心 swap 上下文值 |
| `loadSwapFeeBps()` | 读取 | 读取 effective fee bps |
| `loadPreSwapSqrtPriceX96()` | 读取 | 读取 swap 前的 sqrt price |
| `storeRequestedInputBudget(budget)` | 写入 | 写入请求的输入预算 |
| `loadRequestedInputBudget()` | 读取 | 读取请求的输入预算 |

### 4.3 传递的数据

Transient storage 在 `beforeSwap` 与 `afterSwap` 之间传递两项关键数据：

- **`feeBps`**：`_beforeSwap` 中通过动态费率报价（或 launch fee / base fee 降级路径）计算得到的 effective fee bps。`_afterSwap` 读取此值以拆分 LP fee 和 protocol fee，确保两个回调使用完全一致的费率。
- **`preSqrtPriceX96`**：`_beforeSwap` 开始时从 `PoolManager.getSlot0` 读取的 swap 前价格。`_afterSwap` 中 `updateDynamicStateAfterSwap` 读取此值，与 swap 后价格对比计算价格冲击（PIF），用于更新 EWVWAP、波动率偏差累加器、短期冲击状态和 per-address batch 累积。

此外，`storeRequestedInputBudget` / `loadRequestedInputBudget` 在 launch settlement 路径中用于传递输入预算。

### 4.4 完整流程

1. **`_beforeSwap` 阶段**：
   - 从 `PoolManager.getSlot0` 获取 `preSqrtPriceX96`。
   - 刷新波动率锚定价格与携带量（`refreshVolatilityAnchorAndCarry`）。
   - 通过 `quoteSwap` / `quoteSwapQuickReturn` / `quoteSwapBaseFee` 计算动态费率，得到 `dynamicFeeBps`。
   - 调用 `MemeverseTransientState.storeSwapContext(dynamicFeeBps, preSqrtPriceX96)`，将 feeBps 和 preSqrtPriceX96 写入 transient storage。
   - 对 exact-input 方向立即收取 input 侧费用（LP fee 和 protocol fee）。

2. **PoolManager 执行 swap**：核心 AMM 逻辑运行，价格移动。

3. **`_afterSwap` 阶段**：
   - 调用 `MemeverseHookLib.updateDynamicStateAfterSwap`，该函数内部通过 `MemeverseTransientState.loadPreSwapSqrtPriceX96()` 读取 pre-swap 价格，与 post-swap 价格对比更新 EWVWAP 和冲击状态。
   - 通过 `MemeverseTransientState.loadSwapFeeBps()` 读取 feeBps，拆分为 LP fee bps 和 protocol fee bps。
   - 对 exact-output 方向，基于实际成交金额收取 input 侧 LP fee 和 protocol fee；对 exact-input + output 侧 protocol fee 的场景，从实际 output 中扣除 protocol fee。
   - Launch settlement 路径（`executeLaunchSettlement`）也使用相同的 transient storage 机制，在 settlement 完成后将上下文清零（`storeSwapContext(0, 0)`）。

### 4.5 安全属性

- Transient storage 的作用域为单笔交易，交易结束自动清除，无跨交易残留风险。
- 每次写入覆盖前值，同一交易内不存在数据竞争。
- Slot 通过 `keccak256 - 1` 推导，位于持久化 storage 布局之外，不会与常规 storage mapping 冲突。

## 5. 当前已知边界提醒

- swap 当前规则主路径为 launch fee 衰减加显式 `Launcher -> Hook` launch settlement。
- unlock 后的保护窗口是独立安全要求，不由 launch fee 或 launch settlement 替代。
- 受保护公开 swap 的恢复时刻锚定实际 `Locked -> Unlocked` 迁移调用时间，再加上 `unlockProtectionWindow`。
- 注册中心当前把 `durationDays/lockupDays` 按 180 秒测试日换算；分析时不要按自然日推断。
