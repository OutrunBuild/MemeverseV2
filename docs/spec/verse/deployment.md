# MemeverseV2 部署拓扑与初始化事实

## 1. 说明

本文只记录“代码可证”的部署与初始化关系。  
标签说明：

- `[代码已证]`：源码与脚本可直接定位
- `[未知]`：仓库没有最终部署实参/清单

## 2. 顶层部署拓扑（按合约角色）

### 2.1 基础常驻组件

- `LzEndpointRegistry`：`chainId -> endpointId` 映射注册表。`[代码已证]`
- `MemeverseRegistrationCenter`：中心链注册入口与 fan-out。`[代码已证]`
- `MemeverseRegistrarAtLocal` 或 `MemeverseRegistrarOmnichain`：注册执行层。`[代码已证]`
- `MemeverseLauncher`：verse 生命周期与资金总编排。`[代码已证]`
- `MemeverseProxyDeployer`：per-verse clone/proxy 部署器。`[代码已证]`
- `YieldDispatcher`：收益 OFT compose 分发器。`[代码已证]`
- `MemeverseOmnichainInteroperation` + `OmnichainMemecoinStaker`：跨链 staking 路径。`[代码已证]`
- `MemeverseUniswapHook` + `MemeverseSwapRouter`：swap/liquidity 核心与外围。`[代码已证]`

### 2.2 实现合约与按 verse 实例化组件

- 实现合约（模板）：
 - `Memecoin`、`MemePol`、`MemecoinYieldVault`
 - `MemecoinDaoGovernorUpgradeable`、`GovernanceCycleIncentivizerUpgradeable`
- 按 `verseId(uniqueId)` 实例化：
 - memecoin/POL/yieldVault：最小代理（cloneDeterministic）
 - governor/incentivizer：`ERC1967Proxy + Create2`

以上为 `[代码已证]`。

## 3. 初始化与依赖顺序（代码路径）

### 3.1 注册阶段

1. registrar 调 `launcher.registerMemeverse(...)`
2. launcher 通过 deployer 部署 memecoin/POL clone
3. launcher 立即调用两者 `initialize(...)`
4. launcher 依据 `omnichainIds` 对 memecoin/POL 调 `setPeer(...)`
5. launcher 写入 verse 基础信息与反向索引
6. launcher 同交易调用 `POLend.registerLendMarket(verseId)`
7. registrar 后续调 `launcher.setExternalInfo(...)`

以上为 `[代码已证]`。

### 3.2 `Genesis -> Locked` 时的部署动作

1. launcher 判断是否达标并进入 `_deployAndSetupMemeverse`
2. 若 `getTotalLeveragedDebt(verseId) > 0`，launcher 调用 `POLend.finalizeLeveragedGenesis(verseId)`
3. launcher 调用 `POLSplitter.initializeVerse`
4. launcher 在主池建池后把主池实际 `uAsset` / POL raw 写入 `POLSplitter.recordPTBackingRatio(...)`
5. launcher 调用 `POLSplitter.split(...)` 产出 PT/YT，并把杠杆侧初始 YT 转给 `POLend`
6. launcher 按 POLend 四池模型创建 `memecoin/uAsset` 主池与 `POL/uAsset`、`PT/uAsset`、`PT/POL` 三个辅助池，必要时通过 `hook.executeLaunchSettlement(...)` 完成 preorder 启动结算
7. 若治理链是本链：
 - deployer 部署并初始化 `yieldVault/governor/incentivizer`
8. 若治理链非本链：
 - 仅预测 `yieldVault/governor/incentivizer` 地址，不在本链初始化

以上动作发生在同一笔 `changeStage` 交易内；任一步失败都会回滚整笔 `Genesis -> Locked` 迁移。

以上为 `[代码已证]`。

## 4. 关键部署依赖事实

- Launcher 在配置 router / hook 时有 set-time 三重校验：`router.hook() == hook`、`hook.launcher() == launcher`、`hook.poolInitializer() == router`；其中 `memeverseUniswapHook` 仅允许首次设置，后续不可改绑到新 hook。`Genesis -> Locked` 执行建池前会做 launch-time preflight 复核，避免配置漂移到运行建池时才失败。`[代码已证]`
- `polend` 与 `polSplitter` 都是 launcher 构造注入的必需接线，不存在 unset 或运行中换地址路径。注册、创世部署、fee preview/claim、unlock settlement 都直接依赖这两个固定地址。`[代码已证]`
- 具体接线语义：
  - `polend`：注册时 `registerLendMarket`，部署时 `finalizeLeveragedGenesis`，Locked governor PT fee 预兑付时 `preRedeemPTFee`，unlock settlement 时按需 `executeGlobalSettlement`
  - `polSplitter`：部署时 `initializeVerse`、`recordPTBackingRatio`、`split`，normal/gov PT fee preview 时 `previewPTToUAsset`，settled 后 PT 兑现时 `redeemPT`，unlock settlement 时 `settle`
- Hook owner 在部署后仍可 retarget `launcher`；该能力属于与 launcher owner 同一 trust boundary 的配置权，当前产品语义接受这一点。`[代码已证]`
- RegistrationCenter/launcher/interoperation 均依赖 `LzEndpointRegistry` 的 endpointId 映射。`[代码已证]`
- 跨链分发与 staking 的 gas 参数来自 launcher/interoperation 的可配置 gas limits。`[代码已证]`
- `MemeverseProxyDeployer.quorumNumerator` 仅影响后续新部署 governor 初始化，不回溯既有实例。`[代码已证]`

## 5. Launcher 原生 gas dust 边界

- `MemeverseLauncher.removeGasDust(address receiver)` 是 owner-only 运维清理入口，用于转出 Launcher 合约上的 native balance。`[代码已证]`
- 该余额不是用户可 claim 资金，且与 `RegistrationCenter` gas dust 是不同边界。`[代码已证]`
- 目标边界：`redeemAndDistributeFees` 要求 `msg.value` 精确等于 required fee；本地分发、无跨链要求或无 fee 分发时 required fee 为 `0`。精确 native payment 下，费用分发不应产生预期 Launcher dust。
- 无 fee 分发时，`redeemAndDistributeFees` 在返回零值前必须拒绝非零 `msg.value`，避免误带 native value 留作 Launcher dust。`[代码已证]`
- 当前代码按实现行为描述，不额外声明 zero-address receiver 校验。`[代码已证]`

## 6. 脚本层可见事实（非最终清单）

- `script/MemeverseScript.s.sol` 给出了环境变量命名、测试网链表与部署函数模板。`[代码已证]`
- 该脚本包含注释掉的分步部署/查询调用，不能视为“已执行部署记录”。`[代码已证]`

## 7. 明确未知项

- `[未知]` 各链真实部署地址与是否已升级后的实现地址。
- `[未知]` 生产环境 owner/delegate/multisig/timelock 实际控制关系。
- `[未知]` 生产环境实际 `supportedUAssets`、gasLimit、fee 配置最终值。
- `[未知]` 哪条链实际作为 registration center 主链与治理主链（需看部署参数，不在仓库固定）。
