# Memeverse Launcher PRD

> 当前按“严格对齐现有代码逻辑的内部 PRD”口径撰写，主要面向协议内部研发、产品和审阅者。本文档描述的是当前实现已经表达出的产品语义，不把未来想法或已修复历史问题写成现状。

## 1. Executive Summary

### Problem Statement

Memeverse 需要一个统一的启动中枢，把 memecoin 注册、Genesis 募资、初始流动性创建、POL 分配、流动性解锁、费用分发和跨链治理收益接收串成一条明确的生命周期主链路。没有这个中枢，协议各模块虽然可以分别工作，但社区创建、资金归集、治理接入和退出路径会缺少统一状态语义。

### Proposed Solution

`MemeverseLauncher` 作为当前实现中的生命周期总控合约，接收 `MemeverseRegistrar*` 的注册结果，保存每个 verse 的基础信息，并联动 `MemeverseProxyDeployer`、`MemeverseSwapRouter`、`MemeverseOFTDispatcher` 和 `ILzEndpointRegistry`，管理从 `Genesis` 到 `Refund / Locked / Unlocked` 的状态转换与相关资金流。

### Success Criteria

- 新注册的 verse 必须在一次 `registerMemeverse(...)` 后写入基础元数据，并完成 `memecoin` 与 `liquidProof` 地址落库，且 `memecoinToIds[memecoin] == uniqueId`。
- Genesis 期间每笔 `genesis(...)` 存入的 UPT 必须按 75% 进入 memecoin 侧资金、25% 进入 POL 侧资金，并累计到对应用户的 `genesisFund`。
- `changeStage(...)` 必须符合当前代码的阶段机语义：
  `flashGenesis && meetMinTotalFund` 时可提前进入 `Locked`；
  非 `flashGenesis` 时必须在 `currentTime > endTime && meetMinTotalFund` 后进入 `Locked`；
  `currentTime > endTime && !meetMinTotalFund` 时进入 `Refund`。
- `Locked` 后用户必须可以领取一次 POL、继续通过补充 `UPT/memecoin` 流动性铸造 POL，并允许任意执行者触发 Genesis 期间 LP fee 的赎回与分发。
- `Unlocked` 后必须允许两类退出：POL 持有人按 1:1 数量赎回 memecoin LP，Genesis 参与者按 Genesis 资金占比赎回 POL 池 LP。

## 2. User Experience & Functionality

### User Personas

- 社区发起方：通过注册中心和 registrar 创建新的 Memeverse，希望系统自动生成 memecoin、POL 以及后续治理/流动性接入点。
- Genesis 参与者：在 `Genesis` 期间使用 UPT 参与启动募资，希望在成功启动后领取 POL，或在启动失败后退款。
- POL 持有人/后续流动性提供者：在 `Locked` 后继续向 `UPT/memecoin` 池补充流动性，并获得新铸造的 POL。
- 执行者/Keeper：调用 `changeStage(...)` 与 `redeemAndDistributeFees(...)` 推动 verse 生命周期和费用分发，并从 UPT fee 中获得执行奖励。
- 治理收益接收方：接收发射器分配来的 UPT treasury 收入和 memecoin 收益，分别对应 Governor 和 Yield Vault。
- 协议 Owner：维护 launcher 的外部依赖地址、fund metadata、执行奖励比例和跨链 gas 参数，并在必要时暂停关键入口。

### User Stories

#### Story A: 注册一个新的 Memeverse

As a 社区发起方，我希望通过注册中心和 registrar 创建新的 Memeverse，以便 launcher 为后续募资、流动性和治理流程建立统一状态入口。

Acceptance Criteria

