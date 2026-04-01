# MemeverseV2 实现面映射（Implementation Map）

## 1. 映射原则

- 仅记录“当前源码已落地”表面（no roadmap guess）。
- 每个表面都给出：职责、权责边界、升级性、证据来源、实现状态。
- 当前规则真源是 `docs/spec/*.md`；`src/**` 与 `test/**` 是可验证证据面。
- 升级性规则主文档是 `docs/spec/upgradeability.md`；本文 `Upgradeability` 列仅记录各 surface 的代码事实快照。

## 2. Surface Map

| Surface | 核心职责 | Authority / Roles | Upgradeability | 证据来源 | 实现状态 |
| --- | --- | --- | --- | --- | --- |
| `src/verse/MemeverseLauncher.sol` | verse 生命周期主控、资金分配、外部模块编排 | owner 配置；registrar 注册；governor/registrar 元数据更新；业务入口大多 permissionless + stage guard；解锁迁移时为受保护池写入公开 swap 恢复时间 | 构造部署，不走 proxy | `docs/spec/protocol.md`; `docs/spec/state-machines.md`; `src/verse/MemeverseLauncher.sol:51`, `:385-432`, `:582-608`, `:936-947`, `:1175-1217`, `:1307-1314` | 已实现 |
| `src/verse/registration/*` + `MemeverseRegistrationCenter` | 注册参数校验、symbol 生命周期、多链 fan-out | center 配置项 onlyOwner；local registrar 仅接受 center 调用；omnichain registrar gas 配置 onlyOwner | 构造部署，不走 proxy | `docs/spec/state-machines.md`; `src/verse/registration/MemeverseRegistrationCenter.sol:115`, `:308-350`; `src/verse/registration/MemeverseRegistrarAtLocal.sol:58`, `:80`; `src/verse/registration/MemeverseRegistrarOmnichain.sol:122` | 已实现 |
| `src/verse/deployment/MemeverseProxyDeployer.sol` | clone/proxy 部署与初始化编排入口 | deploy 函数仅 launcher；`setQuorumNumerator` onlyOwner | 自身不可升级；负责部署可升级与可初始化模块 | `docs/spec/protocol.md`; `src/verse/deployment/MemeverseProxyDeployer.sol:29-36`, `:93-117`, `:131-170`, `:176` | 已实现 |
| `src/swap/MemeverseSwapRouter.sol` | 用户路由入口（swap/liquidity/claim/bootstrap） | 对外纯 permissionless 公开 surface；构造固定 `hook/permit2` 绑定 | 构造部署，不走 proxy | `docs/spec/protocol.md`; `docs/spec/state-machines.md`; `src/swap/MemeverseSwapRouter.sol:71-77`, `:174-240`, `:264-489` | 已实现 |
| `src/swap/MemeverseUniswapHook.sol` | fee engine、LP 记账、hook callbacks、显式 launch settlement 执行 | 核心 API 对外开放；fee/treasury/emergency/launcher 配置 onlyOwner；launch settlement 与 pool-level 公开 swap 恢复时间写入仅 launcher；公开 swap 保护在 `beforeSwap` 执行 | 构造部署，不走 proxy | `docs/spec/protocol.md`; `docs/spec/state-machines.md`; `src/swap/MemeverseUniswapHook.sol:309-377`, `:440`, `:510`, `:550`, `:565-627`, `:1031-1046` | 已实现 |
| `src/token/Memecoin.sol` + `src/token/MemeLiquidProof.sol` | OFT memecoin/POL 资产层 | launcher 控制 mint 与 poolId；burn 按持币/授权路径开放 | clone + `initialize` 一次性 | `docs/spec/accounting.md`; `docs/spec/access-control.md`; `src/token/Memecoin.sol:24-43`; `src/token/MemeLiquidProof.sol:37-66`; `src/common/access/Initializable.sol:31-41` | 已实现 |
| `src/yield/MemecoinYieldVault.sol` | memecoin yield vault + ERC20Votes share | 无 owner 门禁型业务入口（deposit/yield/redeem）；由流程和资产校验约束 | clone + `initialize` 一次性 | `docs/spec/accounting.md`; `docs/spec/access-control.md`; `src/yield/MemecoinYieldVault.sol:37-50`, `:86`, `:120`, `:132`, `:146` | 已实现 |
| `src/governance/MemecoinDaoGovernorUpgradeable.sol` | DAO Governor + treasury + proposal/vote 扩展 | treasury 支出/升级仅治理执行 | UUPS + initializer | `docs/spec/accounting.md`; `src/governance/MemecoinDaoGovernorUpgradeable.sol:76-92`, `:221`, `:252` | 已实现 |
| `src/governance/GovernanceCycleIncentivizerUpgradeable.sol` | 治理周期奖励与 treasury/reward 账本 | `recordTreasuryIncome` / `recordTreasuryAssetSpend` 仅 governor；`claimReward` 为用户入口；`finalizeCurrentCycle` 可 permissionless | UUPS + initializer | `docs/spec/accounting.md`; `docs/spec/access-control.md`; `src/governance/GovernanceCycleIncentivizerUpgradeable.sol:68-76`, `:365`, `:385`, `:408`, `:648` | 已实现 |
| `src/verse/YieldDispatcher.sol` | OFT compose 收益分发（governor / yieldVault / burn） | `lzCompose` 仅 endpoint 或 launcher | 构造部署，不走 proxy | `docs/spec/protocol.md`; `docs/spec/access-control.md`; `src/verse/YieldDispatcher.sol:39-47`, `:63-79` | 已实现 |
| `src/interoperation/MemeverseOmnichainInteroperation.sol` + `OmnichainMemecoinStaker.sol` | 跨链 staking 入口与治理链落地 | staking permissionless；gas 配置 onlyOwner；staker compose 仅 endpoint | 构造部署，不走 proxy | `docs/spec/protocol.md`; `docs/spec/access-control.md`; `src/interoperation/MemeverseOmnichainInteroperation.sol:93`, `:135`; `src/interoperation/OmnichainMemecoinStaker.sol:39` | 已实现 |
| `src/common/omnichain/LzEndpointRegistry.sol` | chainId -> endpointId 注册表 | `setLzEndpointIds` onlyOwner | 构造部署，不走 proxy | `docs/spec/state-machines.md`; `src/common/omnichain/LzEndpointRegistry.sol:11-31` | 已实现 |
| `src/common/access/*` + `src/common/omnichain/*`（与本任务相关子集） | 最小代理初始化、owner、peer/delegate 与 OFT/OApp 基础边界 | `initializer` 一次性、`onlyOwner` peer/delegate/msgInspector | 基础能力层 | `docs/spec/access-control.md`; `src/common/access/Initializable.sol:27-41`; `src/common/omnichain/oapp/OutrunOAppCoreInit.sol:68-92`; `src/common/omnichain/oft/OutrunOFTCoreInit.sol:143` | 已实现 |

