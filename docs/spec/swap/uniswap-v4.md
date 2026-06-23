# MemeverseV2 集成边界：Uniswap v4

## 1. 范围

本文描述 Memeverse 与 Uniswap v4 的集成边界（Router/Hook/PoolManager）。  
标签：

- `[代码已证]`
- `[未知]`

## 2. 组件边界

### 2.1 Periphery（推荐公开入口）

- `MemeverseSwapRouter` 负责对外 `quote/swap/addLiquidity/removeLiquidity` 与可选 Permit2 拉资（swap 与流动性操作）。
- Router 的 `previewClaimableFees(...)` 仅是只读 preview-only helper，不执行 fee claim。
- Router 的 quote/preview 只读路径委托给构造绑定的 `MemeverseUniswapHookLens`；Lens 必须有代码，且 Lens `poolManager` 必须与 Router 构造注入的 PoolManager 一致。
- Router 的 ERC20 payout helper 对 `recipient == address(0)` fail-close；remove-liquidity 出款不会把资产发送到零地址。
- 池创建 (`createPoolAndAddLiquidity`) 为 `onlyLauncher` 门控，不对外暴露；这是有意设计，建池必须经 `Launcher -> Router`，由 `Launcher` 提供 desired budgets，再由 Router 执行实际建池与首笔加池。`createPoolAndAddLiquidityWithPermit2` 已移除，池创建不再支持 Permit2 路径。
- Router 对 bootstrap 的集成契约是“实际执行后返回 actual spend / actual liquidity”（非 preview-equality 契约）；Launcher 的 post-bootstrap accounting 与记账语义见 [docs/spec/verse/accounting.md](../verse/accounting.md) §3.2 与 [docs/spec/invariants.md](../invariants.md) INV-04；unused bootstrap `uAsset` 进入的 settlement dust reserve 结构与处置 home 在 [docs/spec/polend/core.md §6.7](../polend/core.md)。
- Router 内部固定构造 pool key（`fee = DYNAMIC_FEE_FLAG`、固定 `tickSpacing`、`hooks = configured hook`）；具体固定值与 Hook 侧约束见 [docs/spec/invariants.md](../invariants.md) INV-08（V23）。
- exact-output 强制 `amountInMaximum`；所有 swap 为 execute-or-revert（V10，见 §4）。

`[代码已证]`

### 2.2 Core 引擎（Hook）

- `MemeverseUniswapHook` 负责：
 - 动态费计算与启动窗口费率下限
 - protocol fee 与 LP fee 归集
 - LP token per pool + fee per share 记账
 - `addLiquidityCore/removeLiquidityCore/claimFeesCore` 低层能力；其中 fee claim 执行入口是 `claimFeesCore(...)`，fee owner 由 `msg.sender` 推导，`recipient` 可指定，当前不支持 relayed/signature-based claim
- `removeLiquidityCore(...)` 要求 `recipient != address(0)`，否则回退 `ZeroAddress()`（recipient 非零规则见 [docs/spec/invariants.md](../invariants.md) INV-07）。
- Hook 强制池约束（动态费 + 固定 `tickSpacing`）见 [docs/spec/invariants.md](../invariants.md) INV-08（V23）。

`[代码已证]`

### 2.3 Preorder settlement 显式结算通道

- 启动结算不再走 Router 特殊 `hookData` marker 分支。
- 当前设计是 `MemeverseLauncher -> MemeverseUniswapHook.executePreorderSettlement(...)`。
- Launcher bootstrap pool creation 采用集成契约“desired budgets -> actual Router spend -> post-bootstrap accounting”（Router 返回 actual spend）。
- bootstrap 记账语义、auxiliary underspend 处置见 [docs/spec/verse/accounting.md](../verse/accounting.md) §3.2 与 [docs/spec/invariants.md](../invariants.md) INV-04；unused bootstrap `uAsset` 进入的 settlement dust reserve 结构与处置 home 在 [docs/spec/polend/core.md §6.7](../polend/core.md)。
- Hook 仅接受已绑定 launcher 的直接调用（caller 约束完整规则见 [docs/spec/invariants.md](../invariants.md) INV-04），并将 `unlock/swap` 委托给无状态的 `MemeversePreorderSettlementExecutor`（constructor 期 immutable 绑定 hook proxy，`execute` 在 `msg.sender == HOOK` 守卫下自发起 unlock/swap/settle/take）完成结算。
- 该路径使用固定总费率（数值定义见 [docs/spec/verse/accounting.md §7.4](../verse/accounting.md)）。
- 进入该路径前，Launcher / POLend 的部署资金口径只统计 `totalNormalFunds + totalLeveragedDebt`，不统计 preorder，且该口径必须保持 `<= type(uint128).max`。

