# POLend 规格文档

## 1. 文档定位与来源边界

本文档是 `POLend` 与 MemeverseV2 集成后的正式规格文档，描述产品真相层的规则、边界和资金流。

本文档只定义应该遵循的正式语义，不描述“当前代码已实现”的状态。

规则优先级如下：

1. 本文档 `docs/spec/polend.md`
2. `docs/superpowers/specs/2026-04-07-polend-product-spec.md`
3. `docs/superpowers/specs/2026-04-07-polend-design.md`
4. `docs/superpowers/specs/2026-04-08-polend-memeverse-adaptation.md`
5. `docs/spec/*.md` 中与本协议无冲突的通用规则

不在本文档范围内的内容：

- PT 抵押借款
- `POLendRouter`
- 旧的 `75/25` 创世拆分
- 旧的三池模型

## 2. 核心术语

| 术语 | 含义 |
|---|---|
| `uAsset` | 统一记账资产，也是借贷与赎回的底层计价单位 |
| `memecoin` | verse 的项目代币 |
| `POL` | Proof of Liquidity，创世流动性证明 |
| `PT` | Principal Token，本金凭证，`1 PT = 1 uAsset` |
| `YT` | Yield Token，收益凭证 |

关键关系：

- `1 POL = 1 PT + 1 YT`
- `1 PT = 1 uAsset`
- `YT` 只代表对应 `POL` 的收益权益，不天然代表全部创世剩余资产
- `POL` 在后续结算中可能被 burn 赎回到底层 `uAsset + memecoin`

## 3. 模块边界

### 3.1 `Launcher`

`Launcher` 负责普通创世路径、普通 `YT` 领取、普通 LP 退出与全局编排。

### 3.2 `POLend`

`POLend` 负责杠杆创世路径、杠杆 `YT`、退款、杠杆残值与全局结算。

### 3.3 `Splitter`

`Splitter` 只负责 `split / merge / settle / redeemPT / redeemYT` 的纯资产转换。

`Splitter` 不负责：

- 普通创世资金分配
- 杠杆创世退款
- 杠杆残值记账
- 任何 Router 语义

阶段约束：

- `split / merge` 仅允许在 `Unlocked` 前执行
- `settle(verseId)` 仅允许由 `Launcher.changeStage` 在 `Locked -> Unlocked` 时调用
- `redeemPT / redeemYT` 仅允许在 `settle(verseId)` 完成后执行

## 4. 四池结构

每个 verse 在 `Locked` 时统一部署四个流动性池：

| 池子 | 组成 |
|---|---|
| `memecoin/uAsset` | 主池，用于铸造 `POL` |
| `POL/uAsset` | 辅助池之一 |
| `PT/uAsset` | 辅助池之一 |
| `PT/POL` | 辅助池之一 |

四池之外不再保留旧的三池语义。

## 5. 70/30 创世拆分

普通创世与杠杆创世使用同构部署路径。

任一侧创世资金都先拆分为：

- `70%` 进入主池路径
- `30%` 进入后续辅助池路径

主池路径的作用是铸造 `POL`。

随后 `POL` 再按如下比例拆分：

- `2/7` 进入 `POL/uAsset`
- `3/7` 进入 `split(POL)`，拆成 `PT + YT`
- `2/7` 进入 `PT/POL`

`split(POL)` 得到的 `PT` 再按如下比例拆分：

- `1/3 PT` 进入 `PT/uAsset`
- `2/3 PT` 进入 `PT/POL`

### 5.1 普通创世同构路径

普通创世的 70/30 资金路径如下：

1. `70%` 创世资金进入 `memecoin/uAsset` 主池
2. 主池铸造 `POL`
3. `POL` 按 `2/7, 3/7, 2/7` 分配
4. `3/7` 的 `POL` 经过 `split` 得到 `PT + YT`
5. `1/3 PT` 进入 `PT/uAsset`
6. `2/3 PT` 进入 `PT/POL`

### 5.2 杠杆创世同构路径

杠杆创世使用完全相同的 70/30 路径：

1. `borrowedAmount` 对应的创世资金进入同一套主池路径
2. 主池铸造 `POL`
3. `POL` 按 `2/7, 3/7, 2/7` 分配
4. `3/7` 的 `POL` 经过 `split` 得到 `PT + YT`
5. `1/3 PT` 进入 `PT/uAsset`
6. `2/3 PT` 进入 `PT/POL`

