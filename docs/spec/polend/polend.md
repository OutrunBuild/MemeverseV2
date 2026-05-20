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
| `PT` | Principal Token，本金凭证，按 verse 固定 backing ratio 兑付 `uAsset` |
| `YT` | Yield Token，收益凭证 |

关键关系：

- raw-unit identity：`POL raw = main pool LP raw`，`PT raw = POL raw`，`YT raw = POL raw`
- `1 raw PT` 不等于 `1 raw uAsset`。每个 verse 在 `Locked` / 四池初始化时由 `Launcher` 一次性记录固定 PT backing ratio：
  - `mainUAssetFunds` 是主池 bootstrap budget，不是 PT backing truth
  - `ptBackingNumerator = actualMainUAssetUsed`
  - `ptBackingDenominator = main pool LP / POL raw amount actually minted at launch`
  - `uAssetBacking = FullMath.mulDiv(ptAmount, actualMainUAssetUsed, mainPoolPOLAmount)`
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
- 成功时把杠杆利息按全局 reserve 容量拆分为 settlement reserve 与 `protocolTreasury` 收入
- 杠杆退款
- 杠杆初始 `YT` 托管与发放
- 杠杆残值记账与领取
- settlement dust reserve 预留与手动注入
- 按 `uAsset` 维度记录系统债务
- 杠杆侧全局结算与债务偿还
- settle 前杠杆侧 PT fee 预兑付
- settle 时预兑付 PT fee backing 的 repay

`POLend.protocolTreasury` 只接收超出全局 reserve 容量的杠杆利息、Launcher over-capacity funding excess 以及其他明确归 treasury 的杠杆利息收入。该产品术语映射到当前实现 getter/storage `treasury()` / `treasury`，不要求 ABI 重命名。它不是 Memeverse DAO governor，不是 `yieldVault`，也不接收主池 fee 或辅助池 fee。

`POLend` 维护按 `uAsset` 维度复用的全局 settlement dust reserve。该 reserve 只用于 `executeGlobalSettlement` 中补足有上限的整数舍入缺口，不是坏账兜底池，不参与用户残值分配；成功 settlement 后只扣减实际消耗量，未消耗余额继续留在全局池中。

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

`setDefaultInterestRate(newRate)` 只影响未来新注册 verse，不影响任何已注册 market。setter 必须用当前 `leveragedDebtFactor` 与 `newRate` 校验默认配置仍满足杠杆约束，保证后续注册可用。

`Launcher.registerMemeverse` 必须在同一交易内调用：

```text
POLend.registerLendMarket(verseId)
```

`registerLendMarket` 只能由 `Launcher` 调用，每个 `verseId` 只能调用一次。

已注册判断使用 `market.uAsset != address(0)`。注册时从 `Launcher` 读取的 verse `uAsset` 必须非零；若为零，`registerLendMarket` revert `ZeroInput`，不创建 market。

`registerLendMarket` 还必须要求该 `uAsset` 已完成全局 reserve 配置：

```text
settlementDustStates[uAsset].maxReserve > 0
```

未配置 reserve 的 launch-supported `uAsset` 不是有效运行态，必须在 market 注册阶段直接拒绝，而不是延后到杠杆创世或 settlement 流程。

注册时：

- 从 `Launcher` 读取该 verse 的 `uAsset`
- 复制当前 `defaultInterestRate` 到 `market.interestRate`
- 设置 `market.state = None`
- 不初始化 `PT / YT`
- 不记录 `POL`
- 不记录 `PT`
- 不存储 `totalLeveragedDebt`

`market.interestRate` 注册后固定不变。

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

`claimRefund / claimLeveragedYT / claimResidual` 对 `state == None` revert `InvalidState`。

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

### 6.7 Settlement dust reserve

`POLend` 必须按 `uAsset` 维度维护全局 settlement dust reserve：

```solidity
struct SettlementDustState {
    uint128 reserve;
    uint128 maxReserve;
}

mapping(address uAsset => SettlementDustState) settlementDustStates;
```

其中：

- `reserve` 是 `POLend` 当前持有、可用于 bounded settlement deficit 的该 `uAsset` 全局 reserve 余额
- `maxReserve` 是该 `uAsset` 全局 reserve 总上限，不是单 verse 上限，不是单次 settlement 上限

本文中的 launch-supported `uAsset` 指注册中心允许用于新 verse 注册 / launch 的 supported `uAsset`。治理 / 运维不得把某 `uAsset` 开放为 launch-supported，除非 Launcher 募资参数和 POLend settlement dust reserve 都已配置完成。

所有 launch-supported `uAsset` 都必须先配置 `maxReserve > 0`。POLend 不通过 `fundMetaDatas` 等募资参数推断 supported 状态；owner 必须显式调用：

```text
setMaxSettlementDustReserve(address uAsset, uint128 maxReserve)
```

setter 规则：

- `uAsset != address(0)`
- `maxReserve > 0`
- 若下调上限，必须满足当前 `reserve <= maxReserve`

`finalizeLeveragedGenesis` 必须通过统一内部 credit helper 把已支付杠杆利息注入全局 reserve：

```text
capacity = maxReserve - reserve
credited = min(totalLeveragedInterest, capacity)
treasuryInterest = totalLeveragedInterest - credited
reserve += credited
```

credited 部分进入全局 reserve；`treasuryInterest` 转入 `POLend.protocolTreasury`。该 credit 不 mint，不增加 debt，不创建任何用户债权，并且必须 emit `SettlementDustReservedFromInterest`。

唯一 public funding 入口为：

```text
fundSettlementDustReserve(address uAsset, uint256 amount)
```

规则：

- permissionless，任何地址都可调用
- `amount > 0`
- `settlementDustStates[uAsset].maxReserve > 0`
- 必须在 token transfer 前先读取 `capacity = maxReserve - reserve`
- 若 `msg.sender != Launcher`，必须在 transfer 前要求 `amount <= capacity`
- 若 `msg.sender == Launcher`，允许 over-capacity；credited 进入 reserve，`excess` 同交易转入 `protocolTreasury`
- 成功 funding 不产生 claim 权利，不进入残值
- 不受 pause 阻断；该入口只注入 `uAsset`，不产生 claim 权利，属于 unlock / repay 安全出口

Launcher 在 bootstrap liquidity deployment 后若发现 auxiliary pool actual spend 低于 desired budget 而留下 unused `uAsset`，必须调用该统一入口把该部分 unused `uAsset` 注入全局 reserve；若 reserve 已满，则 excess 进入 treasury。unused `memecoin` 必须 burn，不进入 reserve。该处理直接以实际执行结果为准，不依赖单独文档化的 bootstrap rounding-envelope accept/reject 规则，也不要求 auxiliary underspend 先满足额外的 backing / equality guard。Launcher 必须 emit `BootstrapUnusedAssetsHandled` 记录该 `verseId` 的 unused `uAsset` 与 burned `memecoin` 来源；POLend 的 `SettlementDustReserveFunded` 记录实际 reserve credited / treasury excess 结果。

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

