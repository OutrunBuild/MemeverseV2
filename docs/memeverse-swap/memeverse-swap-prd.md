# Memeverse Swap PRD

## 1. 文档定位

本文档从产品与业务语义角度描述当前 `MemeverseSwapRouter` 与 `MemeverseUniswapHook` 的设计目标、角色边界、核心规则、资金流、配置项、约束条件与验收标准。

本文档描述的是**当前实现对应的产品逻辑**，不是未来规划稿。

---

## 2. 执行摘要

Memeverse Swap 是一套面向 memecoin 池子的交易与流动性管理系统，核心特征包括：

- 使用 `MemeverseSwapRouter` 作为推荐公开入口
- 使用 `MemeverseUniswapHook` 作为 Core 规则引擎
- 支持可选 Permit2 并行入口（不替代常规 approve 路径）
- 支持启动期 anti-snipe 保护
- 支持动态手续费
- 支持保护期失败费
- 支持多协议费币种（ERC20 / native）
- 使用统一输入预算模型处理保护期成功/失败路径
- 对 LP 和 Treasury 进行可持续 fee 分配

一句话概括：

> 保护期外像普通动态费 DEX；保护期内先做 permissionless anti-snipe attempt，同一笔交易对同一个 pool 只能 request 一次；失败时从同一份输入预算中收失败费，成功时继续真实 swap，并只按正常动态费结算。

---

## 3. 产品目标

### 3.1 核心目标

Memeverse Swap 旨在同时满足以下目标：

- 启动期反狙击保护
- 动态手续费
- 单笔原子交易体验
- 对外统一 Router 接入
- LP 可持续激励
- 协议可持续收费

### 3.2 设计原则

- 普通用户默认只面对 `MemeverseSwapRouter`
- Hook 负责规则、计费、状态更新与反狙击
- 启动期保护优先于极致可组合性
- 保护期外尽量接近常规 DEX 使用体验
- 失败尝试也应形成经济成本，而不是零成本刷 attempts

### 3.3 非目标

本 PRD 不重点展开以下内容：

- `PoolBootstrapLib` 的实现细节
- 部署脚本
- 前端 UI 细节
- 链下风控与运营流程

---

## 4. 角色与对象

### 4.1 普通交易用户

通过 Router 发起：

- exact-input 交易
- exact-output 交易
- add/remove liquidity
- claim LP fee
- 以上路径的可选 Permit2 资金入口

### 4.2 LP

向池子提供全范围流动性，并按份额获得：

- 正常 swap 的 LP fee
- 某些保护期失败费（当失败费不归 treasury 时）

### 4.3 协议财库 Treasury

接收：

- 正常 swap 中归协议的 protocol fee
- 保护期失败费中，输入币属于支持的 protocol fee 币种的那一部分

### 4.4 第三方 Router / 聚合器 / 链上 SDK

可以：

- 直接接入 `MemeverseSwapRouter`
- 或直接接入 Hook 的低层能力
- 在 anti-snipe 窗口内 permissionless 调用 `requestSwapAttempt(...)`

### 4.5 协议 Owner

负责：

- 设置 treasury
- 设置 protocol fee 币种支持列表
- 设置 anti-snipe duration
- 设置 emergency flag

---

## 5. 模块职责

### 5.1 `MemeverseSwapRouter`

Router 是推荐公开入口，负责：

- 对外统一交易入口
- exact-output 的 `amountInMaximum` 保护
- `amountOutMinimum` / `deadline` 检查
- 提供可选 Permit2 签名拉资入口，并在拉资后复用同一核心执行逻辑
- 保护期内先请求 anti-snipe ticket，再决定是否继续真实 swap
- 保护期内对同一个 pool 执行 same-tx single-request 约束
- 统一 native 退款体验
- 统一 LP add/remove/claim 外围体验

Router 的定位是：

- **Periphery**
- **用户入口**
- **预算管理层**

