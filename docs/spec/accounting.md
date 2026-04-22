# MemeverseV2 记账与资金语义

## 1. 说明与来源边界

- 本文档是当前产品真相层的一部分，定义当前记账规则。
- 规则证据来自 `src/**` 与 `test/**`。

## 2. Genesis 与 Preorder 入账

### 2.1 Genesis 拆分

- 每笔 `genesis(amountInUPT)` 拆分为：
  - `memecoinFund = amountInUPT * 3/4`
  - `polFund = amountInUPT * 1/4`
- `userGenesisData[verseId][user].genesisFund` 按用户累计，不是覆盖。
- 全局累计在 `genesisFunds.totalMemecoinFunds/totalPolFunds`。

### 2.2 Preorder 入账

- preorder 仅 Genesis 阶段可入金，入账到 `preorderStates.totalFunds` 与 `userPreorderData.funds`。
- 容量上限：`totalPreorderFunds <= totalMemecoinFunds * preorderCapRatio / 10000`。

## 3. Locked 时的初始资金部署

### 3.1 初始 memecoin 侧

- 首次铸币量：`memecoinAmount = totalMemecoinFunds * fundBasedAmount`。
- launcher 把 `memecoinAmount + totalMemecoinFunds(UPT)` 加到 `memecoin/UPT` 池。

### 3.2 preorder 结算

- 若 `preorderStates.totalFunds > 0`，launcher 在进入 Locked 时执行一次 launch settlement swap，把 preorder 的 UPT 预算换成 memecoin。
- 结果记为：
  - `settledMemecoin`
  - `settlementTimestamp`
  用于后续线性解锁领取。

### 3.3 POL 侧与两类 LP 账

- launcher 先按 `memecoinLiquidity` 等量 mint POL 到自己。
- 其中 `deployedPOL = memecoinLiquidity / 3` 用于创建 `POL/UPT` 首池。
- 记账：
  - `totalPolLiquidity = polPoolLiquidity`
  - `totalClaimablePOL = memecoinLiquidity - deployedPOL`

## 4. 用户份额公式

### 4.1 POL 领取

- 可领 POL（未领取时）：
`claimable = totalClaimablePOL * userGenesisFund / (totalMemecoinFunds + totalPolFunds)`

### 4.2 preorder 线性解锁

- 用户总可得 preorder memecoin：
`purchased = settledMemecoin * userPreorderFunds / preorderTotalFunds`
- 线性释放窗口：`preorderVestingDuration`，已领数量累计在 `claimedMemecoin`。

### 4.3 Unlocked 后退出

- `redeemMemecoinLiquidity`：burn `amountInPOL`，按 1:1 转出 memecoin LP。
- `redeemPolLiquidity`：一次性按比例赎回 POL LP：
`amountInLP = totalPolLiquidity * userGenesisFund / totalGenesisFunds`。

## 5. Fee 记账与分发

### 5.1 fee 来源与映射

- launcher 从两池 claim fee：
  - `memecoin/UPT` 池 -> `(memecoinFee, UPTFee_part1)`
  - `POL/UPT` 池 -> `(liquidProofFee, UPTFee_part2)`
- `UPTFee = part1 + part2`。
- `liquidProofFee` 在 launcher 内直接 burn，不进入收益分发。

### 5.2 执行者奖励与治理收入

- `executorReward = UPTFee * executorRewardRate / 10000`。
- `govFee = UPTFee - executorReward`。
- 执行者奖励直接发给 `rewardReceiver`。

### 5.3 治理链本地/异链分发

- 若治理链为本链：
  - `govFee(UPT)` -> `yieldDispatcher` -> `Governor.receiveTreasuryIncome`
  - `memecoinFee` -> `yieldDispatcher` -> `YieldVault.accumulateYields`
- 若治理链为异链：
  - 分别构建两笔 OFT send
  - `msg.value` 必须等于两笔报价和（实现要求“等于”，不是“大于等于”）

## 6. Treasury / Yield / Governance 周期语义

- Governor 作为 treasury 入口，收到收入时先把真实资产记入 `Governor` 托管余额，再同步通知 `GovernanceCycleIncentivizer` 做周期账本累计。
- `Governor` 持有真实 treasury 资产与 reward payout 资产。
- `Incentivizer` 只维护对应的周期账本，不承担奖励资产托管职责。
- `treasuryBalances[token]` 表示某周期内记入 DAO treasury 的可支配账本余额，其真实资产由 `Governor` 托管。
- `rewardBalances[token]` 表示某周期内已为用户奖励保留的可支付账本额度，其真实资产仍由 `Governor` 托管。
- `Incentivizer` 的账本字段不应被解释为 `Incentivizer` 的 ERC20 实际余额。
- treasury / reward accounting 默认按名义 `amount` 记账，只支持已审查的标准 ERC20。
- fee-on-transfer、rebasing、或其他会使名义 `amount` 与实际余额变化不一致的 token 不在支持范围内。
- Incentivizer 周期结算时按 `rewardRatio` 从 treasury ledger 划拨到 reward ledger。
- 用户奖励按“上一周期 userVotes / totalVotes”分配。
- `Incentivizer.claimReward()` 结算后，由 `Governor.disburseReward(...)` 完成真实付款。
- claim 成功前，账本扣减与真实付款必须保持同一事务内原子完成。
- 上一周期未领完的 `rewardBalances[token]` 不永久保留；它们会在后续 `finalizeCurrentCycle()` 时回卷到 treasury ledger，并重新参与后续周期结算。
- YieldVault 在 `totalSupply == 0` 时收到 yield 会 burn（防首存者攫取历史收益）。