若 `settlementDustStates[uAsset].maxReserve == 0`，该 market 对应 `uAsset` 未完成全局 reserve 配置，`getLeveragedDebtInfo(verseId)` 必须返回 `debtCap=0,remainingAdditionalInterest=0`，避免 view 层展示实际运行态会拒绝的可用容量。

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
rawDebtCap = fullPrecisionMulDiv(leveragedDebtFactor, max(totalNormalFunds, minTotalFund), 1e18)
aggregateDebtCap = MAX_SUPPORTED_TOTAL_GENESIS_FUNDS - totalNormalFunds
debtCap = min(rawDebtCap, aggregateDebtCap)
totalLeveragedDebt = totalLeveragedInterest * 1e18 / market.interestRate
```

`debtCap` 是当前可新增杠杆创世状态下的有效上限，已包含 aggregate genesis funds 上限；`rawDebtCap` 只表示 `leveragedDebtFactor` 推导出的原始上限。`remainingAdditionalInterest` 表示在当前 `Genesis` 状态下还能新增的最大利息，使新增后的推导债务仍满足 `totalLeveragedDebt <= debtCap`。

精确计算：

```text
maxTotalLeveragedInterest = ((debtCap + 1) * market.interestRate - 1) / 1e18

if maxTotalLeveragedInterest <= totalLeveragedInterest:
    remainingAdditionalInterest = 0
else:
    remainingAdditionalInterest = maxTotalLeveragedInterest - totalLeveragedInterest
```

以上容量计算只在 `settlementDustStates[uAsset].maxReserve > 0` 时执行；否则容量返回 0。

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
rawDebtCap = fullPrecisionMulDiv(leveragedDebtFactor, debtCapBase, 1e18)
debtCap = min(rawDebtCap, MAX_SUPPORTED_TOTAL_GENESIS_FUNDS - totalNormalFunds)
totalLeveragedDebt <= debtCap
```

`leveragedDebtFactor` 是全局杠杆债务上限系数，所有 verse 共享，不是单用户倍数。对单个 verse 而言，factor 推导出的原始杠杆债务上限为 `fullPrecisionMulDiv(leveragedDebtFactor, max(totalNormalFunds, minTotalFund), 1e18)`，实际有效上限还必须受 aggregate genesis funds 剩余容量限制。

约束：`fullPrecisionMulDiv(leveragedDebtFactor, interestRate, 1) >= 1e36`。该条件是纯杠杆创世独立达到成功门槛的前提。`leveragedDebtFactor` 无独立下限，只与 `interestRate` 联合约束。market 注册在复制当前默认配置前校验该约束；全局配置 setter 也必须保持同一约束，保证后续注册可用。

`fundBasedAmount` 的地址排序最紧分支（`memecoin > uAsset`）要求 `fundBasedAmount <= 2^64 - 1`，该上界只服务 launcher bootstrap 初始价格参数，不用于约束 `minTotalFund`、`totalNormalFunds` 或其他 fund-size 变量。

`MAX_LEVERAGED_DEBT_FACTOR = uint128.max * 1e18` 是 `leveragedDebtFactor` 的技术有效上限，不是经济最优值。aggregate genesis funds 支持域已按 `uint128.max` 封顶，更大的 `leveragedDebtFactor` 不会增加任何 verse 的可用 `debtCap` 或 `remainingAdditionalInterest`，因此 `initialize` 与 `setLeveragedDebtFactor` 都必须按 `InvalidConfig` 拒绝。所有 `leveragedDebtFactor` 相关计算都必须使用全精度 `mulDiv` 或等价 overflow-safe 实现安全完成，该上限校验不能依赖把 `minTotalFund`、`totalNormalFunds` 或 `totalLeveragedInterest` 预先限制到 `2^64 - 1` 这一错误前提。

`setLeveragedDebtFactor(newFactor)` 只影响仍可新增杠杆创世的未来 debt cap / `remainingAdditionalInterest` 计算，即 market 为 `None / Genesis` 且 Launcher verse 仍处于 `Genesis` 的情形。setter 不改变已注册 market 的固定 `interestRate`，不改变已 mint 债务，不改变 `Locked / Settled / Refund` 的结算或 claim 语义。降低 `leveragedDebtFactor` 后，若已有 Genesis market 的累计债务已达到或超过新 cap，后续 `leveragedGenesis` 可能被阻止，但既有利息不会被追溯 revert。`finalizeLeveragedGenesis` 仍不重复检查 debt cap。

`MAX_SUPPORTED_TOTAL_GENESIS_FUNDS` 固定为：

```text
type(uint128).max
```

成功路径的创世总资金口径为：

```text
totalGenesisFunds = totalNormalFunds + totalLeveragedDebt
```

`totalGenesisFunds` 不包含 preorder。

成功 `genesis` / `leveragedGenesis` 写入后都必须保持：

```text
totalGenesisFunds <= MAX_SUPPORTED_TOTAL_GENESIS_FUNDS
```

即使普通资金为 0，杠杆债务上限也仍受 aggregate MAX 约束，实际可达到的上限为：

```text
min(fullPrecisionMulDiv(leveragedDebtFactor, minTotalFund, 1e18), MAX_SUPPORTED_TOTAL_GENESIS_FUNDS)
```

`leveragedGenesis` 写入前必须用本次新增利息后的总利息做预检：

```text
nextTotalLeveragedInterest = totalLeveragedInterest + interestAmount
previewDebt = nextTotalLeveragedInterest * 1e18 / market.interestRate
rawDebtCap = fullPrecisionMulDiv(leveragedDebtFactor, max(totalNormalFunds, minTotalFund), 1e18)
previewDebt <= rawDebtCap
totalNormalFunds + previewDebt <= MAX_SUPPORTED_TOTAL_GENESIS_FUNDS
```

预检必须基于累计 `nextTotalLeveragedInterest -> previewDebt`，不能只检查当前调用新增 delta。

成功门槛比较 `totalLeveragedInterest`（用户实际支付的 uAsset 利息总额），四池部署资金口径使用 `totalLeveragedDebt`（利息推导出的债务本金，`debt = interest × 1e18 / interestRate`）。二者数值不同但方向一致。

## 11. 杠杆创世

`leveragedGenesis(verseId, interestAmount)`：

- 只允许 Launcher 已注册的 verse
- 只允许 Launcher verse 处于 `Genesis`
- market 为 `None` 时，本次调用成功后进入 `Genesis`
- market 为 `Genesis` 时，继续累计利息
- market 为其他状态时 revert
- `interestAmount` 必须大于 0
- 要求该 verse 的 `uAsset` 已完成全局 reserve 配置：`settlementDustStates[uAsset].maxReserve > 0`
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
5. Router 主池执行完成、主池实际消耗 `uAsset` 与主池 LP/POL raw amount 已知后，调用 `POLSplitter.recordPTBackingRatio(verseId, mainPoolUAssetUsed, mainPoolPOLAmount)`
6. split 用于辅助池的 `POL`，部署三个辅助池
7. 若 `getTotalLeveragedDebt(verseId) > 0`，转移杠杆初始 `YT` 给 `POLend`
8. 若 `getTotalLeveragedDebt(verseId) > 0`，调用 `POLend.recordLeveragedYT(verseId, yt, totalLeveragedYT)`

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
- 要求该 verse 的 `uAsset` 已完成全局 reserve 配置：`settlementDustStates[uAsset].maxReserve > 0`
- 先把 market 状态设为 `Locked`
- mint `totalLeveragedDebt` 数量的该 verse `uAsset` 到 `Launcher`
- 调用 `_creditSettlementDustReserve(uAsset, totalLeveragedInterest)`，把 `credited` 注入该 `uAsset` 全局 reserve
- 把 `excess` 作为 `treasuryInterest` 转给 `POLend.protocolTreasury`
- `globalDebtByUAsset[market.uAsset] += totalLeveragedDebt`
- emit `SettlementDustReservedFromInterest(verseId, uAsset, totalLeveragedInterest, credited, treasuryInterest, reserveAfter)`