杠杆创世与普通创世的差异只在于资金来源、退款归属、`YT` 领取归属、残值归属和手续费归属，不在于部署路径。

### 5.3 1000 `uAsset` 示例

假设一侧创世资金为 `1000 uAsset`，且 `1 uAsset` 对应铸造 `1 memecoin`：

```text
1000 uAsset -> 700 uAsset + 300 uAsset

700 uAsset + 700 memecoin -> 700 POL

700 POL 拆分为：
200 POL -> 200 uAsset + 200 POL 组成 POL/uAsset 池
300 POL -> split 成 300 PT + 300 YT
200 POL -> 200 PT + 200 POL 组成 PT/POL 池

300 PT 再拆分为：
100 PT -> 100 uAsset + 100 PT 组成 PT/uAsset 池
200 PT -> 200 PT + 200 POL 组成 PT/POL 池
```

这个示例同时适用于普通创世与杠杆创世。

## 6. 预购容量

预购容量只以 `Genesis` 阶段的实时聚合资金为基准扩容：

```text
preorderBase = (totalMemecoinFunds + totalLeveragedDebt) * 7 / 10
preorderCap = preorderBase * preorderCapRatio / RATIO
```

其中：

- `totalMemecoinFunds` 是普通创世侧累计资金
- `totalLeveragedDebt` 是杠杆创世侧累计借款本金
- `preorderCapRatio` 是预购容量比例参数
- `RATIO` 沿用源 spec 的比例精度写法；若未特别说明，按同一精度体系解释

`Genesis` 期间每次新增杠杆债务都会抬高 `preorderBase`，因此预购容量是实时扩容的。

预购上限不是静态常量，不再只看 `totalMemecoinFunds`。

## 7. 杠杆创世

### 7.1 基本语义

杠杆创世用户先支付利息，再获得 `borrowedAmount` 对应的杠杆创世额度。

`leveragedGenesis(verseId, interestAmount)` 的记账规则如下：

```text
borrowedAmount = interestAmount * 1e18 / interestRate
```

其中：

- `interestRate` 是全局统一年化利率
- `interestRate` 使用 `1e18` 精度比例，`1e18 = 100% / year`

用户侧按聚合头寸累计：

- `interestPaid += interestAmount`
- `borrowedAmount += borrowedAmount`

全局侧按市场累计：

- `totalLeveragedDebt += borrowedAmount`
- `totalLeveragedInterest += interestAmount`

用户可多次参与杠杆创世，按同一聚合头寸持续累加。

杠杆创世成功后：

- 用户领取 `YT`
- 杠杆创世资金按普通创世同构路径参与四池部署
- `Unlocked` 后按统一结算流程优先还债，再分配残值

### 7.2 成功门槛

创世成功采用 `OR` 门槛：

- 普通创世资金达标
- 或杠杆利息达标

任一条件满足即可进入 `Locked`。

`flashGenesis=true` 时，任一条件一旦满足即可提前进入 `Locked`。

### 7.3 杠杆上限参数

`leveragedDebtFactor` 是单个 verse 的总杠杆债务上限参数，不是单用户倍数。

它约束的是整个 verse 里累计的 `totalLeveragedDebt`，进入 `Locked` 后冻结，不再变化。

形式上：

```text
totalLeveragedDebt <= leveragedDebtFactor * (totalMemecoinFunds + totalPolFunds) / 1e18
```

其中：

- `1e18 = 1x`
- 分母基准是该 verse 的普通创世资金总量

### 7.4 失败退款

如果 verse 最终进入 `Refund`：

- 普通创世用户走 `Launcher` 的退款路径
- 杠杆创世用户走 `POLend` 的退款路径
- 杠杆退款退还的是用户支付的利息

## 8. Refund 与 claim 边界

### 8.1 普通创世

普通创世的退款、`YT` 领取、普通辅助池赎回都由 `Launcher` 管理。

普通 `YT` 的正式语义如下：

- 由 `Launcher` 发放
- 仅 `Locked` 及之后可领
- 仅初始创世地址可领
- 一次性 claim
- `YT` token 可转让，但初始 claim 权不可转移

普通 `YT` 的领取公式如下：

```text
totalNormalFunds = totalMemecoinFunds + totalPolFunds
amount = totalNormalClaimableYT * userGenesisFund / totalNormalFunds
```

其中 `totalPolFunds` 是普通创世侧对应的 `POL` 资金基数。