`[代码已证]`

## 3. 收费/币种/native 边界

本节是 swap 栈收费语义、币种配置与 native 拒绝规则的 canonical home。其它 swap 文档（`swap-flow.md`、`swap-integration.md`、`permit2.md`、`common/common-foundations.md`）只引用本节，不重述这些规则本体。

- `LP fee` 永远在输入侧。
- `Protocol fee` 币种由 `supportedProtocolFeeCurrencies` 决定：输入侧优先，输入不支持再看输出侧。
- 若输入和输出都不在支持列表，swap 回退 `CurrencyNotSupported`。
- Exact-output swap 若实际 gross output 小于请求输出，Hook 回退 `ExactOutputPartialFill()`。
- Exact-input swap 若实际 pool input 与预期不符，Hook 回退 `ExactInputPartialFill()`。
- `FeeMath.PROTOCOL_FEE_SHARE_BPS = 3500`；shared fee math 将 `feeBps` 按 35% protocol / 65% LP 拆分。
- 公开 swap 始终使用正常费率路径：`feeBps = max(current launch fee, dynamic fee, FEE_BASE_BPS)`；dynamic fee engine 故障通过升级/修复处理，不提供 bypass mode。
- 返佣（referral rebate）：普通 swap 可在 `hookData` 前 20 字节 packed 携带 referrer 地址（caller 用 `abi.encodePacked(referrer)`；`abi.encode` 会左 padding 导致 `MemeverseUniswapHook::_decodeReferrer` 误读，禁止使用）。有 referrer 时，protocol fee 在 `_collectProtocolFee` 内切出 rebate：`rebate = protocolFee × referrerRebateBps / PROTOCOL_FEE_SHARE_BPS`（默认 `referrerRebateBps = 1000` = 总 fee 的 10%），`toTreasury = protocolFee - rebate` 到 treasury，`rebate` 由 hook `poolManager.take(feeCurrency, address(engine), rebate)` 拉到 engine 地址（v4 `PoolManager.take` delta 记调用者 hook，被 beforeSwap specifiedDelta credit 抵消，token 进 engine custody），再调 `MemeverseDynamicFeeEngine::accrueRebate` 纯记账累加 `pendingRebate[referrer][currency]`（无 PoolManager 调用）。无 referrer 时不切 rebate，protocol 收全额 35%。rebate custody 在 engine（与 LP fee 在 hook 隔离）；referrer 经 `MemeverseDynamicFeeEngine::claimRebate` pull 领取（不经 hook）。preorder settlement 路径不携带 referrer，不参与返佣。**返佣按链独立**：每条链的 hook/engine 独立 settle / accrue / claim 该链 swap 的 rebate，无 LayerZero 同步、无跨链聚合、无全局 referrer 状态；referrer 在 A 链累积的 `pendingRebate` 只能在 A 链经 A 链的 engine `claimRebate` 领取，不能在 B 链领。
- `_decodeReferrer` 在 `_beforeSwap` 与 `_afterSwap` 各解码一次；4 个 `_collectProtocolFee` 调用点（exact-input `beforeSwap` input 侧、exact-input `afterSwap` output 侧、exact-output `afterSwap` input 侧、exact-output `afterSwap` output 侧）均传入 referrer。
- native 拒绝（V5）：swap 栈只支持 ERC20/ERC20 pair；`key.currency0` / `key.currency1` 任一侧为 `address(0)` 直接 `revert NativeCurrencyUnsupported`。swap 栈不接受 `msg.value`，Permit2 也不为 native 提供任何兜底路径。
- 非 standard 余额语义 token（fee-on-transfer / rebasing / 其它使名义 `amount` 与实到余额不一致的 token）不在支持范围内：swap 栈（含 preorder settlement 的 Executor 中转 hop）一律按名义 `amount` 执行 `transferFrom` / `settle` / `take`。FoT token 下 settle 因余额不足而整笔原子回滚，不产生资金损失；准入应排除此类 token，运行时不做 FoT 检测。