mint 数量：

```text
mintedUAsset = totalLeveragedInterest * 1e18 / market.interestRate
```

`finalizeLeveragedGenesis` 不重复检查 debt cap。

`finalizeLeveragedGenesis` 完成成功路径的利息 reserve / treasury 拆分后，`claimRefund` 不可用。

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

主池铸造 `POL`。主池 LP token 即为 POL。POL mint 数量由主池部署时的 uAsset 存入量和初始价格决定，初始价格由 `fundBasedAmount` 参数定义。`fundBasedAmount` 配置语义见 [docs/spec/verse/config-matrix.md](../verse/config-matrix.md)。

`ptBackingNumerator / ptBackingDenominator` 的唯一权威写入点是 `POLSplitter.recordPTBackingRatio(verseId, numerator, denominator)`。`Launcher` 必须在主池 LP/POL 实际 mint 后、任何 `split` 或 PT 相关辅助池创建前调用一次；之后不可变。

记录参数：

- `mainUAssetFunds` 仅表示主池 bootstrap budget / 计划投入额，不表示实际 backing
- `numerator = mainPoolUAssetUsed`
- `denominator = mainPoolPOLAmount`

WR-004 要求 PT backing ratio 必须基于主池 Router / AMM 实际执行结果，而不是基于期望预算。若 Router 或 AMM 在主池创建过程中退回未使用的 bootstrap `uAsset` / `memecoin`，该未使用部分不计入 PT backing。auxiliary pool actual spend 低于 desired budget 形成的未使用 bootstrap `uAsset` 必须按 §6.7 注入 POLend settlement dust reserve / treasury excess 路径，未使用 bootstrap `memecoin` 必须 burn。

`denominator` 必须使用 launch 实际 mint 出来的 main pool LP/POL raw amount，不能使用预估值。

`POL` 统一按：

- `2/7` 进入 `POL/uAsset`
- `3/7` 进入 `split(POL)` 得到 `PT + YT`
- `2/7` 进入 `PT/POL`

split 得到的 `PT` 再按：

- `1/3` 进入 `PT/uAsset`
- `2/3` 进入 `PT/POL`

PT 切分的整数取整差额归 PT/POL 侧（`ptForPtUAsset = totalPT / 3`，`ptForPtPol = totalPT - ptForPtUAsset`）。

辅助池 uAsset 侧分配（`totalAuxiliaryFunds` = `totalGenesisFunds * 30%`）：

- `POL/uAsset`: `totalAuxiliaryFunds * 2/3`（与 2/7 POL 等值配对）
- `PT/uAsset`: `totalAuxiliaryFunds * 1/3`（与 1/7 PT 按固定 backing ratio 对应的 `uAsset` 配对）
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

`POLSplitter.recordPTBackingRatio`：

- 只由 `Launcher` 调用
- 每个 `verseId` 只能调用一次
- 只能在 `POLSplitter.initializeVerse` 后调用
- 必须在任何 `split / preRedeemPTFee / redeemPT / redeemYT` 路径前调用
- `numerator > 0`
- `denominator > 0`
- 记录 `ptBackingNumerator = numerator` 与 `ptBackingDenominator = denominator`
- `numerator` 必须等于 Router 执行后主池实际消耗的 `uAsset` raw amount，不得直接使用 bootstrap budget `mainUAssetFunds`
- 不 mint、burn 或转移 token

`split / merge`：

- 只在 `POLSplitter.initializeVerse` 后开放
- 只在 `recordPTBackingRatio` 后开放
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

`Splitter` 必须暴露并使用 PT raw -> uAsset backing raw 的 preview：

```text
previewPTToUAsset(verseId, ptAmount) = FullMath.mulDiv(ptAmount, ptBackingNumerator, ptBackingDenominator)
```

所有 `preRedeemPTFee`、`redeemPT`、`redeemYT` 的 PT reserve、settle 时预兑付 backing burn、`POLend.executeGlobalSettlement` 回收 PT settlement 都必须使用该转换后的 `uAsset` 数量，不得直接把 `ptAmount` 当作 `uAsset` 数量。

`mintPOLToken` 在 `Locked` 后继续 mint 新 POL 时，不再执行运行时 `InvalidPOLBacking` 风格的 strict backing equality 检查。

当前产品规则是：

- fixed PT backing ratio 仍由启动时记录的 `ptBackingNumerator / ptBackingDenominator` 定义
- `mintPOLToken` 继续走 exact-liquidity minting
- 若报价后的实际执行无法 mint 出请求的 LP/POL 数量，则整笔 mint fail closed
- 不存在一个单独的“bootstrap 式 underbacking”运行时豁免路径，也不存在一个允许额外 backing 改写 PT/YT 经济的路径

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
- `None / Genesis / Refund` 时 revert `InvalidState`
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

govUAssetFee = fullPrecisionMulDiv(totalUAssetFee, totalLeveragedDebt, totalGenesisFunds)
normalUAssetFee = totalUAssetFee - govUAssetFee

govPTFee = fullPrecisionMulDiv(totalPTFee, totalLeveragedDebt, totalGenesisFunds)
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

若 `previewPTToUAsset(verseId, currentAuxiliaryGovPTFee + pendingPTFee) == 0`：

- 本次不调用 `preRedeemPTFee` / `redeemPT`
- 合并后的 PT fee 继续保留在 `pendingPTFee`
- 同次可分发的 `uAsset fee` / `memecoin fee` 继续正常分发
- 后续 `redeemAndDistributeFees` 再次尝试该 PT fee 的兑现

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

若 `settled=true` 且 `previewPTToUAsset(verseId, claimablePT) == 0`：

- 本次不调用 `redeemPT`
- 本次不更新 `claimedPTFee`
- `claimableUAsset` 仍按正常路径领取
- `claimablePT` 继续保持未领取状态，后续 `claimNormalFees` 可再次尝试
- 返回值中的 `ptAmount` 表示本次仍未兑现的 PT fee，不表示已实际转给用户

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

除三个辅助池普通份额 LP 外，该路径还必须分发 bootstrap pre-LP residual 的 normal share：

```text
normalResidualPOL = totalResidualPOL - floor(totalResidualPOL * totalLeveragedDebt / totalGenesisFunds)
normalResidualPT = totalResidualPT - floor(totalResidualPT * totalLeveragedDebt / totalGenesisFunds)
```

用户领取 normal residual 的公式与普通 LP 一样，按：

```text
userGenesisFund / totalNormalFunds
```

做一次 floor 分配。只有这里最终按用户比例 floor 后的尾差 dust 可以残留。

若 `totalLeveragedDebt > 0`，`changeStage Locked -> Unlocked` 同一笔交易内完成 `executeGlobalSettlement`，用户无法在杠杆 LP 切走前领取普通 LP；原因是 `redeemAuxiliaryLiquidity` 在 `Locked` 阶段不可调用，`changeStage` 原子完成后才进入 `Unlocked`。