- `MemeverseRegistrationCenter.registration(...)` 必须校验 `durationDays`、`lockupDays`、`name`、`symbol`、`uri`、`desc`、`omnichainIds` 和 `UPT` 支持性。
- `MemeverseLauncher.registerMemeverse(...)` 只能由 `memeverseRegistrar` 调用。
- 注册时必须部署 memecoin 与 POL 代理，并调用各自的 `initialize(...)`。
- 注册时必须写入 `name`、`symbol`、`UPT`、`endTime`、`unlockTime`、`omnichainIds`、`flashGenesis`、`memecoin`、`liquidProof`；当前实现不会在此阶段落库 `uri`、`desc` 或 `communities`。
- `setExternalInfo(...)` 不在 `registerMemeverse(...)` 中完成，而是由 registrar 在后续单独调用；注册完成后 governor 也可以更新这部分展示信息。
- `setExternalInfo(...)` 当前是“增量覆盖”语义：空 `uri` / 空 `description` / 空 `communities` 不会清空旧值；`communities` 只覆盖本次传入的索引，不主动删除更长旧数组的尾部数据。
- 非本链的 `omnichainIds` 必须在 `_lzConfigure(...)` 中完成 peer 配置，否则注册应回滚。

#### Story B: 在 Genesis 期间参与募资

As a Genesis 参与者，我希望存入 UPT 参与启动募资，以便在 verse 成功启动后获得 POL 或在失败时退款。

Acceptance Criteria

- `genesis(...)` 只能在 `Stage.Genesis` 且未暂停时执行。
- 调用者必须先授权 launcher 拉取 UPT。
- 每笔 UPT 存款必须按 `3:1` 比例拆分为 `totalMemecoinFunds` 与 `totalLiquidProofFunds`。
- `userGenesisData[verseId][user].genesisFund` 必须累计用户总出资，而不是只记录最近一笔。
- 事件 `Genesis` 必须记录 verseId、用户地址和两侧新增资金。
- 当 verse 进入 `Refund` 后，`refund(...)` 只能由存在 `genesisFund` 且尚未退款的地址成功调用一次，并按用户累计 `genesisFund` 原额退回 UPT。

#### Story C: 推动 Genesis 结束并进入下一阶段

As a Keeper，我希望在条件满足时推进阶段，以便 verse 可以启动流动性、进入退款，或在锁仓结束后解锁退出。

Acceptance Criteria

- `changeStage(...)` 必须拒绝已经处于 `Refund` 或 `Unlocked` 的最终阶段。
- 当 `flashGenesis == true` 且 `meetMinTotalFund == true` 时，verse 可以在 `endTime` 到达前进入 `Locked`。
- 当 `flashGenesis == false` 时，verse 只有在 `currentTime > endTime && meetMinTotalFund` 时才会进入 `Locked`。
- 当 `currentTime > endTime && !meetMinTotalFund` 时，verse 必须进入 `Refund`。
- 当条件不足以结束 `Genesis` 时，`changeStage(...)` 必须以 `StillInGenesisStage(endTime)` 回退。
- 当 `Stage.Locked` 且 `currentTime > unlockTime` 时，verse 必须进入 `Unlocked`。
- 当 verse 已处于 `Stage.Locked` 但尚未到 `unlockTime` 时，`changeStage(...)` 当前不会回退，也不会切换阶段，而是继续以 `Locked` 发出 `ChangeStage` 事件。

#### Story D: 领取 POL 与继续铸造 POL

As a Genesis 参与者或后续流动性提供者，我希望在 verse 进入 `Locked` 后领取或铸造 POL，以便把启动期或后续流动性头寸映射为可持有的权益凭证。

Acceptance Criteria

- `claimablePOLToken(...)` 只能为当前调用者预览可领取数量，不支持查询任意账户。
- `claimablePOLToken(...)` 只能在至少 `Locked` 时执行；若用户已领取过，则必须返回 `0`。
- `claimPOLToken(...)` 只能在至少 `Locked` 时执行；若 `claimablePOLToken(...) == 0`，则以 `NoPOLAvailable` 回退。
- `mintPOLToken(...)` 只能在至少 `Locked` 时执行，并要求 `amountInUPTDesired` 与 `amountInMemecoinDesired` 都非零。
- 当 `amountOutDesired == 0` 时，launcher 必须以预算方式调用 router 加池，并根据执行前后余额差计算实际消耗与退款。
- 当 `amountOutDesired != 0` 时，launcher 必须先询价所需输入，任一输入超预算则回退。
- 成功 mint 后，launcher 必须向用户铸造等量 POL。

