# POLend 规格文档

## 1. 文档定位

本文档是 `POLend` 与 MemeverseV2 集成后的唯一产品真源。

本文档定义产品语义、资金流、状态边界、结算规则和接口职责。实现、测试、计划与开发辅助文档都必须服从本文档。

其他 POLend 相关文档只能作为开发辅助材料，不得定义本文档未覆盖的产品规则；若其他文档与本文档冲突，以本文档为准。

本文档不描述“当前代码已实现”的状态。

不在本文档范围内：

- PT 抵押借款
- `POLendRouter`
- 旧 `75/25` 创世拆分
- 旧三池模型
- 未接入 `POLend / POLSplitter` 的降级运行模式

## 2. 核心目标

`POLend` 的核心目标是给 `Memeverse` 创世增加杠杆创世能力。

杠杆创世不是通用借贷。用户在 `Genesis` 阶段支付利息，协议在成功进入 `Locked` 时按该 verse 固定利率 mint 对应 `uAsset` 参与创世。若创世失败进入 `Refund`，杠杆用户只取回自己支付的利息，不发生 `uAsset` mint。

每个 verse 独立绑定自己的 `uAsset`。该 verse 的利息收取、杠杆 mint、退款、fee、PT 兑付、YT 兑付、全局结算都只能使用该 verse 绑定的 `uAsset`。

## 3. 核心术语

| 术语 | 含义 |
|---|---|
| `uAsset` | 统一记账资产，也是利息、mint、债务偿还和 PT 兑付的计价资产 |
| `memecoin` | verse 的项目代币 |
| `POL` | Proof of Liquidity，创世流动性证明 |
| `PT` | Principal Token，本金凭证，`1 PT = 1 uAsset` |
| `YT` | Yield Token，收益凭证 |

关键关系：

- `1 POL = 1 PT + 1 YT`
- `1 PT = 1 uAsset`
- `YT` 代表 `Splitter` 结算池内对应 `POL collateral` 的收益权益：兑付时按比例获得 `settlementUAsset` 中扣除 PT 准备金后的剩余 `uAsset` 以及全部 `settlementMemecoin`，不覆盖 `POLend` 残值，也不天然代表全部创世剩余资产
- `POL` 被 split 后成为 `Splitter` 托管的 `POL collateral`
- `Unlocked` 后，`POL collateral` 统一结算成 `settlementUAsset + settlementMemecoin`

## 4. 模块边界

`POLend` 与 `POLSplitter` 是四池模式的必配模块。

`Launcher` 不支持 `polend=0`、`polSplitter=0` 或任何未接入 `POLend / POLSplitter` 的降级模式。

### 4.1 Launcher

`Launcher` 负责：

- verse 生命周期编排
- 普通创世资金托管与退款
- preorder 资金托管、首笔交易与 vesting
- 四池部署
- 普通初始 `YT` 托管与发放
- 普通辅助池 LP 领取
- 普通辅助池 fee 记账与领取
- 辅助池 fee 捕获与 DAO governor 分发编排
- `Locked -> Unlocked` 编排以 §18 为唯一权威顺序
- 本链与异链 `YieldDispatcher / OFT` 分发路径

### 4.2 POLend

`POLend` 负责：

- 杠杆创世 market 注册
- 固定 market 利率
- 杠杆利息托管
- 成功时 mint 杠杆 `uAsset`
- 成功时把杠杆利息转给 `protocolTreasury`
- 杠杆退款
- 杠杆初始 `YT` 托管与发放
- 杠杆残值记账与领取
- 按 `uAsset` 维度记录系统债务
- 杠杆侧全局结算与债务偿还
- settle 前杠杆侧 PT fee 预兑付
- settle 时预兑付 PT fee backing 的 repay

`POLend.protocolTreasury` 只接收杠杆利息收入。它不是 Memeverse DAO governor，不是 `yieldVault`，也不接收主池 fee 或辅助池 fee。

### 4.3 POLSplitter

`POLSplitter` 负责：

- per-verse 初始化 `PT / YT`
- `split / merge`
- `settle`
- `preRedeemPTFee` 的 PT burn 与 `preRedeemedPT` 记录
- `redeemPT / redeemYT`

`POLSplitter` 不负责普通创世、杠杆退款、杠杆残值、preorder 或跨链发送。

## 5. 市场注册与利率

`POLend` 有全局默认利率：

```text
defaultInterestRate
```

约束：

```text
0 < defaultInterestRate <= 1e18
```

`defaultInterestRate` 是一次性创世利息比例，不是年化利率。

`setDefaultInterestRate(newRate)` 只影响未来新注册 verse，不影响任何已注册 market。

`Launcher.registerMemeverse` 必须在同一交易内调用：

```text
POLend.registerLendMarket(verseId)
```

`registerLendMarket` 只能由 `Launcher` 调用，每个 `verseId` 只能调用一次。

注册时：

- 从 `Launcher` 读取该 verse 的 `uAsset`
- 复制当前 `defaultInterestRate` 到 `market.interestRate`
- 设置 `market.state = None`
- 不初始化 `PT / YT`
- 不记录 `POL`
- 不记录 `PT`
- 不存储 `totalLeveragedDebt`

`market.interestRate` 注册后固定不变。

已注册判断使用 `market.interestRate != 0`。`uAsset == address(0)` 不作为正常产品分支；注册中心 / `Launcher` 必须保证注册的 verse 有有效 `uAsset`。

## 6. POLend 状态

### 6.1 Market

`getLendMarket(verseId)` 返回的 market 字段为：

```solidity
struct LendMarket {
    address uAsset;
    address yt;
    uint256 interestRate;
    uint256 totalLeveragedInterest;
    uint256 totalLeveragedYT;
    MarketState state;
}
```

`POLend` 不在 `LendMarket` 中保存：

- `pt`
- `pol`
- `totalLeveragedDebt`
- `availableLaunchLiquidity`

### 6.2 Market 状态

```solidity
enum MarketState {
    None,
    Genesis,
    Locked,
    Settled,
    Refund
}
```

`None` 表示 market 已注册但无人参与杠杆创世。

第一笔 `leveragedGenesis` 成功存入利息后，market 从 `None` 进入 `Genesis`。

纯普通创世成功后，market 保持 `None`，不进入 `Locked / Settled / Refund`。

`claimRefund / claimLeveragedYT / claimResidual` 对 `state == None` revert `InvalidClaim`。

`Genesis → Refund` 的触发条件：创世阶段结束时（`totalNormalFunds < minTotalFund` 且 `totalLeveragedInterest < minTotalFund`），且 `market.state == Genesis`（有人参与杠杆创世）。`Launcher.changeStage` 在此条件下调用 `POLend.markRefundable(verseId)`。若 `market.state == None`（无杠杆参与），不调用 `markRefundable`。

### 6.3 用户杠杆状态

用户级只保存：

```solidity
mapping(uint256 verseId => mapping(address user => uint256 interestPaid)) leveragedInterestPaid;
```

不保存 `borrowedAmount`，不需要 `LeveragedPosition` 结构体。

用户可多次参与杠杆创世，`interestPaid` 持续累加。

### 6.4 残值状态

`ResidualState` 只保存初始总残值：

```solidity
struct ResidualState {
    uint256 residualUAsset;
    uint256 residualMemecoin;
}
```

用户 claim 后不递减这两个基数，只用 `residualClaimed` 防止重复领取。

### 6.5 Claim 状态

语义上保留三类独立 claim 状态：

- `refundClaimed`
- `leveragedYTClaimed`
- `residualClaimed`

三类状态在本文档中视为独立 bool 语义；实现层可将其压缩为位图等内部表示，只要对外行为与三个独立 bool 等价即可。

### 6.6 按 uAsset 维度的系统债务

`POLend` 必须按 `uAsset` 维度保存系统债务：

```text
globalDebtByUAsset[uAsset]
```

