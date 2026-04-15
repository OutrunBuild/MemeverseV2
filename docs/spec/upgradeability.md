# MemeverseV2 升级性与初始化约束（Source-Backed）

## 1. 结论摘要

当前仓库存在三类 surface：

1. 构造函数部署、不可升级（无 proxy）
2. 最小代理（EIP-1167 clone）+ 自定义 `initializer`
3. `ERC1967Proxy` + `UUPSUpgradeable`

补充约束：

- 本文档是升级性规则主文档（canonical source）。
- `docs/spec/implementation-map.md` 仅在各 surface 行内记录升级机制事实与定位锚点，不替代本文规则条目。

## 2. 升级面分类

| Surface | 机制 | 初始化入口 | 升级授权 | 证据 |
| --- | --- | --- | --- | --- |
| **构造函数部署（不可升级）** | | | | |
| Launcher | constructor 部署 | constructor | 不适用 | `src/verse/MemeverseLauncher.sol:69` |
| Router | constructor 部署 | constructor | 不适用 | `src/swap/MemeverseSwapRouter.sol:75` |
| Hook | constructor 部署 | constructor | 不适用 | `src/swap/MemeverseUniswapHook.sol:158` |
| RegistrationCenter | constructor 部署 | constructor | 不适用 | `src/verse/registration/MemeverseRegistrationCenter.sol:46` |
| RegistrarAtLocal | constructor 部署 | constructor | 不适用 | `src/verse/registration/MemeverseRegistrarAtLocal.sol:16` |
| RegistrarOmnichain | constructor 部署 | constructor | 不适用 | `src/verse/registration/MemeverseRegistrarOmnichain.sol:33` |
| YieldDispatcher | constructor 部署 | constructor | 不适用 | `src/verse/YieldDispatcher.sol:26` |
| OmnichainInteroperation | constructor 部署 | constructor | 不适用 | `src/interoperation/MemeverseOmnichainInteroperation.sol:36` |
| OmnichainMemecoinStaker | constructor 部署 | constructor | 不适用 | `src/interoperation/OmnichainMemecoinStaker.sol:19` |
| LzEndpointRegistry | constructor 部署 | constructor | 不适用 | `src/common/omnichain/LzEndpointRegistry.sol:14` |
| ProxyDeployer | constructor 部署 | constructor | 不适用 | `src/verse/deployment/MemeverseProxyDeployer.sol:38` |
| **最小代理 clone（不可升级）** | | | | |
| `Memecoin` / `MemePol` / `MemecoinYieldVault` | EIP-1167 clone | 外部 `initialize`（单次） | 无实现内升级入口 | `src/verse/deployment/MemeverseProxyDeployer.sol:93-117`; `src/token/Memecoin.sol:24`; `src/token/MemePol.sol:37`; `src/yield/MemecoinYieldVault.sol:37` |
| **UUPS 可升级** | | | | |
| `MemecoinDaoGovernorUpgradeable` | `ERC1967Proxy` + UUPS | `initialize(...)` | `onlyGovernance` | `src/verse/deployment/MemeverseProxyDeployer.sol:141-150`; `src/governance/MemecoinDaoGovernorUpgradeable.sol:76`, `:252` |
| `GovernanceCycleIncentivizerUpgradeable` | `ERC1967Proxy` + UUPS | `initialize(...)` | `onlyGovernance` | `src/verse/deployment/MemeverseProxyDeployer.sol:141-150`; `src/governance/GovernanceCycleIncentivizerUpgradeable.sol:83`, `:640` |

## 3. 初始化约束（当前代码实际支持）

### 3.1 最小代理初始化一次性

- `src/common/access/Initializable.sol` 在实现合约 constructor 中把 `initialized=true`，阻止实现本体被初始化。
  - 证据：`src/common/access/Initializable.sol:27-29`
- clone 实例通过 `initializer` 进入一次初始化，重复调用回退 `AlreadyInitialized`。
  - 证据：`src/common/access/Initializable.sol:31-41`

### 3.2 由 launcher 驱动 token 初始化

- launcher 在注册时通过 deployer 克隆 `memecoin`/`POL` 并立即 `initialize`。
  - 证据：`src/verse/MemeverseLauncher.sol:1087-1097`

**owner 与 delegate 的初始化值：**

- `initialize` 调用时，`owner` 和 `delegate` 均被设为 `msg.sender`——即执行调用的 launcher 实例（`address(this)`）。
  - 含义：刚部署的 memecoin / POL token 的 admin 权限（owner）与治理代理权（delegate）都归属于 launcher。
  - 证据：`src/verse/MemeverseLauncher.sol:1089-1097`; `src/token/Memecoin.sol:29-33`; `src/token/MemePol.sol:44-49`
- 此行为仅反映源码层的初始化语义；线上部署后 owner 是否被迁移（例如转给多签 / timelock）不在仓库证据范围内。
  - 同源：section 6 "中确定性" 条目

### 3.3 governance 组件仅在治理链本地部署初始化

- 当 `govChainId == block.chainid`：部署并初始化 `yieldVault/governor/incentivizer`。
  - 证据：`src/verse/MemeverseLauncher.sol:487-499`
- 否则只做地址预测，不在当前链初始化。
  - 证据：`src/verse/MemeverseLauncher.sol:500-503`

## 4. Proxy / Deployer 假设（仅限代码可证）

- `MemeverseProxyDeployer` 只允许 launcher 调用 deploy 系列函数。
  - 证据：`src/verse/deployment/MemeverseProxyDeployer.sol:29-36`, `:93`, `:103`, `:113`, `:139`
- governor 与 incentivizer 使用 `Create2 + ERC1967Proxy`，部署后立即执行 `initialize(...)`。
  - 证据：`src/verse/deployment/MemeverseProxyDeployer.sol:141-150`, `:153-169`
- UUPS 升级授权绑定治理：
  - governor 自身升级授权 `onlyGovernance`
  - incentivizer 升级授权 `onlyGovernance`（实际校验 `msg.sender == governor`）
  - 证据：`src/governance/MemecoinDaoGovernorUpgradeable.sol:252`; `src/governance/GovernanceCycleIncentivizerUpgradeable.sol:68-71`, `:640`

## 5. 与文档链的关系

- deployer + governance proxy 属于 launcher 生命周期编排的一部分，与上述代码路径一致。
- Harness 层对 `src/**/*.sol` 的 gate、review 与测试映射要求以 `.harness/policy.json` 为真源；governance 升级路径已由 governance / deployment 相关测试与 policy 内的测试映射覆盖。

## 6. 确定性与未知项

- 高确定性
  - 合约是否声明 UUPS / initializer、是否通过 clone/proxy 部署，均可由源码直接判定。
  - governor / incentivizer 的 proxy 初始化与 `upgradeToAndCall` 授权路径已有执行级测试证据。
- 中确定性
  - 线上部署是否额外加 timelock、多签或 owner 转移，不在仓库证据范围内。
- 未知项
  - 当前仓库未给出“生产链部署清单 + 实际 proxy admin 关系”文档，因此无法给出环境级最终控制人结论。
