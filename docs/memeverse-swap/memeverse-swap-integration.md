# Memeverse Swap 集成说明

本文档面向前端、路由层、SDK 与第三方集成方，说明如何使用：

- `MemeverseSwapRouter`
- `MemeverseSwapRouter.quoteSwap(...)`
- `MemeverseSwapRouter` 的可选 Permit2 入口

完成 Memeverse 池子的报价、下单、LP 管理与 fee claim。

当前推荐的分层是：

- `MemeverseSwapRouter`：公开 Periphery / 统一入口
- `MemeverseUniswapHook`：Core 引擎 / 低层 API
- 启动期建池与首笔流动性：收敛到 `MemeverseSwapRouter.createPoolAndAddLiquidity(...)`

推荐理解为：

- **普通集成方 / 链上 SDK：只认 `MemeverseSwapRouter`**
- **高级集成方 / 自定义 Router：可直接接 `MemeverseUniswapHook` 的 Core API**

另外还有一个重要运维约束：

- `treasury` 必须是**被动收款地址**
- swap 栈的 protocol fee settlement currency 只允许 ERC20
- `treasury` 的 `receive()` / `fallback()` 不得继续触发 swap、加减流动性或其他重入式链上交易逻辑

---

## 1. 总体架构

当前推荐的交易入口不是直接调用 `PoolManager.swap`，而是调用：

- `MemeverseSwapRouter.swap(...)`

同样，当前推荐的 LP 入口也不是直接调用 Hook Core，而是调用：

- `MemeverseSwapRouter.addLiquidity(...)`
- `MemeverseSwapRouter.removeLiquidity(...)`
- `MemeverseSwapRouter.claimFees(...)`
- `MemeverseSwapRouter.createPoolAndAddLiquidity(...)`
- 可选：对应 `*WithPermit2(...)` 入口

原因：

1. Router 统一处理 `deadline`、`amountOutMinimum`、`amountInMaximum`
2. Router 对 swap 栈执行 fail-close 输入约束：任一侧为 `address(0)` 直接 `revert NativeCurrencyUnsupported`
3. Router 提供 pair 级 helper，如 `lpToken(...)`、`quoteAmountsForLiquidity(...)`
4. Router 保持纯公开 surface；启动结算由 Launcher 直接走 Hook 显式路径，普通集成方无需感知专用 settlement 接线

当前普通 swap 语义是：

- 所有 swap 都是 execute-or-revert
- 公开交易入口集中在 Router

如果需要直接接入 Hook，应把它理解为：

- `MemeverseSwapRouter` = **Recommended Public Entry Points**
- `MemeverseUniswapHook` 的 Core 接口 = **Low-level Core APIs**

---

## 2. 当前最终收费语义

### 2.1 LP fee

- `LP fee` 永远在 **输入币** 上收取
- 不会因为协议收费币配置变化而改变结算币种

### 2.2 Protocol fee

- swap 栈的 protocol fee settlement currency 只允许 ERC20
- 每一笔 swap 会优先检查输入币是否属于支持列表
- 如果输入币不在支持列表，再检查输出币是否属于支持列表
- 如果输入/输出都不在支持列表，swap 会视为配置错误并失败
- 如果输入/输出都在支持列表，则优先按输入币收 protocol fee
- `treasury` 必须只是收款方，不应在收款回调里继续发起交易

### 2.3 两者是分开结算的

正确理解是：

- `LP fee`：输入侧
- `Protocol fee`：由支持列表决定，输入侧优先

### 2.4 启动期收费语义

当前启动期保护语义是：

- 普通路径：`launch fee window` 费率衰减
- 特殊路径：`MemeverseLauncher -> MemeverseUniswapHook.executeLaunchSettlement(...)` 固定 `1%`

---

## 3. 关键接口

### 3.1 Router 交易入口

```solidity
function swap(
    PoolKey calldata key,
    SwapParams calldata params,
    address recipient,
    uint256 deadline,
    uint256 amountOutMinimum,
    uint256 amountInMaximum,
    bytes calldata hookData
) external returns (BalanceDelta delta);
```

参数含义：

- `key`：池子 key
- `key.currency0` / `key.currency1` 必须都是 ERC20；任一侧为 `address(0)` 直接 `revert NativeCurrencyUnsupported`
- `params`：Uniswap v4 swap 参数
- `recipient`：最终接收输出币的地址
- `deadline`：过期时间
- `amountOutMinimum`：
  - exact-input 时用于最小输出保护
  - exact-output 时通常可传 `0`
