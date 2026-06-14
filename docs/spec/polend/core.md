# POLend Core

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
- `Locked -> Unlocked` 编排以 [settlement-and-fees.md §4](settlement-and-fees.md) 为唯一权威顺序
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

## 8. 错误语义

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

## 9. 互斥关系

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
