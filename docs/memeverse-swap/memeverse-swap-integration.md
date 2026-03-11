# Memeverse Swap 集成说明

本文档面向前端、路由层、SDK 与第三方集成方，说明如何使用：

- `MemeverseSwapRouter`
- `MemeverseSwapRouter.quoteSwap`
- `MemeverseSwapRouter` 的可选 Permit2 入口

完成 Memeverse 池子的报价、下单、soft-fail 处理与 exact-output 保护。

当前推荐的分层是：

- `MemeverseSwapRouter`：公开 Periphery / 统一入口
- `MemeverseUniswapHook`：Core 引擎 / 低层 API
- `PoolBootstrapLib`：启动期 bootstrap 工具库

推荐理解为：

- **普通集成方 / 链上 SDK：只认 `MemeverseSwapRouter`**
- **高级集成方 / 自定义 Router：可直接接 `MemeverseUniswapHook` 的 Core API**

另外还有一个重要运维约束：

- `treasury` 必须是**被动收款地址**
- 如果 protocol fee 可能以 native 支付，`treasury` 必须能正常收 ETH
- `treasury` 的 `receive()` / `fallback()` 不得继续触发 swap、加减流动性或其他重入式链上交易逻辑

换句话说，推荐把 `treasury` 设为 EOA 或简单多签，而不是复杂业务合约。

---

## 1. 总体架构

当前推荐的交易入口不是直接调用 `PoolManager.swap`，而是调用：

- `MemeverseSwapRouter.swap(...)`

同样，当前推荐的 LP 入口也不是直接调用 Hook Core，而是调用：

- `MemeverseSwapRouter.addLiquidity(...)`
- `MemeverseSwapRouter.removeLiquidity(...)`
- `MemeverseSwapRouter.claimFees(...)`
- 可选：对应 `*WithPermit2(...)` 入口

原因：

1. 在 anti-snipe 窗口内，Router 会先走一次 anti-snipe attempt 流程
2. soft-fail 时，Router 会返回成功结果，但不会真的执行 swap
3. anti-snipe 窗口外，Router 会自动跳过 attempt 流程，直接执行真实 swap
4. exact-output 的 `amountInMaximum` 保护也在 Router 这一层生效

换句话说：

- anti-snipe 期内：`Recommended Router -> requestSwapAttempt -> swap`
- anti-snipe 期外：`Router -> swap`

用户视角始终是一笔原子交易。

这里的关键点是：

- `MemeverseSwapRouter` 仍然是**推荐公开入口**
- 但 `requestSwapAttempt(...)` 本身已经是 **permissionless anti-snipe primitive**
- 所以第三方自定义 Router / 聚合器也可以先请求 ticket，再在同一笔交易里执行真实 swap
- 在 anti-snipe 保护期内，同一笔交易对同一个 pool 只允许 request 一次

这一点非常重要：

- same-pool tx 锁限制的是 **request 次数**
- 不是单纯限制最终成功的 swap 次数
- 目的在于阻止同 tx 内通过重复 request 去 grind `gasleft()` / `currentAttempts`

---

## 2. 当前最终收费语义

### 2.1 LP fee

- `LP fee` 永远在 **输入币** 上收取
- 不会因为协议收费币配置变化而改变结算币种

### 2.2 Protocol fee

- 协议支持同时配置多种 protocol fee 币种，币种既可以是 ERC20，也可以是 native
- 每一笔 swap 会优先检查输入币是否属于支持列表
- 如果输入币不在支持列表，再检查输出币是否属于支持列表
- 如果输入/输出都不在支持列表，swap 会视为配置错误并失败
- 如果输入/输出都在支持列表，则优先按输入币收 protocol fee
- `treasury` 必须只是收款方，不应在收款回调里继续发起交易

### 2.3 两者是分开结算的

不要把手续费理解成“一笔 total fee 全在同一个币种收”。

正确理解是：

- `LP fee`：输入侧
- `Protocol fee`：协议收费币侧