`executeGlobalSettlement` 会先切走杠杆份额 LP，并把 `auxiliaryLiquidities` 更新为剩余普通份额 LP。普通用户只能领取剩余普通份额。
同一条 leveraged auxiliary settlement 输出还必须包含 bootstrap pre-LP residual 的 leveraged share：`leveragedResidualPOL` 与 `leveragedResidualPT`。这两个量不是新的永久托管桶，而是 leveraged side 在现有 settlement/claim 流程里的附加输出。

bootstrap pre-LP residual `POL/PT` 不是这里的普通 auxiliary LP split dust。它必须在更早的 bootstrap accounting 阶段先单独记录为四个量：

```text
normalResidualPOL
normalResidualPT
leveragedResidualPOL
leveragedResidualPT
```

其中：

```text
leveragedResidualPOL = floor(totalResidualPOL * totalLeveragedDebt / totalGenesisFunds)
leveragedResidualPT = floor(totalResidualPT * totalLeveragedDebt / totalGenesisFunds)
```

normal share 取余数，不能另建永久 launcher bucket。

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
settled = true                     （重入守卫，在外部调用前设置）
burn POL collateral
-> 得到 totalRedeemedUAsset + settlementMemecoin
-> 若 preRedeemedPT > 0：
     preRedeemedUAssetBacking = preRedeemedPT.uAssetBacking
     Splitter approve 该 verse uAsset 给 POLend，金额为 preRedeemedUAssetBacking
     POLend repay Splitter 持有的 preRedeemedUAssetBacking
     settlementUAsset = totalRedeemedUAsset - preRedeemedUAssetBacking
     delete preRedeemedPT
-> 写入 settlementUAsset / settlementMemecoin
```

`totalRedeemedUAsset` 表示 burn `POL collateral` 后赎回出的全部 `uAsset`，尚未扣除已预兑付 `PT fee` backing。

`preRedeemedPT` 逻辑上是 `{ ptAmount, uAssetBacking }` 结构，包含 `Locked` 阶段主动分发时已经预兑付给 Memeverse DAO governor 路径的杠杆侧 PT fee raw 数量及其固定 ratio 转换后的 backing。不得用两个互不关联的 mapping 表达该状态。

`preRedeemedPT` 不包含：

- 普通用户领取到地址上的 PT fee
- 普通用户后续 `redeemPT`
- `executeGlobalSettlement` 后真实 `redeemPT`
- `_captureLockedAuxiliaryFees` 捕获进 `pendingAuxiliaryGovFeeStates.pendingPTFee` 的 PT fee

不变量：

```text
preRedeemedPT.uAssetBacking <= totalRedeemedUAsset
totalRedeemedUAsset >= preRedeemedPT.uAssetBacking + previewPTToUAsset(PT.totalSupply())
settlementUAsset >= previewPTToUAsset(PT.totalSupply())
```

这些不变量由以下产品设计保证：

- settle 时 burn 全部 POL collateral 赎回底层 uAsset
- `PT` 按固定 backing ratio 预留 `uAsset`
- settle 前，`preRedeemedPT.uAssetBacking + previewPTToUAsset(PT.totalSupply())` 是 still-held POL collateral 需要覆盖的固定 PT backing
- settlement 必须满足 `totalRedeemedUAsset >= preRedeemedPT.uAssetBacking + previewPTToUAsset(PT.totalSupply())`
- 扣除 `preRedeemedPT.uAssetBacking` 后，才能推出 `settlementUAsset >= previewPTToUAsset(PT.totalSupply())`

自然产品路径的安全依赖主池 POL 回收满足上述 solvency / backing invariant：

- `Locked` 阶段 `preRedeemPTFee` 的 `PT fee` 必须来自真实 `PT` supply，不能凭空生成。
- `Splitter.preRedeemPTFee` 固定 burn `Launcher` 持有的该部分 `PT`，并记录 `{ ptAmount, uAssetBacking }`。
- 被 burn 的 `PT` 已经从后续 `PT.totalSupply()` 中移除；settlement 只需要继续为剩余 `PT.totalSupply()` 保留 backing。
- settle 中扣 `preRedeemedPT.uAssetBacking` 不是重复扣 backing，而是把已经提前 mint / distributed 给 governor 路径的 backing 从 `totalRedeemedUAsset` 中结清 / repay。
- 结清后必须满足 `settlementUAsset >= previewPTToUAsset(PT.totalSupply())`。

### 19.1 WR-003 验证结果

WR-003 已按真实产品路径验证，不接受任意 mocked settlement 数字作为结论依据。

验证结论是产品模型 / 不变量证据，不是任意 mocked settlement 数字推演：

- 初始与 `Locked` 后新增的 `PT` 都来自真实 `split(POL)`。
- `preRedeemPTFee` burn 的是 `Launcher` 实际持有的真实 `PT`，因此 `preRedeemedPT.uAssetBacking` 对应的 backing 需求已从后续 `PT.totalSupply()` 中移除。
- 成功 settlement 的既有不变量是：先偿还 `preRedeemedPT.uAssetBacking`，偿还后剩余 `settlementUAsset` 继续覆盖 `previewPTToUAsset(PT.totalSupply())`。
- 对应关系为：

```text
totalRedeemedUAsset >= preRedeemedPT.uAssetBacking + previewPTToUAsset(PT.totalSupply())
settlementUAsset = totalRedeemedUAsset - preRedeemedPT.uAssetBacking
settlementUAsset >= previewPTToUAsset(PT.totalSupply())
```

验证证据：

- `forge test --match-path test/verse/MemeverseLauncherPOLendSettlementInvariant.t.sol --match-test 'testRealPathFundBasedAmountAboveOneCoversSettlementPTBacking|testRealPathLockedPreRedeemPTFeeSettlementBacking|testRealPathMixedFundsCoversSettlementDustAndLeavesNormalAuxiliaryRemainder' -vv` 通过 3 个测试。
- `forge test --match-contract MemeverseLauncherPOLendSettlementStdInvariantTest -vv` 通过 7 个 invariant 测试。
- 其中 `invariant_successfulSplitterSettlementBacksPTSupply` 明确验证 successful splitter settlement 后剩余 `PT.totalSupply()` 仍被足额 backing。

因此，`preRedeemedPT.uAssetBacking > totalRedeemedUAsset` 或 `totalRedeemedUAsset < preRedeemedPT.uAssetBacking + previewPTToUAsset(PT.totalSupply())` 只能来自以下破坏：

- `PT fee` 不是从真实 `PT` supply 转入并被 burn，而是被伪造。
- 主池 `POL -> uAsset` 回收低于固定 PT backing 总需求，形成 solvency / backing boundary failure。

上述两类都不是合法自然产品路径，不能作为 `settle` 的正常业务分支。若后续有真实产品路径 / router 数学被证明会产生 `totalRedeemedUAsset < preRedeemedPT.uAssetBacking + previewPTToUAsset(PT.totalSupply())`，该情形属于 solvency / boundary failure；它不能被归类为 `preRedeemPTFee` deficit，也不能被归类为 settlement dust。处理该边界需要单独的显式 enforcement 决策 / guard，不能按正常流程静默接受。

不作为正常业务分支处理。

`settlementMemecoin` 不受 `preRedeemedPT` 影响。

settle 后：

- `redeemPT / redeemYT` 开放
- `split / merge` 关闭

错误命名：

- `AlreadyUnlocked`：`split / merge` 已关闭（verse 已 Unlocked 或 settle 已完成）
- `NotUnlocked`：`settle` 阶段不正确（verse 尚未 Unlocked）
- `NotSettled`：redeem 前尚未 settle
- `AlreadyDeployed`：`initializeVerse` 重复调用
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
- 返回 `uAssetBacking`
- 不调用 `YieldDispatcher.lzCompose`
- 不调用 `IOFT.send`
- 不重新 claim fee
- 不重新拆分普通侧 / 杠杆侧
- 只处理 `Launcher` 传入的 `ptAmount`
- 只能在 `Splitter` 尚未 settled 时按产品路径调用

流程：

```text
POLend.preRedeemPTFee
-> uAssetBacking = Splitter.preRedeemPTFee(verseId, ptAmount)
-> POLend mint uAssetBacking uAsset 到 mintTo
-> globalDebtByUAsset[market.uAsset] += uAssetBacking
-> emit PreRedeemPTFee(verseId, market.uAsset, ptAmount, uAssetBacking, mintTo)
```

`Splitter.preRedeemPTFee`：

- 只允许 `POLend` 调用
- burn account 固定为 `Launcher`
- 返回 `uAssetBacking = previewPTToUAsset(verseId, ptAmount)`
- 若 `ptAmount > 0` 但 `uAssetBacking == 0`，revert，不得 burn PT 或记录预兑付
- burn `Launcher` 当前持有的 `ptAmount` PT
- `preRedeemedPT.ptAmount += ptAmount`
- `preRedeemedPT.uAssetBacking += uAssetBacking`
- 不修改 `settlementUAsset`

settle 前还没有 settlement pool。

`preRedeemPTFee` 只处理已经进入 `Launcher` 的真实杠杆侧 `PT fee`。该路径的产品证据为：

```text
genesis + leveragedGenesis
-> Locked
-> mintPOLToken
-> split
-> real PT transferred to hook
-> redeemAndDistributeFees
-> preRedeemPTFee
-> unlock settlement
```

测试 `testRealPathLockedPreRedeemPTFeeSettlementBacking` 覆盖上述路径，并验证真实 `PT` 被转入 hook、分发时被 `Launcher` 持有、预兑付时被 burn、unlock settlement 后仍满足剩余 `PT.totalSupply()` 的 backing 要求。

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
event PreRedeemPTFee(uint256 indexed verseId, address indexed uAsset, uint256 ptAmount, uint256 uAssetBacking, address mintTo);
```

