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
 - `Memecoin`、`MemeLiquidProof`、`MemecoinYieldVault`
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
5. registrar 继续调 `launcher.setExternalInfo(...)`

以上为 `[代码已证]`。

### 3.2 `Genesis -> Locked` 时的部署动作

1. launcher 判断是否达标并进入 `_deployAndSetupMemeverse`
2. 若治理链是本链：
 - deployer 部署并初始化 `yieldVault/governor/incentivizer`
3. 若治理链非本链：
 - 仅预测 `yieldVault/governor/incentivizer` 地址，不在本链初始化
4. launcher 创建 `memecoin/UPT` 与 `POL/UPT` 两池，必要时做 preorder 启动结算 swap

以上为 `[代码已证]`。

## 4. 关键部署依赖事实

- Launcher 对 router 有硬校验：`launchSettlementOperator==launcher` 且 `hook.launchSettlementCaller==router`。`[代码已证]`
- RegistrationCenter/launcher/interoperation 均依赖 `LzEndpointRegistry` 的 endpointId 映射。`[代码已证]`
- 跨链分发与 staking 的 gas 参数来自 launcher/interoperation 的可配置 gas limits。`[代码已证]`
- `MemeverseProxyDeployer.quorumNumerator` 仅影响后续新部署 governor 初始化，不回溯既有实例。`[代码已证]`

## 5. 脚本层可见事实（非最终清单）

- `script/MemeverseScript.s.sol` 给出了环境变量命名、测试网链表与部署函数模板。`[代码已证]`
- 该脚本包含注释掉的分步部署/查询调用，不能视为“已执行部署记录”。`[代码已证]`

## 6. 明确未知项

- `[未知]` 各链真实部署地址与是否已升级后的实现地址。
- `[未知]` 生产环境 owner/delegate/multisig/timelock 实际控制关系。
- `[未知]` 生产环境实际 `supportedUPTs`、gasLimit、fee 配置最终值。
- `[未知]` 哪条链实际作为 registration center 主链与治理主链（需看部署参数，不在仓库固定）。
