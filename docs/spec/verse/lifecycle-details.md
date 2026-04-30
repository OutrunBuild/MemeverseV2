# MemeverseV2 生命周期细化说明

## 1. 目标

本文用用户视角、资金流视角和模块协作视角，把 MemeverseV2 的完整生命周期串起来。

本文补充：

- `docs/spec/protocol.md`
- `docs/spec/verse/state-machines.md`
- `docs/spec/verse/accounting.md`
- `docs/spec/invariants.md`

本文不替代上述真源；若与实现冲突，以真源和源码锚点为准。

## 2. 生命周期总览

MemeverseV2 的主路径可以概括为：

1. 注册
2. `Genesis`
3. 成功进入 `Locked`，或失败进入 `Refund`
4. `unlockTime` 到达
5. 在 `unlockTime` 之后实际执行 `changeStage()` 时进入 `Unlocked`，并为受保护池写入恢复公开 swap 的时间
6. 保护窗口结束后才恢复无限制公开 swap

其中：

- 启动期保护针对 pool bootstrap / preorder settlement
- 解锁后保护针对 POL 公平退出与全局结算

这两类保护不是同一个机制，不能互相替代。

## 3. 注册阶段

注册阶段由 `MemeverseRegistrationCenter` 统一生成并写入以下关键时间与标识：

- `uniqueId`
- `endTime`
- `unlockTime`

注册链路负责：

- 校验参数是否合法
- 检查 symbol 是否仍在占用窗口内
- 生成本次 verse 的唯一身份与时间边界
- 把结果 fan-out 到本链或异链 registrar
- 由 registrar 最终落库到 launcher

这一阶段决定了后续募资何时结束，以及最早可进入解锁迁移的时间边界；退出保护窗口的实际起点仍以后续 `changeStage()` 交易时间为准。

## 4. Genesis 募资阶段

### 4.1 用户动作

用户在 `Genesis` 期可以执行：

- `genesis`
- `preorder`

### 4.2 资金模型

普通 Genesis 入金不再逐笔拆成 memecoin 侧与 POL 侧资金，而是按 POLend 模型累计：

- `totalNormalFunds`
- `userGenesisFund`

杠杆 Genesis 入金先支付利息，再派生 `totalLeveragedDebt`。募资成功部署时使用：

- `totalGenesisFunds = totalNormalFunds + totalLeveragedDebt`

随后按 POLend 四池模型执行 `70/30` 规则，进入 `memecoin/uAsset` 主池与 `POL/uAsset`、`PT/uAsset`、`PT/POL` 三个辅助池路径。

### 4.3 preorder 语义

`preorder` 是 V2 新增能力：

- 只在 `Genesis` 期开放
- 单独记账
- 进入 `Locked` 时通过 launch settlement 统一结算成 memecoin
- 后续按线性解锁领取

因此 preorder 不是普通 Genesis LP 份额，也不是立即可交易资产。

## 5. Genesis 结束后的两条分叉

### 5.1 募资失败 -> `Refund`

当 `endTime` 到达且募资未达最小门槛时，verse 进入 `Refund`：

- Genesis 参与者可退款
- preorder 参与者可退款
- 不进入后续流动性部署与 fee 分发路径

### 5.2 募资成功 -> `Locked`

当达到最小募资要求时，verse 进入 `Locked`，并发生一组强副作用：

- 部署 memecoin / POL
- 按治理链位置决定是否部署或预测 `yieldVault / governor / incentivizer`
- 按 POLend 四池模型创建 `memecoin/uAsset` 主池与 `POL/uAsset`、`PT/uAsset`、`PT/POL` 三个辅助池
- 若存在 preorder，则执行 launch settlement

这一时刻是“资产、池子、治理与收益组件同时就位”的分水岭。

## 6. Locked 运行期

`Locked` 是协议的主要运行阶段。

### 6.1 用户动作

用户可以：

- 通过 `claimNormalYT` 领取普通创世初始 YT
- 通过 POLend `claimLeveragedYT` 领取杠杆创世初始 YT
- 用 `uAsset + memecoin` 加池 mint 新 POL；`UPT` 仅作为历史命名 / legacy alias
- 领取线性解锁的 preorder memecoin

### 6.2 协议动作

协议可以：

- 从 `memecoin/uAsset` 主池与三个辅助池捕获 fee
- 主池 `memecoin/uAsset` fee 沿用 Memeverse 分流：`memecoin` fee 进入 yield 路径，`uAsset` fee 拆成 `executorReward + govFee` 后进入执行者奖励与 governor treasury 路径
- 辅助池 `POL/uAsset`、`PT/uAsset`、`PT/POL` fee 按 POLend 四池规则拆分：POL fee burn，普通侧 fee 进入普通领取账本，杠杆侧 `uAsset` fee 分发到 governor treasury 路径，杠杆侧 `PT` fee 在 settle 前走 `preRedeemPTFee`，settle 后走 `redeemPT`
- `liquidProofFee` / `UPTFee` 仅作为 legacy 名称，不再定义目标四池费用语义

