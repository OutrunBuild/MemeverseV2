# MemeverseV2 记账与资金语义

## 1. 说明与来源边界

- 本文档是当前产品真相层的一部分，定义当前记账规则。
- 规则证据来自 `src/**` 与 `test/**`。

## 2. Genesis 与 Preorder 入账

### 2.1 普通 Genesis

- 普通创世不再使用旧 `75/25`、`GenesisFund`、`totalMemecoinFunds/totalPolFunds` 拆账模型。
- `genesis(verseId, amount, user)` 只接受该 verse 的 `uAsset`，累加：
  - `totalNormalFunds += amount`
  - `userGenesisFund += amount`
- `totalNormalFunds` 不包含 preorder、杠杆利息或杠杆债务。

### 2.2 杠杆 Genesis

- 杠杆创世由 `POLend` 记录用户支付的利息，并按 market 固定利率推导债务：
`totalLeveragedDebt = totalLeveragedInterest * 1e18 / market.interestRate`
- `Genesis` 阶段不 mint 杠杆 `uAsset`；只有成功进入 `Locked` 时才由 `POLend.finalizeLeveragedGenesis` mint 推导债务并计入按 `uAsset` 维度的系统债务。
- 杠杆退款、初始 `YT`、残值、PT fee 预兑付与全局结算规则以 `docs/spec/polend/polend.md` 为准。

### 2.3 Preorder 入账

- preorder 是独立账本，不参与四池部署本金。
- preorder 容量只基于主池 memecoin 侧资金计算：
`preorderCap = (totalNormalFunds + totalLeveragedDebt) * 70% * preorderCapRatio / RATIO`
- `totalLeveragedDebt` 由当前 market 利率和 `totalLeveragedInterest` 推导；无杠杆参与时视为 0。
- `Refund` 状态下，preorder 用户按 `userPreorderFunds` 一次性退回该 verse 的 `uAsset`。

## 3. Locked 时的初始资金部署

### 3.1 Genesis -> Locked 资金口径

- 成功部署资金口径：
`totalGenesisFunds = totalNormalFunds + totalLeveragedDebt`
- `totalGenesisFunds` 不等于退款资金池，也不包含 preorder。
- `POLSplitter.initializeVerse` 在四池部署前调用；PT/YT 初始化不依赖是否有杠杆参与。

### 3.2 四池部署

- `totalGenesisFunds` 统一按 `70/30` 拆分：
  - `70%` 进入 `memecoin/uAsset` 主池。
  - `30%` 进入三个辅助池路径。
- 四池为：
  - `memecoin/uAsset`
  - `POL/uAsset`
  - `PT/uAsset`
  - `PT/POL`
- POL、PT、YT 的拆分比例、辅助池资产配比和 LP 记录以 `docs/spec/polend/polend.md` 为准。

### 3.3 preorder 结算

- `Launcher` 先部署 `memecoin/uAsset` 主池，再使用托管 preorder `uAsset` 执行首笔交易买入 `memecoin`。
- 买出的 `memecoin` 由 `Launcher` 托管，并按 `userPreorderFunds / totalPreorderFunds` 线性释放。

## 4. 用户份额公式

### 4.1 初始 YT

- 四池部署时 split 得到的 `YT` 按资金占比分配：
`totalNormalClaimableYT = totalYT * totalNormalFunds / totalGenesisFunds`
`totalLeveragedYT = totalYT - totalNormalClaimableYT`
- 普通初始 `YT` 由 `Launcher` 托管并按 `userGenesisFund / totalNormalFunds` 领取。
- 杠杆初始 `YT` 由 `POLend` 托管并按 `userInterestPaid / totalLeveragedInterest` 领取。

### 4.2 preorder 线性解锁

- 用户总可得 preorder memecoin：
`purchased = settledMemecoin * userPreorderFunds / totalPreorderFunds`
- 线性释放窗口：`preorderVestingDuration`，已领数量累计在 `claimedMemecoin`。

### 4.3 Unlocked 后退出

- `redeemMemecoinLiquidity(verseId, amountInPOL)` 等价于 `unwrap=false`。
- `redeemMemecoinLiquidity(verseId, amountInPOL, unwrap)`：先 burn `amountInPOL`，再令 `amountInLP = amountInPOL`。
  - `unwrap=false`：按 `amountInLP` 转出 `memecoin/uAsset` LP token。
  - `unwrap=true`：按 `amountInLP` 移除 `memecoin/uAsset` LP，并发送底层 `memecoin` 与 `uAsset`。