#### Story E: 赎回费用并把收益送往治理侧

As a 执行者，我希望在 Genesis 期间积累到 LP fee 后触发赎回和分发，以便 UPT treasury 收入、memecoin 收益和执行奖励都能到达当前实现定义的接收方。

Acceptance Criteria

- `previewGenesisMakerFees(...)` 与 `redeemAndDistributeFees(...)` 只能在至少 `Locked` 时执行。
- 预览与实际 claim 必须使用同一套 pair fee 映射逻辑，避免 fee0/fee1 与业务 token 语义漂移。
- `liquidProofFee` 必须先在 launcher 内被 burn，不参与后续跨链或本链收益接收。
- `UPTFee` 必须拆成 `executorReward` 和 `govFee`，其中 `executorReward = UPTFee * executorRewardRate / 10000`。
- 当治理链就是当前链时，launcher 必须把 `govFee` 和 `memecoinFee` 先转给 `oftDispatcher`，再通过 `lzCompose(...)` 分别送往 Governor 和 Yield Vault。
- 当治理链不在当前链时，launcher 必须分别为 `govFee` 与 `memecoinFee` 构建发送参数并汇总原生手续费报价；调用者提供的 `msg.value` 少于总报价时必须回退。

#### Story F: 在流动性解锁后退出

As a POL 持有人或 Genesis 参与者，我希望在 `Unlocked` 后按当前实现定义的两条退出路径赎回 LP，以便结束启动期头寸。

Acceptance Criteria

- `redeemMemecoinLiquidity(...)` 只能在 `Unlocked` 时执行，且输入 POL 不得为零。
- `redeemMemecoinLiquidity(...)` 必须 burn 用户输入的 POL，并按 1:1 数量向用户转出 `memecoin/UPT` LP。
- `redeemPolLiquidity(...)` 只能在 `Unlocked` 时执行，且每个地址对每个 verse 只能成功赎回一次。
- `redeemPolLiquidity(...)` 必须按 `totalPolLiquidity * userFunds / totalFunds` 计算用户可赎回的 `POL/UPT` LP。
- 当 launcher 持有的 LP 不足时，两条退出路径都必须回退。

### Non-Goals

- 本 PRD 不定义前端页面、钱包流程、交互文案或运营侧提示逻辑。
- 本 PRD 不重写 `MemeverseSwapRouter` / hook 的交易规则，只把它们视为 launcher 的流动性和 fee 基础设施。
- 本 PRD 不覆盖上币审核、社区运营、市场投放或链下人工审批流程。
- 本 PRD 不定义非 EVM 链的适配方案。
- 本 PRD 不把部署脚本、CI 流程和生成文档流程当作产品能力本体。

## 3. AI System Requirements (If Applicable)

不适用。`MemeverseLauncher` 是纯链上生命周期与资金流编排模块，不依赖 AI 模型、推理服务或 AI 输出评估。

## 4. Technical Specifications

### Architecture Overview

`MemeverseLauncher` 位于 Memeverse 启动链路中央，承担“状态机 + 资金分发 + 外部依赖编排”的角色。上游的注册中心和 registrar 负责产生注册参数并把 verse 落到 launcher；下游的 deployer、router、dispatcher 和 LayerZero 相关组件负责具体部署、流动性和跨链收益传递。

当前实现中的主要模块职责如下：

- `MemeverseRegistrationCenter`：注册入口、参数校验、symbol 占用管理、多链消息派发。
- `MemeverseRegistrarAtLocal` / `MemeverseRegistrarOmnichain`：把注册结果发给 launcher。
- `MemeverseProxyDeployer`：部署 memecoin、POL、Yield Vault、Governor 和 Incentivizer，或在非治理链路径上返回可预测地址。
- `MemeverseSwapRouter`：创建 `memecoin/UPT` 与 `POL/UPT` 池、补充流动性、查询 LP token、预览/领取 Genesis 期间 LP fee。
- `MemeverseOFTDispatcher`：在本链或跨链收益到达后，把 UPT 和 memecoin 转交给 Governor 或 Yield Vault。
- `ILzEndpointRegistry`：完成 `chainId -> endpointId` 的映射。