`[代码已证]`

## 4. 启动保护语义

- 当前普通 swap 路径为 execute-or-revert。
- 启动保护语义体现为 launch fee 衰减窗口与显式 preorder settlement 结算通道。
- preorder settlement 只消费 preorder 托管的 `uAsset`，不消费普通 genesis 本金；preorder 容量口径由 launcher 侧 `totalNormalFunds + totalLeveragedDebt` 决定。
- 解锁后的公开 swap 保护由 launcher 在 `Locked -> Unlocked` 迁移的 settlement 调用完成后写入各受保护池的 `publicSwapResumeTime`，再由 `hook.beforeSwap` 执行；hook-side public swap protection 在该写入后生效。
- `Locked -> Unlocked` 同交易 settlement 顺序与公开 swap 恢复时间写入约束见 [docs/spec/invariants.md](../invariants.md) INV-07A / INV-12（窗口数值见 [docs/spec/verse/config-matrix.md §3](../verse/config-matrix.md)）。
- swap API 保持单路径结算语义。

## 5. LP 总量与零供给语义

- `cachedLpTotalSupply[poolId]` 追踪每池 LP token 真实总量，无 `MINIMUM_LIQUIDITY` 锁定，所有 LP token 均参与 fee 分配。
- 加/减流动性路径在 LP token `mint` / `burn` 后直接同步 `cachedLpTotalSupply[poolId]`，保持缓存总量与实际 LP token supply 一致；不要求额外的一行转发 helper。
- swap 路径使用 `_activeLpSupplyForSwap` 作为有效 LP 供应量的业务入口：`cachedLpTotalSupply == 0` 时 fallback 到 `poolManager.getLiquidity(poolId)`。
  - 两者均为 0 → 返回 0，允许零流动性 quote 语义正常执行。
  - 缓存为 0 但 pool liquidity > 0 → revert `NoActiveLiquidityShares`（不一致状态，不应出现）。
- LP 全部移除后：swap 走零流动性路径不 revert，但 `_collectPreorderSettlementInputFees` 检测到 `effectiveSupply == 0` 时 revert，因为没有 LP 可接收 fee 分配。
- 此行为与移除 `MINIMUM_LIQUIDITY` 前不同：之前 1000 单位永久锁定保证最小 supply，现在无此保证，零供给由上述 fallback 逻辑显式处理。

`[代码已证]`

## 6. 运维配置边界

- Hook owner 可改：
 - `treasury`
 - protocol fee 币种支持
 - `launcher`
 - `defaultLaunchFeeConfig`
- Launcher owner 配置 router / hook 时的 set-time 三重校验与 launcher 侧 `memeverseUniswapHook` write-once 约束见 [docs/spec/invariants.md](../invariants.md) INV-04（权限视角见 [docs/spec/access-control.md](../access-control.md) §5）。
- Hook owner 在配置完成后仍可 retarget `launcher`；这是接受的同一 trust boundary 内配置权，不视为额外越权模型。
- Router 的 `hook/permit2` 为构造不可变参数。
- 建池可用性依赖 router/hook/launcher 五个配置指针同时一致（含 INV-04 三重校验），`Genesis -> Locked` launch-time preflight 复核与完整约束见 [docs/spec/invariants.md](../invariants.md) INV-04。
- Launcher pause 不会直接阻断 `changeStage(...)` 驱动的建池，因为 `changeStage(...)` 不是 `whenNotPaused`；但 Hook `launcher` retarget、Router/Hook 指针不一致或 `poolInitializer` 漂移会阻断新池创建。

`[代码已证]`

## 7. 已知缺口与外部依赖

- Router 不发业务事件，索引主要依赖 Hook 事件与 token transfer。`[代码已证]`
- PoolManager 实例地址、Factory/部署策略属于部署环境，不在仓库固定。`[未知]`
