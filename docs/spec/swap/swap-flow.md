# Memeverse Swap 流程图

本文档聚焦当前 `swap`、`preorder settlement` 与 LP 主路径的执行与资金流，不展开治理、部署与链下流程。
其中资金准备既可来自常规 approve 路径，也可来自 `*WithPermit2(...)`。

相关实现主要位于：

- `src/swap/MemeverseSwapRouter.sol`
- `src/swap/MemeverseUniswapHook.sol`

---

## 1. 总体交易执行流

```mermaid
flowchart TD
    A[用户调用 Router.swap / swapWithPermit2] --> B[Router 基础校验]
    B --> B1{currency0 或 currency1 是否为 address(0)?}
    B1 -- 是 --> BX[revert NativeCurrencyUnsupported]
    B1 -- 否 --> C[准备 ERC20 输入资金]
    C --> D[调用 PoolManager.swap]
    D --> E[Hook.beforeSwap]
    E --> F[执行动态费与启动期费率逻辑]
    F --> G[PoolManager 完成 swap]
    G --> H[Hook.afterSwap]
    H --> I[Router 做 minOut / maxIn 校验]
    I --> K[返回 BalanceDelta]
```

说明：

- 普通 swap 采用单路径结算，execute-or-revert（V10 定义见 [docs/spec/swap/uniswap-v4.md](uniswap-v4.md) §4）。
- swap 栈只支持 ERC20/ERC20 pair；native 拒绝规则（V5）与收费/币种边界见 [docs/spec/swap/uniswap-v4.md](uniswap-v4.md) §3。
- 启动期保护通过 Hook 内的 `launch fee window` 费率逻辑体现。

---

## 2. 启动期费率窗口

```mermaid
flowchart TD
    A[PoolInitialized] --> B[记录 poolLaunchTimestamp]
    B --> C{当前时间是否仍在 decayDurationSeconds 内?}
    C -- 是 --> D[使用 launch fee floor 约束]
    C -- 否 --> E[回到正常动态费 / 最小费逻辑]
```

说明：

- 新池初始化后会记录 `poolLaunchTimestamp`。
- 在衰减窗口内，fee 从 `startFeeBps` 逐步下降到 `minFeeBps`。
- 窗口结束后，回到常规动态费与最小费逻辑。

---

## 3. Preorder Settlement 显式通道

```mermaid
sequenceDiagram
    participant L as Launcher
    participant H as Hook
    participant E as Executor
    participant PM as PoolManager

    L->>H: executePreorderSettlement(params)
    H->>H: 校验 msg.sender == launcher
    H->>H: 计算固定 1% fee, 收取 input 费用
    H->>E: execute(params)
    E->>PM: unlock(...)
    PM->>E: unlockCallback(...)
    E->>PM: swap(..., hookData=ZERO_BYTES)
    PM-->>E: 返回 BalanceDelta
    E->>E: settle + take（含 output-side protocol fee）
    E-->>H: 返回 ExecuteResult
    H->>H: 更新动态费引擎状态
    H-->>L: 返回 adjustedDelta
```

说明：

- 这条路径不是普通用户路径。
- 启动结算不再经过 Router，也不再依赖特殊 `hookData` marker。
- Hook 将 unlock/swap 逻辑委托给 Executor 合约（constructor 时 immutable 绑定 hook proxy）执行；Executor 持有 unlock 回调上下文，负责 swap、settle、take 与 output-side protocol fee 扣减。
- 该路径使用固定总费（数值定义见 [docs/spec/verse/accounting.md §7.4](../verse/accounting.md)）；caller 约束见 [docs/spec/invariants.md](../invariants.md) INV-04。不复用普通动态费结果。
- **资金与 approve 路径**：Launcher 只需对 Hook 做一次 infinite approve。Hook 作为 `transferFrom` 的 spender，分别拉取 input 费用到自身/treasury 和 netInput 到 Executor；Executor 用自身余额直接 `transfer` 给 PoolManager，不需要任何 approve。详见 [docs/spec/swap/swap-integration.md §5.1](swap-integration.md)。

---

## 4. Permit2 并行资金流

```mermaid
flowchart TD
    A[用户调用 swapWithPermit2 / addLiquidityWithPermit2 / removeLiquidityWithPermit2] --> B[Router 校验 Permit2 payload]
    B --> C[Permit2 将 ERC20 拉到 Router]
    C --> D[进入普通 Router 执行逻辑]
    D --> E[swap / addLiquidity / removeLiquidity]
```

说明：

