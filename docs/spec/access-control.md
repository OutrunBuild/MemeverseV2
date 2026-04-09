# MemeverseV2 访问控制边界（Authority / Evidence）

## 1. 目标与范围

本文档定义当前产品真相层的权限边界，聚焦：

- `owner` 边界
- `registrar` 边界
- `governor` 边界
- `permissionless`（无白名单）入口
- 外部 dispatcher / endpoint 边界

来源边界：
- 当前规则真源是 `docs/spec/*.md`（含本文档）。
- 规则证据来自 `src/**` 与 `test/**`。

## 2. 角色定义（按当前产品规则语义）

- `owner`
  - 主要是 OpenZeppelin `Ownable` 或 Outrun `OutrunOwnableInit` 的 `onlyOwner`。
  - 证据：`src/verse/MemeverseLauncher.sol:1138`, `src/swap/MemeverseUniswapHook.sol:836`, `src/interoperation/MemeverseOmnichainInteroperation.sol:135`
- `registrar`
  - launcher 侧为 `memeverseRegistrar` 地址；注册中心与 local/omnichain registrar 构成上游链路。
  - 证据：`src/verse/MemeverseLauncher.sol:946`, `src/verse/registration/MemeverseRegistrarAtLocal.sol:58`
- `governor`
  - launcher 元数据更新与治理 treasury/upgrade 授权主体，同时也是 DAO treasury 与 reward payout 的唯一资产托管者。
  - 证据：`src/verse/MemeverseLauncher.sol:1313`, `src/governance/MemecoinDaoGovernorUpgradeable.sol:221`, `src/governance/MemecoinDaoGovernorUpgradeable.sol:252`
- `permissionless caller`
  - 未加 owner/role 白名单，仅靠阶段/参数约束。
  - 证据：`src/verse/MemeverseLauncher.sol:318`, `src/verse/MemeverseLauncher.sol:382`, `src/yield/MemecoinYieldVault.sol:86`
- `external dispatcher / endpoint caller`
  - 仅允许 LayerZero endpoint、launcher 或合约自身的调度入口。
  - 证据：`src/verse/YieldDispatcher.sol:46`, `src/interoperation/OmnichainMemecoinStaker.sol:39`, `src/verse/registration/MemeverseRegistrationCenter.sol:180`

## 3. 边界矩阵（源码锚点）