### 20.2 settle 时：burnPreRedeemedBacking

`Splitter.settle` 遇到 `preRedeemedPT > 0` 时：

1. `Splitter` approve 该 verse `uAsset` 给 `POLend`，金额为 `preRedeemedPT.uAssetBacking`
2. `Splitter` 调用 `POLend.burnPreRedeemedBacking(verseId, preRedeemedPT.uAssetBacking)`
3. `POLend` 调 `uAsset.repay(address(splitter), preRedeemedPT.uAssetBacking)`
4. `globalDebtByUAsset[market.uAsset] -= preRedeemedPT.uAssetBacking`
5. `Splitter` 设置 `settlementUAsset = totalRedeemedUAsset - preRedeemedPT.uAssetBacking`
6. `Splitter` delete `preRedeemedPT[verseId]`

`burnPreRedeemedBacking`：

- 只允许 `Splitter` 调用
- 只能在该 verse settle 流程中调用
- 使用该 verse 记录的 `uAsset`
- 不能由调用方传入 token 地址

`preRedeemedPT = 0` 时，`Splitter.settle` 直接跳过 `burnPreRedeemedBacking`。

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
- `uAssetAmount = previewPTToUAsset(verseId, ptAmount)`
- 若 `ptAmount > 0` 但 `uAssetAmount == 0`，revert，不得 burn PT
- `settlementUAsset -= uAssetAmount`
- 向 `to` 转出 `uAssetAmount`
- 不需要 approve
- 不额外读取 `PT.totalSupply()`
- 不使用 `preRedeemedPT`

公式：

```text
uAssetAmount = FullMath.mulDiv(ptAmount, actualMainUAssetUsed, ptBackingDenominator)
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
reservedUAssetForPT = previewPTToUAsset(verseId, PT.totalSupply())
ytRedeemableUAssetPool = settlementUAsset - reservedUAssetForPT

uAssetAmount = ytRedeemableUAssetPool * ytAmount / outstandingYT
memecoinAmount = settlementMemecoin * ytAmount / outstandingYT
```

若 `uAssetAmount == 0 && memecoinAmount == 0`，必须在 burn YT 前 revert，不得销毁无法兑付任何输出的 YT。

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
- 按 `previewPTToUAsset(verseId, ptAmount)` 兑回 `uAsset`
- 不得把非零 `PT` 静默当作 0 backing 处理
- 输出进入 `POLend`

回收的 `uAsset` 汇总后先偿还该 verse 全部债务。若出现有上限的整数舍入缺口，只能由对应 `uAsset` 的全局 settlement dust reserve 补足：

```text
verseDebt = totalLeveragedInterest * 1e18 / market.interestRate
deficit = verseDebt > recoveredUAsset ? verseDebt - recoveredUAsset : 0

if deficit == 0:
    consumedSettlementDustReserve = 0
    residualUAsset = recoveredUAsset - verseDebt

if deficit > 0:
    if deficit > settlementDustStates[market.uAsset].reserve:
        revert SettlementDustInsufficient(deficit, settlementDustStates[market.uAsset].reserve)
    consumedSettlementDustReserve = deficit
    settlementDustStates[market.uAsset].reserve -= deficit
    residualUAsset = 0

globalDebtByUAsset[market.uAsset] -= verseDebt
uAsset.repay(address(POLend), verseDebt)
```

`recoveredUAsset + consumedSettlementDustReserve >= verseDebt` 是必须成立的产品不变量。`consumedSettlementDustReserve` 只能覆盖正确执行固定 PT backing ratio 转换后的辅助 LP unwind、POL 赎回、PT 兑付和 full-range LP 数学中的整数舍入 dust；不得覆盖真实资不抵债、PT backing ratio / 模型错误、错误 LP 份额或 fee 账务缺口。

如果 `deficit > settlementDustStates[market.uAsset].reserve`，说明该 `uAsset` 全局 reserve 余额不足，该缺口不再被当前 reserve 规则接受为可补偿 dust，`executeGlobalSettlement` 必须 revert。实现前必须提供可审查的安全 / 证明证据：数学证明或 invariant tests，覆盖辅助 LP unwind、POL 赎回、PT 兑付、fee、整数舍入、极端价格状态，并证明任意允许 dust 补偿都被 `maxReserve` 全局容量约束。

不设计：

- `remainingDebt`
- `badDebt`
- `unrepaidDebt`
- 部分偿还
- reserve 超上限兜底

剩余净资产写入 `ResidualState`：

```text
residualUAsset = recoveredUAsset > verseDebt ? recoveredUAsset - verseDebt : 0
residualMemecoin = recoveredMemecoin
```

