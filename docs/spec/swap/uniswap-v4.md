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
- 池创建 (`createPoolAndAddLiquidity`) 为 `onlyLauncher` 门控，不对外暴露；这是有意设计，建池必须经 `Launcher -> Router`，再由 Hook 的 `poolInitializer` 授权 Router 完成初始化。`createPoolAndAddLiquidityWithPermit2` 已移除，池创建不再支持 Permit2 路径。
- Router 内部固定构造 pool key：`fee = DYNAMIC_FEE_FLAG`、`tickSpacing = 200`、`hooks = configured hook`。
- exact-output 强制 `amountInMaximum`；所有 swap 为 execute-or-revert。

`[代码已证]`

### 2.2 Core 引擎（Hook）

- `MemeverseUniswapHook` 负责：
 - 动态费计算与启动窗口费率下限
 - protocol fee 与 LP fee 归集
 - LP token per pool + fee per share 记账
 - `addLiquidityCore/removeLiquidityCore/claimFeesCore` 低层能力；其中 fee claim 执行入口是 `claimFeesCore(...)`，fee owner 由 `msg.sender` 推导，`recipient` 可指定，当前不支持 relayed/signature-based claim
- Hook 强制池约束：动态费 + tickSpacing=200。

`[代码已证]`

### 2.3 Launch settlement 显式结算通道

- 启动结算不再走 Router 特殊 `hookData` marker 分支。
- 当前设计是 `MemeverseLauncher -> MemeverseUniswapHook.executeLaunchSettlement(...)`。
- Hook 仅接受已绑定 launcher 的直接调用，并在内部自发起 `PoolManager.unlock/swap` 完成结算。
- 该路径固定总费 `1%`（100 bps）。

`[代码已证]`

## 3. 收费语义边界

- `LP fee` 永远在输入侧。
- `Protocol fee` 币种由 `supportedProtocolFeeCurrencies` 决定：输入侧优先，输入不支持再看输出侧。
- 若输入和输出都不在支持列表，swap 回退 `CurrencyNotSupported`。
- `PROTOCOL_FEE_RATIO_BPS = 3000`，即 `feeBps` 中 30% 归 protocol、70% 归 LP。

`[代码已证]`

## 4. 启动保护语义

- 当前普通 swap 路径为 execute-or-revert。
- 启动保护语义体现为 launch fee 衰减窗口与显式 launch settlement 结算通道。
- launch settlement 只消费 preorder 托管的 `uAsset`，不消费普通 genesis 本金；preorder 容量口径由 launcher 侧 `totalNormalFunds + totalLeveragedDebt` 决定。
- 解锁后的公开 swap 保护由 launcher 在 `Locked -> Unlocked` 迁移时写入各受保护池的 `publicSwapResumeTime`，再由 `hook.beforeSwap` 执行；未到该时间前，受保护 pair 的公开 swap 会被拒绝。
- `hook.beforeSwap` 负责 pool-level 公开 swap 恢复时点；launcher 还在 `changeStage()` 的 unlock settlement 同交易内用 `unlockSettlementActive` 暂时阻断普通外部赎回，避免结算中与 LP 提取并发。
- swap API 保持单路径结算语义。

## 5. LP 总量与零供给语义

- `cachedLpTotalSupply[poolId]` 追踪每池 LP token 真实总量，无 `MINIMUM_LIQUIDITY` 锁定，所有 LP token 均参与 fee 分配。
- `_activeLpSupplyForSwap`：`cachedLpTotalSupply == 0` 时 fallback 到 `poolManager.getLiquidity(poolId)`。
  - 两者均为 0 → 返回 0，允许零流动性 quote 语义正常执行。
  - 缓存为 0 但 pool liquidity > 0 → revert `NoActiveLiquidityShares`（不一致状态，不应出现）。
- LP 全部移除后：swap 走零流动性路径不 revert，但 `_collectLaunchSettlementInputFees` 检测到 `effectiveSupply == 0` 时 revert，因为没有 LP 可接收 fee 分配。
- 此行为与移除 `MINIMUM_LIQUIDITY` 前不同：之前 1000 单位永久锁定保证最小 supply，现在无此保证，零供给由上述 fallback 逻辑显式处理。

`[代码已证]`

## 6. 运维配置边界

- Hook owner 可改：
 - `treasury`
 - protocol fee 币种支持
 - `emergencyFlag`
 - `launcher`
 - `defaultLaunchFeeConfig`
- Launcher owner 配置 router / hook 时，必须同时校验 `router.hook()==hook`、`hook.launcher()==launcher`、`hook.poolInitializer()==router`；其中 launcher 侧 `memeverseUniswapHook` 是 write-once。
- Hook owner 在配置完成后仍可 retarget `launcher`；这是接受的同一 trust boundary 内配置权，不视为额外越权模型。
- Router 的 `hook/permit2` 为构造不可变参数。
- 建池可用性依赖五个配置不变量同时成立：`launcher.memeverseSwapRouter()==router`、`launcher.memeverseUniswapHook()==hook`、`router.hook()==hook`、`hook.launcher()==launcher`、`hook.poolInitializer()==router`；`Genesis -> Locked` 执行建池前会做 launch-time preflight 复核，避免配置漂移到运行建池时才失败。
- Launcher pause 不会直接阻断 `changeStage(...)` 驱动的建池，因为 `changeStage(...)` 不是 `whenNotPaused`；但 Hook `launcher` retarget、Router/Hook 指针不一致或 `poolInitializer` 漂移会阻断新池创建。

`[代码已证]`

## 7. 已知缺口与外部依赖

- Router 不发业务事件，索引主要依赖 Hook 事件与 token transfer。`[代码已证]`
- PoolManager 实例地址、Factory/部署策略属于部署环境，不在仓库固定。`[未知]`
