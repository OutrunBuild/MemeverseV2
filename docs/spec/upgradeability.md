# MemeverseV2 升级性与初始化约束（Source-Backed）

## 1. 结论摘要

当前仓库存在四类 surface：

1. 构造函数部署、不可升级（无 proxy）
2. 最小代理（EIP-1167 clone）+ 自定义 `initializer`
3. `ERC1967Proxy` + `UUPSUpgradeable`
4. `TransparentUpgradeableProxy` + `ProxyAdmin`

补充约束：

- 本文档是升级性规则主文档（canonical source）。
- [docs/implementation-map.md](../implementation-map.md) 仅在各 surface 行内记录升级机制事实与定位锚点，不替代本文规则条目。

## 2. 升级面分类

| Surface | 机制 | 初始化入口 | 升级授权 | 证据 |
| --- | --- | --- | --- | --- |
| **构造函数部署（不可升级）** | | | | |
| Router | constructor 部署 | constructor | 不适用 | `src/swap/MemeverseSwapRouter.sol::constructor` |
| RegistrationCenter | constructor 部署 | constructor | 不适用 | `src/verse/registration/MemeverseRegistrationCenter.sol::constructor` |
| RegistrarAtLocal | constructor 部署 | constructor | 不适用 | `src/verse/registration/MemeverseRegistrarAtLocal.sol::constructor` |
| RegistrarOmnichain | constructor 部署 | constructor | 不适用 | `src/verse/registration/MemeverseRegistrarOmnichain.sol::constructor` |
| YieldDispatcher | constructor 部署 | constructor | 不适用 | `src/verse/YieldDispatcher.sol::constructor` |
| OmnichainInteroperation | constructor 部署 | constructor | 不适用 | `src/interoperation/MemeverseOmnichainInteroperation.sol::constructor` |
| OmnichainMemecoinStaker | constructor 部署 | constructor | 不适用 | `src/interoperation/OmnichainMemecoinStaker.sol::constructor` |
| LzEndpointRegistry | constructor 部署 | constructor | 不适用 | `src/common/omnichain/LzEndpointRegistry.sol::constructor` |
| ProxyDeployer | constructor 部署 | constructor | 不适用 | `src/verse/deployment/MemeverseProxyDeployer.sol::constructor` |
| `lpTokenImplementation` | constructor 部署；`DeploymentResult.lpTokenImplementation` 返回 | constructor | 不适用 | `script/DeployMemeverseHookProxy.s.sol`（部署脚本） |
| `preorderSettlementExecutor` | constructor 部署；constructor 接收 hook proxy 地址并 immutable 绑定（`HOOK`）；`DeploymentResult.preorderSettlementExecutor` 返回 | constructor | 不适用 | `src/swap/MemeversePreorderSettlementExecutor.sol::constructor`、`::HOOK`；`script/DeployMemeverseHookProxy.s.sol::_deployPreorderSettlementExecutor`（在 creationCode 末尾拼接 `abi.encode(hookProxy)`，`hookProxy` 为 CREATE3 预测的 hook proxy `selectedProxy`） |
| **最小代理 clone（不可升级）** | | | | |
| `Memecoin` / `MemePol` / `MemecoinYieldVault` | EIP-1167 clone | 外部 `initialize`（单次） | 无实现内升级入口 | `src/verse/deployment/MemeverseProxyDeployer.sol::deployMemecoin`、`::deployPOL`、`::deployYieldVault`; `src/token/Memecoin.sol::initialize`; `src/token/MemePol.sol::initialize`; `src/yield/MemecoinYieldVault.sol::initialize` |
| **UUPS 可升级** | | | | |
| `MemeverseLauncher` | `ERC1967Proxy` + UUPS | `initialize(initialOwner, localLzEndpoint_, memeverseRegistrar_, memeverseProxyDeployer_, yieldDispatcher_, lzEndpointRegistry_, polend_, polSplitter_, executorRewardRate_, oftReceiveGasLimit_, yieldDispatcherGasLimit_, preorderCapRatio_, preorderVestingDuration_)` | `_authorizeUpgrade(...) => onlyOwner` | `src/verse/MemeverseLauncher.sol`（`_authorizeUpgrade`）; `script/MemeverseScript.s.sol`（部署脚本） |
| `MemecoinDaoGovernorUpgradeable` | `ERC1967Proxy` + UUPS | `initialize(...)` | `_authorizeUpgrade(...) => onlyGovernance` | `src/governance/MemecoinDaoGovernorUpgradeable.sol`（`_authorizeUpgrade`）; `src/verse/deployment/MemeverseProxyDeployer.sol`（proxy 部署） |
| `GovernanceCycleIncentivizerUpgradeable` | `ERC1967Proxy` + UUPS | `initialize(...)` | `_authorizeUpgrade(...) => onlyGovernance` | `src/governance/GovernanceCycleIncentivizerUpgradeable.sol`（`_authorizeUpgrade`）; `src/verse/deployment/MemeverseProxyDeployer.sol`（proxy 部署） |
| `POLend` | `ERC1967Proxy` + UUPS | `initialize(initialOwner, interestRate_, leveragedDebtFactor_, treasury_, launcher_, splitter_)` | `_authorizeUpgrade(...) => onlyOwner` | `src/polend/POLend.sol`（`_authorizeUpgrade`） |
| `POLSplitter` | `ERC1967Proxy` + UUPS | `initialize(initialOwner, _launcher)` | `_authorizeUpgrade(...) => onlyOwner` | `src/polend/POLSplitter.sol`（`_authorizeUpgrade`） |
| `MemeverseDynamicFeeEngine` | `ERC1967Proxy` + UUPS | `initialize(initialOwner, authorizedHook_)` | `_authorizeUpgrade(...) => onlyOwner + poolManager mismatch guardrail` | `src/swap/MemeverseDynamicFeeEngine.sol::initialize`、`::_authorizeUpgrade` |
| **透明代理可升级** | | | | |
| `MemeverseUniswapHook` | `TransparentUpgradeableProxy` + `ProxyAdmin` | `initialize(initialOwner, treasury_, dynamicFeeEngine_, lpTokenImplementation_, preorderSettlementExecutor_)` | Hook proxy admin 的 `ProxyAdmin.owner()`；已部署 Hook 使用同一 `hookOwner` 作为 Hook `owner()` 与 `ProxyAdmin.owner()` | `script/DeployMemeverseHookProxy.s.sol`（Hook proxy 部署与 existing proxy 校验）；`src/swap/MemeverseUniswapHook.sol::initialize`；getter 区 `::dynamicFeeEngine`、`::lpTokenImplementation`、`::preorderSettlementExecutor` |

