# MemeverseV2 运维语义（Operator / Keeper Runbook）

## 1. 说明

本文是“当前实现语义”的操作手册，不定义链下组织流程。  
标签说明：

- `[代码已证]`：源码可直接验证
- `[未知]`：依赖生产部署或链外系统信息

## 2. 角色与职责边界

- `owner`：改配置、地址指针调整。`[代码已证]`
- `keeper/executor`：推进阶段、触发 fee 分发并领取执行奖励。`[代码已证]`
- 任意用户：参与 Genesis/Preorder、领取、赎回、staking。`[代码已证]`
- registrar/center：注册链路入口与跨链 fan-out。`[代码已证]`

## 3. 核心操作语义

### 3.1 注册（本地或异链发起）

1. 先 quote，再提交：
 - 本地路径：`MemeverseRegistrarAtLocal.quoteRegister(...)` -> `registerAtCenter(...)`
 - 异链路径：`MemeverseRegistrarOmnichain.quoteRegister(...)` -> `registerAtCenter(...)`
2. 中心链 `registration(...)` 成功后会：
 - 校验参数与 symbol 锁
 - 生成 `uniqueId/endTime/unlockTime`
 - 对目标链本地调用或 LZ 发送
3. 成功信号：
 - `Registration`
 - 目标链完成后 `RegisterMemeverse` + `SetExternalInfo`

补充说明：

- `SetExternalInfo` 采用增量覆盖语义；空字符串或空数组不会主动清空旧值。

失败要点：symbol 未解锁、uAsset 未支持（历史文档中也可能写作 UPT）、`msg.value` 不足、目标链 endpointId 未配置。`[代码已证]`

### 3.2 阶段推进（keeper 高频）

入口：`MemeverseLauncher.changeStage(verseId)`。  
语义：

- `Genesis -> Locked`：满足募资条件（`flashGenesis` 可提前）并执行部署/建池/preorder 结算
- `Genesis -> Refund`：到期未达标
- 当前实现中的 `Locked -> Unlocked`：需要 `block.timestamp > unlockTime`，并在该次 `changeStage()` 交易里把受保护公开 swap 的恢复时刻写成 `block.timestamp + 24 hours`

补充说明：

- 当前实现没有新增独立阶段，而是通过解锁迁移时写入 pool-level `publicSwapResumeTime`，把保护窗口叠加在 `Unlocked` 状态上
- 因此 keeper 推进到 `Unlocked` 后，仍需按窗口语义理解“赎回已开放，但受保护公开 swap 可能仍被阻断”
- 这是显式接受的产品规则；保护窗口现为固定 `24 hours` 产品常量

注意：`Locked` 且未到解锁时间时，调用不回退，但事件仍是 `ChangeStage(..., Locked)`。`[代码已证]`

### 3.3 费用分发（keeper）

入口：`quoteDistributionLzFee(verseId)` 与 `redeemAndDistributeFees(verseId,rewardReceiver)`。  
语义：

- 先从 `memecoin/uAsset` 主池与三个辅助池捕获 fee；目标分流规则见 [docs/spec/polend/polend.md](spec/polend/polend.md)
- 主池 `memecoin/uAsset` fee：`memecoin` fee 进入 yield 路径；`uAsset` fee 拆成 `executorReward + govFee`
- 辅助池 `POL/uAsset`、`PT/uAsset`、`PT/POL` fee：POL fee burn；普通侧 `uAsset/PT` fee 进入普通 fee 领取账本；杠杆侧 `uAsset` fee 进入 governor treasury 路径；杠杆侧 `PT` fee 在 settle 前 `preRedeemPTFee` 预兑付，settle 后 `redeemPT` 后分发；settle 前捕获但未主动分发的杠杆侧 PT fee 作为 pending，后续 settled 后再 `redeemPT` 分发
- `liquidProofFee` / `UPTFee` 是旧费用名；只能作为 legacy alias 解读，不是 POLend 四池目标术语
- 本链治理：经 `yieldDispatcher.lzCompose` 分发到 governor / yieldVault
- 异链治理：走 OFT `send`，`msg.value` 必须精确等于总报价

失败要点：未到 `Locked`、`rewardReceiver=0`、跨链费用不精确、外部依赖回退。`[代码已证]`

### 3.4 Preorder 相关

- 参与：`preorder(...)`（仅 Genesis）
- 退款：`refundPreorder(...)`（仅 Refund）
- 领取：`claimUnlockedPreorderMemecoin(...)`（至少 Locked，按线性释放）

建议：先读 `previewPreorderCapacity(...)` 与 `claimablePreorderMemecoin(...)`。`[代码已证]`

### 3.5 Memecoin staking（跨链/本链）