## 3. 测试与流程映射状态

- 已有 rule-map 正式覆盖：
  - swap / launcher 主面
  - registration / dispatcher / deployment
  - governance
  - interoperation
  - token / yield
  - common 的已测子集（registry、token initializer、OApp initializer、OFT initializer、governance token extension）
- 仍保留 residual testing gap：
  - `src/common/**` 中少量仍未被 targeted rule 单独建模的基础层子集（如 `ReentrancyGuard`、`IBurnable`、`OutrunOAppPreCrimeSimulatorInit`、`TokenHelper`）
  - 证据：`docs/process/rule-map.json`
- 结论
  - 产品实现面是完整的；流程层“规则 -> 测试映射”已覆盖主要业务域，残余缺口已收敛到少量 common 基础件。

## 4. 后续业务解释事项（不影响“已实现”状态）

- `src/governance/GovernanceCycleIncentivizerUpgradeable.sol` 采用“Governor 托管真实资产、Incentivizer 维护账本并结算用户 claim”的治理奖励路径；其当前产品解释已由 `docs/spec/accounting.md`、`docs/spec/access-control.md` 与对应测试证据闭环。
- unlock 后的公开 swap 保护当前由 launcher 在解锁迁移时把恢复时间 snapshot 到 hook，hook 在 `beforeSwap` 执行阻断；该能力没有额外生命周期阶段，但已形成行为闭环。