若使用 reserve 补足 dust，`residualUAsset = 0`。`residualUAsset / residualMemecoin` 只从实际回收数量记录，任一项都可以为 0。

settlement 成功后不得清空该 `uAsset` 的全局 reserve，也不得把未消耗 reserve 转入 `POLend.protocolTreasury`。全局 reserve 只扣减实际消耗量，剩余余额保留给后续使用同一 `uAsset` 的 settlement。

完成后 market state 变为 `Settled`。

安全要求：

- `POLend.executeGlobalSettlement` 和 `POLSplitter.redeemYT` 必须使用重入锁
- `executeGlobalSettlement` 分三阶段执行，阶段之间不可交叉：
  1. **资产回收**：外部调用回收辅助池 LP、burn POL 赎回底层资产、PT→uAsset 兑付，获取 `totalRecoveredUAsset`
  2. **状态写入**：写入 `market.state = Settled`、防重复 settlement 状态、全局 reserve 实际消耗量、`residualStates`、`globalDebtByUAsset`
  3. **债务偿还与转账**：`uAsset.repay` 偿还 verseDebt；若流程中存在 treasury 收入，只能转已定义为 treasury 的金额，不能转未消耗 reserve；这两步必须在阶段 2 完成之后执行
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

Settlement dust reserve 不属于用户级 floor allocation dust。它只在 `executeGlobalSettlement` 中按 `settlementDustStates[uAsset].reserve` 可用余额消耗，未消耗部分继续留在该 `uAsset` 全局 reserve 池中。

## 24. uAsset mint / repay 权限

每个 verse 的 `uAsset` 必须是受支持的 mint / repay / OFT 资产，由注册中心或 `Launcher` 在注册阶段保证。

`POLend` 不重复维护 supported asset 鉴权。

### 24.1 uAsset 信任边界（无回调要求）

`uAsset` 必须是受信任且**无外部回调**语义的资产实现。

具体要求：

- `transfer / transferFrom / approve / mint / repay` 不得在执行过程中触发任意外部回调（包括但不限于对调用方、接收方、第三方 hook 的同步可重入调用）。
- 不支持带“转账钩子 / 回调执行器 / 可插拔外部逻辑”的 `uAsset` 变体作为产品资产。
- 该约束由注册中心、部署流程与治理配置共同保证；违反该约束的资产不属于本协议支持范围。

该要求是产品级前置条件，不依赖运行时检测；其目的是确保 `POLend` 与 `Launcher` 的资金路径在面对 `uAsset` 调用时不引入额外可重入攻击面。

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
Splitter approve POLend exact converted uAssetBacking amount
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

- `initialOwner`
- `defaultInterestRate`
- `leveragedDebtFactor`
- `protocolTreasury`
- `launcher`
- `splitter`

`protocolTreasury` 必须非零。

`fullPrecisionMulDiv(leveragedDebtFactor, interestRate, 1) >= 1e36`。market 注册在复制当前默认配置前校验该约束；全局配置 setter 也必须保持同一约束，保证后续注册可用。`initialize` 输入的 `leveragedDebtFactor` 还必须满足 `<= MAX_LEVERAGED_DEBT_FACTOR`，其中 `MAX_LEVERAGED_DEBT_FACTOR = uint128.max * 1e18`；超出即 `InvalidConfig`。

`setProtocolTreasury(newTreasury)`：

- 仅 owner
- `newTreasury != address(0)`
- 只影响未来杠杆利息 treasury 份额与 Launcher over-capacity funding excess 的接收地址
- 事件 `event ProtocolTreasuryChanged(address indexed oldTreasury, address indexed newTreasury);`

`setDefaultInterestRate(newRate)`：

- 仅 owner
- `0 < newRate <= 1e18`
- 使用当前 `leveragedDebtFactor` 与 `newRate` 校验 `fullPrecisionMulDiv(leveragedDebtFactor, newRate, 1) >= 1e36`
- 只影响未来注册 market
- 事件 `event DefaultInterestRateChanged(uint256 oldRate, uint256 newRate);`

`setLeveragedDebtFactor(newFactor)`：

- 仅 owner
- `newFactor != 0`
- 使用 `newFactor` 与当前 `defaultInterestRate` 校验 `fullPrecisionMulDiv(newFactor, defaultInterestRate, 1) >= 1e36`
- `newFactor <= MAX_LEVERAGED_DEBT_FACTOR`，其中 `MAX_LEVERAGED_DEBT_FACTOR = uint128.max * 1e18`；超出即 `InvalidConfig`
- 相关计算使用全精度 `mulDiv` 或等价 overflow-safe 实现；该校验不能依赖 `minTotalFund`、`totalNormalFunds` 或 `totalLeveragedInterest` 被统一限制到 `2^64 - 1`
- 只影响仍处于 `None / Genesis` 且 Launcher verse 仍处于 `Genesis` 的 market 后续 debt cap / `remainingAdditionalInterest` 计算；不改变已注册 market 利率、已 mint 债务或 `Locked / Settled / Refund` 结算 / claim 语义
- 事件 `event LeveragedDebtFactorChanged(uint256 oldFactor, uint256 newFactor);`

`setMaxSettlementDustReserve(address uAsset, uint128 maxReserve)`：

- 仅 owner
- `uAsset != address(0)`
- `maxReserve > 0`
- 按 supported `uAsset` 配置全局 reserve 总上限；setter 不通过募资参数推断 supported 状态
- 若下调上限，必须满足当前 `reserve <= maxReserve`
- 只影响之后执行的 market 注册检查、reserve credit 容量和 `executeGlobalSettlement` reserve 可用余额校验
- 事件 `event SettlementDustReserveConfigured(address indexed uAsset, uint128 oldMaxReserve, uint128 newMaxReserve);`

`fundSettlementDustReserve(address uAsset, amount)`：

- permissionless
- `amount > 0`
- 该 `uAsset` 必须已完成 reserve 配置
- 从调用者转入该 `uAsset`
- 非 `Launcher` 调用者必须在 transfer 前满足 `amount <= remaining capacity`
- `Launcher` 可以 over-capacity；credited 进入 reserve，`excess` 转入 treasury
- 不受 pause 阻断，作为 settlement dust reserve 不足时的 unlock / repay 安全出口
- 事件 `event SettlementDustReserveFunded(address indexed uAsset, address indexed funder, uint256 amount, uint256 credited, uint256 excess);`

### 26.1 权限 / 配置矩阵