## 3. 初始化约束（当前代码实际支持）

### 3.1 最小代理初始化一次性

- `src/common/access/Initializable.sol` 在实现合约 constructor 中把 `initialized=true`，阻止实现本体被初始化。
  - 证据：`src/common/access/Initializable.sol::constructor`
- clone 实例通过 `initializer` 进入一次初始化，重复调用回退 `AlreadyInitialized`。
  - 证据：`src/common/access/Initializable.sol::initializer`（modifier）与 `::AlreadyInitialized`（error）

### 3.2 由 launcher 驱动 token 初始化

- launcher 在注册时通过 deployer 克隆 `memecoin`/`POL` 并立即 `initialize`。
  - 证据：`src/verse/MemeverseLauncher.sol::_deployAndInitializeVerseTokens`

**owner 与 delegate 的初始化值：**

- `initialize` 调用时，`owner` 和 `delegate` 均被设为 `msg.sender`——即执行调用的 launcher 实例（`address(this)`）。
  - 含义：刚部署的 memecoin / POL token 的 admin 权限（owner）与治理代理权（delegate）都归属于 launcher。
  - 证据：`src/verse/MemeverseLauncher.sol::_deployAndInitializeVerseTokens`; `src/token/Memecoin.sol::initialize`; `src/token/MemePol.sol::initialize`
- 此行为仅反映源码层的初始化语义；线上部署后 owner 是否被迁移（例如转给多签 / timelock）不在仓库证据范围内。
  - 同源：section 6 "中确定性" 条目

### 3.3 governance 组件仅在治理链本地部署初始化

- 当 `govChainId == block.chainid`：部署并初始化 `yieldVault/governor/incentivizer`。
  - 证据：`src/verse/MemeverseLauncher.sol::_deployGovernanceComponents`（local 分支：`govChainId == block.chainid`）
