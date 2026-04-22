# MemeverseV2 治理与收益细化说明

## 1. 目标

本文解释 yield vault、governor treasury 与 governance cycle incentivizer 在 V2 中如何协作，以及 fee / yield / reward 在账本上的流向。

## 2. 三个核心模块

- `MemecoinYieldVault`
  - 持有 memecoin 收益
  - 铸造 share token
  - 管理延迟赎回队列
- `MemecoinDaoGovernorUpgradeable`
  - 作为 DAO treasury 入口
  - 接收 UPT treasury 收入
  - 执行治理动作
- `GovernanceCycleIncentivizerUpgradeable`
  - 记录 treasury / reward 周期账本
  - 结算 reward
  - 按上一周期投票份额分发奖励

## 3. fee 到治理与收益的分流

launcher 从两池 claim fee 后，当前主分流为：

- `liquidProofFee`：直接 burn
- `UPTFee`
  - 拆成 `executorReward + govFee`
- `memecoinFee`
  - 进入 yield 路径

进一步流向：

- `govFee(UPT)` -> `YieldDispatcher` -> `Governor.receiveTreasuryIncome`
- `memecoinFee` -> `YieldDispatcher` -> `YieldVault.accumulateYields`

## 4. YieldVault 的份额模型

YieldVault 不是简单余额池，而是 share 模型：

- 用户 deposit underlying memecoin
- vault 按当前 `totalAssets / totalSupply` 关系铸造 shares
- yield 进入后增加 `totalAssets`
- share 汇率随之变化

因此 vault 的核心不是“固定收益率”，而是“share 对 underlying 的兑换关系”。

## 5. 为什么 `totalSupply == 0` 时要 burn yield

当 vault 还没有任何 share 持有人时，历史 yield 不能留在池中等待第一个存入者白拿。

因此当前规则是：

- 若 `totalSupply == 0`
- 收到 yield 时直接 burn

这条规则的目标是防止首存者攫取历史收益。

## 6. 延迟赎回队列

V2 当前没有即时赎回 underlying，而是：

1. `requestRedeem`
2. 进入队列
3. 等待 `REDEEM_DELAY`
4. `executeRedeem`

关键约束：

- 每个地址最多 `MAX_REDEEM_REQUESTS`
- 请求时即锁定本次 underlying 数量
- 实际转账在执行时完成

这个模型的目的，是降低 flash 攻击和瞬时套利对 vault 的影响。

## 7. Governor Treasury 语义

Governor 在 V2 中不只是投票入口，也是 DAO treasury 与 governance reward payout 的唯一资产托管者。

治理与奖励路径采用以下固定语义：

- `MemecoinDaoGovernorUpgradeable`
  - 持有 DAO treasury 资产
  - 持有 governance reward payout 资产
  - 执行真实 treasury 收款、真实 treasury 支出与真实 reward payout
- `GovernanceCycleIncentivizerUpgradeable`
  - 维护 treasury ledger
  - 维护 reward ledger
  - 负责 cycle finalize 与用户 reward claim 结算
  - 不承担奖励资产托管职责

因此：

- `Governor` 中的真实 ERC20 余额才是 DAO treasury / reward payout 的 canonical asset state
- `Incentivizer` 中的 `treasuryBalances` 与 `rewardBalances` 只是针对 `Governor` 托管资产的账本视图，不等同于 `Incentivizer` 的 ERC20 实际余额
- 除文档显式声明 escrow 模式外，`Incentivizer` 不应作为 reward token 的 canonical holder
- `registerTreasuryToken(...)` 与 `registerRewardToken(...)` 仅允许治理注册已审查的标准 ERC20
- fee-on-transfer、rebasing、或其他会使名义 `amount` 与实际余额变化不一致的 token 不在支持范围内
- treasury / reward 资产准入责任由治理承担，不由运行时 delta 检查兜底

Treasury income 与 treasury spend 的调用链为：

