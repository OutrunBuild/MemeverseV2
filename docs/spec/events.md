# MemeverseV2 事件面（用户 / 索引器 / 运维）

## 1. 说明

本文覆盖“对用户、索引器、运维有直接价值”的已发出事件，以及明确标注为目标事件规格的 target-only 条目。
标签说明：

- `[代码已证]`：当前实现直接 `emit`
- `[目标规格]`：目标事件规格，当前实现尚未直接 `emit`
- `[已知缺口]`：业务动作存在，但没有对应事件或难以完整重建
- `[未知]`：需依赖链外系统或外部协议事件

## 2. 用户与索引主事件

### 2.1 注册与生命周期

| 事件 | 触发模块 | 触发时机 | 用途 |
| --- | --- | --- | --- |
| `Registration(uniqueId,param)` | `MemeverseRegistrationCenter` | 中心链注册成功后 | 跟踪 symbol 占用与参数快照 |
| `RegisterMemeverse(verseId,verse)` | `MemeverseLauncher` | launcher 完成新 verse 写入 | 建立 verse 主索引 |
| `Genesis(verseId,user,...)` | `MemeverseLauncher` | Genesis 入金成功 | 跟踪募资累计 |
| `Preorder(verseId,caller,user,amountInUAsset)` | `MemeverseLauncher` | Preorder 入金成功 | preorder 资金流入与累计索引；区分 caller 与 user 覆盖 relayer 场景 |
| `ChangeStage(verseId,currentStage)` | `MemeverseLauncher` | `changeStage` 每次成功执行 | 生命周期状态索引 |
| `Refund(verseId,receiver,amount)` | `MemeverseLauncher` | Genesis 退款成功 | 退款账本 |
| `RefundPreorder(uint256 indexed verseId,address indexed receiver,uint256 refundAmount)` | `MemeverseLauncher` | Preorder 退款成功 | preorder 退款账本；目标事件规格 |
| `ClaimNormalYT(...)` | `MemeverseLauncher` | 普通创世初始 YT 领取成功 | 初始 YT claim 索引 |
| `ClaimNormalFees(verseId,receiver,uAssetAmount,ptAmount)` | `MemeverseLauncher` | 普通侧辅助池手续费领取成功 | 普通侧 uAsset/PT fee claim 索引；settled 后 PT 已兑换为 uAsset，ptAmount=0 |
| `ClaimPreorderMemecoin(verseId,user,amount)` | `MemeverseLauncher` | Unlocked 后 preorder memecoin 领取成功 | preorder memecoin vested claim 索引 |
| `MintPOLToken(...)` | `MemeverseLauncher` | Locked 后用户主动加池并 mint POL 成功 | 加池 POL 头寸变动；不代表 Genesis 初始 POL claim |
| `RedeemMemecoinLiquidity(...)` | `MemeverseLauncher` | unlock 后主池退出成功 | 主池退出路径索引 |
| `RedeemAuxiliaryLiquidity(verseId,user,polUAssetLpAmount,ptUAssetLpAmount,ptPolLpAmount)` | `MemeverseLauncher` | Unlocked 后辅助池 LP 退出成功 | 辅助池退出路径索引；携带三类 LP 精确金额 |
| `RedeemAndDistributeFees(...)` | `MemeverseLauncher` | 费用赎回分发成功 | 执行者奖励与收益分账 |
| `SetExternalInfo(...)` | `MemeverseLauncher` | 外部元数据更新 | 前端展示元数据刷新 |

除标注为目标事件规格的条目外，以上均为 `[代码已证]`。

### 2.2 POLend / POLSplitter 目标事件面

本节描述 `docs/spec/polend/polend.md` 要求的目标事件面。若当前代码未 emit，对索引器而言是 current vs target gap，不能标成 `[代码已证]`。

