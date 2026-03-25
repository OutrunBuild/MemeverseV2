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

Governor 在 V2 中不只是投票入口，也是 treasury 入口。

收到 treasury 收入时：

- 先记 treasury 账
- 再联动 incentivizer 做周期账本累计

因此 governor 和 incentivizer 不是两个孤立系统，而是 treasury 与 reward 的前后层。

## 8. Incentivizer 周期语义

Incentivizer 负责把 treasury 余额的一部分，按周期转成 reward 余额。

关键要点：

- 周期长度固定
- `rewardRatio` 决定从 treasury 划拨多少到 reward
- 用户最终按“上一周期 userVotes / totalVotes”获取奖励

因此 reward 分发依赖的不是实时余额，而是周期化结算。

## 9. 权限边界

当前语义下：

- governor treasury 支出与升级授权属于治理执行权限
- incentivizer 多数敏感接口由 governor 路径控制
- 但 `receiveTreasuryIncome` 与 `finalizeCurrentCycle` 不是完全封闭的 owner-only 入口

这意味着：

- 需要用规则文档而不是直觉理解权限
- 对开放入口要关注其调用前提，而不是只看是否 `onlyGovernance`

## 10. 当前实现提醒

- yield vault、governor、incentivizer 三者的高层产品叙事是连续的，但执行层是三个独立账本系统
- reward 不是在 fee 到达时立即逐用户发放，而是先进入 treasury / cycle 账本，再按周期结算
- 若后续引入更多治理金融化能力，必须继续尊重这个周期化结算边界

## 11. 相关真源与证据

- `docs/spec/accounting.md`
- `docs/spec/access-control.md`
- `docs/spec/deployment.md`
- `docs/spec/implementation-map.md`
- `docs/TRACEABILITY.md`