- `Governor.receiveTreasuryIncome(token, amount)`
  - 表示真实资产进入 DAO treasury
  - 在同一事务中把 `token` 转入 `Governor`
  - 再调用 `Incentivizer.recordTreasuryIncome(token, amount)` 把这笔收入登记到当前周期账本
- `Governor.sendTreasuryAssets(token, to, amount)`
  - 表示真实 treasury 支出
  - 在同一事务中先调用 `Incentivizer.recordTreasuryAssetSpend(token, to, amount)` 把这笔支出登记到当前周期账本
  - 再把真实 token 从 `Governor` 转给 `to`

这里：

- `Incentivizer.recordTreasuryIncome(token, amount)` 是纯账本动作，不发生 token transfer
- `Incentivizer.recordTreasuryAssetSpend(token, to, amount)` 是纯账本动作，不发生 token transfer

## 8. Incentivizer 周期语义

Incentivizer 负责把 treasury ledger 的一部分，按周期转成 reward ledger，并按用户投票份额结算奖励。

关键要点：

- 周期长度固定
- `rewardRatio` 决定从 treasury ledger 划拨多少到 reward ledger
- 用户最终按“上一周期 userVotes / totalVotes”获取奖励
- `finalizeCurrentCycle()` 的核心语义是账本切换与结算，不要求把 token 从 `Governor` 转入 `Incentivizer`
- 上一周期未领完的 `rewardBalances` 会在后续 `finalizeCurrentCycle()` 时回卷到 treasury ledger

因此 reward 分发依赖的不是实时余额，而是周期化结算。

用户奖励领取入口采用以下固定语义：

- 用户通过 `Incentivizer.claimReward()` 领取奖励
- 第一版只支持 `msg.sender` 领取给自己，不支持指定 `receiver`，不支持代领
- `Incentivizer.claimReward()` 在同一事务中：
  1. 以 `msg.sender` 作为 reward owner 计算上一周期可领奖励
  2. 扣减上一周期对应的 `rewardBalances`
  3. 调用 `Governor.disburseReward(token, msg.sender, amount)` 完成真实付款
- `Governor.disburseReward(...)` 只允许配对的 `Incentivizer` 调用，不属于通用 treasury 支出入口
- 若 `Governor.disburseReward(...)` 失败，则整笔 claim 回滚，账本扣减也回滚

## 9. 权限边界

当前语义下：

- governor treasury 支出与升级授权属于治理执行权限
- `Governor.disburseReward(...)` 属于 `Incentivizer` 驱动的受限 payout 路径，不属于治理执行权限
- `Incentivizer.recordTreasuryIncome(...)` 与 `Incentivizer.recordTreasuryAssetSpend(...)` 仅允许 `Governor` 调用
- `Incentivizer.claimReward()` 属于用户业务入口，不受 `onlyGovernance` 限制
- `finalizeCurrentCycle()` 可保持 permissionless，但其开放性仅限于推进周期状态

这意味着：

- 需要用规则文档而不是直觉理解权限
- 对开放入口要关注其调用前提，而不是只看是否 `onlyGovernance`
- `claimReward()` 必须始终把终端用户 `msg.sender` 视为 reward owner，不能把 `Governor`、治理执行者或其他中间调用者视为 reward owner

## 10. 当前实现提醒

- yield vault、governor、incentivizer 三者的高层产品叙事是连续的，但 custody 与 ledger 语义必须严格分层
- reward 不是在 fee 到达时立即逐用户发放，而是先进入 treasury ledger，再在 finalize 后转成 reward ledger，最后由用户 claim
- 若后续引入更多治理金融化能力，必须继续尊重“Governor 托管资产、Incentivizer 维护账本”的边界

## 11. 相关真源与证据

- `docs/spec/accounting.md`
- `docs/spec/access-control.md`
- `docs/spec/deployment.md`
- `docs/spec/implementation-map.md`
- `docs/TRACEABILITY.md`