普通侧的正式入口包括：

- `claimNormalYT(verseId)`
- `claimNormalFees(verseId)`
- `redeemAuxiliaryLiquidity(verseId)`

### 8.2 杠杆创世

杠杆创世的退款、`YT` 领取、残值领取都由 `POLend` 管理。

杠杆 refund 的正式语义如下：

- 仅在 verse 进入 `Refund` 后可领
- 一次性 claim
- 退回的是用户支付的 `interestPaid`

杠杆 `YT` 的正式语义如下：

- 只对应 `3/7 leveragedPOL` split 得到的部分
- 一次性 claim
- 公式为：

```text
userLeveragedYT = totalLeveragedYT * userBorrowedAmount / totalLeveragedDebt
```

- `Locked` 后即可领取
- `totalLeveragedYT` 只记录真正 split 出来的杠杆 `YT` 总量

### 8.3 `Splitter`

`Splitter` 只负责：

- `split`
- `merge`
- `settle`
- `redeemPT`
- `redeemYT`

`Splitter` 不持有普通 / 杠杆用户级 claim 语义。

## 9. 手续费规则

### 9.1 `POL/uAsset` 与 `PT/POL`

这两条辅助池的 `POL` 手续费永久 burn。

非 `POL` 一侧手续费按普通 / 杠杆份额分账：

- 普通部分按创世资金占比分给普通创世用户
- 杠杆部分分给对应 DAO treasury

`Unlocked` 后：

- 未赎回 LP 后续产生的新手续费全部归对应 DAO treasury
- `POL` 侧继续 burn
- 普通用户仍可补领 `Locked` 阶段已累计但未领取的普通份额 fee；只是 `Unlocked` 后新产生的 fee 归 DAO

### 9.2 `PT/uAsset`

`PT/uAsset` 的手续费规则如下：

- 普通份额手续费全归普通创世用户
- 杠杆份额手续费全归 DAO treasury
- `Unlocked` 后未赎回 LP 产生的新手续费全部归 DAO treasury

### 9.3 普通创世手续费基准

普通创世用户的手续费分配基准始终按“创世资金占比”计算，不改成按普通 `YT` 占比。

普通侧 fee 的累计与领取公式如下：

```text
totalFunds = totalNormalFunds + totalLeveragedDebt
leveragedUAssetFee = totalUAssetFee * totalLeveragedDebt / totalFunds
normalUAssetFee = totalUAssetFee - leveragedUAssetFee
leveragedPTFee = totalPTFee * totalLeveragedDebt / totalFunds
normalPTFee = totalPTFee - leveragedPTFee
entitledUAsset = accUAssetFee * userGenesisFund / totalNormalFunds
claimableUAsset = entitledUAsset - claimedUAssetFee
entitledPT = accPTFee * userGenesisFund / totalNormalFunds
claimablePT = entitledPT - claimedPTFee
```

`Unlocked` 后，普通用户仍可补领 `Locked` 阶段已经累计但未领取的 fee；只是 `Unlocked` 后不再产生新的普通侧 fee。

## 10. Unlocked 编排

`Launcher.changeStage` 在 `Locked -> Unlocked` 时必须按以下顺序执行：

1. 先把状态设为 `Stage.Unlocked`
2. 再调用 `Splitter.settle(verseId)`
3. 再调用 `POLend.executeGlobalSettlement(verseId)`

这三个动作不能交换顺序。

## 11. `Splitter.settle`

`Splitter.settle(verseId)` 的意义是：

1. 将 `POL collateral` burn 掉
2. 赎回底层 `uAsset + memecoin`
3. 写入 `settlementUAsset`
4. 写入 `settlementMemecoin`

`settlementUAsset` 与 `settlementMemecoin` 是后续 PT / YT 兑付的唯一结算池来源。

## 12. PT / YT 兑付

### 12.1 PT 兑付池

`PT` 采用严格的 `1 PT = 1 uAsset` 规则。

结算时：

```text
totalPTSupply = IERC20(pt).totalSupply()
outstandingPT = totalPTSupply
reservedUAssetForPT = outstandingPT
ytRedeemableUAssetPool = settlementUAsset - reservedUAssetForPT
```

其中：

- `split` 只影响 PT / YT token 的 `totalSupply()`
- `redeemPT` / `redeemYT` 都通过 burn token 直接减少各自 `totalSupply()`
- `outstandingPT` 直接等于当前 `PT` 的 `totalSupply()`

