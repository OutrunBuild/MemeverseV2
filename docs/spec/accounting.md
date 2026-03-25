# MemeverseV2 记账与资金语义

## 1. 说明与来源边界

- 本文档是当前产品真相层的一部分，定义当前记账规则。
- 规则证据来自 `src/**` 与 `test/**`。

## 2. Genesis 与 Preorder 入账

### 2.1 Genesis 拆分

- 每笔 `genesis(amountInUPT)` 拆分为：
  - `memecoinFund = amountInUPT * 3/4`
  - `liquidProofFund = amountInUPT * 1/4`
- `userGenesisData[verseId][user].genesisFund` 按用户累计，不是覆盖。
- 全局累计在 `genesisFunds.totalMemecoinFunds/totalLiquidProofFunds`。

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
`claimable = totalClaimablePOL * userGenesisFund / (totalMemecoinFunds + totalLiquidProofFunds)`

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

- Governor 作为 treasury 入口，收到收入时同步通知 `GovernanceCycleIncentivizer` 做周期账本累计。
- Incentivizer 周期结算时按 `rewardRatio` 从 treasury balance 划拨到 reward balance。
- 用户奖励按“上一周期 userVotes / totalVotes”分配。
- YieldVault 在 `totalSupply == 0` 时收到 yield 会 burn（防首存者攫取历史收益）。

## 7. 启动期会计提醒

- 启动期会计重点是 launch fee 衰减与 launch settlement 固定 `1%` 路径。
