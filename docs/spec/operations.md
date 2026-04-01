# MemeverseV2 运维语义（Operator / Keeper Runbook）

## 1. 说明

本文是“当前实现语义”的操作手册，不定义链下组织流程。  
标签说明：

- `[代码已证]`：源码可直接验证
- `[未知]`：依赖生产部署或链外系统信息

## 2. 角色与职责边界

- `owner`：改配置、应急开关、地址指针调整。`[代码已证]`
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

失败要点：symbol 未解锁、UPT 未支持、`msg.value` 不足、目标链 endpointId 未配置。`[代码已证]`

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

- 先从两池 claim fee
- `liquidProofFee` 直接 burn
- `UPTFee` 拆成 `executorReward + govFee`
- 本链治理：经 `yieldDispatcher.lzCompose` 分发到 governor / yieldVault
- 异链治理：走 OFT `send` 两笔，`msg.value` 必须精确等于总报价

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

- Hook owner 可改：`treasury`、protocol fee 币种支持、`emergencyFlag`、`launcher`、launch fee 衰减参数。
- Launcher owner 配置 router / hook 时，会同时校验 `router.hook()==hook` 且 `hook.launcher()==launcher`，配置不一致会直接拒绝；其中 `memeverseUniswapHook` 仅允许首次设置。`[代码已证]`
- Hook owner 在配置完成后仍可 retarget `launcher`；这是接受的同一 trust boundary 内运维能力，不否定 set-time 双重校验的必要性。`[代码已证]`

### 3.7 unlock 后保护窗口运维语义

- 按产品安全要求，unlock 后应先进入 `post-unlock liquidity protection period`
- 在该窗口内，运维与 keeper 应优先支持退出/结算，而不是开放普通公开 swap
- 当前实现已把这套窗口语义落在“解锁迁移时写入 pool-level `publicSwapResumeTime` + `hook.beforeSwap` 阻断”
- 因此现阶段仍不能把“`unlockTime` 到达”误解为“产品上已经安全进入完全开放交易阶段”；是否恢复公开 swap 还要看实际 `changeStage()` 时间点加上固定 `24 hours` 保护窗口

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