### 12.2 YT 兑付池

`redeemYT` 只动两部分资产：

- `ytRedeemableUAssetPool`
- `settlementMemecoin`

`redeemYT` 不得动 PT 的本金准备金。

`redeemYT` 的计算公式如下：

```text
totalYTSupply = IERC20(yt).totalSupply()
outstandingYT = totalYTSupply
uAssetAmount = ytRedeemableUAssetPool * ytAmount / outstandingYT
memecoinAmount = settlementMemecoin * ytAmount / outstandingYT
```

`redeemYT` 必须先读取本次赎回前的 `outstandingYT`、`ytRedeemableUAssetPool`、`settlementMemecoin`，再计算应得资产并 burn `YT`。

### 12.3 结算含义

`redeemPT` 先保证本金兑付。
`redeemYT` 再领取除本金准备金之外的剩余 `uAsset + memecoin`。

## 13. 全局结算

`POLend.executeGlobalSettlement(verseId)` 不直接切 `Launcher` 里的 LP，而是调用 `Launcher.settleLeveragedAuxiliaryLiquidity(verseId)`。

`Launcher.settleLeveragedAuxiliaryLiquidity(verseId)` 仅 `onlyPolend` 可调，职责如下：

- 基于 `auxiliaryLiquidities`、`totalLeveragedDebt`、`totalNormalFunds` 计算杠杆份额 LP
- 从 `POL/uAsset`、`PT/uAsset`、`PT/POL` 中移除杠杆份额 LP
- 回收 `POL / PT / uAsset`
- 将 `auxiliaryLiquidities` 扣减为普通剩余 LP
- 将回收资产转给 `POLend`

`POLend.executeGlobalSettlement(verseId)` 只处理杠杆辅助池份额。

处理范围只包括：

- `POL/uAsset`
- `PT/uAsset`
- `PT/POL`

处理步骤如下：

1. 从三条辅助池中切出杠杆份额 LP
2. 将切出的 LP 赎回为 `POL / PT / uAsset`
3. 把回收的 `POL` 继续 burn，赎回底层 `uAsset + memecoin`
4. 把回收的 `PT` 通过 `Splitter.redeemPT` 赎回成 `uAsset`
5. 先偿还当初杠杆创世所借的 `uAsset`
6. 余下的 `uAsset + memecoin` 记入 `ResidualState`

## 14. `ResidualState`

`ResidualState` 表示杠杆侧净剩余资产：

```solidity
struct ResidualState {
    uint256 residualUAsset;
    uint256 residualMemecoin;
}
```

`ResidualState` 不包含那 `3/7 leveragedPOL` 已 split 并由用户持有的 `YT` 对应权益。

### 14.1 分配基准

`ResidualState` 按 `Genesis -> Locked` 时冻结的 `borrowedAmount` 快照分配。

分配比例以用户的 `borrowedAmount / totalLeveragedDebt` 为准。

### 14.2 claim 语义

`ResidualState`：

- 一次 claim 同时领取两种资产
- 永久可领，但每个地址只能领取一次
- 尾差留在合约

### 14.3 claim 公式

```text
userResidualUAsset = residualUAsset * userBorrowedAmount / totalLeveragedDebt
userResidualMemecoin = residualMemecoin * userBorrowedAmount / totalLeveragedDebt
```

## 15. 普通辅助池赎回

普通创世用户在 `Unlocked` 后走 `Launcher.redeemAuxiliaryLiquidity(verseId)`。

该入口一次性按创世资金占比赎回三条普通份额：

- `POL/uAsset`
- `PT/uAsset`
- `PT/POL`

普通用户看见的是单次赎回入口，不需要分别处理三池。

实现语义上，普通赎回基准必须是扣除杠杆结算份额后的剩余普通 LP。

## 16. 杠杆用户入口

杠杆创世用户在 `POLend` 侧使用三个入口：

- `claimRefund(verseId)`
- `claimLeveragedYT(verseId)`
- `claimLeveragedResidual(verseId)`

其中：

- `claimRefund` 处理失败退款
- `claimLeveragedYT` 领取杠杆 `YT`
- `claimLeveragedResidual` 领取全局结算后的净残值

## 17. 非目标

以下内容不属于本文档范围：

- PT 抵押借款
- `POLendRouter`
- 旧的 `75/25` 创世拆分
- 旧的三池模型
- 将普通 `YT` 领取迁移到 `POLend`