入口：`MemeverseOmnichainInteroperation.quoteMemecoinStaking(...)` 与 `memecoinStaking(...)`。  
语义：

- 治理链在本链：`msg.value` 必须为 0，直接存入 yieldVault
- 治理链在异链：先 quote，`msg.value` 必须精确匹配，走 OFT 到 `OmnichainMemecoinStaker`

成功信号：`OmnichainMemecoinStaking`（发起侧）与 `OmnichainMemecoinStakingProcessed`（治理链接收侧）。`[代码已证]`

### 3.6 Swap/LP 运维配置

- Hook owner 可改：`treasury`、protocol fee 币种支持、`launcher`、launch fee 衰减参数。
- 公开 swap 始终使用正常费率路径：`feeBps = max(current launch fee, dynamic fee, FEE_BASE_BPS)`；dynamic fee engine 故障通过升级/修复处理，不提供 bypass mode。`[代码已证]`
- Launcher owner 配置 router / hook 时，会同时校验 `router.hook()==hook`、`hook.launcher()==launcher`、`hook.poolInitializer()==router`，配置不一致会直接拒绝；其中 `memeverseUniswapHook` 仅允许首次设置。`[代码已证]`
- Hook owner 在配置完成后仍可 retarget `launcher`；这是接受的同一 trust boundary 内运维能力，不否定 set-time 三重校验的必要性。`[代码已证]`
- `createPoolAndAddLiquidity(...)` 的 `onlyLauncher` 是有意设计；建池要求 `Launcher -> Router` 调用链，并要求 Hook 的 `poolInitializer` 授权 Router。部署或配置变更后必须复核：`launcher.memeverseSwapRouter()==router`、`launcher.memeverseUniswapHook()==hook`、`router.hook()==hook`、`hook.launcher()==launcher`、`hook.poolInitializer()==router`；`Genesis -> Locked` 建池前也会做 launch-time preflight 复核，避免配置漂移到运行建池时才失败。`[代码已证]`
- Launcher pause 不会直接阻断 `changeStage(...)` 驱动的建池，因为 `changeStage(...)` 不是 `whenNotPaused`；但 Hook 的 `launcher` retarget 或 Router/Hook/Initializer 配置漂移会阻断后续新池创建。`[代码已证]`

### 3.7 POLend / POLSplitter 运维边界

- Launcher 构造时保存 `POLend` 与 `POLSplitter` 的 proxy 地址，当前规范不支持地址级替换，也不支持降级为零地址模式。`[代码已证]`
- 这不等于实现不可升级：`POLend` 与 `POLSplitter` 是 UUPS proxy，`_authorizeUpgrade(...)` 为 `onlyOwner`。`[代码已证]`
- `POLend.setLeveragedDebtFactor` 的技术上限为 `uint128.max * 1e18`；该值是有效上限，不代表运营最优值。普通创世与杠杆创世的累计部署资金必须保持 `totalNormalFunds + totalLeveragedDebt <= type(uint128).max`。`[代码已证]`
- 地址级替换、迁移或从零地址恢复不在当前规范内；如需支持，必须先给出显式迁移设计。`[代码已证]`
- `SettlementDustInsufficient` 出现在回退交易上时，不会留下可用事件日志，不能按失败交易已发事件监控。keeper/monitor 应在目标区块状态用 `eth_call` 或 fork simulation 预执行 `MemeverseLauncher.changeStage(verseId)` 的 `Locked -> Unlocked` 路径；如需单独模拟内部结算步骤，可预执行 `POLend.executeGlobalSettlement(verseId)`。若模拟回退 `SettlementDustInsufficient(uint256 deficit,uint256 availableReserve)`，需先用 `POLend.getLendMarket(verseId).uAsset` 确认目标 uAsset，再计算 `topUpAmount = deficit - availableReserve`，对该 uAsset 完成 approve/transfer 后调用 `fundSettlementDustReserve(uAsset, topUpAmount)`，随后重试 settlement / `changeStage`。补资前还要检查 `settlementDustStates(uAsset)` 的容量：若 `topUpAmount` 超过剩余 capacity，非 Launcher 调用 `fundSettlementDustReserve` 会回退 `SettlementDustReserveExceeded(amount, capacity)`；此时应走告警、升级或配置处理，不能盲目重试。当前合约没有暴露完整 side-effect-free preview 来提前得出 `recoveredUAsset`，因为 settlement 会通过移除 LP、POL redemption、PT redemption 路径回收 uAsset。`[代码已证]`

### 3.8 unlock 后保护窗口运维语义