当前阶段状态机如下：

- `Genesis`：允许接收 UPT 募资；不允许领取 POL、分发 fee 或赎回 LP。
- `Refund`：Genesis 结束但未达到最小募资额后的退款状态；允许调用 `refund(...)`。
- `Locked`：初始池和治理组件相关地址已经确定；允许领取 POL、继续铸造 POL、预览和分发 fee，但不允许赎回 LP。
- `Unlocked`：锁仓期结束；允许赎回 memecoin LP 和 POL LP。

当前实现中的关键金额关系如下：

- Genesis 资金拆分：`memecoinFund = amountInUPT * 3 / 4`，`polFund = amountInUPT / 4`。
- 初始 memecoin 铸造量：`memecoinAmount = totalMemecoinFunds * fundBasedAmount`。
- memecoin 首池初始价格：`InitialPriceCalculator.calculateMemecoinStartPriceX96(memecoin, UPT, fundBasedAmount)`。
- POL 首次投放量：`deployedPOL = memecoinLiquidity / 3`。
- 可领取 POL 总量：`totalClaimablePOL = memecoinLiquidity - deployedPOL`。
- 用户可领取 POL：`totalClaimablePOL * userFunds / totalFunds`，但已领取用户直接视为 `0`。
- 用户可赎回 POL LP：`totalPolLiquidity * userFunds / totalFunds`。
- 执行者奖励：`executorReward = UPTFee * executorRewardRate / 10000`。

### Integration Points

外部合约接口

- `registerMemeverse(...)`：由 `memeverseRegistrar` 调用，部署并记录新的 verse。
- `setExternalInfo(...)`：由 `memeverseRegistrar` 或该 verse 的 `governor` 调用，按增量覆盖方式更新 URI、描述和社区链接。
- `createPoolAndAddLiquidity(...)`、`addLiquidity(...)`、`previewClaimableFees(...)`、`claimFees(...)`、`lpToken(...)`：由 launcher 调用 router 完成池子、LP 和 fee 相关流程。
- `quoteSend(...)` 与 `send(...)`：由 launcher 通过 OFT / LayerZero 路径完成异链费用报价和发送。
- `lzCompose(...)`：由 launcher 或本地 endpoint 驱动 `MemeverseOFTDispatcher` 把收益送达实际接收方。

权限与 Auth 模型

- `owner`：可以设置 router、registrar、proxyDeployer、OFTDispatcher、LZ registry、fund metadata、执行奖励比例、gas limit，并可以 `pause()` / `unpause()` 以及 `removeGasDust(...)`。
- `memeverseRegistrar`：是注册新 verse 的唯一入口，也可以在注册后写入外部展示信息。
- `governor`：可以在 verse 已有 governor 地址时调用 `setExternalInfo(...)`。
- 任意用户：可以参与 `genesis(...)`、`changeStage(...)`、`claimPOLToken(...)`、`mintPOLToken(...)`、`refund(...)`、`redeemAndDistributeFees(...)`、`redeemMemecoinLiquidity(...)` 和 `redeemPolLiquidity(...)`；其中 `claimablePOLToken(...)` 只支持调用者查看自己的可领额度。

链下/数据依赖

- 无数据库依赖，核心状态全部保存在链上映射中。
- 前端或脚本通常需要在异链分发前先调用 `quoteDistributionLzFee(...)`，否则容易因 `msg.value` 不足导致回退。
- 当前实现没有内建 keeper 或调度器，阶段推进和费用分发完全依赖外部账户主动触发。
- launcher 在 `registerMemeverse(...)` 内不自行校验 `endTime`、`unlockTime` 是否非零，也不校验 `uniqueId` 是否为空槽，默认信任上游 registrar/registration center 已提供正确参数。