- 该路径是 `Unlocked` 退出路径；解锁后保护窗口内仍允许执行，但不是公开 swap。
- `redeemAuxiliaryLiquidity`：普通用户在 `Unlocked` 后一次性领取三个辅助池普通份额 LP token，份额基准为 `userGenesisFund / totalNormalFunds`。
- 若存在杠杆债务，`Locked -> Unlocked` 的同一笔交易内先执行 POLend 全局结算并切走杠杆份额 LP；普通用户只能领取结算后剩余的普通份额。
- 杠杆残值由 `POLend` 记录并按 `userInterestPaid / totalLeveragedInterest` 领取；残值不属于 `POLSplitter` 的 PT/YT 兑付池。
- 旧 `claimable POL` / `redeemPolLiquidity` 两池语义不再作为当前规则。

## 5. Fee 记账与分发

### 5.1 主池 fee

- `memecoin/uAsset` 主池 fee 沿用 Memeverse 原规则：
  - `uAsset` fee 走 Memeverse DAO governor 路径。
  - `memecoin` fee 给 `yieldVault`。

### 5.2 辅助池 fee

- 辅助池为 `POL/uAsset`、`PT/uAsset`、`PT/POL`。
- `POL` fee 全部 burn。
- `Locked` 阶段的 `uAsset fee / PT fee` 按 `totalGenesisFunds = totalNormalFunds + totalLeveragedDebt` 切分：
  - 普通侧进入 `normalFeeStates`，用户按 `userGenesisFund / totalNormalFunds` 领取。
  - 杠杆侧最终转换为 `uAsset` 后进入 Memeverse DAO governor 路径，不进入 `POLend.protocolTreasury`。
- `Unlocked` 后新产生的辅助池非 `POL` fee 全部归 Memeverse DAO governor，普通用户仍可补领历史 `Locked` 阶段普通侧 fee。
- PT fee 的预兑付、settle 后 redeem、pending auxiliary gov fee 规则以 `docs/spec/polend/polend.md` 为准。

### 5.3 执行者奖励与治理收入

- 对进入 DAO governor 路径的 `uAsset` fee，`executorReward = uAssetFee * executorRewardRate / 10000`。
- `govFee = uAssetFee - executorReward`。
- 执行者奖励直接发给 `rewardReceiver`。

### 5.4 治理链本地/异链分发

- 若治理链为本链：
  - `govFee(uAsset)` -> `yieldDispatcher` -> `Governor.receiveTreasuryIncome`
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
- **EWVWAP 豁免**：当池存在 EWVWAP 历史且交易方向回归 EWVWAP（即交易后 spot 距离 EWVWAP 更近）时，跳过全部动态费组件（adverse + volatility + short），直接返回 `baseFeeBps`。无历史时视为 adverse。此豁免大幅降低零售用户回归方向的费率负担。
- 当不满足 EWVWAP 豁免时，动态费率由三部分组成：
  - **Adverse（per-address）**：基于 per-address 3 秒窗口内的累积 PIF 计算的逆向冲击费。同一地址在 3 秒内连续交易的 PIF 会累积，使拆单攻击面临与大单等同的费率。3 秒窗口从 batch 首笔交易开始计时，到期后重置。普通用户单笔交易不受影响。公式为软饱和曲线：`adverse = dffMax × effectivePif / (effectivePif + pifCap) × effectivePif / 1e6`。
  - **Volatility（per-pool）**：基于波动率偏差累加器计算的波动费。使用 sqrt 曲线平滑费率响应（避免二元跳变），累加器按价格偏差步数增长，经 10 秒 filter period 和 60 秒 decay period 衰减。实现采用整数公式 `floor(sqrt(accumulator * VOL_MAX_FEE_BPS^2 / VOL_MAX_DEVIATION_ACCUMULATOR))`；其中 `VOL_MAX_FEE_BPS = 50`、`VOL_MAX_DEVIATION_ACCUMULATOR = 1_500_000`，当累加器达到上限时精确得到 `50` bps，低累加器区间会因整数除法与整数开方产生截断。
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