### 2.4 anti-snipe 保护期内的失败费语义

保护期内如果 attempt 失败：

- 不会执行真实 swap
- 但会额外收取一笔**输入侧失败费**
- 这笔失败费的费率等级与当前动态费率一致
- 如果输入币属于支持的 protocol fee 币种，则失败费全部归 `treasury`
- 否则失败费全部归 LP
- exact-output 时，这笔失败费按当前报价下的预计实际输入计算，而不是直接按 `amountInMaximum` 计算

成功 attempt 不收这笔失败费；成功成交时仍按正常 swap 动态费语义结算。

这两部分费率都来自同一个动态费率 `feeBps`，但结算币种和结算时机可能不同。

---

## 3. 关键接口

### 3.1 Router 交易入口

```solidity
function swap(
    PoolKey calldata key,
    SwapParams calldata params,
    address recipient,
    address nativeRefundRecipient,
    uint256 deadline,
    uint256 amountOutMinimum,
    uint256 amountInMaximum,
    bytes calldata hookData
) external payable returns (
    BalanceDelta delta,
    bool executed,
    AntiSnipeFailureReason failureReason
)
```

参数含义：

- `key`：池子 key
- `params`：Uniswap v4 swap 参数
- `recipient`：最终接收输出币的地址
- `nativeRefundRecipient`：接收未使用原生币退款的地址；如果本次调用附带了 `msg.value`，这里必须传一个可收 ETH 的地址
- `deadline`：过期时间
- `amountOutMinimum`：
  - exact-input 时用于最小输出保护
  - exact-output 时通常可传 `0`
- `amountInMaximum`：
  - exact-input 时可传 `0`
  - exact-output 时必须传
- `hookData`：透传给 hook 的额外数据，目前通常可传空

返回值含义：

- `delta`：最终 swap delta
- `executed`：
  - `true`：真实执行了 swap
  - `false`：触发 anti-snipe soft-fail，没有执行 swap
- `failureReason`：
  - `executed == false` 时返回 soft-fail 原因
  - `executed == true` 时通常是 `None`

---

### 3.2 Router 报价入口

```solidity
function quoteSwap(PoolKey calldata key, SwapParams calldata params)
    external
    view
    returns (SwapQuote memory quote);
```

保护期内如果需要预估失败费，还可以调用：

- `MemeverseSwapRouter.quoteFailedAttempt(...)`

当前推荐把 Router 视为统一公开入口：

- `MemeverseSwapRouter.quoteSwap(...)`
- `MemeverseSwapRouter.swap(...)`
- `MemeverseSwapRouter.swapWithPermit2(...)`
- `MemeverseSwapRouter.addLiquidity(...)`
- `MemeverseSwapRouter.addLiquidityWithPermit2(...)`
- `MemeverseSwapRouter.removeLiquidity(...)`
- `MemeverseSwapRouter.removeLiquidityWithPermit2(...)`
- `MemeverseSwapRouter.claimFees(...)`
- `MemeverseSwapRouter.createPoolAndAddLiquidity(...)`
- `MemeverseSwapRouter.createPoolAndAddLiquidityWithPermit2(...)`

Hook 的 `quoteSwap(...)` 仍然存在，但更适合作为 Core 层能力。

对所有可能附带 `msg.value` 的 Router 入口，还应额外注意：

- `swap(...)`：显式传 `nativeRefundRecipient`
- `addLiquidity(...)`：显式传 `nativeRefundRecipient`
- `createPoolAndAddLiquidity(...)`：显式传 `nativeRefundRecipient`

另外，当前 Hook 体系下：

- `addLiquidity(...)` / `removeLiquidity(...)` 不再要求用户传 `fee`
- 这些 LP 入口内部固定作用于 `LPFeeLibrary.DYNAMIC_FEE_FLAG` 对应的动态费池
- 也就是说，当前 Memeverse Hook 不存在“同一套 Router/Hook Core 还能再操作非动态费池”的公开语义