- `amountInMaximum`：
  - exact-input 时可传 `0`
  - exact-output 时必须传
- `hookData`：透传给 hook 的额外数据；普通集成路径通常可传空，当前公开 Router 不再为 launch settlement 保留专用 marker

返回值含义：

- `delta`：最终 swap delta

返回值聚焦最终 `delta` 结算结果。

---

### 3.2 Router 报价入口

```solidity
function quoteSwap(PoolKey calldata key, SwapParams calldata params)
    external
    view
    returns (SwapQuote memory quote);
```

当前推荐把 Router 视为统一公开入口：

- `quoteSwap(...)`
- `previewClaimableFees(...)`
- `getHookPoolKey(...)`
- `lpToken(...)`
- `quoteAmountsForLiquidity(...)`
- `swap(...)`
- `swapWithPermit2(...)`
- `addLiquidity(...)`
- `addLiquidityWithPermit2(...)`
- `removeLiquidity(...)`
- `removeLiquidityWithPermit2(...)`
- `claimFees(...)`
- `createPoolAndAddLiquidity(...)`
- `createPoolAndAddLiquidityWithPermit2(...)`

对只知道 token pair、不想感知 `PoolKey` / Hook 细节的集成方，当前只读 helper 可以这样理解：

- `lpToken(tokenA, tokenB)`：返回该 pair 对应的 Hook LP token 地址
- `quoteAmountsForLiquidity(tokenA, tokenB, liquidityDesired)`：按当前池价返回目标 LP liquidity 需要的两侧 token 数量

---

### 3.3 Permit2 入口要点

Permit2 入口是并行路径，不替代现有 approve 路径。集成时应注意：

- `permit2()` 可用于确认 Router 绑定的 Permit2 合约地址
- `swapWithPermit2(...)` / `addLiquidityWithPermit2(...)` / `removeLiquidityWithPermit2(...)` / `createPoolAndAddLiquidityWithPermit2(...)` 只负责签名拉资
- Permit2 拉资后，deadline、slippage、Hook 语义与普通入口一致
- Permit2 只处理 ERC20；swap 栈不接受 native 资产，也不接受 `msg.value`
- 签名里的 `spender` 必须是 Router 地址，`transferDetails.to` 必须是 Router

---

## 4. `SwapQuote` 字段说明

`SwapQuote` 当前包含这些核心字段：

- `feeBps`
- `estimatedUserInputAmount`
- `estimatedUserOutputAmount`
- `estimatedProtocolFeeAmount`
- `estimatedLpFeeAmount`
- `protocolFeeOnInput`

### 4.1 输入/输出金额字段

- `estimatedUserInputAmount`
  - 用户最终总共要支付的输入数量
- `estimatedUserOutputAmount`
  - 用户最终净到手的输出数量

### 4.2 手续费字段

- `estimatedLpFeeAmount`
  - LP fee 金额
  - 永远在输入侧计价
- `estimatedProtocolFeeAmount`
  - protocol fee 金额
  - 输入币优先，输入不支持时再看输出币

### 4.3 `protocolFeeOnInput`

- `true`：本次 protocol fee 在输入侧收
- `false`：本次 protocol fee 在输出侧收

---

## 5. Launch Settlement 集成注意事项

- 这是启动结算专用通道，不是普通用户交易接口。
- 当前路径是 `MemeverseLauncher` 直接调用 `MemeverseUniswapHook.executeLaunchSettlement(...)`。
- Hook 侧要求 `msg.sender == launcher`。
- 该路径固定总费 `1%`。
- `MemeverseLauncher` 在接入 Router 时会校验 `router.hook().launcher() == launcher`。

普通集成方不应自行构造这条路径。

---

## 6. Hook Core 的定位

Hook 仍保留：

- `quoteSwap(...)`
- `addLiquidityCore(...)`
- `removeLiquidityCore(...)`
- `claimFeesCore(...)`

这些低层接口主要面向：

- 官方 Router
- 其他链上自定义 Router / 聚合器
- 高级集成场景

但应注意：

- 当前 Hook Core 只面向动态费池
- 普通集成方优先走 Router，而不是自己拼 `PoolManager.swap`

---

## 7. 最终理解方式

把当前 Memeverse Swap 理解成：

- `Router`：统一公开入口、预算与退款管理层
- `Hook`：动态费、启动期费率、LP 记账、协议收费引擎，以及显式 launch settlement 执行面
- `launch settlement`：`Launcher -> Hook` 的受限专用结算通道

其中普通交易、启动期费率、LP 记账和结算专用通道都在同一套 Router + Hook 语义下协同完成。