### 5.2 `MemeverseUniswapHook`

Hook 是 Core 引擎，负责：

- anti-snipe attempt 判定
- 保护期失败费逻辑
- 正常动态手续费逻辑
- LP fee / protocol fee 归集
- 动态状态更新（ewVWAP、波动率、short impact）
- LP token 与 fee per share accounting

Hook 的定位是：

- **Core rule engine**
- **Fee engine**
- **Anti-snipe engine**

---

## 6. 总体产品语义

### 6.1 保护期外

保护期外，交易体验尽量接近普通 DEX：

- Router 直接执行真实 swap
- 不经过 anti-snipe attempt 判定
- 只按正常动态手续费结算

### 6.2 保护期内

保护期内，交易体验分成两步：

1. 先请求一次 anti-snipe attempt
2. 再根据结果决定：
   - 成功：继续真实 swap
   - 失败：不执行真实 swap，但会收取保护期失败费

此外，保护期内还施加额外流程约束：

- 同一笔交易里，对同一个 pool 只允许 request 一次

### 6.3 单笔原子交易原则

不论成功或失败，用户视角都应保持：

- 一笔交易完成
- 不需要第二笔 claim 或补款
- 失败时资产自动退回剩余部分

---

## 7. 统一输入预算模型

这是当前 swap 主路径最重要的业务规则之一。

### 7.1 exact-input

- 统一输入预算 = `abs(amountSpecified)`

### 7.2 exact-output

- 统一输入预算 = `amountInMaximum`

### 7.3 预算语义

保护期内，用户只提供**一份总输入预算**。

这份预算同时覆盖两种可能结果：

- 如果 attempt 失败：从预算里扣失败费，剩余退回
- 如果 attempt 成功：不扣失败费，直接用这份预算继续做真实 swap

### 7.4 为什么这样设计

目标是保证：

- 用户实际被拉取/附带的输入资金，不超过自己明确给出的预算
- 不出现“额外再收一笔失败费预算”的第二层占款

---

## 8. Anti-Snipe 规则

### 8.1 反狙击窗口

每个池在初始化后，会进入一个按区块计数的 anti-snipe 保护窗口。

在窗口内：

- 交易必须先过 attempt 判定
- 失败会被 soft-fail
- 同块只允许一笔成功 swap
- 同一笔交易内，同一个 pool 只允许 request 一次

### 8.2 attempt 是 permissionless

`requestSwapAttempt(...)` 本身不需要 Router 白名单。

这意味着：

- 官方 Router 可以用
- 第三方 Router / 聚合器可以用
- 高级链上策略也可以用

### 8.3 same-pool tx 锁

保护期内：

- same-pool tx 锁限制的是 **request 次数**
- 不是单纯限制最终成功的 swap 次数
- 目标是阻止同 tx 内通过重复 request 去 grind `gasleft()` / `currentAttempts`

重复 request 命中 same-pool tx 锁时：

- 不作为新的有效 attempt
- 不再继续正常的 anti-snipe 竞争判定

### 8.4 ticket 绑定语义

一旦 attempt 成功：

- Hook 会 arm 一个 transient ticket
- ticket 绑定：
  - `poolId`
  - `caller`
  - `SwapParams`
  - `inputBudget`

### 8.5 ticket 绑定预算的业务意义

该设计用于防止：

- 小预算 request
- 成功后拿大预算真实成交

特别是 exact-output：

- 最终真实输入金额必须小于等于 request 时绑定的 `inputBudget`

否则交易会失败。

### 8.6 软失败（Soft-Fail）语义

竞争性 attempt 失败时：

- 不执行真实 swap
- 返回 `executed = false`
- 返回具体失败原因
- attempts 仍会上链
- 用户会被收失败费
- 剩余预算退回

需要区分两类失败：

- **竞争性失败**：会 soft-fail、记 attempts、并收失败费
- **同 tx 同 pool 重复 request**：视为无效流程，直接拒绝，不作为新的有效 attempt