- 按产品安全要求，unlock 后应先进入 `post-unlock liquidity protection period`
- 在该窗口内，运维与 keeper 应优先支持退出/结算，而不是开放普通公开 swap
- 当前实现已把这套窗口语义落在“解锁迁移时写入 pool-level `publicSwapResumeTime` + `hook.beforeSwap` 阻断”
- 因此现阶段仍不能把“`unlockTime` 到达”误解为“产品上已经安全进入完全开放交易阶段”；是否恢复公开 swap 还要看实际 `changeStage()` 时间点加上固定 `24 hours` 保护窗口

### 3.9 Hook + Engine 部署流程

部署脚本 `script/DeployMemeverseHookProxy.s.sol` 通过 OutrunDeployer（CREATE3）按序部署四份合约：

1. Engine 实现（`MemeverseDynamicFeeEngine`）
2. Engine proxy（`ERC1967Proxy`，initialize 绑定 hook owner + authorized hook）
3. Hook 实现（`MemeverseUniswapHook`）
4. Hook proxy（`ERC1967Proxy`，initialize 绑定 owner/treasury/engine）

四份合约地址由 `(deployer, DEPLOYMENT_NONCE)` 唯一确定。同一 nonce 重跑是幂等的：已部署的同配置 proxy 会被复用，中间合约若已存在则 revert。

**所需环境变量**（见 `.env.example`）：

| 变量 | 说明 |
| --- | --- |
| `PRIVATE_KEY` | 部署者私钥 |
| `OUTRUN_DEPLOYER` | 目标链 OutrunDeployer 地址 |
| `POOL_MANAGER` | 目标链 Uniswap v4 PoolManager 地址 |
| `HOOK_OWNER` | Hook proxy owner |
| `HOOK_TREASURY` | protocol fee 接收地址 |
| `DEPLOYMENT_NONCE` | 部署版本号，首次用 `0`，每次新部署递增 |
| `EXPECTED_HOOK_IMPLEMENTATION_CODEHASH` | 可选，用于同 nonce 复用时校验实现字节码 |
| `EXPECTED_ENGINE_IMPLEMENTATION_CODEHASH` | 可选，同上 |

**`DEPLOYMENT_NONCE` 语义**：

- 嵌入所有 CREATE3 salt，决定四份合约的最终地址
- 同 nonce + 同配置 → 幂等复用
- 同 nonce + 不同配置 → revert（中间合约不可复用）
- 不同 nonce → 全新地址集

**原子性保证**：

`run()` 和 `deployHookProxy()` 在单笔交易中执行全部四步 CREATE3 部署。任一步失败则整笔交易回滚，不会留下中间部署的僵尸合约，CREATE3 salt 也不会被消耗。

**⚠️ 禁止拆分部署步骤到多笔交易**。Engine proxy 在部署时立即以预测的 hook proxy 地址初始化（owner 和 authorizedHook 均为 hook proxy 地址）。这是因为 hook 的 `initialize()` 会验证 `engine.authorizedHook() == address(this)`，所以 engine 必须先于 hook 初始化。Hook proxy 地址在部署前已通过 CREATE3 salt 挖矿确定。

若将 engine proxy 部署和 hook proxy 部署拆成两笔交易，且第二笔失败，engine proxy 将永久绑定到一个不存在的 owner，无法恢复。

**失败恢复**：

在单笔交易的原子部署中，失败不会消耗 salt。若通过非标准方式（如手动拆分步骤）导致中间部署残留，该 nonce 下的 CREATE3 salt 已消耗，恢复方式为递增 `DEPLOYMENT_NONCE` 重新执行。残留的中间合约地址不会被新 nonce 覆盖，不影响新部署。

脚本为每个失败路径提供明确的错误类型（`Create3SaltConsumed`、`ExistingIntermediateDeploymentNotReusable`、`EngineImplementationCreate3SaltConsumed` 等），而非 solmate 默认的 `DEPLOYMENT_FAILED`。

## 4. 治理周期相关操作语义

- `finalizeCurrentCycle()` 是对外开放入口，时间到即可执行，不要求 `onlyGovernance`。`[代码已证]`
- `claimReward()`、`accumCycleVotes()`、token 注册/注销、reward ratio 修改等由 governor 路径调用（`onlyGovernance`）。`[代码已证]`

## 5. 观察与告警建议（最小集）

- 阶段机：`ChangeStage` + `RegisterMemeverse`
- 资金分发：`RedeemAndDistributeFees`、`OFTProcessed`
- 跨链 staking：`OmnichainMemecoinStaking`、`OmnichainMemecoinStakingProcessed`
- 配置变更：Launcher/Hook/RegistrationCenter 的 `Set*` 事件
- unlock 后保护：当前缺少专用事件，需结合 stage、时间与 swap/赎回行为联合判断

## 6. 确定性边界

- `[未知]`：生产环境 keeper 调度频率、告警阈值、重试策略、密钥托管方案，不在仓库代码内。