| Surface | 权限边界 | 证据 |
| --- | --- | --- |
| `MemeverseLauncher` 配置面 | `set*`、`pause/unpause`、`removeGasDust` 为 `onlyOwner` | `src/verse/MemeverseLauncher.sol:1127`, `:1138`, `:1155`, `:1181`, `:1194`, `:1207`, `:1220`, `:1235`, `:1256`, `:1270`, `:1290` |
| `MemeverseLauncher.registerMemeverse` | 仅 `memeverseRegistrar` | `src/verse/MemeverseLauncher.sol:936-947` |
| `MemeverseLauncher.setExternalInfo` | `governor` 或 `memeverseRegistrar` | `src/verse/MemeverseLauncher.sol:1307-1314` |
| Launcher 生命周期入口 | `genesis`/`changeStage`/`refund`/`claimPOLToken`/`redeemAndDistributeFees` 等无白名单，靠阶段与输入校验 | `src/verse/MemeverseLauncher.sol:318`, `:382`, `:619`, `:671`, `:719`, `:813`, `:841`, `:884` |
| `MemeverseRegistrationCenter` | `registration` 对外开放；参数配置和 gas dust 清理是 `onlyOwner` | `src/verse/registration/MemeverseRegistrationCenter.sol:115`, `:158`, `:308`, `:319`, `:332`, `:344` |
| `MemeverseRegistrarAtLocal` | `localRegistration` 仅 center；`setRegistrationCenter` 仅 owner | `src/verse/registration/MemeverseRegistrarAtLocal.sol:57-60`, `:80` |
| `MemeverseRegistrarOmnichain` | `setRegistrationGasLimit` 仅 owner | `src/verse/registration/MemeverseRegistrarOmnichain.sol:122` |
| `MemeverseSwapRouter` | 主路由入口纯 permissionless；不承载 launch-settlement 特权授权；launcher 配置时需校验其 `hook` 绑定 | `src/swap/MemeverseSwapRouter.sol:74-77`, `:174-240`, `:264`, `:365`, `:422`, `:446` |
| `MemeverseUniswapHook` | 核心 `addLiquidityCore/removeLiquidityCore/claimFeesCore` 对外开放；配置项 `onlyOwner`；`executeLaunchSettlement(...)` 与 pair-based `setPublicSwapResumeTime(address,address,uint40)` 仅当前 launcher；`beforeSwap` 读取 pool-level resume time 执行公开 swap 保护 | `src/swap/MemeverseUniswapHook.sol:309-377`, `:440`, `:510`, `:550`, `:577-627`, `:1038-1055` |
| `Memecoin` | `mint` 仅 launcher；`burn` 自主 | `src/token/Memecoin.sol:39-43`, `:48-51` |
| `MemePol` | `setPoolId` 与 `mint` 仅 launcher；`burn` 为持币人或 allowance 授权方 | `src/token/MemePol.sol:54`, `:62`, `:72-75` |
| `MemecoinYieldVault` | `accumulateYields` / `deposit` / `requestRedeem` / `executeRedeem` 为 permissionless 业务入口（非 owner 门禁） | `src/yield/MemecoinYieldVault.sol:86`, `:120`, `:132`, `:146` |
| `YieldDispatcher` | `lzCompose` 仅 `localEndpoint` 或 `memeverseLauncher` | `src/verse/YieldDispatcher.sol:39-47` |
| `OmnichainMemecoinStaker` | `lzCompose` 仅 `localEndpoint` | `src/interoperation/OmnichainMemecoinStaker.sol:30-40` |
| `MemeverseRegistrationCenter` dispatcher 封装 | `lzSend` 仅合约自身可调用；`_lzReceive` 校验 origin.sender 为 registrar | `src/verse/registration/MemeverseRegistrationCenter.sol:173-183`, `:296-297` |
| `MemeverseOmnichainInteroperation` | staking 入口 permissionless；`setGasLimits` 仅 owner | `src/interoperation/MemeverseOmnichainInteroperation.sol:93`, `:135` |
| `MemecoinDaoGovernorUpgradeable` | treasury 支出与升级授权仅治理执行；reward payout 资产由 governor 托管，`disburseReward(...)` 为 `Incentivizer` 专用 payout 路径 | `docs/spec/governance-yield-details.md`; `docs/spec/accounting.md` |
| `GovernanceCycleIncentivizerUpgradeable` | `recordTreasuryIncome(...)` / `recordTreasuryAssetSpend(...)` 仅 governor；`claimReward()` 为用户入口；`finalizeCurrentCycle()` 可 permissionless | `docs/spec/governance-yield-details.md`; `docs/spec/accounting.md`; `docs/spec/access-control.md` |

## 4. Governance Reward Path 边界

- `Governor.sendTreasuryAssets(...)` 属于治理执行权限路径。
- `Governor.disburseReward(...)` 不属于治理执行权限路径，而是 `Incentivizer` 驱动的受限 payout 路径。
- `Governor.disburseReward(...)` 仅允许配对的 `Incentivizer` 调用。
- `Incentivizer.recordTreasuryIncome(...)` 仅允许 `Governor` 调用。
- `Incentivizer.recordTreasuryAssetSpend(...)` 仅允许 `Governor` 调用。
- `Incentivizer.claimReward()` 属于用户业务入口，不受 `onlyGovernance` 限制。
- `Incentivizer.claimReward()` 必须以 `msg.sender` 作为 reward owner，不能把 `Governor`、治理执行者或其他中间调用者视为 reward owner。
- `Incentivizer.claimReward()` 第一版仅支持 self-claim，不支持指定 `receiver`，不支持代领。
- 若 `finalizeCurrentCycle()` 保持 permissionless，则其开放性仅限于推进周期状态，不应削弱 treasury custody 与 reward claim 的权限边界。

## 5. 与当前规则文档的对齐

- Launcher 的 owner / registrar / governor / permissionless 边界与 `docs/spec/protocol.md`、`docs/spec/state-machines.md` 一致。
- Swap 的“Router 公开入口 + Hook 核心引擎 + 显式 `Launcher -> Hook` launch settlement 路径”与 `docs/spec/protocol.md`、`docs/spec/state-machines.md` 一致。
- Router / Hook 绑定在 launcher 配置时必须做双重校验；launcher 侧 `memeverseUniswapHook` 为 write-once，不允许后续改绑到新 hook；hook owner 后续 retarget `launcher` 仍属于同一 trust boundary 内的接受配置权。
- 注册中心和 registrar 的边界与 `docs/spec/state-machines.md` 一致。

## 6. 确定性边界

- 高确定性：函数级访问控制（`onlyOwner` / `require(msg.sender==...)`）可直接由源码证实。
- 中确定性：治理链上“最终权限持有地址”依赖部署清单，不在本仓库源码内。
