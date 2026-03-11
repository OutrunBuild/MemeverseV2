# Memeverse Swap 流程图

本文档聚焦当前 `swap` 主路径的执行与资金流，不展开 LP、claim fee、bootstrap 等其他路径。

相关实现主要位于：

- `src/verse/MemeverseSwapRouter.sol`
- `src/verse/MemeverseUniswapHook.sol`
- `src/libraries/MemeverseTransientState.sol`

---

## 1. 总体执行流

```mermaid
flowchart TD
    A[用户调用 Router.swap] --> B[Router 基础校验]
    B --> C{是否处于 anti-snipe 保护期?}

    C -- 否 --> D[直接进入真实 swap]
    D --> E[Hook.beforeSwap]
    E --> F[PoolManager.swap]
    F --> G[Hook.afterSwap]
    G --> H[Router 做 minOut / maxIn 校验]
    H --> I[退款未使用预算]
    I --> J[返回 executed = true]

    C -- 是 --> K[计算统一输入预算 inputBudget]
    K --> L[Router 调 quoteFailedAttempt]
    L --> L1{本 tx 是否已 request 过该 pool?}
    L1 -- 是 --> L2[直接拒绝]
    L1 -- 否 --> M[Router 准备这 1 份输入预算]
    M --> N[Router 调 requestSwapAttempt]
    N --> O{request 是否通过?}

    O -- 否 --> P[Hook 从 inputBudget 扣失败费]
    P --> Q[剩余预算退回 Router]
    Q --> R[Router 退回用户]
    R --> S[返回 executed = false]

    O -- 是 --> T[Hook arm ticket 并绑定 inputBudget]
    T --> U[Hook 把整份预算退回 Router]
    U --> V[Router 继续真实 swap]
    V --> E
```

---

## 2. 统一输入预算模型

保护期内不再区分“swap 预算”和“失败费预算”，而是统一成一份输入预算。

```mermaid
flowchart TD
    A[Router 进入保护期逻辑] --> B{交易类型}
    B -- exact-input --> C[inputBudget = abs(amountSpecified)]
    B -- exact-output --> D[inputBudget = amountInMaximum]

    C --> E{输入币是否为 native?}
    D --> E

    E -- 是 --> F[msg.value = inputBudget]
    E -- 否 --> G[Router 从用户 pull inputBudget ERC20]

    F --> H[requestSwapAttempt 使用这同一份预算]
    G --> H
```

说明：

- exact-input：总预算等于用户愿意支付的输入数量
- exact-output：总预算等于用户设置的 `amountInMaximum`
- 失败费与成功成交都从这同一份预算里结算
- exact-output 时，失败费按预计实际输入计费，`amountInMaximum` 只作为预算上限

---

## 3. 保护期失败路径资金流

```mermaid
sequenceDiagram
    participant U as 用户
    participant R as Router
    participant H as Hook
    participant T as Treasury
    participant L as Hook LP Accounting

    U->>R: swap(...)
    R->>R: 计算 inputBudget
    R->>H: quoteFailedAttempt(key, params, inputBudget)

    alt 输入币是 ERC20
        U->>R: transfer inputBudget
    else 输入币是 native
        U->>R: msg.value = inputBudget
    end

    R->>H: requestSwapAttempt(key, params, trader, inputBudget, refundRecipient)
    H->>H: _checkAntiSnipe(...)
    H->>H: 判定失败

    alt 输入币属于支持的 protocol fee 币种
        H->>T: failureFeeAmount
    else 输入币不属于支持的 protocol fee 币种
        H->>L: failureFeeAmount 记入 LP fee per share
    end

    H-->>R: 返回剩余预算
    R-->>U: 退回 inputBudget - failureFeeAmount
    R-->>U: executed = false, reason = ...
```

说明：

- 失败时不会执行真实 swap
- 失败费统一从输入侧收
- 输入币属于支持的 protocol fee 币种时，失败费全部归 `treasury`
- 否则失败费全部归 LP

---

## 4. 保护期成功路径资金流

```mermaid
sequenceDiagram
    participant U as 用户
    participant R as Router
    participant H as Hook
    participant PM as PoolManager

    U->>R: swap(...)
    R->>R: 计算 inputBudget
    R->>H: quoteFailedAttempt(key, params, inputBudget)

    alt 输入币是 ERC20
        U->>R: transfer inputBudget
    else 输入币是 native
        U->>R: msg.value = inputBudget
    end

    R->>H: requestSwapAttempt(key, params, trader, inputBudget, refundRecipient)
    H->>H: anti-snipe 判定通过
    H->>H: arm ticket(poolId, caller, params, inputBudget)
    H-->>R: 整份 inputBudget 原路返回

    R->>PM: unlock(...)
    PM->>H: beforeSwap
    H->>H: consume ticket
    H->>H: 读取并保存 requestedInputBudget
    H->>H: 计算正常动态费
    PM->>PM: 执行真实 swap
    PM->>H: afterSwap
    H->>H: 更新动态状态
    H->>H: exact-output 校验 actualInput <= requestedInputBudget
    H->>H: 结算正常动态费

    PM-->>R: delta
    R->>R: 校验 amountOutMinimum / amountInMaximum
    R-->>U: 退回 inputBudget 中未使用部分
    R-->>U: executed = true
```

说明：

- 成功时不收失败费
- 成功时只走正常 swap 动态费
- 未使用的输入预算会退回用户

---

## 5. 预算绑定到 ticket

成功 request 后，ticket 不仅绑定 `poolId + caller + params`，还绑定 `inputBudget`。

```mermaid
flowchart TD
    A[保护期内 request 成功] --> B[Hook arm ticket]
    B --> C[ticket 绑定: poolId + caller + params + inputBudget]
    C --> D[真实 swap 进入 beforeSwap]
    D --> E[consume ticket]
    E --> F[把 requestedInputBudget 写入 transient state]
    F --> G[afterSwap 读取 requestedInputBudget]
    G --> H{actualInput <= requestedInputBudget?}
    H -- 是 --> I[继续正常结算]
    H -- 否 --> J[revert InputBudgetExceeded]
```

这个绑定用于防止：

- 小预算 request
- 成功后拿大预算成交

尤其是 exact-output 路径，会在 `afterSwap` 用真实输入额做最终校验。

---

## 6. 失败费归属流向

```mermaid
flowchart LR
    A[保护期内失败] --> B{输入币属于支持的 protocol fee 币种?}
    B -- 是 --> C[失败费全部归 Treasury]
    B -- 否 --> D[失败费全部归 LP]

    C --> E[用户拿回剩余输入预算]
    D --> E
```

---

## 7. 超简版摘要

```mermaid
flowchart TD
    A[保护期外] --> B[直接 swap]
    B --> C[正常动态费]

    D[保护期内] --> E[先 requestSwapAttempt(inputBudget)]
    E --> F{是否失败?}
    F -- 是 --> G[从 inputBudget 扣 failureFee]
    G --> H[退回剩余预算]
    F -- 否 --> I[不收 failureFee]
    I --> J[继续真实 swap]
    J --> K[按正常动态费结算]
    K --> L[退回未使用预算]
```

一句话概括：

- 保护期外：直接正常 swap
- 保护期内：先用同一份输入预算请求 ticket
  - 失败：扣失败费，剩余退回
  - 成功：不扣失败费，继续真实 swap，按正常动态费结算