### 6.3 启动期保护

V2 当前已实现的启动保护是：

- `launch fee window`
- `launch settlement`

它们的作用是保护：

- 初始建池
- preorder settlement

它们不负责保护 `unlockTime` 之后的退出公平性。

## 7. unlockTime 到达后的保护窗口

这是 V2 生命周期里最关键的安全要求之一。

### 7.1 为什么必须存在

当 `unlockTime` 到达后，如果协议立刻允许：

- POL / genesis liquidity 赎回
- 普通公开 swap

那么先行动者可以：

1. 先赎回 LP 权益
2. 立即在公开市场卖出底层资产
3. 让后续赎回者面对更差的剩余池子状态

这会破坏：

- POL 公平退出
- Genesis 退出价值的一致性
- POL Lend / PT-YT 类模块所依赖的全局结算窗口

因此 `post-unlock liquidity protection period` 不是外围增强，而是安全前提。

### 7.2 保护窗口内应允许什么

- `redeemMemecoinLiquidity(verseId, amountInPOL)` / `redeemMemecoinLiquidity(verseId, amountInPOL, unwrap)`：burn `amountInPOL` 后令 `amountInLP = amountInPOL`；`unwrap=false` 转出 `memecoin/uAsset` LP token，`unwrap=true` 移除 LP 并发送底层 `memecoin` 与 `uAsset`
- `redeemAuxiliaryLiquidity`
- `POLSplitter.redeemPT / redeemYT`
- POLend leveraged residual claims
- 按产品定义允许的兼容性补池行为

### 7.3 保护窗口内必须禁止什么

- 普通公开 swap
- 绕过公开入口的等价 swap 路径
- 任何会改变后续赎回价值基准的公开市场行为

### 7.4 当前实现状态

当前实现已经落地该窗口语义，但方式不是新增阶段：

- verse 需先到达 `unlockTime`，然后在实际 `changeStage()` 调用里进入 `Unlocked`
- launcher 在该次迁移里按 `block.timestamp + 24 hours` 为受保护池写入 `publicSwapResumeTime`
- hook 在 `beforeSwap` 中读取该 pool-level 时间；未到期时继续拒绝受保护 pair 的公开 swap

因此当前实现采用的是“阶段直接进入 `Unlocked`，但公开 swap 恢复时间锚定实际迁移调用”的实现方式。

## 8. 真正完全解锁的市场状态

只有在 `post-unlock liquidity protection period` 结束后，协议才应恢复：

- 无限制公开 swap
- 退出与公开市场行为同时存在的自由状态

因此，“`unlockTime` 到达”“实际进入 `Unlocked`”和“市场完全开放”在产品语义上不是同一时刻。

## 9. 生命周期中的三类保护

### 9.1 启动保护

- `launch fee window`
- `launch settlement`

保护目标：启动建池与 preorder settlement。

### 9.2 阶段保护

- `Genesis`
- `Refund`
- `Locked`
- `Unlocked`

保护目标：确保流程顺序与账本动作不越阶段执行。

### 9.3 解锁后保护

- `post-unlock liquidity protection period`

保护目标：保证公平退出与统一结算窗口。

## 10. 生命周期中的关键资金流

- Genesis 入金按 POLend 四池规则进入主池与辅助池路径。
- preorder 单独积累，直到进入 `Locked` 时统一换成 memecoin。
- `Locked` 期主池与辅助池 fee 会按 POLend 四池规则拆成 burn、执行者奖励、governor treasury 收入、普通 fee 与 yield 收入。
- 实际 `Locked -> Unlocked` 迁移完成后，协议应优先保障 POL 与 Genesis LP 的退出，而不是立即恢复公开市场竞争。

## 11. 当前实现与目标规则差异

当前已经实现：

- 注册 -> `Genesis` -> `Locked/Refund` 的主流程
- preorder
- launch 保护
- `Locked` / `Unlocked` 的赎回路径

当前需要注意的不是“缺少保护窗口”，而是：

- 保护窗口没有独立生命周期阶段或专用事件，需要由 stage、解锁迁移交易时间与 swap 行为联合解释

## 12. 相关真源与证据

- `docs/spec/protocol.md`
- `docs/spec/verse/state-machines.md`
- `docs/spec/verse/accounting.md`
- `docs/spec/invariants.md`
- `docs/TRACEABILITY.md`
- `docs/memeverse-swap/memeverse-swap-flow.md`