- 否则只做地址预测，不在当前链初始化。
  - 证据：`src/verse/MemeverseLauncher.sol::_deployGovernanceComponents`（remote 分支：`govChainId != block.chainid`）

### 3.4 Launcher UUPS 初始化事实

- 当前 `MemeverseLauncher` 是 `ERC1967Proxy + UUPS` surface。实现合约 constructor 只调用 `_disableInitializers()`，阻止 implementation 本体被初始化。
  - 证据：`src/verse/MemeverseLauncher.sol::constructor`
- Launcher proxy 通过 `initialize(...)` 写入原 constructor-equivalent 配置：`initialOwner`、local endpoint、registrar、proxy deployer、yield dispatcher、endpoint registry、`POLend`、`POLSplitter`、gas、reward 与 preorder 初始配置。
  - 证据：`src/verse/MemeverseLauncher.sol::initialize`
- Launcher 升级通过 UUPS `upgradeToAndCall(...)` 进入实现合约，并由 `_authorizeUpgrade(...) => onlyOwner` 放行。
  - 证据：`src/verse/MemeverseLauncher.sol::_authorizeUpgrade`
- 协议真实 Launcher 地址是 `IOutrunDeployer` CREATE3 部署的 ERC1967 proxy 地址，不是 implementation 地址。脚本对 implementation salt 与 proxy salt 分开建模，`MemeverseLauncher` salt 对应 canonical proxy 地址。
  - 证据：`script/MemeverseScript.s.sol::_deployMemeverseProxyDeployer`、`::_deployMemeverseLauncher`
- `deployCaller` 是执行 CREATE3 / proxy 部署的调用者，`initialOwner` 是 Launcher proxy 初始化后的 owner；两者显式拆分。默认脚本支持两种模式：`deployCaller == initialOwner` 时脚本在部署中直接写入 `setFundMetaData`；`deployCaller != initialOwner` 时跳过 fund metadata，由 `initialOwner` 单独调用 `setFundMetaData`。测试 harness 通过覆盖 `_beginMemeverseLauncherOwnerExecution` 实现 `vm.startPrank` 以在单交易内测试双角色路径。`[代码已证]`
  - 证据：`script/MemeverseScript.s.sol::_deployMemeverseLauncher`、`::_setMemeverseLauncherFundMetaData`; `test/verse/deployment/MemeverseProxyDeployer.t.sol::_beginMemeverseLauncherOwnerExecution`
- `POLend` / `POLSplitter` 通过 Launcher `initialize(...)` 参数（`polend_`、`polSplitter_`）写入，且必须是各自 canonical proxy address。
- readiness 检查覆盖 Launcher proxy 可读配置、launcher-bound 依赖 back-reference、`fundMetaDatas[uAsset]`、以及 `POLend.settlementDustStates(uAsset).maxReserve`，不能只检查 implementation 或 proxy code 存在。
  - 证据：`script/MemeverseScript.s.sol::_checkMemeverseLauncherDeployment`、`::_requireDeploymentReady`、`::_requireFundMetaDataReady`、`::_readSettlementDustState`
- `proxiableUUID()` 在 implementation 上可读；通过 proxy 调用 `proxiableUUID()` 必须按 UUPS guard 回退，不能作为 proxy readiness 成功检查。

## 4. Proxy / Deployer 假设（仅限代码可证）

- 当前 `MemeverseLauncher` 是 UUPS surface，不使用独立 `ProxyAdmin`。
- `MemeverseProxyDeployer` 只允许 launcher 调用 deploy 系列函数。
  - 证据：`src/verse/deployment/MemeverseProxyDeployer.sol::onlyMemeverseLauncher`（modifier）；deploy 系列 `::deployMemecoin`、`::deployPOL`、`::deployYieldVault`、`::deployGovernorAndIncentivizer`
- governor 与 incentivizer 使用 `Create2 + ERC1967Proxy`，部署后立即执行 `initialize(...)`。
  - 证据：`src/verse/deployment/MemeverseProxyDeployer.sol::deployGovernorAndIncentivizer`