---

## 9. 正常手续费规则

### 9.1 LP fee

正常成交时：

- LP fee 永远按输入侧收

### 9.2 Protocol fee

正常成交时：

- 协议支持同时配置多种 protocol fee 币种
- 每一笔 swap 会优先尝试用输入币作为 protocol fee 币
- 如果输入币不受支持，则回退到输出币
- 如果输入/输出都不受支持，则 swap 失败
- 如果输入/输出都受支持，则优先按输入币收 protocol fee

### 9.3 动态费组成

总动态费率 `feeBps` 来自：

- base fee
- dynamic part
- volatility part
- short impact part

### 9.4 成功路径收费原则

保护期内如果 attempt 成功：

- **不收失败费**
- 只按正常 swap 动态费逻辑收费

---

## 10. 保护期失败费规则

### 10.1 触发条件

仅在 anti-snipe 保护期内，且 attempt 失败时触发。

### 10.2 收费方向

失败费统一：

- **从输入侧收**

### 10.3 费率等级

失败费使用与当前动态费同等级的 `feeBps`。

### 10.4 金额基数

失败费金额计算规则：

- exact-input：以 `abs(amountSpecified)` 为基数
- exact-output：以**当前报价下的预计实际输入**为基数，并且不会超过 `amountInMaximum`

### 10.5 归属规则

如果输入币属于支持的 protocol fee 币种：

- 失败费全部归 `treasury`

如果输入币不属于支持的 protocol fee 币种：

- 失败费全部归 LP

### 10.6 失败费不是正常 protocol fee 的镜像复刻

这点要明确：

- 成功成交时，protocol fee 可能不在输入侧
- 失败时没有真实成交，所以无法按成功成交的结算路径复刻

因此：

- 保护期失败费是一个**产品化的保护期费语义**
- 它统一从输入侧收费

---

## 11. 保护期内资金流

### 11.1 失败路径

1. 用户给出统一输入预算
2. Router 请求 anti-snipe attempt
3. Hook 判定失败
4. Hook 从预算中扣失败费
5. 剩余预算退回 Router
6. Router 把剩余预算退回用户
7. 不执行真实 swap

### 11.2 成功路径

1. 用户给出统一输入预算
2. Router 请求 anti-snipe attempt
3. Hook 判定成功，不收失败费
4. Hook 返回完整预算
5. Router 用这份预算继续真实 swap
6. 成功成交时按正常动态费规则收费
7. 未使用预算退回用户

---

## 12. 用户体验规则

### 12.1 用户只感知一笔交易

无论：

- attempt 失败
- attempt 成功后真实成交

都应保持单笔交易体验。

### 12.2 exact-output 用户体验

用户只需要给出：

- `amountInMaximum`

该值同时覆盖：

- 失败时可能扣除的失败费
- 成功时真实成交所需的实际输入

但需要注意：

- exact-output 的失败费**不是按 `amountInMaximum` 直接计费**
- 它按当前报价下的预计实际输入计费
- `amountInMaximum` 只作为用户总预算上限与最终输入约束

### 12.3 native 退款体验

Router 负责：

- 把未消耗的 native 预算退回 `nativeRefundRecipient`

这样可以支持：

- non-payable 合约调用方
- 自定义退款地址

---

## 13. LP 规则

### 13.1 LP token

每个池有独立 LP token。

### 13.2 LP 收益来源

LP 可以获得：

- 正常成交中的 LP fee
- 某些保护期失败费（当失败费不归 treasury 时）

### 13.3 记账方式

LP fee 使用 `feePerShare` 进行累计记账。

用户最终通过：

- `claimFees(...)`

提取自己应得部分。

---

## 14. Treasury 规则

### 14.1 财库收什么

Treasury 接收：

- 正常成交中的 protocol fee
- 输入币属于支持的 protocol fee 币种时的保护期失败费

### 14.2 财库约束