不保留单一 `globalTotalDebt` 产品语义，不把不同 `uAsset` 的债务混成名义总数。

对外 view：

```text
getTotalDebtByUAsset(uAsset)
```

不需要 `getTotalDebt()` 返回所有 `uAsset` 债务的名义总和。

`globalDebtByUAsset[uAsset]` 与 `uAsset.mintingStatusTable[POLend].amountInMinted` 保持一致口径：

- POLend mint 增加对应 `uAsset` 债务
- POLend repay 减少对应 `uAsset` 债务

`Genesis` 阶段的推导债务不计入 `globalDebtByUAsset`。

## 7. 债务推导

每个 market 的总杠杆债务不存储，始终由固定利率和累计利息推导：

```text
totalLeveragedDebt = totalLeveragedInterest * 1e18 / market.interestRate
```

用户债务也不存储：

```text
userLeveragedDebt = userInterestPaid * 1e18 / market.interestRate
```

debt view 状态矩阵：

| Market 状态 | `getTotalLeveragedDebt` | `getUserLeveragedDebt` | `debtCap` | `remainingAdditionalInterest` |
| --- | --- | --- | --- | --- |
| 未注册 | revert | revert | revert | revert |
| `None` 且 Launcher verse 仍处于 `Genesis` | `0` | `0` | 正常计算 | 正常计算 |
| `None` 且 Launcher verse 已离开 `Genesis` | `0` | `0` | `0` | `0` |
| `Genesis` | 推导值 | 推导值 | 正常计算 | 正常计算 |
| `Locked` | 推导值 | 推导值 | `0` | `0` |
| `Settled` | 推导值 | 推导值 | `0` | `0` |
| `Refund` | 理论推导值 | 理论推导值 | `0` | `0` |

已注册但 `state == None` 时，`getLeveragedDebtInfo(verseId)` 返回 `totalLeveragedInterest=0,totalLeveragedDebt=0,interestRate=market.interestRate`，并按上表返回 `debtCap / remainingAdditionalInterest`。

`Refund` 状态下的 `getTotalLeveragedDebt(verseId)` 仍只是理论推导值，不代表真实已 mint 债务。只有成功执行 `finalizeLeveragedGenesis` 后，该 verse 的债务才进入真实系统债务。

`getLeveragedDebtInfo(verseId)` 只查询该 verse 的债务信息，与全局债务无关。

```solidity
struct LeveragedDebtInfo {
    uint256 totalLeveragedInterest;
    uint256 totalLeveragedDebt;
    uint256 interestRate;
    uint256 debtCap;
    uint256 remainingAdditionalInterest;
}
```

其中：

```text
debtCap = fullPrecisionMulDiv(leveragedDebtFactor, max(totalNormalFunds, minTotalFund), 1e18)
totalLeveragedDebt = totalLeveragedInterest * 1e18 / market.interestRate
```

`remainingAdditionalInterest` 表示在当前 `Genesis` 状态下还能新增的最大利息，使新增后的推导债务仍满足 `totalLeveragedDebt <= debtCap`。

精确计算：

```text
maxTotalLeveragedInterest = ((debtCap + 1) * market.interestRate - 1) / 1e18

if maxTotalLeveragedInterest <= totalLeveragedInterest:
    remainingAdditionalInterest = 0
else:
    remainingAdditionalInterest = maxTotalLeveragedInterest - totalLeveragedInterest
```

该公式与 `totalLeveragedInterest * 1e18 / market.interestRate` 的向下取整语义严格匹配。实现应使用全精度乘除，避免中间乘法溢出。

## 8. 普通创世状态

`Launcher` 不再使用 `GenesisFund`。

`Memeverse` 内保存：

```text
totalNormalFunds
```

`totalNormalFunds` 表示普通创世用户支付的 `uAsset` 总额，不包含 preorder，不包含杠杆利息，不包含杠杆债务。

用户侧只保存：

```text
userGenesisFund
```

普通创世不拆存 `userMemecoinFund / userAuxiliaryFund`。

`genesis(verseId, amount, user)`：

- `amount` 使用 `uint256`
- 只接受该 verse 的 `uAsset`
- 只在 `Genesis` 阶段开放
- 累加 `totalNormalFunds += amount`
- 累加 `userGenesisFund += amount`
- `Genesis` 事件只记录 `amount`

普通退款：

- 只在 `Refund` 状态开放
- 按 `userGenesisFund` 全额退回该 verse 的 `uAsset`
- 一次性领取
- 不清零 `userGenesisFund`，用 `isRefunded` 标记
- `userGenesisFund = 0` 或重复领取 revert `InvalidClaim`

## 9. Preorder

`preorder` 是独立于普通创世与杠杆创世的资金池。

`preorder` 资金：

- 只接受该 verse 的 `uAsset`
- 托管在 `Launcher`
- 不参与四池部署本金
- 与 `genesis` 是独立账本
- 同一地址可以同时参与 `genesis` 和 `preorder`

`preorder(verseId, amount, user)`：

- `amount` 使用 `uint256`
- `amount > 0`
- `user != address(0)`
- 只在 `Genesis` 阶段开放
- 只要仍处于 `Genesis`，即使已经满足 flash lock 条件，也仍可继续参与

`preorder` 容量只基于主池 memecoin 侧资金计算：

```text
preorderCap = (totalNormalFunds + totalLeveragedDebt) * 7 / 10 * preorderCapRatio / RATIO
```

`preorderCap` 不把辅助池 30% 纳入容量。

`preorderCapRatio` 必须满足 `0 < preorderCapRatio <= RATIO`。

`preorder` 写入前必须满足：

```text
totalPreorderFunds + amount <= preorderCap
```

超出容量时 revert cap exceeded 语义错误。`preorderCap` 与容量预检必须使用全精度乘除或等价的 overflow-safe 计算顺序，不允许依赖不安全的普通中间乘法。

`totalLeveragedDebt` 使用该 market 固定利率和当前 `totalLeveragedInterest` 推导；market 为 `None` 时视为 0。

`preorder` 在 `Locked` 建池后的行为：

- `Launcher` 先部署 `memecoin/uAsset` 主池
- 所有初始 `memecoin` 都在主池
- `Launcher` 使用托管 preorder `uAsset` 执行主池第一笔交易，买出 `memecoin`
- 买出的 `memecoin` 进入 `Launcher` 托管
- 用户按 `userPreorderFunds / totalPreorderFunds` 分配
- vesting 从首笔交易完成时间开始

`Refund` 状态下，preorder 用户按 `userPreorderFunds` 一次性退回 `uAsset`。`userPreorderFunds = 0` 或重复 refund revert `InvalidClaim`。

## 10. 成功门槛与杠杆上限

`Genesis -> Locked` 成功门槛是 OR：

```text
totalNormalFunds >= minTotalFund
OR
totalLeveragedInterest >= minTotalFund
```

杠杆侧成功门槛比较的是 `totalLeveragedInterest`，不是 `totalLeveragedDebt`。

`minTotalFund` 按该 verse 的 `uAsset` 精度解释：

- 普通侧比较 `uAsset` 本金总额
- 杠杆侧比较已支付 `uAsset` 利息总额

`flashGenesis=true` 只表示允许提前 `changeStage`，不会自动进入 `Locked`。

只有真正离开 `Genesis` 后，`genesis / leveragedGenesis / preorder` 才关闭。

杠杆上限：

```text
debtCapBase = max(totalNormalFunds, minTotalFund)
totalLeveragedDebt <= fullPrecisionMulDiv(leveragedDebtFactor, debtCapBase, 1e18)
```

`leveragedDebtFactor` 是全局杠杆债务上限系数，所有 verse 共享，不是单用户倍数。对单个 verse 而言，其总杠杆债务上限 = `fullPrecisionMulDiv(leveragedDebtFactor, max(totalNormalFunds, minTotalFund), 1e18)`。