| 事件 | 触发模块 | 触发时机 | 用途 | 状态 |
| --- | --- | --- | --- | --- |
| `LeveragedGenesis(uint256 indexed verseId,address indexed user,uint256 interestAmount)` | `POLend` | 用户在 Genesis 支付杠杆利息成功 | 杠杆创世参与与利息累计索引 | `[代码已证]` |
| `ClaimLeveragedYT(uint256 indexed verseId,address indexed user,address indexed to,uint256 amount)` | `POLend` | 杠杆创世初始 YT 领取成功 | leveraged YT claim 索引 | `[代码已证]` |
| `ClaimResidual(uint256 indexed verseId,address indexed user,address indexed to,uint256 uAssetAmount,uint256 memecoinAmount)` | `POLend` | 全局结算后杠杆残值领取成功 | leveraged residual claims 索引 | `[代码已证]` |
| `PreRedeemPTFee(uint256 indexed verseId,address indexed uAsset,uint256 ptAmount,address mintTo)` | `POLend` | settle 前杠杆侧 PT fee 预兑付 | PT fee 预兑付、债务增加与后续 backing 对账 | `[代码已证]` |
| `DefaultInterestRateChanged(uint256 oldRate,uint256 newRate)` | `POLend` | owner 修改默认利率 | 新注册 market 利率参数索引；不影响已注册 market | `[代码已证]` |
| `LeveragedDebtFactorChanged(uint256 oldFactor,uint256 newFactor)` | `POLend` | owner 修改全局杠杆债务上限系数 | 新增杠杆创世 debt cap 参数索引；不影响已 mint 债务 | `[代码已证]` |
| `ProtocolTreasuryChanged(address indexed oldTreasury,address indexed newTreasury)` | `POLend` | owner 修改 POLend protocol treasury | 杠杆利息 treasury 变更索引；与 Memeverse DAO governor treasury 不同 | `[代码已证]` |
| `MaxSettlementDustChanged(address indexed uAsset,uint256 oldDust,uint256 newDust)` | `POLend` | owner 修改某 `uAsset` 的 settlement dust 上限 | C1 dust 补偿上限审计 | `[代码已证]` |
| `SettlementDustReserved(uint256 indexed verseId,address indexed uAsset,uint256 totalLeveragedInterest,uint256 autoReserve,uint256 treasuryInterest)` | `POLend` | `finalizeLeveragedGenesis` 自动预留 reserve 并转出剩余利息 | 自动 reserve 与 treasury 利息拆分审计 | `[代码已证]` |
| `SettlementDustReserveFunded(uint256 indexed verseId,address indexed funder,address indexed uAsset,uint256 amount)` | `POLend` | 任意地址为 Locked market 手动注入 settlement dust reserve | reserve 来源与人工补足流水审计 | `[代码已证]` |
| `GlobalSettlementExecuted(uint256 indexed verseId,address indexed uAsset,uint256 verseDebt,uint256 recoveredUAsset,uint256 consumedSettlementDustReserve,uint256 unusedSettlementDustReserve,uint256 residualUAsset,uint256 residualMemecoin)` | `POLend` | `executeGlobalSettlement` 成功完成 | 债务偿还、reserve 消耗、未用 reserve 归集与 residual 记账审计 | `[代码已证]` |
| `RedeemPT(uint256 indexed verseId,address indexed from,address indexed to,uint256 ptAmount)` | `POLSplitter` | settle 后 PT 兑付 | PT 兑付流水索引 | `[代码已证]` |
| `RedeemYT(uint256 indexed verseId,address indexed from,address indexed to,uint256 ytAmount,uint256 uAssetAmount,uint256 memecoinAmount)` | `POLSplitter` | settle 后 YT 兑付 | YT 兑付流水索引 | `[代码已证]` |

目标事件面必须覆盖 `POLend.executeGlobalSettlement(...)` 产生的 leveraged residual 与 settlement dust reserve 记账结果。若实现只依赖 token transfer 或内部状态变化，则属于事件面缺口。

### 2.3 Swap 与 LP

| 事件 | 触发模块 | 触发时机 | 用途 |
| --- | --- | --- | --- |
| `PoolInitialized` | `MemeverseUniswapHook` | 池初始化 | poolId 与 LP token 建档 |
| `LiquidityAdded` / `LiquidityRemoved` | `MemeverseUniswapHook` | Core 加减池 | LP 头寸变动 |
| `LPFeeCollected` / `ProtocolFeeCollected` | `MemeverseUniswapHook` | fee 归集时 | 手续费归属跟踪 |
| `FeesClaimed` | `MemeverseUniswapHook` | LP 提取收益时 | 已领取 fee 对账 |

以上均为 `[代码已证]`。

### 2.4 Yield / Governance / Cross-chain

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
- RegistrationCenter：`SetSupportedUAsset`、`SetDurationDaysRange`、`SetRegisterGasLimit`
- Hook：`TreasuryUpdated`、`ProtocolFeeCurrencySupportUpdated`、`EmergencyFlagUpdated`、`LauncherUpdated`、`DefaultLaunchFeeConfigUpdated`
- Interoperation：`SetGasLimits`
- ProxyDeployer：`SetQuorumNumerator`

运维清理事件（均 `[代码已证]`）：

- Launcher：`RemoveGasDust(address indexed receiver,uint256 dust)`，owner-only 清理 Launcher native gas dust 时发出。

## 4. 已知事件缺口与解释

- `preorder(...)`、`claimUnlockedPreorderMemecoin(...)`、`redeemAuxiliaryLiquidity(...)` 已实现专用事件（`Preorder`、`ClaimPreorderMemecoin`、`RedeemAuxiliaryLiquidity`）。不再属于 Launcher 事件面缺口。
- `refundPreorder(...)` 的目标事件规格为 `RefundPreorder(uint256 indexed verseId,address indexed receiver,uint256 refundAmount)`；实现 emit 后不再属于 Launcher 事件面缺口。
- POLend / POLSplitter 目标事件面已实现。`burnPreRedeemedBacking` 保持可调用 settle 行为，但不要求专用 emitted event。
- Router 自身没有业务事件（swap/add/remove/permit2 路径）；链上索引主要依赖 Hook 事件与 token transfer。`[已知缺口]`
- `changeStage` 在 `Locked` 且未到 `unlockTime` 时也会发 `ChangeStage(..., Locked)`；索引器不能仅凭事件判断“是否真的迁移”。`[已知缺口]`
- 当前实现没有“保护窗口开始/结束”的专用阶段或专用事件，也没有 dedicated event 单独标记 `publicSwapResumeTime` 的激活或到期；索引器需要结合 stage、实际 `Locked -> Unlocked` 迁移交易时间、固定 `24 hours` 窗口与 swap 成败联合判断“unlock 后保护中”与“完全开放交易”的状态。`[已知缺口]`
- `SetExternalInfo` 事件携带的是本次传入数组；合约内 `communitiesMap` 为按索引覆盖，旧尾部数据可能保留，事件本身无法单独重建完整当前快照。`[已知缺口]`
- LayerZero endpoint / PoolManager 等外部协议事件不在本仓库定义。`[未知]`

## 5. 确定性边界

- 除明确标注为目标事件规格或 target-only 的条目外，本文只覆盖仓库 `src/**` 明确 `emit` 的事件。
- 继承自 OpenZeppelin 的通用事件（如 `Paused/Unpaused`、`OwnershipTransferred`）存在，但未作为 Memeverse 业务主索引面展开。