这样即使调用方本身是 non-payable contract，也不会因为退款失败而把 soft-fail / LP 操作整笔回滚。

同理，Hook 还保留：

- `addLiquidityCore(...)`
- `removeLiquidityCore(...)`
- `claimFeesCore(...)`

这些低层接口主要面向：

- 官方 Router、其他链上自定义 Router / 聚合器
- 高级集成场景

其中 `requestSwapAttempt(...)` 现在也是开放式能力：

- 不需要 Router 白名单
- 但必须满足：**同一笔交易、同一个 caller、同一组 SwapParams**
- 否则请求到的 transient ticket 无法被真实 swap 消费

换句话说：

- `MemeverseSwapRouter` = **Recommended Public Entry Points**
- `MemeverseUniswapHook` 的 Core 接口 = **Low-level Core APIs**

### 3.3 Permit2 入口要点

Permit2 入口是并行路径，不替代现有 approve 路径。集成时应注意：

- `permit2()` 可用于确认 Router 绑定的 Permit2 合约地址
- `swapWithPermit2(...)` / `addLiquidityWithPermit2(...)` / `removeLiquidityWithPermit2(...)` / `createPoolAndAddLiquidityWithPermit2(...)` 只负责签名拉资
- Permit2 拉资后，deadline、slippage、anti-snipe 判定与普通入口一致
- native 资产仍走 `msg.value` 与 `nativeRefundRecipient`，不经过 Permit2
- witness 签名必须使用 Permit2 规范类型串：`<WitnessType> witness)<WitnessType>(...)TokenPermissions(address token,uint256 amount)`，且 `witness` 取 `keccak256(abi.encode(WITNESS_TYPEHASH, ...业务字段))`
- 签名里的 `spender` 必须是 Router 地址（Permit2 校验时的 `msg.sender`），并且 `transferDetails.to` 必须是 Router（`address(this)`）

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
  - Protocol fee 金额
  - 永远在协议收费币侧计价

### 4.3 侧别字段

- `protocolFeeOnInput`
  - `true`：protocol fee 在输入侧收
  - `false`：protocol fee 在输出侧收

---

## 5. exact-input 集成方式

### 5.1 用户语义

exact-input 即：

- 用户指定“我最多就付这么多输入”
- 输出数量由池子和手续费决定

在 v4 里通常体现为：

- `params.amountSpecified < 0`

### 5.2 推荐流程

1. 调用 `quoteSwap`
2. 用以下字段展示报价：
   - `estimatedUserOutputAmount`
   - `estimatedLpFeeAmount`
   - `estimatedProtocolFeeAmount`
3. 调用 `router.swap(...)`
4. `amountInMaximum` 传 `0`

### 5.3 前端重点展示

对 exact-input，最值得展示的是：

- 用户支付输入：`abs(params.amountSpecified)`
- 用户净到手：`estimatedUserOutputAmount`
- LP fee 金额：`estimatedLpFeeAmount`
- protocol fee 金额：`estimatedProtocolFeeAmount`
- protocol fee 是否输入侧：`protocolFeeOnInput`

---

## 6. exact-output 集成方式

### 6.1 用户语义

exact-output 即：

- 用户指定“我最终一定要拿到多少输出”
- 愿意多付一点输入，但要受到上限保护

在 v4 里通常体现为：

- `params.amountSpecified > 0`

### 6.2 推荐流程

1. 调用 `quoteSwap`
2. 使用：
   - `estimatedUserOutputAmount`
   - `estimatedUserInputAmount`
3. 调用 `router.swap(...)`
4. 将 `amountInMaximum` 设置为：
   - 默认：`preview.estimatedUserInputAmount`
   - 或者在此基础上叠加额外用户滑点容忍

### 6.3 为什么必须传 `amountInMaximum`

因为 exact-output 时，最终真实输入需要：

- 先算出池子的基础输入
- 再叠加输入侧手续费

所以如果没有 `amountInMaximum`，用户就没有明确的最大支付边界。

Router 会在最终结算阶段校验：