约束：`fullPrecisionMulDiv(leveragedDebtFactor, interestRate, 1) >= 1e36`。该条件是纯杠杆创世独立达到成功门槛的前提。`leveragedDebtFactor` 无独立下限，只与注册时的 `interestRate` 联合约束。

`MAX_SUPPORTED_FUND_BASED_AMOUNT = 2^64 - 1` 是系统支持的最大 fund base。`leveragedDebtFactor` 必须有有界上限校验：在 `debtCapBase <= MAX_SUPPORTED_FUND_BASED_AMOUNT`、`interestRate <= 1e18`、`totalLeveragedInterest <= MAX_SUPPORTED_FUND_BASED_AMOUNT` 的边界下，所有 `leveragedDebtFactor` 相关计算必须能用全精度 `mulDiv` 或等价 overflow-safe 实现安全完成。

即使普通资金为 0，也允许杠杆债务达到：

```text
fullPrecisionMulDiv(leveragedDebtFactor, minTotalFund, 1e18)
```

`leveragedGenesis` 写入前必须用本次新增利息后的总利息做预检：

```text
nextTotalLeveragedInterest = totalLeveragedInterest + interestAmount
previewDebt = nextTotalLeveragedInterest * 1e18 / market.interestRate
previewDebt <= fullPrecisionMulDiv(leveragedDebtFactor, max(totalNormalFunds, minTotalFund), 1e18)
```

成功门槛比较 `totalLeveragedInterest`（用户实际支付的 uAsset 利息总额），四池部署资金口径使用 `totalLeveragedDebt`（利息推导出的债务本金，`debt = interest × 1e18 / interestRate`）。二者数值不同但方向一致。

## 11. 杠杆创世

`leveragedGenesis(verseId, interestAmount)`：

- 只允许 Launcher 已注册的 verse
- 只允许 Launcher verse 处于 `Genesis`
- market 为 `None` 时，本次调用成功后进入 `Genesis`
- market 为 `Genesis` 时，继续累计利息
- market 为其他状态时 revert
- `interestAmount` 必须大于 0
- 参与地址为 `msg.sender`，没有 user-address 输入
- 从用户转入该 verse 的 `uAsset` 到 `POLend`
- 只累计 `leveragedInterestPaid[verseId][msg.sender]`
- 只累计 `market.totalLeveragedInterest`
- 不 mint `uAsset`
- 不存储 `borrowedAmount`
- 不存储 `totalLeveragedDebt`

事件：

```solidity
event LeveragedGenesis(uint256 indexed verseId, address indexed user, uint256 interestAmount);
```

如果最终进入 `Refund`：

- 杠杆用户只取回自己支付的利息
- 不存在 `uAsset` 本金退款
- 因为 `uAsset` 从未在 `Genesis` 阶段 mint

`Genesis -> Refund` 时，只有 `getTotalLeveragedDebt(verseId) > 0` 才调用：

```text
POLend.markRefundable(verseId)
```

无杠杆参与时，market 保持 `None`，不记录 `Refund`，因为没有杠杆利息可退。

`markRefundable`：

- 只由 `Launcher` 调用
- 只允许 market 处于 `Genesis`
- 不需要推导或保存债务
- 只把 market 状态改成 `Refund`

`claimRefund`：

- 只允许 `Refund`
- 权益和领取标记基于 `msg.sender`
- `to != address(0)`，退款转给 `to`
- 按 `leveragedInterestPaid[verseId][msg.sender]` 全额退还该 verse 的 `uAsset`
- 一次性领取
- 不清零 `leveragedInterestPaid[verseId][msg.sender]`
- 用 `refundClaimed` 标记
- `leveragedInterestPaid[verseId][msg.sender] = 0` 或重复领取 revert `InvalidClaim`

普通 refund、preorder refund、杠杆 `claimRefund` 三套账本独立，同一用户可分别领取自己参与过的部分。

## 12. Genesis -> Locked

`Launcher.changeStage` 从 `Genesis` 进入 `Locked` 时：

1. 若 `getTotalLeveragedDebt(verseId) > 0`，调用 `POLend.finalizeLeveragedGenesis(verseId)`
2. 调用 `POLSplitter.initializeVerse(verseId, pol, memecoin, uAsset, name, symbol)`
3. 部署 `memecoin/uAsset` 主池
4. 执行 preorder 首笔交易
5. 部署三个辅助池
6. 若 `getTotalLeveragedDebt(verseId) > 0`，转移杠杆初始 `YT` 给 `POLend`
7. 若 `getTotalLeveragedDebt(verseId) > 0`，调用 `POLend.recordLeveragedYT(verseId, yt, totalLeveragedYT)`

`POLSplitter.initializeVerse` 无论有没有杠杆参与都必须调用。PT/YT 是 POL 拆分体系，与是否有杠杆创世无关。

纯普通创世时：

- 不调用 `finalizeLeveragedGenesis`
- 不调用 `recordLeveragedYT`
- 所有初始 `YT` 都归普通初始 claim 池
- POLend 不托管 `YT`
- market 保持 `None`

### 12.1 finalizeLeveragedGenesis

`finalizeLeveragedGenesis`：

- 只允许 `Launcher` 调用
- 只允许 `Genesis -> Locked` 流程调用一次
- 只允许 market 处于 `Genesis`
- 只在 `getTotalLeveragedDebt(verseId) > 0` 时调用
- 先把 market 状态设为 `Locked`
- mint `totalLeveragedDebt` 数量的该 verse `uAsset` 到 `Launcher`
- 把 `totalLeveragedInterest` 对应 `uAsset` 转给 `POLend.protocolTreasury`
- `globalDebtByUAsset[market.uAsset] += totalLeveragedDebt`

mint 数量：

```text
mintedUAsset = totalLeveragedInterest * 1e18 / market.interestRate
```

`finalizeLeveragedGenesis` 不重复检查 debt cap。

`finalizeLeveragedGenesis` 后利息已转给 `protocolTreasury`，`claimRefund` 不可用。

### 12.2 四池部署

四池部署先汇总普通创世资金与杠杆债务：

```text
totalGenesisFunds = totalNormalFunds + totalLeveragedDebt
```

再统一按 `70/30` 拆分：

```text
totalMemecoinFunds = totalGenesisFunds * 7 / 10
totalAuxiliaryFunds = totalGenesisFunds - totalMemecoinFunds
```

其中：

- `70%` 进入 `memecoin/uAsset` 主池
- `30%` 进入后续三个辅助池路径

不分别拆普通侧和杠杆侧。

`totalGenesisFunds` 只用于成功部署资金口径，不等于用户可 refund 的资金池，也不包含 preorder。

主池铸造 `POL`。主池 LP token 即为 POL。POL mint 数量由主池部署时的 uAsset 存入量和初始价格决定，初始价格由 `fundBasedAmount` 参数定义。`fundBasedAmount` 配置语义见 `docs/spec/verse/config-matrix.md`。

`POL` 统一按：

- `2/7` 进入 `POL/uAsset`
- `3/7` 进入 `split(POL)` 得到 `PT + YT`
- `2/7` 进入 `PT/POL`

split 得到的 `PT` 再按：

- `1/3` 进入 `PT/uAsset`
- `2/3` 进入 `PT/POL`

辅助池 uAsset 侧分配（`totalAuxiliaryFunds` = `totalGenesisFunds * 30%`）：

- `POL/uAsset`: `totalAuxiliaryFunds * 2/3`（与 2/7 POL 等值配对）
- `PT/uAsset`: `totalAuxiliaryFunds * 1/3`（与 1/7 PT 等值配对，1 PT = 1 uAsset）
- `PT/POL`: 无 uAsset 侧

四池：

| 池子 | 组成 |
|---|---|
| `memecoin/uAsset` | 主池 |
| `POL/uAsset` | 辅助池 |
| `PT/uAsset` | 辅助池 |
| `PT/POL` | 辅助池 |

