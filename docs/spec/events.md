# MemeverseV2 事件面（用户 / 索引器 / 运维）

## 1. 说明

本文聚焦“对用户、索引器、运维有直接价值”的已发出事件。  
标签说明：

- `[代码已证]`：当前实现直接 `emit`
- `[已知缺口]`：业务动作存在，但没有对应事件或难以完整重建
- `[未知]`：需依赖链外系统或外部协议事件

## 2. 用户与索引主事件

### 2.1 注册与生命周期

| 事件 | 触发模块 | 触发时机 | 用途 |
| --- | --- | --- | --- |
| `Registration(uniqueId,param)` | `MemeverseRegistrationCenter` | 中心链注册成功后 | 跟踪 symbol 占用与参数快照 |
| `RegisterMemeverse(verseId,verse)` | `MemeverseLauncher` | launcher 完成新 verse 写入 | 建立 verse 主索引 |
| `Genesis(verseId,user,...)` | `MemeverseLauncher` | Genesis 入金成功 | 跟踪募资累计 |
| `ChangeStage(verseId,currentStage)` | `MemeverseLauncher` | `changeStage` 每次成功执行 | 生命周期状态索引 |
| `Refund(verseId,receiver,amount)` | `MemeverseLauncher` | Genesis 退款成功 | 退款账本 |
| `ClaimPOLToken(...)` / `MintPOLToken(...)` | `MemeverseLauncher` | POL 领取/铸造成功 | POL 用户头寸变动 |
| `RedeemMemecoinLiquidity(...)` / `RedeemPolLiquidity(...)` | `MemeverseLauncher` | unlock 后退出路径成功 | 退出路径索引 |
| `RedeemAndDistributeFees(...)` | `MemeverseLauncher` | 费用赎回分发成功 | 执行者奖励与收益分账 |
| `SetExternalInfo(...)` | `MemeverseLauncher` | 外部元数据更新 | 前端展示元数据刷新 |

以上均为 `[代码已证]`。

### 2.2 Swap 与 LP

| 事件 | 触发模块 | 触发时机 | 用途 |
| --- | --- | --- | --- |
| `PoolInitialized` | `MemeverseUniswapHook` | 池初始化 | poolId 与 LP token 建档 |
| `LiquidityAdded` / `LiquidityRemoved` | `MemeverseUniswapHook` | Core 加减池 | LP 头寸变动 |
| `LPFeeCollected` / `ProtocolFeeCollected` | `MemeverseUniswapHook` | fee 归集时 | 手续费归属跟踪 |
| `FeesClaimed` | `MemeverseUniswapHook` | LP 提取收益时 | 已领取 fee 对账 |

以上均为 `[代码已证]`。

### 2.3 Yield / Governance / Cross-chain

| 事件 | 触发模块 | 触发时机 | 用途 |
| --- | --- | --- | --- |
| `Deposit` / `RedeemRequested` / `RedeemExecuted` / `AccumulateYields` | `MemecoinYieldVault` | 存入、排队赎回、执行赎回、收益累积 | vault 份额与收益流水 |
| `CycleStarted` / `CycleFinalized` / `RewardClaimed` / `TreasuryIncomeRecorded` / `TreasuryAssetSpendRecorded` 等 | `GovernanceCycleIncentivizerUpgradeable` | 治理周期与奖励账本变化 | 治理奖励索引 |
| `OFTProcessed` | `YieldDispatcher` | OFT compose 到账处理 | 收益路由或 burn 结果 |
| `OmnichainMemecoinStaking` / `OmnichainMemecoinStakingProcessed` | interoperation/staker | 发起远端 staking / 远端处理完成 | 跨链 staking 追踪 |

以上均为 `[代码已证]`。

## 3. 运维配置事件

重点配置事件（均 `[代码已证]`）：

- Launcher：`SetMemeverseSwapRouter`、`SetFundMetaData`、`SetExecutorRewardRate`、`SetPreorderConfig`、`SetGasLimits` 等
- RegistrationCenter：`SetSupportedUPT`、`SetDurationDaysRange`、`SetLockupDaysRange`、`SetRegisterGasLimit`
- Hook：`TreasuryUpdated`、`ProtocolFeeCurrencySupportUpdated`、`EmergencyFlagUpdated`、`LauncherUpdated`、`DefaultLaunchFeeConfigUpdated`
- Interoperation：`SetGasLimits`
- ProxyDeployer：`SetQuorumNumerator`

## 4. 已知事件缺口与解释

- `preorder(...)`、`refundPreorder(...)`、`claimUnlockedPreorderMemecoin(...)` 没有专用事件。`[已知缺口]`
- Router 自身没有业务事件（swap/add/remove/permit2 路径）；链上索引主要依赖 Hook 事件与 token transfer。`[已知缺口]`
- `changeStage` 在 `Locked` 且未到 `unlockTime` 时也会发 `ChangeStage(..., Locked)`；索引器不能仅凭事件判断“是否真的迁移”。`[已知缺口]`
- 当前实现已有 `SetPostUnlockLiquidityProtectionWindow` 配置事件，但仍没有“保护窗口开始/结束”的专用阶段或专用事件；索引器需要结合 stage、`unlockTime`、窗口参数与 swap 成败联合判断“unlock 后保护中”与“完全开放交易”的状态。`[已知缺口]`
- `SetExternalInfo` 事件携带的是本次传入数组；合约内 `communitiesMap` 为按索引覆盖，旧尾部数据可能保留，事件本身无法单独重建完整当前快照。`[已知缺口]`
- LayerZero endpoint / PoolManager 等外部协议事件不在本仓库定义。`[未知]`

## 5. 确定性边界

- 本文只覆盖仓库 `src/**` 明确 `emit` 的事件。
- 继承自 OpenZeppelin 的通用事件（如 `Paused/Unpaused`、`OwnershipTransferred`）存在，但未作为 Memeverse 业务主索引面展开。
