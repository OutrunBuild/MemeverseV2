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

- `src/swap/MemeverseSwapRouter.sol`
- `src/swap/MemeverseUniswapHook.sol`
- 负责 swap、加减流动性、LP fee claim、启动期费用语义与 launch settlement 通道。

### 1.4 资产层

- `src/token/Memecoin.sol`
- `src/token/MemePol.sol`
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

## 2. 文档分层

1. Harness Contract 层
   - `AGENTS.md`
   - `CLAUDE.md`
   - `.harness/policy.json`
   - `script/harness/gate.sh`
   - `README.md`
   - `.github/workflows/test.yml`
   - `.githooks/*`
   - `.claude/settings.json`
2. Product Truth 层（当前规则真源）
   - `docs/spec/protocol.md`
   - `docs/spec/state-machines.md`
   - `docs/spec/accounting.md`
   - `docs/spec/access-control.md`
   - `docs/spec/upgradeability.md`
   - `docs/spec/lifecycle-details.md`
   - `docs/spec/registration-details.md`
   - `docs/spec/governance-yield-details.md`
   - `docs/spec/interoperation-details.md`
   - `docs/spec/common-foundations.md`
   - `docs/spec/implementation-map.md`
   - `docs/ARCHITECTURE.md`
   - `docs/GLOSSARY.md`
   - `docs/TRACEABILITY.md`
   - `docs/VERIFICATION.md`
   - `docs/SECURITY_AND_APPROVALS.md`
3. Implementation Evidence 层（规则落地证据）
   - `src/**`
   - `test/**`
4. Topic Guides 层（设计稿与专题补充，不是当前规则真源）
   - `docs/memeverse-swap/*`
   - `docs/superpowers/specs/*`
   - `docs/superpowers/plans/*`

冲突处理顺序：

- 当前规则判断以 Product Truth 层为准，并用 Implementation Evidence 层核验。
- Topic Guides 层用于补充模块说明，不单独定义当前规则。
- 若 `docs/spec/*.md` 与 `src/**` 冲突，以 `src/**` 为准。

## 3. 推荐阅读顺序

1. `CLAUDE.md`
2. `docs/ARCHITECTURE.md`
3. `docs/GLOSSARY.md`
4. `docs/spec/protocol.md`
5. `docs/spec/state-machines.md`
6. `docs/spec/accounting.md`
7. `docs/spec/access-control.md`
8. `docs/spec/upgradeability.md`
9. `docs/TRACEABILITY.md` + `docs/VERIFICATION.md`

## 4. 当前已知边界提醒

- swap 当前规则主路径为 launch fee 衰减加显式 `Launcher -> Hook` launch settlement。
- unlock 后的保护窗口是独立安全要求，不由 launch fee 或 launch settlement 替代。
- 受保护公开 swap 的恢复时刻锚定实际 `Locked -> Unlocked` 迁移调用时间，再加上 `unlockProtectionWindow`。
- 注册中心当前把 `durationDays/lockupDays` 按 180 秒测试日换算；分析时不要按自然日推断。