三个辅助池 LP 总量由 `Launcher` 记录：

- `polUAssetLpAmount`
- `ptUAssetLpAmount`
- `ptPolLpAmount`

不在部署时分别存普通 LP / 杠杆 LP。后续按资金占比切分。

### 12.3 初始 YT

四池部署时统一 split 得到的 `YT`，再按资金占比切初始 claim 池：

```text
totalNormalClaimableYT = totalYT * totalNormalFunds / totalGenesisFunds
totalLeveragedYT = totalYT - totalNormalClaimableYT
```

取整差额归杠杆侧。所有涉及普通侧 / 杠杆侧按比例切分的场景，统一使用减法得到一侧，floor 除法得到另一侧；本文档中每个切分公式会显式声明取整差额归属。

普通初始 `YT` 托管在 `Launcher`。

杠杆初始 `YT` 必须先转给 `POLend`，再调用：

```text
POLend.recordLeveragedYT(verseId, yt, totalLeveragedYT)
```

`recordLeveragedYT`：

- 只由 `Launcher` 调用
- 必须在同一笔 `Genesis -> Locked` 交易内完成
- 只允许 market 处于 `Locked`
- 用 `market.yt != address(0)` 防重复
- 只记录 `yt` 与 `totalLeveragedYT`
- 不转 token
- 不改变 market 主状态

## 13. PT / YT 生命周期

`POLSplitter.initializeVerse`：

- 只由 `Launcher` 调用
- 每个 `verseId` 只能调用一次
- 在 `Genesis -> Locked`、四池部署前调用
- 从 `Launcher` 传入 `pol / memecoin / uAsset / name / symbol`
- 创建该 verse 的 `PT / YT`
- 绑定该 verse 的 `uAsset / memecoin / pol / pt / yt`
- 允许纯普通创世调用

`split / merge`：

- 只在 `POLSplitter.initializeVerse` 后开放
- 只在 `settled=false` 时开放
- 只在 Launcher verse 尚未 `Unlocked` 时开放
- `Locked` 阶段可继续 `split / merge`
- `settle` 执行后关闭（`settle` 在 `Locked -> Unlocked` 转换交易内执行）
- `split(0)` 与 `merge(0)` revert `ZeroInput`

这意味着 `PT/YT` 不只在 `Locked` 初始部署时 mint。用户在 `Locked` 期间仍可主动 `split POL` 得到新的 `PT/YT`。

后续主动 split 得到的 `PT/YT`：

- 直接转移到 split 用户地址
- 不进入普通/杠杆初始 claim 账本
- `Unlocked` 后与其他 `PT/YT` 一样从 `Splitter` 结算池兑付

`PT/YT` 的 burn 权限只授予 `Splitter`。

`redeemPT / redeemYT` 由 `Splitter` burn `msg.sender` 持有的 token，不需要 approve。

`Splitter.preRedeemPTFee` 只用于固定 burn `Launcher` 持有的杠杆侧 PT fee，不接受任意 account 作为 burn 来源，也不需要 `Launcher` approve。

## 14. 初始 YT claim

普通和杠杆初始 `YT` 都是一人一次性领取全部应得初始 `YT`，重复领取 revert `InvalidClaim`，领取后拿到的是同一个 verse 的同一个 `YT token`。

普通初始 `YT`：

- 依赖 `Launcher` 成功路径
- verse 成功进入 `Locked` 后永久可领
- verse 处于 `Locked` 或 `Unlocked` 后均可补领
- `Unlocked` 后补领也允许，补领后可立即 `redeemYT`

杠杆初始 `YT`：

- 依赖 `POLend` market 成功路径
- 只在 market 处于 `Locked` 或 `Settled` 状态时可领取
- `None / Genesis / Refund` 时 revert `InvalidClaim`
- `Unlocked` 后补领也允许，补领后可立即 `redeemYT`

```text
normalYT = totalNormalClaimableYT * userGenesisFund / totalNormalFunds
```

`userGenesisFund = 0` revert `InvalidClaim`。

```text
leveragedYT = totalLeveragedYT * userInterestPaid / totalLeveragedInterest
```

`userInterestPaid = 0` revert `InvalidClaim`。

`claimLeveragedYT` 的权益和领取标记基于 `msg.sender`；`to != address(0)`，`YT` 转给 `to`。

不存在独立的“claim 权资产”。只有领取规则：初始参与地址可以领取其应得初始 `YT`；领取后的 `YT token` 可自由转让。

## 15. 辅助池 fee

`memecoin/uAsset` 主池 fee 沿用 Memeverse 原规则：

- `uAsset` fee 走 Memeverse DAO governor 路径
- `memecoin` fee 给 `yieldVault`

新增规则只覆盖三个辅助池：

- `POL/uAsset`
- `PT/uAsset`
- `PT/POL`

### 15.1 token 级处理

`POL` fee 不区分普通侧 / 杠杆侧，全部永久 burn。

`uAsset fee / PT fee` 在 `Locked` 阶段按普通侧 / 杠杆侧切分，直接按金额计算，不保存或使用整数比例：

```text
totalGenesisFunds = totalNormalFunds + totalLeveragedDebt

govUAssetFee = totalUAssetFee * totalLeveragedDebt / totalGenesisFunds
normalUAssetFee = totalUAssetFee - govUAssetFee

govPTFee = totalPTFee * totalLeveragedDebt / totalGenesisFunds
normalPTFee = totalPTFee - govPTFee

取整差额归普通侧。
```

普通侧进入 `normalFeeStates`。

杠杆侧最终发给 Memeverse DAO governor：

- 杠杆侧 `uAsset fee` 走 Memeverse DAO governor 分发
- 杠杆侧 `PT fee` 必须转换成等值 `uAsset` 后走 Memeverse DAO governor 分发
- 杠杆侧 fee 不进入 `POLend.protocolTreasury`
- 杠杆侧 fee 不进入普通 fee 累计池

### 15.2 Locked 阶段主动分发

`redeemAndDistributeFees` 在 `Locked` 阶段主动调用时：

- 捕获三个辅助池 fee
- `POL fee` burn
- 普通侧 `uAsset fee / PT fee` 写入 `normalFeeStates`
- 杠杆侧 `uAsset fee` 本次直接分发
- 杠杆侧 `PT fee` 必须走 `POLend.preRedeemPTFee` 预兑付成 `uAsset` 后本次直接分发
- 不写 `pendingAuxiliaryGovFeeStates`

### 15.3 Locked -> Unlocked 最后捕获

`Locked -> Unlocked` 时，`Launcher` 必定先调用 `_captureLockedAuxiliaryFees`，作为 `Locked` 阶段最后一次辅助池 fee 捕获。

`_captureLockedAuxiliaryFees`：

- 只在 `Locked -> Unlocked` 调用一次
- 捕获三个辅助池 fee
- `POL fee` burn
- 普通侧 `uAsset fee / PT fee` 写入 `normalFeeStates`
- 杠杆侧 `uAsset fee / PT fee` 写入 `pendingAuxiliaryGovFeeStates`
- 不调用 `preRedeemPTFee`

`pendingAuxiliaryGovFeeStates` 只承接这次切阶段时捕获但尚未分发的杠杆侧 fee：

```text
pendingUAssetFee
pendingPTFee
```

`pendingPTFee` 对应的 PT token 托管在 `Launcher` 地址上（从辅助池 claim 后直接持有）。

`pendingUAssetFee` 对应的 uAsset 同样托管在 `Launcher` 地址上，后续 `redeemAndDistributeFees` 调用时直接分发。

`pendingPTFee` 虽然是在 settle 前捕获，但后续会在 `Splitter` 已 settled 后分发，因此走 `Splitter.redeemPT`，不进入 `preRedeemedPT`。

