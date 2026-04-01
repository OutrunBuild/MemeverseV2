# MemeverseV2 生命周期细化说明

## 1. 目标

本文用用户视角、资金流视角和模块协作视角，把 MemeverseV2 的完整生命周期串起来。

本文补充：

- `docs/spec/protocol.md`
- `docs/spec/state-machines.md`
- `docs/spec/accounting.md`
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

### 4.2 资金拆分

每笔 `genesis` 入金按当前 V2 语义拆成两部分：

- `75%` 进入 memecoin 侧资金
- `25%` 进入 POL 侧资金

这已经不是 V1 的 `4/5 + 1/5` 语义。

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
- 创建 `memecoin/UPT` 与 `POL/UPT` 两池
- 若存在 preorder，则执行 launch settlement

这一时刻是“资产、池子、治理与收益组件同时就位”的分水岭。

## 6. Locked 运行期

`Locked` 是协议的主要运行阶段。

### 6.1 用户动作

用户可以：

- 领取 Genesis 对应的 POL
- 用 `UPT + memecoin` 加池 mint 新 POL
- 领取线性解锁的 preorder memecoin

### 6.2 协议动作

协议可以：

- 从两池 claim fee
- 把 `liquidProofFee` burn
- 把 `UPTFee` 拆成 `executorReward + govFee`
- 把 `memecoinFee` 送到 yield 路径
- 把 `govFee` 送到 governor treasury 路径

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

- `redeemMemecoinLiquidity`
- `redeemPolLiquidity`
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

- Genesis 入金先拆成 memecoin 侧与 POL 侧两部分。
- preorder 单独积累，直到进入 `Locked` 时统一换成 memecoin。
- `Locked` 期产生的两池 fee 会拆成 burn、执行者奖励、governor treasury 收入与 yield 收入。
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
- `docs/spec/state-machines.md`
- `docs/spec/accounting.md`
- `docs/spec/invariants.md`
- `docs/TRACEABILITY.md`
- `docs/memeverse-swap/memeverse-swap-flow.md`
