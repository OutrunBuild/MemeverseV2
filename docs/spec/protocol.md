# MemeverseV2 协议总览（产品真相层）

## 1. 文档目的与来源边界

本文档描述 MemeverseV2 当前“产品真相层”规则，不做逐行代码注释。

规则分层（从高到低）：
- 当前规则真源：`docs/spec/*.md`（含本文档）。
- 落地证据：`src/**` 与 `test/**` 可验证行为。

## 2. 系统目标

- 建立从注册、募资、初始流动性、治理接入到退出的统一生命周期入口。
- 把同一 verse 的资金与状态集中在 `MemeverseLauncher` 编排，降低模块分散状态。
- 在 swap 层提供统一 Router 入口、动态费与启动期费用保护能力。
- 支持治理链本地与异链两种收益投递路径（Governor / Yield Vault）。

## 3. 当前范围（In Scope）

| 模块 | 主要职责 | 对用户可见影响 | 规则状态 |
| --- | --- | --- | --- |
| `MemeverseRegistrationCenter` | 注册参数校验、symbol 占用与历史、多链分发 | 是否能注册、注册费与跨链分发成功与否 | 当前规则（代码已证） |
| `MemeverseRegistrarAtLocal` / `MemeverseRegistrarOmnichain` | 把注册结果写入 Launcher | 本地/异链注册路径差异 | 当前规则（代码已证） |
| `MemeverseLauncher` | verse 状态机与资金主编排 | Genesis/Refund/Locked/Unlocked 行为、领取/退款/赎回/分发 | 当前规则（代码已证） |
| `MemeverseProxyDeployer` | memecoin/POL/vault/governor/incentivizer 部署或地址预测 | Locked 时治理与收益组件是否就绪 | 当前规则（代码已证） |
| `MemeverseSwapRouter` + `MemeverseUniswapHook` | swap/liquidity 统一入口与费用引擎 | 交易费率、LP 记账、启动期费用曲线、launch settlement 特权路径 | 当前规则（代码已证） |
| `Memecoin` / `MemeLiquidProof` | 发行与销毁权限边界 | 谁可 mint、如何 burn、POL 与 LP 的关系 | 当前规则（代码已证） |
| `MemecoinYieldVault` | memecoin 收益累积、份额化与延迟赎回 | 质押收益、请求赎回与延迟执行 | 当前规则（代码已证） |
| `MemecoinDaoGovernorUpgradeable` + `GovernanceCycleIncentivizerUpgradeable` | DAO treasury 与投票激励周期 | 国库收入记录、周期奖励结算 | 当前规则（代码已证） |
| `YieldDispatcher` / `MemeverseOmnichainInteroperation` / `OmnichainMemecoinStaker` | 跨链收益与跨链 staking 路径 | 异链 fee 要求、到帐目标（Governor / Vault） | 当前规则（代码已证） |

## 4. 用户可见主流程

### 4.1 注册流程
- 用户经注册中心提交参数，中心校验并生成 `uniqueId`，然后本地/跨链分发至 registrar。
- registrar 调用 launcher 注册并补写外部信息（`uri/desc/communities`）。
- 外部信息后续也可由 governor 更新；当前更新语义是增量覆盖，不会自动清空未提供字段。

### 4.2 Genesis 与 Preorder
- Genesis 入金 token 为 UPT；每笔按 75% / 25% 拆分到 memecoin 侧与 POL 侧资金池。
- Preorder 仅在 Genesis 可入金，容量受 `preorderCapRatio` 限制。

### 4.3 阶段推进
- `changeStage` 把 `Genesis -> Locked/Refund`，以及解锁后推进到退出阶段。
- `flashGenesis=true` 且达最小募资时可提前进入 Locked。

### 4.4 Locked 后行为
- 可领取 Genesis 对应 POL。
- 可继续用 `UPT + memecoin` 加池并 mint 新 POL。
- 可触发 LP fee 赎回与分发（含执行者奖励）。
- preorder 份额按线性解锁领取 memecoin。

### 4.5 Unlocked 后退出
- 从产品安全要求看，`unlockTime` 到达后不能立即恢复无限制公开 swap。
- 该保护窗口必须优先保障：
  - POL 持有人按 1:1 burn POL 赎回 memecoin/UPT LP
  - Genesis 参与者按出资比例一次性赎回 POL/UPT LP
  - 依赖 POL 全局结算窗口的上层模块（如 POL Lend）按一致基准结算
- 当前接受的产品规则是：有效的公开 swap 恢复时刻锚定在实际 `changeStage()` 完成 `Locked -> Unlocked` 的交易时间，再加上固定 `24 hours`。
- 当前实现把这套语义落在 `Launcher` 于解锁迁移时向 `Hook` 写入每个受保护池的 `publicSwapResumeTime`，再由 `hook.beforeSwap` 按该时间阻断公开 swap。
- 保护窗口现为固定产品常量；已写入的 pool-level 恢复时间不再依赖 owner 配置。

## 5. 模块矩阵（按生命周期）

| 生命周期阶段 | 关键模块 | 可执行动作 |
| --- | --- | --- |
| 注册前 | RegistrationCenter / Registrar | 参数校验、symbol 可用性检查、报价 |
| Genesis | Launcher | `genesis`、`preorder`、`changeStage` |
| Refund | Launcher | `refund`、`refundPreorder` |
| Locked | Launcher + Swap + Governance/Yield | `claimPOLToken`、`mintPOLToken`、`redeemAndDistributeFees`、preorder 线性领取 |
| Unlocked | Launcher + Swap | 保护窗口内优先退出；窗口结束后恢复公开 swap |
| 全程跨链 | Interoperation / YieldDispatcher | 跨链 staking、跨链收益投递 |

## 6. 非目标（当前文档与协议范围外）

- 前端交互、钱包引导与运营文案。
- 部署脚本与 CI 流程本身。
- 非 EVM 链适配。

## 7. 当前实现提醒

### 7.1 Swap 的启动期语义
- `swap` 路径采用 execute-or-revert。
- 启动期保护语义体现为 `launch fee` 衰减窗口与显式 `launch settlement` 路径（固定 `1%`）。
- unlock 后的流动性保护则由解锁迁移时写入的 pool-level `publicSwapResumeTime` 与 `hook.beforeSwap` 实现。

### 7.2 Preorder 能力
- launcher 已实现 preorder 入金、退款、启动时结算与线性解锁领取。
- 这部分属于当前用户可见行为。

### 7.3 注册时间单位
- `MemeverseRegistrationCenter` 当前把 `DAY` 定义为 `180` 秒（测试常量），`durationDays/lockupDays` 在中心链按此单位换算。
- `MemeverseRegistrarAtLocal.quoteRegister` 的报价辅助仍按 `24 * 3600` 秒换算 end/unlock 时间。
- 因此“天数”在当前实现里不是统一的自然日语义。