| 函数 | Caller | 状态要求 | 输入 / 零值检查 | 事件 / 配置语义 |
| --- | --- | --- | --- | --- |
| `registerLendMarket` | `Launcher` | market 未注册 | verse `uAsset` 必须有效，且 `settlementDustStates[uAsset].maxReserve > 0`；复制当前 `defaultInterestRate`，校验 `leveragedDebtFactor` 与利率约束 | 注册后利率固定 |
| `leveragedGenesis` | 用户 | Launcher verse 为 `Genesis`；market 为 `None / Genesis` | `interestAmount > 0`；该 `uAsset` 已完成全局 reserve 配置；参与地址为 `msg.sender`，无 user-address 输入；累计 `nextTotalLeveragedInterest -> previewDebt` 预检必须同时满足 `previewDebt <= rawDebtCap` 与 `totalNormalFunds + previewDebt <= MAX_SUPPORTED_TOTAL_GENESIS_FUNDS` | `LeveragedGenesis` |
| `markRefundable` | `Launcher` | market 为 `Genesis` | 无金额输入 | 状态改为 `Refund` |
| `finalizeLeveragedGenesis` | `Launcher` | `Genesis -> Locked` 流程；market 为 `Genesis` | `totalLeveragedDebt > 0`；该 `uAsset` 已完成全局 reserve 配置 | 状态改为 `Locked`，mint debt，把杠杆利息按 reserve 容量拆分为 reserve 与 treasury，emit `SettlementDustReservedFromInterest` |
| `recordLeveragedYT` | `Launcher` | market 为 `Locked` | `yt != address(0)`，`totalLeveragedYT > 0`，防重复 | 记录杠杆初始 `YT` |
| `preRedeemPTFee` | `Launcher` | market 为 `Locked`，Splitter 未 settled | `ptAmount > 0`，`mintTo != address(0)`，converted `uAssetBacking > 0` | `PreRedeemPTFee`，增加 debt |
| `burnPreRedeemedBacking` | `Splitter` | Splitter settle 流程 | `amount > 0`；`amount == preRedeemedPT.uAssetBacking` 由 `onlySplitter` 调用约束保证，不由 POLend 运行时校验 | 减少 debt |
| `executeGlobalSettlement` | `Launcher` | `Locked -> Unlocked` 编排；market 为 `Locked` | 只处理一次；若 `recoveredUAsset < verseDebt`，缺口必须等于实际 `deficit`，且 `<= settlementDustStates[uAsset].reserve` | 状态改为 `Settled`，只扣减实际 reserve 消耗，emit `SettlementDustReserveConsumed` 与 `GlobalSettlementExecuted` |
| `fundSettlementDustReserve` | 任意地址 | reserve 已配置；不受 pause 阻断 | `amount > 0`；非 `Launcher` 成功路径要求 `amount <= remaining capacity` | 注入该 `uAsset` 全局 settlement dust reserve，无 claim 权利 |
| `claimRefund` | 用户 | market 为 `Refund` | `to != address(0)`，有未领取利息 | 标记 `refundClaimed` |
| `claimLeveragedYT` | 用户 | market 为 `Locked / Settled` | `to != address(0)`，有未领取杠杆利息份额 | 标记 `leveragedYTClaimed` |
| `claimResidual` | 用户 | market 为 `Settled` | `to != address(0)`，有有效利息且未领取；四舍五入向下后 payout 可为 0 | 标记 `residualClaimed` |
| `setProtocolTreasury` | owner | 任意 | `newTreasury != address(0)` | 仅影响未来杠杆利息 treasury 份额与 Launcher over-capacity funding excess 的接收地址 |
| `setDefaultInterestRate` | owner | 任意 | `0 < newRate <= 1e18`；当前 `leveragedDebtFactor` 与 `newRate` 满足杠杆约束 | 仅影响未来注册 market |
| `setLeveragedDebtFactor` | owner | 任意 | `newFactor != 0`；`newFactor <= uint128.max * 1e18`；`newFactor` 与当前 `defaultInterestRate` 满足杠杆约束 | 仅影响可继续新增杠杆创世的 `None / Genesis` market 后续 debt cap / `remainingAdditionalInterest` |
| `setMaxSettlementDustReserve` | owner | 任意 | `uAsset != address(0)`，`maxReserve > 0`，且下调时当前 `reserve <= maxReserve` | 配置该 `uAsset` 全局 settlement dust reserve 上限；不支持用 0 作为 launch-supported 运行模式 |
| upgrade authorization | owner（UUPS `_authorizeUpgrade`） | 按升级框架 | 新实现初始化与存储布局必须兼容 | 不改变既有 market 语义 |
| pause behavior | pauser / owner policy | 任意 | pause 不得阻断必要的 unlock / refund / repay 安全出口；`fundSettlementDustReserve` 视为 unlock / repay 安全出口 | pause 只限制新增资金入口和非必要领取入口。受 `whenNotPaused` 阻断的函数清单：`MemeverseLauncher.genesis`、`MemeverseLauncher.preorder`、`MemeverseLauncher.claimNormalYT`、`MemeverseLauncher.claimNormalFees`、`MemeverseLauncher.redeemAuxiliaryLiquidity`、`MemeverseLauncher.claimUnlockedPreorderMemecoin`、`MemeverseLauncher.redeemAndDistributeFees`、`POLend.leveragedGenesis`。不受 pause 阻断的安全出口：`POLend.claimRefund`、`POLend.claimLeveragedYT`、`POLend.claimResidual`、`POLend.fundSettlementDustReserve`、`POLend.executeGlobalSettlement`、`POLSplitter.redeemPT`、`POLSplitter.redeemYT`、`POLSplitter.settle` |

### 26.2 输入校验矩阵

| 入口 | 必要校验 |
| --- | --- |
| `genesis` | `amount > 0`，`user != address(0)` |
| `preorder` | `amount > 0`，`user != address(0)`，`totalPreorderFunds + amount <= preorderCap` |
| `redeemPT` | `amount > 0`，`to != address(0)` |
| `redeemYT` | `amount > 0`，`to != address(0)` |
| `leveragedGenesis` | `interestAmount > 0`；该 `uAsset` 已完成全局 reserve 配置；参与地址为 `msg.sender`，无 user-address 输入；累计 `nextTotalLeveragedInterest -> previewDebt` 必须同时满足 `previewDebt <= rawDebtCap` 与 `totalNormalFunds + previewDebt <= MAX_SUPPORTED_TOTAL_GENESIS_FUNDS` |
| `claimResidual` | 用户有有效利息且未领取时可标记 claimed，即使向下取整后的 payout 为 0 |
| `getUserLeveragedDebt` | `user != address(0)`，`ZeroInput`；market 未注册时 `InvalidState` |
| `getTotalDebtByUAsset` | `uAsset != address(0)`，`ZeroInput` |

## 27. Target ABI

本节区分 deployment / proxy 初始化 ABI 与 runtime integration ABI。

`initialize(...)` 是 proxy 初始化入口，用于部署编排和升级工具，不属于 Launcher / POLend / POLSplitter 运行期集成接口。`IPOLend` 与 `IPOLSplitter` 表达 runtime integration ABI；若部署脚本需要强类型 initializer，可使用单独的 initializer-only interface，不能把初始化入口误解为 per-verse 产品动作。

`POLend` deployment / proxy 初始化 ABI：

```solidity
function initialize(address initialOwner, uint256 defaultInterestRate, uint256 leveragedDebtFactor, address protocolTreasury, address launcher, address splitter) external;
```

`POLend` runtime integration ABI：

