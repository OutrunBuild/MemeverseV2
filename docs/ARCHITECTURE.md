# MemeverseV2 架构总览

## 1. 模块地图

### 1.1 启动与生命周期核心

- `src/verse/MemeverseLauncher.sol`
- 负责 verse 生命周期状态机与资金主编排（Genesis/Refund/Locked/Unlocked）。

### 1.2 注册与跨链注册

- `src/verse/registration/MemeverseRegistrationCenter.sol`
- `src/verse/registration/MemeverseRegistrarAtLocal.sol`
- `src/verse/registration/MemeverseRegistrarOmnichain.sol`
- 负责参数校验、symbol 占用、local/remote fan-out，以及对 launcher 的落库调用。

### 1.3 交易与流动性

- `src/swap/MemeverseSwapRouter.sol`（公开入口）
- `src/swap/MemeverseUniswapHook.sol`（核心费率与 LP 记账引擎）
- 负责 swap、加减流动性、LP fee claim、启动期费用语义与 launch settlement 通道。

### 1.4 资产层

- `src/token/Memecoin.sol`
- `src/token/MemeLiquidProof.sol`
- 负责 memecoin 与 POL 的铸造/销毁权限边界。

### 1.5 收益与治理

- `src/yield/MemecoinYieldVault.sol`
- `src/governance/MemecoinDaoGovernorUpgradeable.sol`
- `src/governance/GovernanceCycleIncentivizerUpgradeable.sol`
- 负责收益份额、国库接收、投票周期奖励。

### 1.6 跨链互操作

- `src/verse/YieldDispatcher.sol`
- `src/interoperation/MemeverseOmnichainInteroperation.sol`
- `src/interoperation/OmnichainMemecoinStaker.sol`
- 负责治理收益跨链投递与 memecoin 跨链 staking。

## 2. 关键资金流

### 2.1 启动成功路径

1. 用户向 launcher 存入 UPT（Genesis + 可选 Preorder）。
2. 进入 Locked 时，launcher：
 - 用 Genesis 资金创建 `memecoin/UPT` 与 `POL/UPT` 两池。
 - 结算 preorder（若有）并记录可线性解锁的 memecoin。
3. 后续用户领取 POL、继续加池 mint POL、触发 fee 分发。

### 2.2 启动失败路径

1. 到期未达最小募资 -> `Refund`。
2. Genesis 与 preorder 参与者分别按记录金额退款。

### 2.3 Fee 分发路径

1. launcher claim 两池 fee。
2. `liquidProofFee` 直接 burn。
3. `UPTFee` 拆分为 `executorReward + govFee`。
4. `govFee` 送 Governor treasury，`memecoinFee` 送 YieldVault（本链或异链）。

### 2.4 Unlocked 退出路径

1. `unlockTime` 之后，verse 在实际 `changeStage()` 调用中进入 `Unlocked`，并为受保护池写入公开 swap 恢复时间。
2. 在保护窗口内，POL 持有人 burn POL 换 memecoin LP。
3. Genesis 参与者按占比赎回 POL LP（每地址一次）。
4. 保护窗口结束后，才恢复无限制公开 swap。

## 3. 文档分层（Doc Layering）

当前文档系统按四层组织：

1. Harness / Process 层（流程契约与质量门禁）
 - `AGENTS.md`
 - `docs/process/*`
 - `script/process/*`
2. Product Truth 层（当前规则真源）
 - `docs/spec/*.md`
 - `docs/spec/lifecycle-details.md`
 - `docs/spec/registration-details.md`
 - `docs/spec/governance-yield-details.md`
 - `docs/spec/interoperation-details.md`
 - `docs/spec/common-foundations.md`
 - `docs/ARCHITECTURE.md`
 - `docs/GLOSSARY.md`
 - `docs/TRACEABILITY.md`
 - `docs/VERIFICATION.md`
 - 升级性规则以 `docs/spec/upgradeability.md` 为主，`docs/spec/implementation-map.md` 仅记录各 surface 的升级性实现事实
3. Implementation Evidence 层（规则落地证据）
 - `src/**`
 - `test/**`
4. Topic Guides 层（专题补充）
 - `docs/memeverse-swap/*`

冲突处理顺序：
- 当前规则判断以 Product Truth 层为准，并用 Implementation Evidence 层核验。
- Topic Guides 层用于补充特定模块说明，不单独定义当前规则。

## 4. 推荐阅读顺序

1. `AGENTS.md`（仓库流程与真源约定）
2. `docs/ARCHITECTURE.md`（本文件，先建立层次与边界）
3. `docs/spec/*`（产品真相核心规则；建议先读 `protocol`、`state-machines`、`accounting`、`access-control`、`upgradeability`）
4. `docs/GLOSSARY.md`（术语与定义基线）
5. `docs/TRACEABILITY.md` + `docs/VERIFICATION.md`（规则到证据追溯与验证路径）
6. `docs/process/subagent-workflow.md` + `docs/process/*`（Harness/Process 执行细则）

## 5. 当前已知边界提醒

- swap 当前规则主路径为 launch fee 衰减 + 显式 `Launcher -> Hook` launch settlement 路径。
- unlock 后的保护窗口是独立安全要求，不由 launch fee / launch settlement 替代。
- 受保护公开 swap 的有效恢复时刻锚定实际 `Locked -> Unlocked` 迁移调用时间，再加上 `unlockProtectionWindow`。
- 注册中心当前把 `durationDays/lockupDays` 按 180 秒“测试日”换算；与自然日含义存在偏差。
- 评审与实现对齐时，先看 Product Truth 层与 `src/**` / `test/**`。