### 15.4 Unlocked 后 fee

`Unlocked` 后：

- 新产生的辅助池 fee 不再拆普通侧 / 杠杆侧
- 新产生的辅助池非 `POL` fee 全部归 Memeverse DAO governor
- `POL fee` 继续 burn
- 普通用户仍可补领 `Locked` 阶段已累计但未领取的普通侧 fee

### 15.5 quoteDistributionLzFee

`quoteDistributionLzFee` 是计算 `redeemAndDistributeFees` 所需跨链 fee 的 view，必须与 `redeemAndDistributeFees` 逻辑同步。

异链分发 quote 必须覆盖：

- 主池 gov fee
- `pendingAuxiliaryGovFeeStates`
- 本次 preview 出的辅助池 governor fee
- settle 前 PT fee 预兑付后需要跨链发送的等值 `uAsset`
- settle 后 PT fee redeemPT 后需要跨链发送的等值 `uAsset`

## 16. 普通 fee 领取

普通 fee 是持续累计池，必须保存用户已领快照。

累计池：

```text
accUAssetFee
accPTFee
```

用户已领：

```text
claimedUAssetFee
claimedPTFee
```

领取公式：

```text
entitledUAsset = accUAssetFee * userGenesisFund / totalNormalFunds
claimableUAsset = entitledUAsset - claimedUAssetFee

entitledPT = accPTFee * userGenesisFund / totalNormalFunds
claimablePT = entitledPT - claimedPTFee
```

普通 fee 分配基准始终是 `userGenesisFund / totalNormalFunds`，不依赖 `YT` 持仓。

`accUAssetFee / accPTFee` 只累加，不随用户领取减少。

`claimNormalFees`：

- 只允许 `Stage.Locked` 及之后调用
- `Refund` 不允许
- `userGenesisFund = 0` 时 revert `InvalidClaim`
- 没有新增可领时返回 `(0, 0)`
- 只在 `claimableUAsset > 0` 时更新 `claimedUAssetFee`
- 只在 `claimablePT > 0` 时更新 `claimedPTFee`
- 先更新 claimed 状态，再转账或 redeem
- 在 `Unlocked` 后只补领历史 `Locked` 阶段累计的普通侧 fee

返回值：

```text
(uAssetAmount, ptAmount)
```

`Splitter` 尚未 settle：

- `uAssetAmount = claimableUAsset`
- `ptAmount = claimablePT`
- `PT fee` 直接发 `PT` 给用户

`Splitter` 已 settle：

- `Launcher` 用 `claimablePT` 调 `Splitter.redeemPT`
- `uAssetAmount = claimableUAsset + redeemedPTUAsset`
- `ptAmount = 0`
- 不处理用户此前已领取到自己地址上的 `PT`

该判断基于 `Splitter` per-verse settled 状态，不基于 Launcher stage。

用户在 `settled=false` 已领取 PT fee 到自己地址后，后续 `claimNormalFees` 不再处理这部分 PT；用户自己调用 `redeemPT`。

## 17. 普通辅助池 LP 领取

`redeemAuxiliaryLiquidity`：

- 只允许普通创世参与者调用
- 只在 `Stage.Unlocked` 后开放
- `Refund` 下不可调用
- 一次性领取三个辅助池普通份额 LP token
- 不 remove liquidity
- 不赎回 `POL / PT / uAsset / memecoin`
- 用 `isRedeemed` 防重复
- `userGenesisFund = 0`、`totalNormalFunds = 0` 或重复领取 revert `InvalidClaim`

返回值只包含三个 LP token 数量：

```text
polUAssetLpAmount
ptUAssetLpAmount
ptPolLpAmount
```

不返回 `polAmount / ptAmount / uAssetAmount / memecoinAmount`。

领取公式：

```text
polUAssetLpAmount = auxiliaryLiquidities.polUAssetLpAmount * userGenesisFund / totalNormalFunds
ptUAssetLpAmount = auxiliaryLiquidities.ptUAssetLpAmount * userGenesisFund / totalNormalFunds
ptPolLpAmount = auxiliaryLiquidities.ptPolLpAmount * userGenesisFund / totalNormalFunds
```

普通用户领取后不更新 `auxiliaryLiquidities`，只用 `isRedeemed` 防双领。

若 `totalLeveragedDebt > 0`，`changeStage Locked -> Unlocked` 同一笔交易内完成 `executeGlobalSettlement`，用户无法在杠杆 LP 切走前领取普通 LP；原因是 `redeemAuxiliaryLiquidity` 在 `Locked` 阶段不可调用，`changeStage` 原子完成后才进入 `Unlocked`。

`executeGlobalSettlement` 会先切走杠杆份额 LP，并把 `auxiliaryLiquidities` 更新为剩余普通份额 LP。普通用户只能领取剩余普通份额。

纯普通创世时不调用 `executeGlobalSettlement`，三个辅助池 LP 全部留在 `auxiliaryLiquidities` 供普通用户领取。

纯杠杆创世时三个辅助池 LP 在 `executeGlobalSettlement` 中 100% 切给杠杆侧，普通侧 `auxiliaryLiquidities` 最终为 0。

## 18. Locked -> Unlocked 编排

`Launcher.changeStage` 在 `Locked -> Unlocked` 时按顺序执行（以下步骤在同一笔交易内原子执行，任一步骤失败则全部回滚）：

1. `_captureLockedAuxiliaryFees(verseId)`
2. `verse.currentStage = Unlocked`
3. `POLSplitter.settle(verseId)`
4. 若 `getTotalLeveragedDebt(verseId) > 0`，调用 `POLend.executeGlobalSettlement(verseId)`
5. 激活 unlock 后 public swap protection

`Splitter.settle` 只由 `Launcher` 调一次。

`POLend.executeGlobalSettlement` 只由 `Launcher` 调一次。纯普通创世没有杠杆份额 LP，不调用该函数。

无杠杆参与时不调用：

- `markRefundable`
- `finalizeLeveragedGenesis`
- `recordLeveragedYT`
- `executeGlobalSettlement`

## 19. POLSplitter settle

`settle` 语义：

```text
burn POL collateral
-> 得到 totalRedeemedUAsset + settlementMemecoin
-> 若 preRedeemedPT > 0，POLend repay Splitter 持有的 preRedeemedPT backing
-> settlementUAsset = totalRedeemedUAsset - preRedeemedPT
-> delete preRedeemedPT
-> settled = true
```

`totalRedeemedUAsset` 表示 burn `POL collateral` 后赎回出的全部 `uAsset`，尚未扣除已预兑付 `PT fee` backing。

`preRedeemedPT` 只包含 `Locked` 阶段主动分发时已经预兑付给 Memeverse DAO governor 路径的杠杆侧 PT fee。

`preRedeemedPT` 不包含：

- 普通用户领取到地址上的 PT fee
- 普通用户后续 `redeemPT`
- `executeGlobalSettlement` 后真实 `redeemPT`
- `_captureLockedAuxiliaryFees` 捕获进 `pendingAuxiliaryGovFeeStates.pendingPTFee` 的 PT fee

不变量：

```text
preRedeemedPT <= totalRedeemedUAsset
settlementUAsset >= PT.totalSupply()
```

这些不变量由以下产品设计保证：

- settle 时 burn 全部 POL collateral 赎回底层 uAsset
- 1 POL = 1 PT，POL 赎回时的 uAsset 产出 ≥ 初始投入量（保护窗口内价格最低点保证）
- 因此 `totalRedeemedUAsset >= PT.totalSupply()`
- 若有 `preRedeemedPT`，对应 PT 已 burn，PT supply 已减少，settlementUAsset 扣除后仍满足

不作为正常业务分支处理。

`settlementMemecoin` 不受 `preRedeemedPT` 影响。

settle 后：

- `redeemPT / redeemYT` 开放
- `split / merge` 关闭

