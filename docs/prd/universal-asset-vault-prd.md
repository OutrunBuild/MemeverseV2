# Universal Asset Vault PRD

> 当前按“新功能 PRD”口径撰写，面向协议研发、产品、审阅者与后续测试执行。本文档描述的是已确认的目标产品语义、v1 范围、风险控制要求和技术边界，不等同于最终合约实现细节。

## 1. Executive Summary

### Problem Statement

Memeverse 需要一套链上稳定资产基础设施，为生态提供统一的收益资产层和统一报价锚点。当前仓库已有 `MemecoinYieldVault`，但它面向 verse 级 memecoin 收益归集，不满足“用户存入主流资产、铸造统一协议资产、以该资产贯穿生态报价与收益分发”的产品目标。

### Proposed Solution

新增一套全新的单资产通用金库系统。用户可存入 `USDC`、`WETH`、`WBNB` 等底层资产，分别 1:1 铸造 `UniversalAssetToken`，例如 `UUSD`、`UETH`、`UBNB`。底层资产由 `ReserveVault` 与 `StrategyManager` 按策略进行部署和回收；`UniversalAssetToken` 本身保持 1:1 赎回语义，不承载收益。v1 阶段策略收益默认归协议 treasury，并预留未来切换到 `stUUSD` / `stUETH` / `stUBNB` 质押分润的扩展点。

### Success Criteria

- v1 必须支持至少三种单资产 vault：`USDC -> UUSD`、`WETH -> UETH`、`WBNB -> UBNB`。
- 在 `Active` 状态且 `totalManagedBaseAsset >= totalSupply` 时，用户对对应 `UniversalAssetToken` 的 1:1 redeem 必须始终成立。
- 任一会改变资金状态的操作在发现覆盖率跌破 100% 时，必须在同一笔交易内进入 `Deficit`，并阻止新的 `mint`、`redeem`、`allocate`。
- v1 必须支持 mock strategy / 手工收益注入，在测试网完成 `deposit -> allocate -> harvest -> deallocate -> redeem` 的完整闭环验证。
- v1 必须保证非底层奖励代币不计入 backing，且可直接归集到 treasury，由人工决定何时卖出。
- v1 必须能作为 Memeverse 生态的统一报价稳定币基础设施，其中 `UUSD` 作为稳定报价锚点的实现底座。

## 2. User Experience & Functionality

### User Personas

- 普通用户：希望存入 `USDC`、`ETH`、`BNB` 等主流资产，获得统一的链上协议资产，并在需要时 1:1 赎回。
- 生态协议集成方：希望在 Memeverse 生态内部直接使用 `UUSD` 作为报价、结算或展示锚点，而不需要关心底层策略部署细节。
- 协议 Treasury / 风控执行者：希望把底层资产部署到收益策略中，同时严格控制 backing、暂停、补仓和紧急退出路径。
- 后续质押参与者：当前不直接参与 v1 收益分配，但未来希望把 `UUSD` 质押为 `stUUSD` 并分享策略收益。
- Keeper / 测试执行者：在 v1 阶段通过 mock strategy 或手工收益注入验证资金闭环、状态机和风险处置路径。

### User Stories

#### Story A: 使用主流资产铸造统一协议资产

As a 普通用户，我希望存入 `USDC`、`ETH` 或 `BNB`，并分别得到 `UUSD`、`UETH`、`UBNB`，以便使用统一的 Memeverse 协议资产参与生态。

Acceptance Criteria

- `USDC` 存款必须 1:1 mint `UUSD`。
- `ETH` 存款必须通过包装路径进入 `WETH` backing，并 1:1 mint `UETH`。
- `BNB` 存款必须通过包装路径进入 `WBNB` backing，并 1:1 mint `UBNB`。
- mint 入口只能在 `Active` 状态下成功执行。
- 只有 `UniversalAssetGateway` 可以触发 `UniversalAssetToken` 的 mint / burn。

#### Story B: 以稳定负债语义赎回底层资产

As a 持有人，我希望 burn 我的 `UUSD` / `UETH` / `UBNB`，并在系统 solvent 时 1:1 拿回对应底层资产，以便该资产真正具备稳定可赎回语义。

Acceptance Criteria

- `burn UUSD -> redeem USDC` 必须为 1:1。
- `burn UETH -> redeem WETH` 必须为 1:1；如提供原生币出口，则 unwrap 只能发生在 gateway 层。
- `burn UBNB -> redeem WBNB` 必须为 1:1；原生币出口同样只能发生在 gateway 层。
- 若 idle liquidity 不足，gateway 必须先请求 `StrategyManager` 回撤流动性。
- 若系统处于 `Deficit`、`Paused` 或 `EmergencyExit` 且不满足开放赎回条件，redeem 必须失败。