## 7. Launch Fee 记账

### 7.1 概述

- Launch fee 是在 token launch 阶段（池初始化后的一段时间窗口内）对 swap 施加的额外费率保护。
- 每个池的 launch 时间戳在 `beforeInitialize` 中记录为 `poolLaunchTimestamp[poolId]`。
- Launch fee 与动态费叠加取 max：`effectiveFeeBps = max(dynamicFeeBps, launchFeeBps)`。
- 动态费率由三部分组成：
  - **Adverse（per-address）**：基于 per-address 3 秒窗口内的累积 PIF 计算的逆向冲击费。同一地址在 3 秒内连续交易的 PIF 会累积，使拆单攻击面临与大单等同的费率。3 秒窗口从 batch 首笔交易开始计时，到期后重置。普通用户单笔交易不受影响。公式为软饱和曲线：`adverse = dffMax × effectivePif / (effectivePif + pifCap) × effectivePif / 1e6`。
  - **Volatility（per-pool）**：基于波动率偏差累加器计算的波动费。使用 sqrt 曲线平滑费率响应（避免二元跳变），累加器按价格偏差步数增长，经 10 秒 filter period 和 60 秒 decay period 衰减。上限约 50 bps，由 `sqrt(acc × volQuadraticFeeControl) / 56125` 推导。
  - **Short-term（per-pool）**：基于短期冲击累加器的快速交易惩罚。15 秒线性衰减窗口，2% floor 保护普通用户（累积 PIF 低于 floor 不收费），cap 限制最大 200 bps。
- `dynamicFeeBps = baseFeeBps + adverseBps + volatilityBps + shortBps`，硬上限 `maxFeeBps = 10000`。

### 7.2 衰减公式

- 默认配置 `defaultLaunchFeeConfig`：
  - `startFeeBps = 5000`（50%）
  - `minFeeBps = 100`（1%，即 `FEE_BASE_BPS`）
  - `decayDurationSeconds = 900`（15 分钟）
- 形状参数 `LAUNCH_FEE_EXP_SHAPE_WAD = 4e18`，指数衰减曲线：
  - `elapsed = block.timestamp - launchTimestamp`
  - 若 `elapsed >= decayDurationSeconds`，直接返回 `minFeeBps`
  - 否则：
    ```
    expAtElapsed = wadExp(-elapsed * SHAPE / decayDuration)
    expAtEnd     = wadExp(-SHAPE)
    decayWad     = (expAtElapsed - expAtEnd) * 1e18 / (1e18 - expAtEnd)
    feeBps       = minFeeBps + (startFeeBps - minFeeBps) * decayWad / 1e18
    ```
- 衰减单调递减：`elapsed` 增大时 `feeBps` 单调递减，不变量由 `LaunchFeeQuoteHandler` 测试保证。

### 7.3 Launch Fee 的分配对象

- Launch fee 本身不产生独立分配；它是 effective fee 的一部分，参与与常规 swap fee 相同的拆分：
  - **LP 分配**：`lpFeeBps = effectiveFeeBps - protocolFeeBps`（即 `effectiveFeeBps * 7000 / 10000`）
  - **Protocol 分配**：`protocolFeeBps = effectiveFeeBps * 3000 / 10000`
- LP fee 按 per-share 累加到 `fee0PerShare / fee1PerShare`，LP 持有人通过 `claimFeesCore` 领取。
- Protocol fee 发送到 `treasury` 地址。

### 7.4 Launch Settlement 的固定费率

- Launch settlement swap（preorder 结算）使用独立路径 `executeLaunchSettlement`，不经过 `beforeSwap/afterSwap` 回调。
- 固定费率 `LAUNCH_SETTLEMENT_FEE_BPS = 100`（1%），不使用动态费也不使用衰减曲线。
- 分配同样遵循 70/30 拆分：
  - `lpFeeBps = 70`（0.7%）
  - `protocolFeeBps = 30`（0.3%）
- 输入侧费用在 settlement 入口直接收取：
  - LP fee 部分：从 `payer` pull ERC20 到 hook，按 per-share 计入 LP 分配；若 `totalSupply == 0` 则只收取不计入。
  - Protocol fee 部分：从 `payer` pull ERC20 直接到 `treasury`。
- 输出侧 protocol fee（当 `!protocolFeeOnInput` 时）在 settlement callback 中从 pool output 扣取后发送到 `treasury`。

### 7.5 配置管理

- `setDefaultLaunchFeeConfig`：owner 可更新全局默认配置。
  - 校验：`startFeeBps / minFeeBps / decayDurationSeconds` 均不能为零。
  - 校验：`startFeeBps <= 10000`，`minFeeBps <= 10000`，`minFeeBps <= startFeeBps`。
- 更新后对新池立即生效（已创建的池使用创建时的 `poolLaunchTimestamp`，不受配置变更影响）。
- 变更通过 `DefaultLaunchFeeConfigUpdated` 事件链上可审计。
