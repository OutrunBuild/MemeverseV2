# MemeverseV2 集成边界：Uniswap v4

## 1. 范围

本文描述 Memeverse 与 Uniswap v4 的集成边界（Router/Hook/PoolManager）。  
标签：

- `[代码已证]`
- `[未知]`

## 2. 组件边界

### 2.1 Periphery（推荐公开入口）

- `MemeverseSwapRouter` 负责对外 `quote/swap/liquidity/claimFees` 与可选 Permit2 拉资。
- Router 内部固定构造 pool key：`fee = DYNAMIC_FEE_FLAG`、`tickSpacing = 200`、`hooks = configured hook`。
- exact-output 强制 `amountInMaximum`；所有 swap 为 execute-or-revert。

`[代码已证]`

### 2.2 Core 引擎（Hook）

- `MemeverseUniswapHook` 负责：
 - 动态费计算与启动窗口费率下限
 - protocol fee 与 LP fee 归集
 - LP token per pool + fee per share 记账
 - `addLiquidityCore/removeLiquidityCore/claimFeesCore` 低层能力
- Hook 强制池约束：动态费 + tickSpacing=200。

`[代码已证]`

### 2.3 Launch settlement 特殊通道

- Router 识别特定 `hookData` marker，仅 `launchSettlementOperator` 可走该通道。
- Hook 再次校验 `sender == launchSettlementCaller`。
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
- 启动保护语义体现为 launch fee 衰减窗口与 launch settlement 特权通道。
- swap API 保持单路径结算语义。

## 5. 运维配置边界

- Hook owner 可改：
 - `treasury`
 - protocol fee 币种支持
 - `emergencyFlag`
 - `launchSettlementCaller`
 - `defaultLaunchFeeConfig`
- Router 的 `hook/permit2/launchSettlementOperator` 为构造不可变参数。

`[代码已证]`

## 6. 已知缺口与外部依赖

- Router 不发业务事件，索引主要依赖 Hook 事件与 token transfer。`[代码已证]`
- PoolManager 实例地址、Factory/部署策略属于部署环境，不在仓库固定。`[未知]`