- Permit2 只改变 ERC20 资金准备方式；Permit2 入口语义（V6）见 [docs/spec/swap/permit2.md](permit2.md)。
- 一旦资金到达 Router，后续业务语义与普通入口完全一致。
- native 拒绝（V5）见 [docs/spec/swap/uniswap-v4.md](uniswap-v4.md) §3。

---

## 5. Add Liquidity 主路径

```mermaid
sequenceDiagram
    participant U as 用户
    participant R as Router
    participant H as Hook

    U->>R: addLiquidity(...)
    R->>R: 校验 deadline / minAmount / pair 为 ERC20/ERC20
    R->>R: 准备 ERC20 输入资金
    R->>R: 要求目标 pool 已预先完成初始化
    R->>H: addLiquidityCore(...)
    H->>H: 计算 full-range liquidity
    H->>H: mint LP token
    H-->>R: 返回 liquidity 与 delta
    R-->>U: 返回 liquidity
```

说明：

- `addLiquidity(...)` / `addLiquidityCore(...)` 不负责初始化 pool，调用前目标 pool 必须已经存在且已初始化。
- 初始建池路径为 `Launcher -> Router.createPoolAndAddLiquidity(...)`。
- bootstrap 由 `Launcher` 先给出 desired budgets，再由 Router 执行 `createPoolAndAddLiquidity(...)`；对外记账真源是实际执行后的 actual spend / actual liquidity。

### 5.1 Bootstrap Execution

- 集成契约：Router 从 Launcher 提交的 desired budgets 执行 `createPoolAndAddLiquidity(...)`，并把 actual spend / actual liquidity 返回给 Launcher 做后续 accounting（bootstrap 不返回 preview-equality 结果）。
- 四池 bootstrap 的记账语义、`memecoin/uAsset` 主池 PT backing ratio 口径、auxiliary underspend 处置、unused bootstrap `uAsset` / `memecoin` 处置见 [docs/spec/verse/accounting.md](../verse/accounting.md) §3.2 与 [docs/spec/invariants.md](../invariants.md) INV-04；PT backing ratio 的记录与 split 操作语义 home 在 [docs/spec/polend/pt-yt-splitter.md §1](../polend/pt-yt-splitter.md)，不变量锚点见 [docs/spec/invariants.md](../invariants.md) INV-14 / INV-19；unused bootstrap `uAsset` 进入的 settlement dust reserve 结构与处置 home 在 [docs/spec/polend/core.md §6.7](../polend/core.md)，该 reserve 与杠杆侧 PT fee 预兑付的关联见 [docs/spec/polend/settlement-and-fees.md §5](../polend/settlement-and-fees.md)。

---

## 6. Remove Liquidity 与 Claim Fee 主路径

```mermaid
flowchart TD
    A[用户调用 removeLiquidity / removeLiquidityWithPermit2] --> B[Router 校验 deadline 与最小输出]
    B --> C[Router 准备 LP token]
    C --> D[Hook.removeLiquidityCore]
    D --> E[销毁 LP 并返回底层资产]
    E --> F[Router 校验 recipient 非零并把资产发给 recipient]

    G[fee owner 调用 Hook.claimFeesCore] --> H[Hook 由 msg.sender 推导 owner]
    H --> I[Hook 结算 pending fees]
    I --> J[校验 recipient 非零后把 fee 发给 recipient]
```

说明：

- 上图中两条路径的 `recipient` 非零 fail-close 规则（V7）见 [docs/spec/invariants.md](../invariants.md) INV-07，不在本文档重述。

---

## 7. 超简版摘要

```mermaid
flowchart TD
    A[普通 swap] --> B[Router 校验]
    B --> C{存在 EWVWAP 历史且交易回归 EWVWAP?}
    C -- 是 --> C1[跳过全部动态费组件<br/>effectiveFee = max(baseFee, launchFee)]
    C -- 否 --> C2[Hook 动态费<br/>adverse per-address + vol per-pool + short per-pool<br/>取 max(dynamicFee, launchFee)]
    C1 --> D[成功则返回 delta，失败则回退]
    C2 --> D

    E[preorder settlement] --> F[Launcher 调 Hook.executePreorderSettlement]
    F --> G[Hook 校验 launcher 绑定 + 收取 input 费用]
    G --> H[Executor 执行 unlock/swap/take]
    H --> I[固定 1% 结算]
```

一句话概括：

- 普通 swap：execute-or-revert，启动期靠费率衰减保护
- 特殊启动结算：显式 `Launcher -> Hook -> Executor`，固定费率（数值见 [docs/spec/verse/accounting.md §7.4](../verse/accounting.md)）