`treasury` 必须是**被动收款地址**：

- 推荐 EOA 或简单多签
- 如果协议收费币可能是 native，必须能接收 ETH
- 不允许通过 `receive()` / `fallback()` 再触发重入式交易逻辑

---

## 15. Liquidity 管理规则

### 15.1 addLiquidity

当前 LP 入口是：

- `MemeverseSwapRouter.addLiquidity(...)`

该入口不再暴露 `fee` 参数：

- Router 内部固定使用动态费池
- 也就是 `LPFeeLibrary.DYNAMIC_FEE_FLAG`

Router 负责：

- 用户参数保护
- native 退款

Hook 负责：

- full-range liquidity 增加
- LP token mint

### 15.2 removeLiquidity

当前 LP 出口是：

- `MemeverseSwapRouter.removeLiquidity(...)`

该入口同样不再暴露 `fee` 参数，并固定操作当前 Hook 管理的动态费池。

Router 负责：

- min amount 检查
- 最终资产发放

Hook 负责：

- full-range liquidity 减少
- LP token burn

---

## 16. Admin 配置项

### 16.1 treasury

Owner 可配置：

- `treasury`

要求：

- 不允许为 0
- 必须是可安全收款地址

### 16.2 protocol fee currencies

Owner 可配置：

- 协议 fee 币种支持列表

要求：

- 至少池子的输入币或输出币中有一个属于支持列表
- 如果输入/输出都属于支持列表，则优先按输入币收 protocol fee

### 16.3 anti-snipe duration

Owner 可配置：

- 新池默认 anti-snipe 保护区块数

### 16.4 emergency flag

Owner 可切换：

- emergency fixed-fee 模式

其效果是：

- 动态费退化成基础费率
- 不暂停交易

---

## 17. 约束与运维前提

### 17.1 attempts 不是纯净信号

attempts 是一个可被博弈的链上状态量，不应被理解成“真实自然流量人数”。

### 17.2 anti-snipe 更像启动期保护器

它的目标是：

- 提高启动期攻击者成本
- 降低机器人成功率

而不是提供严格公平随机。

### 17.3 推荐默认入口仍是 Router

尽管 `requestSwapAttempt(...)` 是 permissionless：

- 对普通前端 / 钱包 / SDK
- 仍然推荐统一通过 `MemeverseSwapRouter`（approve 与 Permit2 都走同一 Router 语义）
- 保护期内如果同一笔交易再次对同一个 pool 发起 request，会被直接拒绝

---

## 18. 验收标准

### 18.1 正常交易

- 保护期外，交易可直接执行
- 成功时按正常动态费收费

### 18.2 保护期失败

- 失败不执行真实 swap
- attempts 上链
- 从统一输入预算中扣失败费
- 剩余预算自动退回

### 18.3 保护期成功

- request 成功不收失败费
- 继续执行真实 swap
- 成功成交只收正常动态费
- 未使用预算自动退回

### 18.4 exact-output 安全性

- 不能通过“小预算 request + 大预算成交”绕过预算约束

### 18.5 多 Router 支持

- 官方 Router 与第三方 Router 都可请求 anti-snipe ticket
- 不依赖 Router 白名单
- 但 protection window 内仍受 same-pool tx 锁约束：同一笔交易对同一个 pool 只能 request 一次

### 18.6 Permit2 并行入口一致性

- Permit2 路径只改变资金准备方式
- Permit2 拉资完成后，沿用与常规 approve 路径相同的 deadline/slippage/anti-snipe 语义
- 保持常规 approve 路径继续可用，二者并存

---

## 19. 一句话总结

Memeverse Swap 当前的产品核心可以概括为：

> 保护期外像普通动态费 DEX；保护期内先做 permissionless anti-snipe attempt，同一笔交易对同一个 pool 只能 request 一次；失败时从同一份输入预算中收失败费，成功时继续真实 swap，并只按正常动态费结算。
