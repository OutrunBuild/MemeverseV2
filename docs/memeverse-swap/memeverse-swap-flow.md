# Memeverse Swap 流程图

本文档聚焦当前 `swap`、`launch settlement` 与 LP 主路径的执行与资金流，不展开治理、部署与链下流程。
其中资金准备既可来自常规 approve 路径，也可来自 `*WithPermit2(...)`。

相关实现主要位于：

- `src/swap/MemeverseSwapRouter.sol`
- `src/swap/MemeverseUniswapHook.sol`

---

## 1. 总体交易执行流

```mermaid
flowchart TD
    A[用户调用 Router.swap / swapWithPermit2] --> B[Router 基础校验]
    B --> C[准备输入资金]
    C --> D[调用 PoolManager.swap]
    D --> E[Hook.beforeSwap]
    E --> F[执行动态费与启动期费率逻辑]
    F --> G[PoolManager 完成 swap]
    G --> H[Hook.afterSwap]
    H --> I[Router 做 minOut / maxIn 校验]
    I --> J[退款未使用 native 输入]
    J --> K[返回 BalanceDelta]
```

说明：

- 普通 swap 采用单路径结算。
- 交易要么成功结算，要么整笔回退。
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

## 3. Launch Settlement 特殊通道

```mermaid
sequenceDiagram
    participant L as Launcher
    participant R as Router
    participant H as Hook
    participant PM as PoolManager

    L->>R: swap(..., hookData=LAUNCH_SETTLEMENT_MARKER)
    R->>R: 校验 msg.sender == launchSettlementOperator
    R->>PM: swap(...)
    PM->>H: beforeSwap
    H->>H: 校验 sender == launchSettlementCaller
    H->>H: 应用固定 1% fee
    PM->>PM: 完成 launch settlement
    PM->>H: afterSwap
    H-->>R: 返回 delta
    R-->>L: 返回 BalanceDelta
```

说明：

- 这条路径不是普通用户路径。
- Router 与 Hook 各自做一层授权校验。
- 该路径固定总费 `1%`，不复用普通动态费结果。

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

- Permit2 只改变 ERC20 资金准备方式。
- 一旦资金到达 Router，后续业务语义与普通入口完全一致。
- native 资产仍通过 `msg.value` 处理，不经过 Permit2。

---

## 5. Add Liquidity 主路径

```mermaid
sequenceDiagram
    participant U as 用户
    participant R as Router
    participant H as Hook

    U->>R: addLiquidity(...)
    R->>R: 校验 deadline / minAmount / refundRecipient
    R->>R: 准备输入资金
    R->>H: addLiquidityCore(...)
    H->>H: 如有必要初始化池
    H->>H: 计算 full-range liquidity
    H->>H: mint LP token
    H-->>R: 返回 liquidity 与 delta
    R-->>U: 退回未使用 native 输入
    R-->>U: 返回 liquidity
```

---

## 6. Remove Liquidity 与 Claim Fee 主路径

```mermaid
flowchart TD
    A[用户调用 removeLiquidity / removeLiquidityWithPermit2] --> B[Router 校验 deadline 与最小输出]
    B --> C[Router 准备 LP token]
    C --> D[Hook.removeLiquidityCore]
    D --> E[销毁 LP 并返回底层资产]
    E --> F[Router 把资产发给 recipient]

    G[用户调用 claimFees] --> H[Router 透传到 Hook.claimFeesCore]
    H --> I[Hook 结算 pending fees]
    I --> J[把 fee 发给 recipient]
```

---

## 7. 超简版摘要

```mermaid
flowchart TD
    A[普通 swap] --> B[Router 校验]
    B --> C[Hook 动态费 + launch fee window]
    C --> D[成功则返回 delta，失败则回退]

    E[launch settlement] --> F[Router operator 校验]
    F --> G[Hook caller 校验]
    G --> H[固定 1% 结算]
```

一句话概括：

- 普通 swap：execute-or-revert，启动期靠费率衰减保护
- 特殊启动结算：双权限校验，固定 `1%` 费率