- `actualInputAmount <= amountInMaximum`

否则整笔交易回滚。

---

## 7. soft-fail 处理方式

anti-snipe 窗口内，如果交易没有通过 attempt 检查：

- Router 不会 revert
- Router 会返回：
  - `executed = false`
  - `failureReason = ...`
- 真实 swap 不会执行
- 用户可能被收取一笔保护期输入侧失败费
- 动态费状态不变
- 但 `attempts + 1`

如果这笔调用附带了 native input：

- Router 会把未使用的 native 退给 `nativeRefundRecipient`
- 因此合约调用方不应该默认把退款地址写成自己，除非它本身可收 ETH

### 前端建议处理

如果返回：

- `executed == false`

就提示用户：

- 当前处于 launch anti-snipe 保护窗口
- 本次尝试未成交
- 可以稍后重试

不应把它当作链上错误处理。

但如果是**同 tx 内对同一个 pool 重复 request**，当前设计会把它视为无效流程并直接拒绝，而不是作为新的 soft-fail attempt。

---

## 8. anti-snipe 窗口内外差异

### anti-snipe 窗口内

推荐官方 Router 时，会：

1. 先通过 `quoteFailedAttempt(...)` 估算保护期失败费预算
2. 再调用 hook 的 `requestSwapAttempt(...)`
2. 如果通过，再继续真实 swap
3. 如果失败，soft-fail 成功返回，并扣除失败费

如果你使用自定义 Router，则也应遵守同样流程：

1. 先调用 hook 的 `requestSwapAttempt(...)`
2. 在**同一笔交易**里，由**同一个 Router 地址**继续执行真实 swap
3. 真实 swap 使用的 `SwapParams` 必须与 request 时完全一致

### anti-snipe 窗口外

Router 会：

- 直接执行真实 swap
- 不再记录 attempts

前端不需要为这两种模式写两套流程；统一调用 Router 即可。

---

## 9. 推荐前端交互模板

### exact-input

1. 用户输入：
   - input amount
   - 方向
2. 前端构造 `SwapParams`
3. 调 `quoteSwap`
4. 展示：
   - 净到手输出
   - LP fee
   - protocol fee
5. 调 `router.swap(..., amountInMaximum = 0, ...)`

### exact-output

1. 用户输入：
   - target output amount
   - 方向
2. 前端构造 `SwapParams`
3. 调 `quoteSwap`
4. 展示：
   - 建议最大输入
   - LP fee
   - protocol fee
5. 用 `estimatedUserInputAmount` 作为默认值
6. 调 `router.swap(..., amountInMaximum, ...)`

---

## 10. 常见失败原因

### 10.1 `executed == false`

代表：

- anti-snipe soft-fail
- 不是 revert

这时重点看：

- `failureReason`

### 10.2 revert：`AmountInMaximumRequired`

代表：

- exact-output 没传 `amountInMaximum`

### 10.3 revert：`InputAmountExceedsMaximum`

代表：

- exact-output 最终所需输入超过了用户给的上限

### 10.4 revert：`CurrencyNotSupported`

代表：

- 当前池子并不包含全局配置的协议收费币

---

## 11. 当前最推荐的前端策略

### 默认策略

- 所有交易都统一走 `quoteSwap -> router.swap`
- exact-output 默认使用：
  - `amountInMaximum = preview.estimatedUserInputAmount`

### 更稳健策略

- exact-output 时，在 `estimatedUserInputAmount` 之上再留一层前端风控 buffer
- 同时给用户明确展示：
  - 预计净到手
  - 预计总支付
  - LP fee
  - protocol fee

---

## 12. 一句话总结

如果你是前端或 SDK 集成方，最简单的接法就是：

- **报价：** 调 `quoteSwap`
- **下单：** 调 `MemeverseSwapRouter.swap`
- **soft-fail：** 看 `executed == false`
- **exact-output：** 用 `estimatedUserInputAmount`
- **保护期内：** 牢记同一笔交易对同一个 pool 只能 request 一次