错误命名：

- `SplitClosed`：`split / merge` 已关闭
- `InvalidSettlementStage`：`settle` 阶段不正确
- `NotSettled`：redeem 前尚未 settle
- 不保留 `InsufficientSettlementUAsset`

## 20. PT fee 预兑付与分发

### 20.1 settle 前：preRedeemPTFee

`Locked` 阶段主动调用 `redeemAndDistributeFees` 时，若捕获到杠杆侧 PT fee，由于 `Splitter` 尚未 settle，必须走预兑付：

```text
POLend.preRedeemPTFee(verseId, ptAmount, mintTo)
```

`POLend.preRedeemPTFee`：

- 只由 `Launcher` 调用
- `mintTo != address(0)`
- 不返回值
- 不调用 `YieldDispatcher.lzCompose`
- 不调用 `IOFT.send`
- 不重新 claim fee
- 不重新拆分普通侧 / 杠杆侧
- 只处理 `Launcher` 传入的 `ptAmount`
- 只能在 `Splitter` 尚未 settled 时按产品路径调用

流程：

```text
POLend.preRedeemPTFee
-> 调 Splitter.preRedeemPTFee(verseId, ptAmount)
-> POLend mint ptAmount uAsset 到 mintTo
-> globalDebtByUAsset[market.uAsset] += ptAmount
```

`Splitter.preRedeemPTFee`：

- 只允许 `POLend` 调用
- burn account 固定为 `Launcher`
- burn `Launcher` 当前持有的 `ptAmount` PT
- `preRedeemedPT += ptAmount`
- 不修改 `settlementUAsset`

settle 前还没有 settlement pool。

`preRedeemPTFee` 的 `mintTo` 是 token 接收地址，不是最终业务 receiver：

- 本链：`mintTo = YieldDispatcher`
- 异链：`mintTo = Launcher`

本链路径：

```text
POLend.preRedeemPTFee(..., mintTo=yieldDispatcher)
Launcher 同笔调用 YieldDispatcher.lzCompose(uAsset, bytes32(0), abi.encode(governor, TokenType.UASSET, amount), address(0), "")
```

异链路径：

```text
POLend.preRedeemPTFee(..., mintTo=Launcher)
Launcher 同笔 IOFT.send 到远端 YieldDispatcher
compose receiver = governor
```

源链 / 本链同交易本地分发步骤失败时，整笔交易 revert，`preRedeemPTFee` 的 PT burn、`preRedeemedPT` 累计、uAsset mint、`globalDebtByUAsset` 增加都回滚。

异链路径中，`IOFT.send` 调用本身失败时整笔源链交易 revert；`IOFT.send` 成功后，目标链 `lzReceive / lzCompose` 失败不会回滚源链状态，由 LayerZero retry 机制处理目标链重试。

事件：

```solidity
event PreRedeemPTFee(uint256 indexed verseId, address indexed uAsset, uint256 ptAmount, address mintTo);
```

### 20.2 settle 时：burnPreRedeemedBacking

`Splitter.settle` 遇到 `preRedeemedPT > 0` 时：

1. `Splitter` approve 该 verse `uAsset` 给 `POLend`，金额为 `preRedeemedPT`
2. `Splitter` 调用 `POLend.burnPreRedeemedBacking(verseId, preRedeemedPT)`
3. `POLend` 调 `uAsset.repay(address(splitter), preRedeemedPT)`
4. `globalDebtByUAsset[market.uAsset] -= preRedeemedPT`
5. `Splitter` 设置 `settlementUAsset = totalRedeemedUAsset - preRedeemedPT`
6. `Splitter` delete `preRedeemedPT[verseId]`

`burnPreRedeemedBacking`：

- 只允许 `Splitter` 调用
- 只能在该 verse settle 流程中调用
- 使用该 verse 记录的 `uAsset`
- 不能由调用方传入 token 地址

`preRedeemedPT = 0` 时，`Splitter.settle` 直接跳过 `burnPreRedeemedBacking`。

事件：

```solidity
event BurnPreRedeemedBacking(uint256 indexed verseId, address indexed uAsset, uint256 amount);
```

### 20.3 settle 后：直接 redeemPT

Splitter 已 settled 后，杠杆侧 PT fee 不再调用 `preRedeemPTFee`。

settle 后 PT fee 直接走：

```text
Splitter.redeemPT(verseId, ptAmount, receiver)
```

本链：

- `receiver = YieldDispatcher`
- Launcher 同笔调用 `YieldDispatcher.lzCompose(... governor ...)`

异链：

- `receiver = Launcher`
- Launcher 同笔 `IOFT.send` 到远端 `YieldDispatcher`
- compose receiver 是 `governor`

settle 后这条路径：

- 不更新 `preRedeemedPT`
- 不 mint
- 不 repay backing
- 不改 `globalDebtByUAsset`
- 本链同交易本地分发失败则 `redeemPT` 回滚
- 异链 `IOFT.send` 成功后目标链 `lzReceive / lzCompose` 失败不回滚源链 `redeemPT`，由 LayerZero retry 处理

`pendingAuxiliaryGovFeeStates.pendingPTFee` 在后续 settled 后分发时走本路径。

## 21. PT / YT 兑付

### 21.1 redeemPT

`redeemPT`：

- 只在 `settled=true` 后开放
- 允许任意 `PT` 持有人调用
- `to` 可指定接收地址
- `ptAmount = 0` revert `ZeroInput`
- burn `msg.sender` 的 `PT`
- `settlementUAsset -= ptAmount`
- 向 `to` 转出等量 `uAsset`
- 不需要 approve
- 不额外读取 `PT.totalSupply()`
- 不使用 `preRedeemedPT`

公式：

```text
uAssetAmount = ptAmount
```

### 21.2 redeemYT

`redeemYT`：

- 只在 `settled=true` 后开放
- 允许任意 `YT` 持有人调用
- `to` 可指定接收地址
- `ytAmount = 0` revert `ZeroInput`
- 不需要 approve
- 必须先用本次扣减前状态计算，再 burn

计算：

```text
outstandingYT = YT.totalSupply()
reservedUAssetForPT = PT.totalSupply()
ytRedeemableUAssetPool = settlementUAsset - reservedUAssetForPT

uAssetAmount = ytRedeemableUAssetPool * ytAmount / outstandingYT
memecoinAmount = settlementMemecoin * ytAmount / outstandingYT
```

执行顺序：

```text
1. 用 burn 前状态计算 uAssetAmount 和 memecoinAmount
2. burn YT
3. settlementUAsset -= uAssetAmount
4. settlementMemecoin -= memecoinAmount
5. transfer uAssetAmount + memecoinAmount to
```

`outstandingYT = 0` 时 revert。

`redeemYT` 不得动 PT 本金准备金。

`redeemPT / redeemYT` 的整数舍入 dust 永久留在 `Splitter`，不设计 sweep。

## 22. POLend 全局结算

`POLend.executeGlobalSettlement(verseId)`：

- 只由 `Launcher` 调用
- 只在 `Locked -> Unlocked` 编排中调用一次
- 只处理杠杆份额的三个辅助池 LP
- 不处理普通份额 LP
- 纯普通创世不调用

`Launcher` 按杠杆资金占比切出三个辅助池 LP 并平仓：

```text
totalFunds = totalNormalFunds + totalLeveragedDebt

leveragedPolUAssetLpAmount = polUAssetLpAmount * totalLeveragedDebt / totalFunds
leveragedPtUAssetLpAmount = ptUAssetLpAmount * totalLeveragedDebt / totalFunds
leveragedPtPolLpAmount = ptPolLpAmount * totalLeveragedDebt / totalFunds

remainingPolUAssetLpAmount = polUAssetLpAmount - leveragedPolUAssetLpAmount
remainingPtUAssetLpAmount = ptUAssetLpAmount - leveragedPtUAssetLpAmount
remainingPtPolLpAmount = ptPolLpAmount - leveragedPtPolLpAmount
```

