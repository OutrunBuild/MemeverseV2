# MemeverseV2 跨链互操作细化说明

## 1. 目标

本文解释治理收益跨链投递与 memecoin 跨链 staking 两条主路径的角色分工、消息方向和安全约束。

## 2. 主要模块

- `YieldDispatcher`
  - 处理治理收益路由
  - 接收 OFT compose 或 launcher 本地 fast path
- `MemeverseOmnichainInteroperation`
  - 用户侧 memecoin staking 入口
  - 根据治理链位置决定本链或异链路径
- `OmnichainMemecoinStaker`
  - 治理链侧接收跨链 staking compose
  - 把 memecoin 存入 yieldVault 或 fallback 给 receiver

## 3. 治理收益分发路径

### 3.1 本链治理

当治理链就是当前链时：

- launcher 先把 token 转给 `YieldDispatcher`
- 再由 launcher 直接调用 `YieldDispatcher.lzCompose`

因此本链场景并不一定经过真正的跨链 message round-trip。

### 3.2 异链治理

当治理链在远端时：

- launcher 先构造 OFT send 参数
- token 通过 OFT 发送到治理链
- 治理链 `YieldDispatcher` 在 compose 回调中完成最终路由

### 3.3 两类 token 的终点

- `TokenType.MEMECOIN`
  - receiver 为合约时 -> `YieldVault.accumulateYields`
  - receiver 不是合约时 -> burn
- `TokenType.UPT`
  - receiver 为合约时 -> `Governor.receiveTreasuryIncome`
  - receiver 不是合约时 -> burn

因此 `YieldDispatcher` 不是只处理 memecoin yield，而是统一处理 yield / treasury 两类协议收入。

## 4. 跨链 staking 路径

### 4.1 本链治理

若治理链在本链：

- 用户直接经 `MemeverseOmnichainInteroperation` 把 memecoin 存入 yieldVault
- `msg.value` 必须为 0

### 4.2 异链治理

若治理链在远端：

- 用户先 quote
- `msg.value` 必须精确匹配报价
- memecoin 通过 OFT 发到治理链
- `OmnichainMemecoinStaker` 在 compose 中完成最终 deposit / fallback transfer

## 5. 为什么要求 exact fee

V2 当前不是“至少足额”语义，而是“严格等于报价”。

这条规则的作用是：

- 让脚本与调用方先 quote 再执行
- 降低跨链费用处理中的不确定性
- 避免把 fee 误差变成隐含状态

## 6. compose 回调与 replay 防护

`YieldDispatcher` 和 `OmnichainMemecoinStaker` 都依赖 compose 回调处理跨链到账。

关键约束：

- endpoint 路径必须检查 `guid` 未执行
- 成功后必须标记已执行

这样做的目的，是避免重复到账、重复记账或重复 staking。

## 7. fallback 语义

在治理收益或 staking 到达治理链时，如果目标 receiver / yieldVault 不存在：

- 不会默默保留悬空余额
- 而是按当前规则 burn 或直接 fallback transfer

因此跨链互操作不是“最佳努力存放”，而是有明确失败出口的。

## 8. 当前实现提醒

- 本链 fast path 和异链 compose path 共享同一个高层收益路由语义
- `YieldDispatcher` 是当前业务语义名称，应作为跨链收益路由模块的正式称呼
- 互操作路径里的安全关键点不是 UI 或脚本，而是链上 exact fee 与 replay 防护

## 9. 相关真源与证据

- `docs/spec/integrations/layerzero-oapp-oft.md`
- `docs/spec/accounting.md`
- `docs/spec/access-control.md`
- `docs/spec/invariants.md`
- `docs/spec/deployment.md`
