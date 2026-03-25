# MemeverseV2 状态机

## 1. 说明与来源边界

当前规则来源：
- 本文档与 `docs/spec/*.md` 共同构成当前规则真源。
- `src/**` 与 `test/**` 提供规则落地证据。

## 2. Launcher 生命周期状态机

主状态：
- `Genesis`
- `Refund`（终态）
- `Locked`
- `Unlocked`（终态；当前实现缺少预期的 post-unlock protection window）

### 2.1 状态迁移规则

| 当前状态 | 触发 | 条件 | 下一状态 | 关键副作用 | 规则状态 |
| --- | --- | --- | --- | --- | --- |
| `Genesis` | `changeStage` | `flashGenesis && meetMinTotalFund` | `Locked` | 部署治理组件 + 建立两条初始池 + preorder 结算 | 当前规则（代码已证） |
| `Genesis` | `changeStage` | `currentTime > endTime && meetMinTotalFund` | `Locked` | 同上 | 当前规则（代码已证） |
| `Genesis` | `changeStage` | `currentTime > endTime && !meetMinTotalFund` | `Refund` | 允许 `refund/refundPreorder` | 当前规则（代码已证） |
| `Genesis` | `changeStage` | 其他条件 | 回退 `StillInGenesisStage` | 无 | 当前规则（代码已证） |
| `Locked` | `changeStage` | `currentTime > unlockTime` | `Unlocked` | 当前实现会直接开放 LP 赎回路径；按安全要求这里应先进入保护窗口 | 当前实现（与目标规则不一致） |
| `Locked` | `changeStage` | `currentTime <= unlockTime` | 保持 `Locked` | 不回退，仍发 `ChangeStage(Locked)` 事件 | 当前规则（代码已证） |
| `Refund`/`Unlocked` | `changeStage` | 任意 | 回退 `ReachedFinalStage` | 无 | 当前规则（代码已证） |

### 2.2 `flashGenesis` 子状态语义

- `flashGenesis=false`：必须等到 `endTime` 后再判断是否进入 `Locked/Refund`。
- `flashGenesis=true`：募资达到最小门槛可提前结束 Genesis 并进入 `Locked`。
- 提前进入 `Locked` 不改变 `unlockTime` 的绝对时间，只改变 Genesis 结束时刻。

### 2.3 Launcher 阶段内可执行动作边界

| 动作 | Genesis | Refund | Locked | Unlocked | 规则状态 |
| --- | --- | --- | --- | --- | --- |
| `genesis` | 允许 | 禁止 | 禁止 | 禁止 | 当前规则（代码已证） |
| `preorder` | 允许 | 禁止 | 禁止 | 禁止 | 当前规则（代码已证） |
| `refund` / `refundPreorder` | 禁止 | 允许（每地址一次） | 禁止 | 禁止 | 当前规则（代码已证） |
| `claimPOLToken` | 禁止 | 禁止 | 允许 | 允许 | 当前规则（代码已证） |
| `mintPOLToken` | 禁止 | 禁止 | 允许 | 允许 | 当前规则（代码已证） |
| `redeemAndDistributeFees` | 禁止 | 禁止 | 允许 | 允许 | 当前规则（代码已证） |
| `redeemMemecoinLiquidity` / `redeemPolLiquidity` | 禁止 | 禁止 | 禁止 | 允许 | 当前规则（代码已证） |
| `claimUnlockedPreorderMemecoin` | 禁止 | 禁止 | 允许（按线性解锁） | 允许 | 当前规则（代码已证） |

### 2.4 `Unlocked` 后的流动性保护窗口

- 安全要求：当 verse 从 `Locked` 进入解锁阶段后，不得立即开放“公开 swap + LP 赎回”并存的状态。
- 必须存在一个 `post-unlock liquidity protection period`，用于保护 POL / genesis liquidity 的赎回公平性，并为依赖全局结算窗口的上层模块（如 POL Lend / PT-YT 语义）提供稳定结算基准。
- 在该保护窗口内：
  - 应允许：`redeemMemecoinLiquidity`、`redeemPolLiquidity`
  - 可按产品定义允许：与保护机制兼容的补池/加池行为
  - 必须禁止：普通公开 swap
  - 必须禁止：绕过公开入口的等价 swap 路径
- 当前实现状态：
  - launcher 在 `currentTime > unlockTime` 时直接进入 `Unlocked`
  - 当前 `src/swap/**` 未体现 unlock 后保护窗口
  - 因此当前实现与上述安全要求不一致

## 3. 注册与跨链状态边界

### 3.1 Symbol 注册状态（RegistrationCenter）

| 状态 | 描述 | 迁移条件 | 规则状态 |
| --- | --- | --- | --- |
| `Available` | symbol 无活跃注册，或已过 `endTime` | `registration` 提交并通过校验 | 当前规则（代码已证） |
| `Active` | symbol 处于占用窗口 | `block.timestamp > endTime` 进入可再次注册 | 当前规则（代码已证） |
| `Historical` | 历史记录归档到 `symbolHistory` | 每次新注册前若旧记录存在则归档 | 当前规则（代码已证） |

### 3.2 注册分发边界

- RegistrationCenter 负责 `uniqueId/endTime/unlockTime` 生成与 fan-out。
- 本链目标：直接调用 `MemeverseRegistrarAtLocal.localRegistration`。
- 异链目标：通过 LayerZero `lzSend` 下发消息到 `MemeverseRegistrarOmnichain`。
- Registrar 只做转发注册：`registerMemeverse` + `setExternalInfo`。
- 当前中心链时间换算单位 `DAY=180` 秒；本地 registrar 的 `quoteRegister` 仍用 `24*3600` 秒估算时间。

### 3.3 Launcher 跨链配置边界

- 注册时 launcher 对 `omnichainIds` 中的非本链 id 执行 `_lzConfigure`。
- 任一远端链在 endpoint registry 中无映射会回退注册。
- `omnichainIds[0]` 被解释为治理链。

## 4. 启动窗口状态行为

### 4.1 当前代码状态机（实际执行）

当前 `src/swap/**` 实现为：

| 状态 | 判定依据 | 行为 | 规则状态 |
| --- | --- | --- | --- |
| `LaunchFeeWindowActive` | `block.timestamp - poolLaunchTimestamp < decayDurationSeconds` | 动态费结果受 launch fee floor 约束（默认 5000 bps 向 100 bps 衰减） | 当前规则（代码已证） |
| `LaunchFeeWindowMatured` | 超过衰减窗口 | 保留动态费/最小费逻辑 | 当前规则（代码已证） |
| `LaunchSettlementPath` | `hookData` 命中 launch settlement marker 且权限通过 | 固定总费 1%，并受 `launchSettlementOperator` + `launchSettlementCaller` 双边界约束 | 当前规则（代码已证） |

### 4.2 结论

- 启动期保护在实现层体现为“launch fee 衰减窗口 + 受限 settlement 通道”。
- 上述启动期保护只覆盖 pool bootstrap / preorder settlement 风险窗口，不覆盖 unlock 后的公平赎回与全局结算风险窗口。