`auxiliaryLiquidities` 更新为三个 `remaining...` 数量。用减法得到普通剩余 LP，避免比例取整导致 LP 丢失。取整差额归普通侧。

平仓结果进入 `POLend`：

- `POL`
- `PT`
- `uAsset`

回收的自由 `POL`：

- 不经过 `Splitter.settle`
- 直接调用 `Launcher.redeemMemecoinLiquidity(..., unwrap=true)` burn POL LP token
- 取回底层 `uAsset + memecoin`
- 输出进入 `POLend`

回收的 `PT`：

- 调用 `Splitter.redeemPT(verseId, ptAmount, address(POLend))`
- 兑回 `uAsset`
- 输出进入 `POLend`

回收的 `uAsset` 汇总后先偿还该 verse 全部债务：

```text
verseDebt = totalLeveragedInterest * 1e18 / market.interestRate
recoveredUAsset >= verseDebt
uAsset.repay(address(POLend), verseDebt)
globalDebtByUAsset[market.uAsset] -= verseDebt
```

`recoveredUAsset >= verseDebt` 是必须成立的产品不变量。实现前必须提供可审查的安全 / 证明证据：数学证明或 invariant tests，覆盖辅助 LP unwind、POL 赎回、PT 兑付、fee、整数舍入、极端价格状态。证据必须证明杠杆份额辅助池平仓 + POL 赎回 + PT 兑付后的 `uAsset` 总量覆盖 `verseDebt`。

如果该证明不能成立，进入实现前必须先加入 fallback 设计，例如 `SettlementFailed`、bad debt 记录、emergency unlock、DAO backstop 中的一种或组合。本文档不在此处规定最终 bad debt 机制；缺少证明时不得依赖无 fallback 的部分偿还假设。

在上述证明成立时，不设计：

- `remainingDebt`
- `badDebt`
- `unrepaidDebt`
- 部分偿还

剩余净资产写入 `ResidualState`：

```text
residualUAsset = recoveredUAsset - verseDebt
residualMemecoin = recoveredMemecoin
```

`residualUAsset / residualMemecoin` 只从实际回收数量记录，任一项都可以为 0。

完成后 market state 变为 `Settled`。

安全要求：

- `POLend.executeGlobalSettlement` 和 `POLSplitter.redeemYT` 必须使用重入锁
- `redeemYT` 必须在 transfer 前完成所有状态更新（CEI 模式）

## 23. 杠杆残值领取

`claimResidual`：

- 只允许 `Settled`
- 只允许参与过杠杆创世的用户
- 权益和领取标记基于 `msg.sender`
- `to != address(0)`，残值转给 `to`
- 一次性领取
- 用 `residualClaimed` 防重复
- `userInterestPaid = 0` 或重复领取 revert `InvalidClaim`

领取公式：

```text
uAssetAmount = residualUAsset * userInterestPaid / totalLeveragedInterest
memecoinAmount = residualMemecoin * userInterestPaid / totalLeveragedInterest
```

`residualUAsset / residualMemecoin` 是初始总残值基数，claim 后不递减。

`ResidualState` 不包含：

- 用户支付的利息
- `Splitter` 结算池中的 PT/YT 兑付资产
- 用户初始 claim 或后续 split 得到的 `YT` 对应权益

所有 `YT` 的价值兑现都从 `Splitter.redeemYT` 完成，和残值无关。

残值整数舍入 dust 永久留在 `POLend`，不提供 sweep。`claimResidual` 永久可领，不能用 owner sweep 或 last claimer 规则改变用户残值分配。

## 23.1 用户级 floor dust 统一规则

所有用户级 floor allocation 产生的 dust 永久留在相关 custody contract，不提供 sweep，不给 last claimer：

- 普通初始 `YT` dust 留在 `Launcher`
- 杠杆初始 `YT` dust 留在 `POLend`
- 普通 fee dust 留在 `Launcher`
- 普通辅助 LP dust 留在 `Launcher`
- 杠杆残值 dust 留在 `POLend`
- `PT / YT` redeem dust 留在 `Splitter`

## 24. uAsset mint / repay 权限

每个 verse 的 `uAsset` 必须是受支持的 mint / repay / OFT 资产，由注册中心或 `Launcher` 在注册阶段保证。

`POLend` 不重复维护 supported asset 鉴权。

`POLend` 必须拥有对所有 supported `uAsset` 的 mint 权限，用于：

- `finalizeLeveragedGenesis`
- settle 前 `preRedeemPTFee`

`POLend` 必须能对所有 supported `uAsset` 执行 repay，用于：

- `executeGlobalSettlement` 偿还 verseDebt
- `burnPreRedeemedBacking` 偿还预兑付 PT fee backing

最小接口：

```solidity
interface IOutrunUniversalAssets {
    function mint(address to, uint256 amount) external;
    function repay(address account, uint256 amount) external;
}
```

`uAsset` 偿还统一使用 `OutrunUniversalAssets.repay(account, amount)` 语义：

```text
msg.sender 是债务 owner
repay(account, amount) burn account 的 uAsset
repay(account, amount) 减少 mintingStatusTable[msg.sender].amountInMinted
```

`mint(to, amount)` 增加 `mintingStatusTable[msg.sender].amountInMinted`；`repay(account, amount)` 只减少同一个 debt owner 即 `msg.sender` 的 minted amount，不减少 `account` 的 owner 额度。

`repay` 的 burn account 语义：

- `account == msg.sender` 时不需要 allowance
- `account != msg.sender` 时，`account` 必须给 `msg.sender` 足额 allowance
- `account` 余额不足、allowance 不足、或 `mintingStatusTable[msg.sender].amountInMinted < amount` 时 revert

`executeGlobalSettlement` 偿还 verseDebt：

```text
uAsset.repay(address(POLend), verseDebt)
```

POLend 自己 repay 自己持有的 recovered `uAsset` 不需要 self-approve。

`burnPreRedeemedBacking` 偿还预兑付 PT fee backing：

```text
Splitter approve POLend exact amount
POLend calls uAsset.repay(address(splitter), amount)
```

Splitter 给 POLend 的 allowance 只在 `preRedeemedPT > 0` 时设置精确金额，用完后不为兼容未知 token 做额外 approve-to-zero。`uAsset` 由 `OutrunUniversalAssets` 发行，支持非零到非零的 approve 变更。

## 25. YieldDispatcher 分发路径

Memeverse DAO governor fee 无论本链还是异链，都统一经过 `YieldDispatcher`。

本链路径：

```text
Launcher / POLend 使 uAsset 到达 YieldDispatcher
Launcher 调 YieldDispatcher.lzCompose(
    uAsset,
    bytes32(0),
    abi.encode(governor, TokenType.UASSET, amount),
    address(0),
    ""
)
YieldDispatcher 调 Governor.receiveTreasuryIncome
```

异链路径：

```text
Launcher 持有待发送 uAsset
Launcher 构造 OFT SendParam
SendParam.to = remote YieldDispatcher
SendParam.composeMsg = abi.encode(governor, TokenType.UASSET)
Launcher 调 IOFT.send
远端 YieldDispatcher compose 后调 Governor.receiveTreasuryIncome
```

最终业务接收者是 DAO governor。

`YieldDispatcher` 是 token 落点和 compose 分发器。

`POLend.protocolTreasury` 与 Memeverse DAO governor fee 没有任何关系。

## 26. 权限与配置

`POLend.initialize` 必须配置：

- `launcher`
- `splitter`
- `protocolTreasury`
- `defaultInterestRate`
- `leveragedDebtFactor`

`protocolTreasury` 必须非零。