- 当前治理组件采用 UUPS，不存在透明代理模式下的独立 `ProxyAdmin`；`upgradeToAndCall(...)` 进入实现合约后，由 `_authorizeUpgrade(...)` 决定是否放行。
  - governor：`_authorizeUpgrade(...) => onlyGovernance`
  - incentivizer：`_authorizeUpgrade(...) => onlyGovernance`（实际校验 `msg.sender == governor`）
  - 证据：`src/governance/MemecoinDaoGovernorUpgradeable.sol::_authorizeUpgrade`; `src/governance/GovernanceCycleIncentivizerUpgradeable.sol::_authorizeUpgrade`、`::onlyGovernance`（modifier）
- `POLend` 与 `POLSplitter` 不由 `MemeverseProxyDeployer` 部署；它们通过外部脚本/工厂独立部署，并以 Launcher `initialize(...)` 参数 `polend_`、`polSplitter_` 接线。其 proxy 部署与升级授权独立于 ProxyDeployer。`[代码已证]`
- Launcher 保存的是 `POLend` / `POLSplitter` 的 proxy 地址，当前规范不提供 setter、地址级替换、迁移或降级零地址模式；这只约束 proxy 地址本身，不否定 proxy 实现升级。`POLend` 与 `POLSplitter` 均为 UUPS，`_authorizeUpgrade(...)` 由 `onlyOwner` 放行。`[代码已证]`
- `MemeverseUniswapHook` 使用 `TransparentUpgradeableProxy + ProxyAdmin`。Hook implementation 不暴露 UUPS `_authorizeUpgrade` / `upgradeToAndCall` 升级入口；升级授权由 Hook proxy admin slot 指向的 `ProxyAdmin.owner()` 控制。`script/DeployMemeverseHookProxy.s.sol` 创建 Hook proxy 时使用 `TransparentUpgradeableProxy(implementation, hookOwner, initializeData)`；同一 `hookOwner` 也是 Hook initializer 的 `initialOwner`，因此已部署 Hook 的 `owner()` 与 `ProxyAdmin.owner()` 必须一致。same-nonce / existing Hook proxy 复用路径校验 `EXPECTED_HOOK_PROXY_CODEHASH`、admin slot、`ProxyAdmin.owner()`，并要求 `ProxyAdmin.owner() == MemeverseUniswapHook(proxy).owner()`；运维侧 ownership transfer 必须保持两者对齐，否则复用校验拒绝 split-control 状态。`poolManager` 一致性不再是 Hook on-chain upgrade guardrail；operator/off-chain upgrade checklist/runbook 必须约束新 Hook implementation 使用相同 PoolManager 构造参数。`poolManager` 不在 proxy storage 中，升级替换字节码后若真实值不同，hook 回调将指向错误目标，导致所有 swap 和流动性操作永久失效。`[代码已证]`
- `MemeverseDynamicFeeEngine.initialize(initialOwner, authorizedHook_)` 初始化 owner 与 authorizedHook；`authorizedHook_` 在首次部署后不可变更，限定唯一 Hook proxy 可写入 engine fee state。`_authorizeUpgrade(...)` 由 `onlyOwner` 放行，并额外校验新实现的 `poolManager()` getter 返回值与当前 immutable `poolManager` 一致（防诚实升级误部署的 guardrail，非安全边界）。`[代码已证]`
- `MemeverseUniswapHook.initialize(initialOwner, treasury_, dynamicFeeEngine_, lpTokenImplementation_, preorderSettlementExecutor_)` 初始化 owner、treasury、dynamicFeeEngine、LP token implementation 与 preorder settlement executor，并写入默认启动费率配置。初始化时执行双向绑定校验：`dynamicFeeEngine_.authorizedHook() == address(this)` 且 `dynamicFeeEngine_.owner() == address(this)`；前者确保 engine 仅接受本 hook 的 fee state 写入，后者确保 hook 持有 engine 的 UUPS 升级授权。部署顺序为 LP implementation → 预测 hook proxy 地址（`script/DeployMemeverseHookProxy.s.sol::_selectProxySalt` 的 CREATE3 预测 `selectedProxy`）→ preorder settlement executor（constructor 接收 `selectedProxy` 作为 immutable `HOOK`；部署脚本 `script/DeployMemeverseHookProxy.s.sol::_deployPreorderSettlementExecutor` 在 creationCode 末尾拼接 `abi.encode(hookProxy)`，`hookProxy` 即 CREATE3 预测的 hook proxy `selectedProxy`）→ engine impl → engine proxy（`ERC1967Proxy`，owner=hook proxy, authorizedHook=hook proxy）→ hook impl → hook proxy（`TransparentUpgradeableProxy(implementation, hookOwner, initializeData)`，传入 engine、LP implementation、executor）。executor 仍始终在 engine 之前部署，因 hook proxy 地址始终先经 CREATE3 预测（部署顺序不变，仅 executor constructor 入参变更）。成功初始化时会触发 `TreasuryUpdated(address(0), treasury_)`、`LPTokenImplementationUpdated(address(0), lpTokenImplementation_)`、`PreorderSettlementExecutorUpdated(address(0), address(preorderSettlementExecutor_))` 与 `DefaultLaunchFeeConfigUpdated(0,0,0,5000,100,900)`。`[代码已证]`
- `lpTokenImplementation` 与 `preorderSettlementExecutor` 是 first-class deployment artifacts，不是 UUPS surface；脚本必须在 `DeploymentResult.lpTokenImplementation` 与 `DeploymentResult.preorderSettlementExecutor` 中返回。same-nonce 复用时二者都要校验预测地址、地址非零与代码存在。二者的运行期 codehash 都必须等于预期值（`lpTokenImplementation` 对应 `EXPECTED_LP_TOKEN_IMPLEMENTATION_CODEHASH`，`preorderSettlementExecutor` 对应 `EXPECTED_PREORDER_SETTLEMENT_EXECUTOR_CODEHASH`，见 `script/DeployMemeverseHookProxy.s.sol::_validateExistingImplementationCodehashes`）；二者 readiness 均不包含 pool-manager getter 检查。`[代码已证]`
- `lpTokenImplementation` 与 `preorderSettlementExecutor` 在升级语义上不对称。`preorderSettlementExecutor` 暴露 owner setter `setPreorderSettlementExecutor`（`src/swap/MemeverseUniswapHook.sol::setPreorderSettlementExecutor`），可由 owner 原子替换，替换后所有 pool 立即生效。`lpTokenImplementation` 同样暴露 owner setter `setLpTokenImplementation`（`src/swap/MemeverseUniswapHook.sol::setLpTokenImplementation`），可由 owner 替换克隆模板；但替换仅影响后续新建的 pool，已部署 pool 的 LP token clone 不受影响。根因：`preorderSettlementExecutor` 是所有 pool 共享的单例，hook 每次 preorder settlement 经内部读取（`src/swap/MemeverseUniswapHook.sol::executePreorderSettlement`）取最新指针，替换后立即生效。`lpTokenImplementation` 则是每个 pool 在 `beforeInitialize` 经 `Clones.clone` 独立克隆的模板（`src/swap/MemeverseUniswapHook.sol::_beforeInitialize`），EIP-1167 minimal proxy 在 clone 时即固化实现地址，clone 实例不可迁移。因此 `setLpTokenImplementation` 替换指针后，仅对此后新建的 pool 生效；已存在 pool 的 LP token clone 永久指向旧实现，无法热修，只能引导流动性迁移到新 pool。`[代码已证]`
- `POLend.initialize(...)` 必须拒绝 `leveragedDebtFactor_ > uint128.max * 1e18`；后续 owner setter 使用同一技术上限，升级不得放宽该边界。`[代码已证]`

## 5. 与文档链的关系

- deployer + governance proxy 属于 launcher 生命周期编排的一部分，与上述代码路径一致。
- Harness 层对 `src/**/*.sol` 的 gate、review 与测试映射要求以 `.harness/policy.json` 为真源；governance 升级路径已由 governance / deployment 相关测试与 policy 内的测试映射覆盖。

## 6. 确定性与未知项

- 高确定性
  - 合约是否声明 UUPS / initializer、是否通过 clone/proxy 部署，均可由源码直接判定。
  - governor / incentivizer 的 proxy 初始化与 `upgradeToAndCall` 授权路径已有执行级测试证据。
- 中确定性
  - 线上部署是否额外挂接 timelock、多签或其他治理执行者封装，不在仓库证据范围内。
- 未知项
  - 当前仓库未给出“生产链部署清单 + 环境级治理执行者配置”文档，因此无法给出环境级最终控制人结论；除 Hook 透明代理外，当前 UUPS surface 不存在独立 `ProxyAdmin` 角色。