```solidity
function registerLendMarket(uint256 verseId) external;
function leveragedGenesis(uint256 verseId, uint256 interestAmount) external returns (uint256 borrowedAmount);
function markRefundable(uint256 verseId) external;
function finalizeLeveragedGenesis(uint256 verseId) external;
function recordLeveragedYT(uint256 verseId, address yt, uint256 totalLeveragedYT) external;
function preRedeemPTFee(uint256 verseId, uint256 ptAmount, address mintTo) external returns (uint256 uAssetBacking);
function burnPreRedeemedBacking(uint256 verseId, uint256 amount) external;
function executeGlobalSettlement(uint256 verseId) external;
function fundSettlementDustReserve(address uAsset, uint256 amount) external;
function claimRefund(uint256 verseId, address to) external returns (uint256 refundedAmount);
function claimLeveragedYT(uint256 verseId, address to) external returns (uint256 amount);
function claimResidual(uint256 verseId, address to) external returns (uint256 uAssetAmount, uint256 memecoinAmount);
function setProtocolTreasury(address newTreasury) external;
function setDefaultInterestRate(uint256 newRate) external;
function setLeveragedDebtFactor(uint256 newFactor) external;
function setMaxSettlementDustReserve(address uAsset, uint128 maxReserve) external;
function pause() external;
function unpause() external;
function getLendMarket(uint256 verseId) external view returns (LendMarket memory);
function getTotalLeveragedDebt(uint256 verseId) external view returns (uint256);
function getUserLeveragedDebt(uint256 verseId, address user) external view returns (uint256);
function getLeveragedDebtInfo(uint256 verseId) external view returns (LeveragedDebtInfo memory);
function getTotalDebtByUAsset(address uAsset) external view returns (uint256);
function getTotalLeveragedInterest(uint256 verseId) external view returns (uint256);
function settlementDustStates(address uAsset) external view returns (uint128 reserve, uint128 maxReserve);
```

`POLSplitter` deployment / proxy 初始化 ABI：

```solidity
function initialize(address initialOwner, address launcher) external;
```

`POLSplitter` runtime integration ABI：

```solidity
function initializeVerse(uint256 verseId, address pol, address memecoin, address uAsset, string calldata name, string calldata symbol) external returns (address pt, address yt);
function recordPTBackingRatio(uint256 verseId, uint256 numerator, uint256 denominator) external;
function split(uint256 verseId, uint256 polAmount) external returns (uint256 ptAmount, uint256 ytAmount);
function merge(uint256 verseId, uint256 ptAmount) external returns (uint256 polAmount);
function settle(uint256 verseId) external returns (uint256 settlementUAsset, uint256 settlementMemecoin);
function preRedeemPTFee(uint256 verseId, uint256 ptAmount) external returns (uint256 uAssetBacking);
function redeemPT(uint256 verseId, uint256 ptAmount, address to) external returns (uint256 uAssetAmount);
function redeemYT(uint256 verseId, uint256 ytAmount, address to) external returns (uint256 uAssetAmount, uint256 memecoinAmount);
function previewPTToUAsset(uint256 verseId, uint256 ptAmount) external view returns (uint256 uAssetAmount);
function previewRedeemYTUAsset(uint256 verseId, uint256 ytAmount) external view returns (uint256 uAssetAmount);
function splitInfos(uint256 verseId) external view returns (address pt, address yt, address pol, address memecoin, address uAsset, uint256 totalPOLCollateral, uint256 settlementUAsset, uint256 settlementMemecoin, uint256 ptBackingNumerator, uint256 ptBackingDenominator, bool settled);
```

`POLSplitter.initialize` 是 proxy 初始化入口，不是 per-verse 产品动作：

- 只在 proxy 初始化时调用一次
- `initialOwner != address(0)`
- `launcher != address(0)`
- 写入 `launcher`
- 初始化 `PrincipalToken / YieldToken` implementation
- 必须先于任何 `initializeVerse / split / settle / redeem` 路径完成

## 28. 错误语义

`InvalidState`：状态前置条件不满足。

`InvalidConfig`：配置前置条件不满足。

`POLend` 侧 `InvalidConfig` 使用场景：

- `registerLendMarket`：对应 `uAsset` 未完成全局 reserve 配置
- `finalizeLeveragedGenesis`：对应 `uAsset` 未完成全局 reserve 配置
- `fundSettlementDustReserve`：`uAsset` 未完成全局 reserve 配置
- `initialize / setLeveragedDebtFactor`：`leveragedDebtFactor > uint128.max * 1e18`
`POLend` 侧 `InvalidState` 使用场景：

- `registerLendMarket`：market 已注册；Launcher 返回的 verse `uAsset == address(0)` 时 `ZeroInput`
- `leveragedGenesis`：market 未注册或非 None/Genesis，Launcher verse 非 Genesis
- `markRefundable`：market 非 Genesis
- `finalizeLeveragedGenesis`：market 非 Genesis
- `recordLeveragedYT`：market 非 Locked 或已记录
- `preRedeemPTFee`：market 非 Locked
- `executeGlobalSettlement`：market 非 Locked
- `claimRefund`：market 非 Refund
- `claimLeveragedYT`：market 非 Locked/Settled
- `claimResidual`：market 非 Settled
- `getLeveragedDebtInfo`：market 未注册
- `getUserLeveragedDebt`：market 未注册；`user == address(0)` 时 `ZeroInput`
- `getTotalDebtByUAsset`：`uAsset == address(0)` 时 `ZeroInput`

`POLSplitter` 侧 `InvalidState` 等价错误：

- `recordPTBackingRatio`：verse 未 initialize 或 ratio 已记录
- `split / previewPTToUAsset / preRedeemPTFee / redeemPT / redeemYT`：ratio 未记录
- `AlreadyUnlocked`：split/merge 时 verse 已 Unlocked 或 settle 已完成
- `NotUnlocked`：settle 时 verse 尚未 Unlocked
- `AlreadySettled`：重复 settle，或 preRedeemPTFee 时已 settled
- `NotSettled`：redeemPT/redeemYT 时尚未 settled
- `AlreadyDeployed`：`initializeVerse` 重复调用

`SettlementDustReserveExceeded(uint256 amount, uint256 capacity)`：`fundSettlementDustReserve(address,uint256)` 的非 `Launcher` 调用者在 transfer 前请求金额超过剩余 capacity。

`SettlementDustInsufficient(uint256 deficit, uint256 availableReserve)`：`executeGlobalSettlement` 中 `recoveredUAsset < verseDebt`，且实际缺口超过当前 `uAsset` 全局 reserve 余额。该错误表示缺口不再被当前 reserve 规则接受为可补偿 dust。

统一使用 `InvalidClaim` 覆盖无份额或重复领取：

- `claimRefund`
- `claimNormalYT`
- `claimLeveragedYT`
- `claimResidual`
- `redeemAuxiliaryLiquidity`
- 普通 refund
- preorder refund
- `redeemYT`：`outstandingYT == 0`

不保留 `InvalidRefund / InvalidRedeem` 这种分裂错误。

`POLend` 与 `POLSplitter` 的重入锁使用 `ReentrancyGuardReentrantCall` 错误。

`ptAmount = 0` 时 `Launcher` / `POLend` 不应调用下游 `Splitter.preRedeemPTFee`；若直接触发 Splitter-only 防御路径，因换算 backing 为 0 而 revert `InvalidClaim`。

settled 后不应再走 `preRedeemPTFee`，而应由 `Launcher` 路由到 `redeemPT`。`preRedeemPTFee` 的 settled 检查不作为正常业务分支设计。`POLSplitter` 侧的 `AlreadySettled` 检查是防御性安全防线：正常流程中该检查不会触发（Launcher 在 `Locked` 时走 `preRedeemPTFee`，`Unlocked` 后走 `redeemPT`）；其作用是在 Launcher 路由逻辑异常时阻止 post-settle PT burn，防止不可逆资金损失。

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