#### Story C: 通过策略模块为协议产生收益

As a 协议 Treasury / 执行者，我希望把 vault 中的可部署资产交给策略模块管理，并在未来扩展更多协议接入，同时不破坏 `UniversalAssetToken` 的稳定语义。

Acceptance Criteria

- 每个 strategy 必须显式注册、可启停，并配置 `debt cap`。
- v1 默认总可部署资金不超过总资产的 `80%`，至少保留 `20% idle buffer`。
- `allocate` 不能超过 strategy 的 `debt cap`。
- `deallocate` 必须能把资产回流到底层 `ReserveVault`。
- v1 上线范围只要求 mock strategy / 手工收益注入，不要求接入真实策略协议。

#### Story D: 将收益归集到协议 treasury

As a 协议 Treasury，我希望策略收益默认归我所有，而不直接体现在 `UUSD` 汇率上，以便 `UUSD` 保持稳定币语义，且未来可平滑切换到 `stUUSD` 分润。

Acceptance Criteria

- 若策略收益直接以底层资产形式出现，必须先形成 vault surplus，再由授权路径提取到 treasury。
- 若策略收益是非底层奖励代币，必须直接发往 treasury。
- v1 不要求自动卖出奖励代币，treasury 可以直接持有原始奖励代币。
- 非底层奖励代币在未兑换成底层资产前，不得计入 backing。

#### Story E: 在风险状态下暂停、补仓并恢复

As a 风控执行者，我希望在发生覆盖率不足或策略异常时暂停系统、回撤资金、补仓并恢复，以便保护稳定币兑付承诺。

Acceptance Criteria

- 覆盖率跌破 100% 时必须在同一笔交易内切换到 `Deficit`。
- `Deficit` 状态下必须禁止新的 `mint`、`redeem`、`allocate` 和 `extractSurplus`。
- `Guardian` 必须可以随时触发 `pause`。
- 协议必须可通过 `recapitalize` 注入底层资产补足缺口。
- 补足完成后只能在覆盖率恢复后重新开启赎回。

### Non-Goals

- v1 不做多稳定币共用一个 `UUSD` 的混合资产池。
- v1 不做 `UniversalAssetToken` 升值、rebase 或 share-price 模型。
- v1 不做完整 Veda `Accountant` 风格的离线净值发布模块。
- v1 不做完整 Merkle action tree strategy manager。
- v1 不接入真实策略协议，不承诺生产级收益率。
- v1 不实现 `stUUSD` / `stUETH` / `stUBNB` 质押分润，只预留收益出口抽象。

## 3. AI System Requirements (If Applicable)

不适用。本功能是纯链上资产、金库、策略与风控系统，不依赖 AI 模型、推理服务、AI 代理决策或 AI 输出评估。

## 4. Technical Specifications

### Architecture Overview

系统采用“稳定负债层 + 储备金库层 + 策略执行层 + 收益出口层”的分层设计，参考市场验证过的模块化金库思想，但不直接把 share exchange rate 语义引入 `UniversalAssetToken`。

建议核心模块如下：

- `UniversalAssetToken`
  - 每个单资产系统一个实例。
  - token 总供应量表示系统负债。
  - 只负责 `mint`、`burn`、转账和必要的暂停能力。
- `ReserveVault`
  - 保管底层资产。
  - 维护 `idle assets`、`strategy debt`、`total managed assets`、`surplus`、`solvency`。
  - 暴露状态机与补仓、提取 surplus 的受控入口。
- `UniversalAssetGateway`
  - 用户唯一入口。
  - 负责 `deposit`、`redeem`、`depositNative`、`redeemNative`。
  - 负责 `ETH -> WETH` 和 `BNB -> WBNB` 的包装与解包。
- `StrategyManager`
  - 负责 strategy 注册、启停、额度、分配、回撤、收割、紧急退出。
  - v1 使用 allowlist + role-based 权限控制，不引入复杂的通用调用树。
- `IUniversalAssetStrategy`
  - 标准策略 adapter 接口。
  - 最少需要支持 `deposit`、`withdraw`、`withdrawAll`、`totalAssets`、`harvest`、`panic`。
- `IYieldSink` / `ProtocolTreasurySink`
  - 抽象收益出口。
  - v1 的实现为协议 treasury。
  - 未来可替换为 `StakingRewardsSink`。

系统内部对每个单资产 vault 维持以下基础关系：

- `totalLiabilities = UniversalAssetToken.totalSupply()`
- `totalManagedBaseAsset = idleBaseAsset + sum(strategyReportedBaseAsset)`
- `surplus = max(totalManagedBaseAsset - totalLiabilities, 0)`