`fullPrecisionMulDiv(leveragedDebtFactor, interestRate, 1) >= 1e36`。该约束在注册时校验。`leveragedDebtFactor` 必须按 §10 的 `MAX_SUPPORTED_FUND_BASED_AMOUNT = 2^64 - 1` 做有界上限校验，在最大支持 fund base、最大支持利率和最大支持利息输入边界下，所有相关计算必须使用全精度 `mulDiv` 或等价 overflow-safe 实现。

`setProtocolTreasury(newTreasury)`：

- 仅 owner
- `newTreasury != address(0)`
- 只影响未来成功进入 `Locked` 的杠杆利息收入
- 事件 `event ProtocolTreasuryChanged(address indexed oldTreasury, address indexed newTreasury);`

`setDefaultInterestRate(newRate)`：

- 仅 owner
- `0 < newRate <= 1e18`
- 只影响未来注册 market
- 事件 `event DefaultInterestRateChanged(uint256 oldRate, uint256 newRate);`

### 26.1 权限 / 配置矩阵

| 函数 | Caller | 状态要求 | 输入 / 零值检查 | 事件 / 配置语义 |
| --- | --- | --- | --- | --- |
| `registerLendMarket` | `Launcher` | market 未注册 | verse `uAsset` 必须有效，复制当前 `defaultInterestRate`，校验 `leveragedDebtFactor` 与利率约束 | 注册后利率固定 |
| `leveragedGenesis` | 用户 | Launcher verse 为 `Genesis`；market 为 `None / Genesis` | `interestAmount > 0`；参与地址为 `msg.sender`，无 user-address 输入；debt cap 预检 | `LeveragedGenesis` |
| `markRefundable` | `Launcher` | market 为 `Genesis` | 无金额输入 | 状态改为 `Refund` |
| `finalizeLeveragedGenesis` | `Launcher` | `Genesis -> Locked` 流程；market 为 `Genesis` | `totalLeveragedDebt > 0` | 状态改为 `Locked`，mint debt，转 treasury |
| `recordLeveragedYT` | `Launcher` | market 为 `Locked` | `yt != address(0)`，`totalLeveragedYT > 0`，防重复 | 记录杠杆初始 `YT` |
| `preRedeemPTFee` | `Launcher` | market 为 `Locked`，Splitter 未 settled | `ptAmount > 0`，`mintTo != address(0)` | `PreRedeemPTFee`，增加 debt |
| `burnPreRedeemedBacking` | `Splitter` | Splitter settle 流程 | `amount == preRedeemedPT`，不能传 token 地址 | `BurnPreRedeemedBacking`，减少 debt |
| `executeGlobalSettlement` | `Launcher` | `Locked -> Unlocked` 编排；market 为 `Locked` | 只处理一次，要求 `recoveredUAsset >= verseDebt` | 状态改为 `Settled` |
| `claimRefund` | 用户 | market 为 `Refund` | `to != address(0)`，有未领取利息 | 标记 `refundClaimed` |
| `claimLeveragedYT` | 用户 | market 为 `Locked / Settled` | `to != address(0)`，有未领取杠杆利息份额 | 标记 `leveragedYTClaimed` |
| `claimResidual` | 用户 | market 为 `Settled` | `to != address(0)`，有有效利息且未领取；四舍五入向下后 payout 可为 0 | 标记 `residualClaimed` |
| `setProtocolTreasury` | owner | 任意 | `newTreasury != address(0)` | 仅影响未来成功进入 `Locked` 的杠杆利息收入 |
| `setDefaultInterestRate` | owner | 任意 | `0 < newRate <= 1e18` | 仅影响未来注册 market |
| upgrade authorization | proxy admin / owner policy | 按升级框架 | 新实现初始化与存储布局必须兼容 | 不改变既有 market 语义 |
| pause behavior | pauser / owner policy | 任意 | pause 不得阻断必要的 unlock / refund / repay 安全出口 | pause 只限制新增资金入口和非必要领取入口 |

### 26.2 输入校验矩阵

| 入口 | 必要校验 |
| --- | --- |
| `genesis` | `amount > 0`，`user != address(0)` |
| `preorder` | `amount > 0`，`user != address(0)`，`totalPreorderFunds + amount <= preorderCap` |
| `redeemPT` | `amount > 0`，`to != address(0)` |
| `redeemYT` | `amount > 0`，`to != address(0)` |
| `leveragedGenesis` | `interestAmount > 0`；参与地址为 `msg.sender`，无 user-address 输入 |
| `claimResidual` | 用户有有效利息且未领取时可标记 claimed，即使向下取整后的 payout 为 0 |

## 27. Target ABI

`POLend` 外部目标 ABI：

```solidity
function initialize(address launcher, address splitter, address protocolTreasury, uint256 defaultInterestRate, uint256 leveragedDebtFactor) external;
function registerLendMarket(uint256 verseId) external;
function leveragedGenesis(uint256 verseId, uint256 interestAmount) external;
function markRefundable(uint256 verseId) external;
function finalizeLeveragedGenesis(uint256 verseId) external;
function recordLeveragedYT(uint256 verseId, address yt, uint256 totalLeveragedYT) external;
function preRedeemPTFee(uint256 verseId, uint256 ptAmount, address mintTo) external;
function burnPreRedeemedBacking(uint256 verseId, uint256 amount) external;
function executeGlobalSettlement(uint256 verseId) external;
function claimRefund(uint256 verseId, address to) external;
function claimLeveragedYT(uint256 verseId, address to) external;
function claimResidual(uint256 verseId, address to) external;
function setProtocolTreasury(address newTreasury) external;
function setDefaultInterestRate(uint256 newRate) external;
function getLendMarket(uint256 verseId) external view returns (LendMarket memory);
function getTotalLeveragedDebt(uint256 verseId) external view returns (uint256);
function getUserLeveragedDebt(uint256 verseId, address user) external view returns (uint256);
function getLeveragedDebtInfo(uint256 verseId) external view returns (LeveragedDebtInfo memory);
function getTotalDebtByUAsset(address uAsset) external view returns (uint256);
```

`POLSplitter` 外部目标 ABI：

```solidity
function initializeVerse(uint256 verseId, address pol, address memecoin, address uAsset, string calldata name, string calldata symbol) external;
function split(uint256 verseId, uint256 polAmount) external;
function merge(uint256 verseId, uint256 ptAmount) external;
function settle(uint256 verseId) external;
function preRedeemPTFee(uint256 verseId, uint256 ptAmount) external;
function redeemPT(uint256 verseId, uint256 ptAmount, address to) external;
function redeemYT(uint256 verseId, uint256 ytAmount, address to) external;
```

## 28. 错误语义

统一使用 `InvalidClaim` 覆盖无份额或重复领取：

- `claimRefund`
- `claimNormalYT`
- `claimLeveragedYT`
- `claimResidual`
- `redeemAuxiliaryLiquidity`
- 普通 refund
- preorder refund

不保留 `InvalidRefund / InvalidRedeem` 这种分裂错误。

`ptAmount = 0` 时 `Launcher` 不应调用 `preRedeemPTFee`，`Splitter` 不需要专门处理。

settled 后不应再走 `preRedeemPTFee`，而应由 `Launcher` 路由到 `redeemPT`。`preRedeemPTFee` 的 settled 检查不作为正常业务分支设计。

## 29. 互斥关系

普通侧：

- `refund` 只在 `Refund`
- 初始 `YT` claim 只在成功路径
- `redeemAuxiliaryLiquidity` 只在 `Unlocked` 及之后成功路径
- `refund` 与成功路径 claim / redeem 互斥

杠杆侧：

- `claimRefund` 只在 `Refund`
- `claimLeveragedYT` 只在成功路径
- `claimResidual` 只在 `Settled`
- `claimRefund` 与 `claimLeveragedYT / claimResidual` 互斥

Preorder：

- 成功路径：主池首笔交易后按比例 vesting 领取 `memecoin`
- Refund 路径：原路退回 `uAsset`