### Security & Privacy

安全边界

- 关键 setter 由 `onlyOwner` 保护，且多数配置要求非零输入。
- `removeGasDust(...)` 当前也受 `onlyOwner` 保护，定位为 owner 的原生币残余清理入口。
- `setFundMetaData(...)` 限制 `fundBasedAmount <= 2^64 - 1`，与当前价格计算器的可支持范围保持一致。
- `setExecutorRewardRate(...)` 要求小于 `10000`，避免执行者奖励超过全部 UPT fee。
- 大多数状态变更入口带 `whenNotPaused`，可用于应急暂停。

外部调用面

- `changeStage(...)` 在进入 `Locked` 时会触发外部部署与建池，依赖 `memeverseProxyDeployer`、`memeverseSwapRouter` 和 token 合约行为正确。
- `redeemAndDistributeFees(...)` 依赖 router fee claim、OFT 报价与跨链发送，存在外部合约回退或报价过期带来的执行失败风险。
- `mintPOLToken(...)` 依赖 router 对 add-liquidity 与 quote 的返回语义，如果 router 实现和 launcher 预期不一致，会直接影响 POL 铸造和退款正确性。

当前实现仍需注意的产品/工程风险

- 生命周期推进完全 permissionless，但协议没有内建 keeper，因此 verse 是否及时从 `Genesis` 进入 `Refund / Locked`、以及 fee 是否及时分发，依赖外部运营或脚本调度。
- `flashGenesis` 的语义是“达到最小募资额即可提前锁定”，这会让 verse 实际结束时间早于 `endTime`；前端和运营必须显式披露这点，否则用户可能误解倒计时含义。
- 异链治理收益分发要求调用者实时补足 LayerZero 原生手续费，若前端不先报价或报价过期，会导致执行失败。
- 当前实现假设上游注册流程会提供合理的 `endTime`、`unlockTime` 和 `omnichainIds`；launcher 自身不重新定义这些业务参数。
- `setExternalInfo(...)` 采用非清空式增量更新，若运营侧想删除旧的社区字段，当前实现没有直接“清空全部旧索引”的原子接口，链下展示层需要明确兼容这一语义。

隐私

- 模块不处理链下隐私数据，全部信息都是链上公开状态或跨链消息载荷。
- `uri`、`desc`、`communities` 是公开元数据，更新后默认可被索引器与前端读取。

## 5. Risks & Roadmap

### Phased Rollout

#### MVP

当前实现已经提供以下闭环：

- 多链注册入口与 verse 元数据落库。
- Genesis 募资、提前锁定或到期锁定、到期退款三种结束路径。
- `Locked` 后的初始池创建、治理接收方地址确定、POL 领取、POL 增发和 Genesis fee 分发。
- `Unlocked` 后的 memecoin LP 与 POL LP 退出。

#### v1.1

在不改变主状态机的前提下，优先完善工程体验：

- 为 keeper 和前端补充更明确的阶段推进与 fee 分发操作指引。
- 对关键只读接口和配置项补更强的集成测试与边界测试。
- 增加围绕 `flashGenesis`、异链 fee 报价和治理链差异路径的文档说明。

#### v2.0

在当前实现稳定后，再考虑更强的可运营性：

- 增加标准化状态索引、告警和运维监控视图。
- 对异链收益分发引入更清晰的失败重试与补偿策略。
- 视业务需要扩展更细粒度的配置校验与生命周期自动化能力。

### Technical Risks

- launcher 对 router、proxyDeployer、OFT、LayerZero registry 的外部依赖较重，任一依赖行为偏离预期都会放大到启动主链路。
- `changeStage(...)` 的 `Locked` 分支包含真实部署和建池调用，执行成本高且失败面广，调试与运营都需要足够可观察性。
- `flashGenesis` 会让 verse 在募资达标后提前结束，若产品层没有清晰暴露“提前锁定”语义，会造成用户理解偏差。
- 异链 fee 分发对 `msg.value` 报价高度敏感，跨链成本波动会直接影响执行成功率。
