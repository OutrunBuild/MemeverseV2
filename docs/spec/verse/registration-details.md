# MemeverseV2 注册链路细化说明

## 1. 目标

本文细化 V2 的注册链路，解释注册中心、local registrar、omnichain registrar 与 launcher 之间的职责分工、时间权威与副作用顺序。

## 2. 角色分工

- `MemeverseRegistrationCenter`
  - 注册参数校验
  - symbol 占用管理
  - `uniqueId/endTime/unlockTime` 生成
  - 本链/异链 fan-out
- `MemeverseRegistrarAtLocal`
  - 本链报价与本链注册入口
  - 接收 center 的本地注册调用
- `MemeverseRegistrarOmnichain`
  - 异链向中心链发起注册
  - 负责跨链 quote/send
- `MemeverseLauncher`
  - 接收最终注册结果
  - 记录 verse 主状态与资产地址

## 3. 注册参数校验顺序

center 当前负责检查：

- `durationDays` 是否落在允许区间
- `lockupDays` 是否落在允许区间
- `name/symbol/uri/desc` 长度是否合法
- `UPT` 是否在支持列表内
- `omnichainIds` 长度是否合法
- `omnichainIds` 去重后再继续分发

因此注册中心不是简单转发器，而是时间与参数的权威入口。

## 4. Symbol 生命周期

一个 symbol 在中心链上有三种语义状态：

- `Available`
- `Active`
- `Historical`

当前注册记录保存在 `symbolRegistry`，旧记录在新注册开始前归档到 `symbolHistory`。

同一个 symbol 只有在当前注册窗口结束后，才会重新变为可注册。

## 5. uniqueId 与 nonce

当前实现会使用 symbol 的历史 nonce 与当前参数生成新的 `uniqueId`。

关键含义：

- symbol 可被重复使用，但每次成功注册都是新的 verse 实例
- `uniqueId` 不是单纯的 symbol hash，而是带有注册序列含义

## 6. 时间权威来源

注册链路最容易误解的部分是时间语义。

当前 V2 的权威时间来源是注册中心写入值：

- `endTime`
- `unlockTime`

并且 center 当前使用：

- `DAY = 180` 秒

而本地 registrar 的报价辅助仍按：

- `24 * 3600`

这意味着：

- 本地 quote 的“天数”只是估算
- 真正写入 launcher 的 `endTime/unlockTime` 以 center 为准
- 当前实现中的“天数”并不等于自然日

## 7. 本链注册路径

本链路径的核心步骤是：

1. 用户或上层入口先做 quote
2. 调用 center 的 `registration`
3. center 生成 `uniqueId/endTime/unlockTime`
4. center 直接调用 `MemeverseRegistrarAtLocal.localRegistration`
5. local registrar 调用 launcher：
   - `registerMemeverse`
   - `setExternalInfo`

这个路径中，center 是时间和 symbol 状态的唯一权威。

## 8. 异链注册路径

异链路径的核心步骤是：

1. 用户在异链调用 omnichain registrar 相关入口
2. omnichain registrar 向中心链发送注册请求
3. center 完成校验与时间生成
4. center 对目标链执行 fan-out
5. 目标链 registrar 最终把结果落库到 launcher

这里的关键边界是：

- 中心链负责决定 symbol 是否可注册
- 中心链负责决定 `unlockTime`
- 异链 registrar 不拥有最终时间解释权

## 9. fan-out 与 fee

`MemeverseRegistrationCenter.quoteSend` 负责累计所有目标链 fan-out 的 native fee。

规则要点：

- 本链目标 fee 为 0
- 异链目标按 LayerZero quote 累加
- 任一目标链没有 endpoint 映射会直接回退

因此一次注册成功，不只是参数合法，还要求所有目标链的 fan-out 前提成立。

## 10. launcher 侧执行顺序

注册成功后，launcher 侧执行顺序应是：

1. 通过 deployer 部署 memecoin / POL
2. 初始化资产合约
3. 按 `omnichainIds` 配置 peer
4. 记录 verse 基础信息、反向索引并发出 `RegisterMemeverse`
5. registrar 再单独调用 `setExternalInfo` 写入 `uri/desc/communities`

这样设计意味着：

- 注册并不是“只写一个数据库记录”
- 它会同时完成资产层初始化
- `external info` 不在 `registerMemeverse(...)` 同一次函数体内写入，而是由 registrar 在后续调用中补写

## 11. 当前实现提醒

- 当前时间语义存在 `DAY=180` 与 `24*3600` 的偏差
- 这不是文档描述差异，而是当前实现中的真实不一致
- Agent 在分析注册和解锁行为时，必须优先相信 center 写入值

## 12. 相关真源与证据

- `docs/spec/state-machines.md`
- `docs/spec/protocol.md`
- `docs/spec/deployment.md`
- `docs/spec/invariants.md`
- `docs/TRACEABILITY.md`