状态机建议为：

- `Active`
- `Paused`
- `Deficit`
- `EmergencyExit`

并要求任一覆盖率不足都不能继续停留在 `Active`。

### Integration Points

建议新增或扩展的链上集成点如下：

- token / vault 模块
  - `src/vault/UniversalAssetToken.sol`
  - `src/vault/ReserveVault.sol`
  - `src/vault/UniversalAssetGateway.sol`
  - `src/vault/StrategyManager.sol`
  - `src/vault/ProtocolTreasurySink.sol`
- strategy 接口
  - `src/vault/interfaces/IUniversalAssetStrategy.sol`
  - `src/vault/interfaces/IYieldSink.sol`
- 测试
  - `test/vault/*.t.sol`
  - `test/vault/mocks/*.sol`

v1 的外部依赖与交互规则：

- 底层 `USDC` 直接作为 `UUSD` backing。
- `ETH` / `BNB` 必须先包装为 `WETH` / `WBNB` 再进入 backing。
- mock strategy 可以通过手工设置 `totalAssets` 或注入收益来模拟收益与亏损。
- treasury 必须能接收底层资产 surplus 与非底层奖励代币。
- `UUSD` 在 Memeverse 生态内部作为统一报价稳定币时，不应依赖策略层额外 oracle 报价。

### Security & Privacy

v1 的安全与风控边界必须至少满足以下要求：

- `1:1 redeem` 只在 `Active` 且 fully backed 时开放。
- 任一会改变资金状态的操作在发现覆盖率跌破 100% 时，必须在同一笔交易内进入 `Deficit`。
- `Guardian` 必须可以随时 `pause`，暂停后只允许 `deallocate`、`harvest`、`recapitalize`、`emergencyExit` 等收缩风险的操作。
- 非底层奖励代币一律不得计入 backing。
- 每个策略必须有 `debt cap`。
- v1 默认总可部署资金不超过总资产的 `80%`，至少保留 `20% idle buffer` 处理日常赎回。
- 协议必须提供 `recapitalize` 路径，补足覆盖率前不得恢复赎回。
- 必须提供可链上读取的 `state`、`totalManagedAssets`、`totalLiabilities`、`surplus`、`isSolvent`。

建议审计与测试重点：

- 只有 `UniversalAssetGateway` 可 mint / burn `UniversalAssetToken`
- surplus 提取不会侵蚀 backing
- 奖励代币无法被错误计入 solvency
- strategy 上报资产的信任边界与操纵风险
- 原生币包装路径的供应量守恒
- `Deficit -> recapitalize -> recover` 的完整闭环

隐私方面，本系统不处理链下隐私数据，所有核心状态与事件均为链上公开信息。

## 5. Risks & Roadmap

### Phased Rollout

#### MVP

- 完成 `USDC -> UUSD`、`WETH -> UETH`、`WBNB -> UBNB` 三个单资产 vault 的统一架构。
- 完成 `UniversalAssetToken`、`ReserveVault`、`UniversalAssetGateway`、`StrategyManager`、`ProtocolTreasurySink` 与 mock strategy。
- 在测试网验证 `deposit -> allocate -> harvest -> deallocate -> redeem` 闭环。
- 在测试网验证 `Deficit -> pause -> recapitalize -> recover` 风险处置闭环。

#### v1.1

- 引入 1 个真实策略适配器，例如稳定币借贷或 LST 类基础策略。
- 增加更完整的 keeper / monitoring 流程。
- 增加更细粒度的参数治理与风险告警。

#### v2.0

- 引入 `stUUSD` / `stUETH` / `stUBNB` 质押分润模块。
- 将收益出口从 `ProtocolTreasurySink` 切换为可治理配置的多实现接口。
- 视业务需求扩展到多策略同 vault、风险分层与更复杂的策略路由。

### Technical Risks

- 稳定负债与可部署策略天然存在流动性冲突；如果 buffer 配置过低，短时大额赎回会放大回撤风险。
- strategy `totalAssets()` 或 mock 行为如果实现不当，会破坏 solvency 判断与测试可信度。
- 非底层奖励代币若被错误计入 backing，会直接破坏 `UUSD` 作为稳定报价资产的可信度。
- `Deficit` 检测如果不能在状态变化交易中即时触发，可能出现错误放行 mint / redeem 的窗口。
- 原生币包装路径若处理不当，容易产生卡资金、重入或 accounting mismatch。
- v1 不接真实策略虽能降低上线复杂度，但也意味着收益逻辑的生产环境风险仍需在后续阶段重新验证。
