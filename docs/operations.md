# MemeverseV2 运维语义（Operator / Keeper Runbook）

## 1. 说明

本文是“当前实现语义”的操作手册，不定义链下组织流程。  
标签说明：

- `[代码已证]`：源码可直接验证
- `[未知]`：依赖生产部署或链外系统信息

## 2. 角色与职责边界

- `owner`：改配置、地址指针调整。`[代码已证]`
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

- `SetExternalInfo` 中 `uri` 和 `description` 采用增量覆盖语义（空字符串不覆盖旧值）。`communities` 数组中，空数组不触发任何操作，但数组内的空字符串会删除对应索引的条目——调用时需确保非目标位置传入现有值而非空字符串。

失败要点：symbol 未解锁、uAsset 未支持、`msg.value` 不足、目标链 endpointId 未配置。`[代码已证]`

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

入口：`quoteDistributionLzFee(verseId)`（经 `MemeverseFeePreviewReader`，地址取 `getLauncherContracts().feePreviewReader`）与 `redeemAndDistributeFees(verseId,rewardReceiver)`（仍调 Launcher）。  
语义：

- 先从 `memecoin/uAsset` 主池与三个辅助池捕获 fee；目标分流规则见 [docs/spec/polend/README.md](spec/polend/README.md)
- 主池 `memecoin/uAsset` fee：`memecoin` fee 进入 yield 路径；`uAsset` fee 拆成 `executorReward + govFee`
- 辅助池 `POL/uAsset`、`PT/uAsset`、`PT/POL` fee：POL fee burn；普通侧 `uAsset/PT` fee 进入普通 fee 领取账本；杠杆侧 `uAsset` fee 进入 governor treasury 路径；杠杆侧 `PT` fee 在 settle 前 `preRedeemPTFee` 预兑付，settle 后 `redeemPT` 后分发；settle 前捕获但未主动分发的杠杆侧 PT fee 作为 pending，后续 settled 后再 `redeemPT` 分发
- 本链治理：经 `yieldDispatcher.lzCompose` 分发到 governor / yieldVault
- 异链治理：走 OFT `send`，`msg.value` 必须精确等于总报价

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

- Hook owner 可改：`treasury`、protocol fee 币种支持、`launcher`、launch fee 衰减参数。
- Hook owner 可通过 `setLpTokenImplementation` 替换 LP token 克隆模板，但替换仅影响后续新建的 pool。已部署 pool 的 LP token 是 EIP-1167 minimal proxy（clone），实现地址在部署时固化，无法迁移或升级。如果旧 LP 实现被发现漏洞，已部署池的 LP token 永久运行旧代码，只能引导流动性迁移到新池。这是 clone 模式的固有局限性，非 bug。`[代码已证]`
- 公开 swap 始终使用正常费率路径：`feeBps = max(current launch fee, dynamic fee, FEE_BASE_BPS)`；dynamic fee engine 故障通过升级/修复处理，不提供 bypass mode。`[代码已证]`
- Launcher owner 配置 router / hook 时，会同时校验 `router.hook()==hook`、`hook.launcher()==launcher`、`hook.poolInitializer()==router`，配置不一致会直接拒绝；其中 `memeverseUniswapHook` 仅允许首次设置。`[代码已证]`
- Hook owner 在配置完成后仍可 retarget `launcher`；这是接受的同一 trust boundary 内运维能力，不否定 set-time 三重校验的必要性。`[代码已证]`
- `createPoolAndAddLiquidity(...)` 的 `onlyLauncher` 是有意设计；建池要求 `Launcher -> Router` 调用链，并要求 Hook 的 `poolInitializer` 授权 Router。部署或配置变更后必须复核：`launcher.memeverseSwapRouter()==router`、`launcher.memeverseUniswapHook()==hook`、`router.hook()==hook`、`hook.launcher()==launcher`、`hook.poolInitializer()==router`；`Genesis -> Locked` 建池前也会做 launch-time preflight 复核，避免配置漂移到运行建池时才失败。`[代码已证]`
- Launcher pause 不会直接阻断 `changeStage(...)` 驱动的建池，因为 `changeStage(...)` 不是 `whenNotPaused`；但 Hook 的 `launcher` retarget 或 Router/Hook/Initializer 配置漂移会阻断后续新池创建。`[代码已证]`

### 3.7 POLend / POLSplitter 运维边界

- Launcher proxy 初始化时保存 `POLend` 与 `POLSplitter` 的 proxy 地址，当前规范不支持地址级替换，也不支持降级为零地址模式。`[代码已证]`
- 这不等于实现不可升级：`POLend` 与 `POLSplitter` 是 UUPS proxy，`_authorizeUpgrade(...)` 为 `onlyOwner`。`[代码已证]`
- `POLend.setLeveragedDebtFactor` 的技术上限为 `uint128.max * 1e18`；该值是有效上限，不代表运营最优值。普通创世与杠杆创世的累计部署资金必须保持 `totalNormalFunds + totalLeveragedDebt <= type(uint128).max`。`[代码已证]`
- 地址级替换、迁移或从零地址恢复不在当前规范内；如需支持，必须先给出显式迁移设计。`[代码已证]`
- `SettlementDustInsufficient` 出现在回退交易上时，不会留下可用事件日志，不能按失败交易已发事件监控。keeper/monitor 应在目标区块状态用 `eth_call` 或 fork simulation 预执行 `MemeverseLauncher.changeStage(verseId)` 的 `Locked -> Unlocked` 路径；如需单独模拟内部结算步骤，可预执行 `POLend.executeGlobalSettlement(verseId)`。若模拟回退 `SettlementDustInsufficient(uint256 deficit,uint256 availableReserve)`，需先用 `POLend.getLendMarket(verseId).uAsset` 确认目标 uAsset，再计算 `topUpAmount = deficit - availableReserve`，对该 uAsset 完成 approve/transfer 后调用 `fundSettlementDustReserve(uAsset, topUpAmount)`，随后重试 settlement / `changeStage`。补资前还要检查 `settlementDustStates(uAsset)` 的容量：若 `topUpAmount` 超过剩余 capacity，非 Launcher 调用 `fundSettlementDustReserve` 会回退 `SettlementDustReserveExceeded(amount, capacity)`；此时应走告警、升级或配置处理，不能盲目重试。当前合约没有暴露完整 side-effect-free preview 来提前得出 `recoveredUAsset`，因为 settlement 会通过移除 LP、POL redemption、PT redemption 路径回收 uAsset。`[代码已证]`

### 3.8 unlock 后保护窗口运维语义

- 按产品安全要求，unlock 后应先进入 `post-unlock liquidity protection period`
- 在该窗口内，运维与 keeper 应优先支持退出/结算，而不是开放普通公开 swap
- 当前实现已把这套窗口语义落在“解锁迁移时写入 pool-level `publicSwapResumeTime` + `hook.beforeSwap` 阻断”
- 因此现阶段仍不能把”`unlockTime` 到达”误解为”产品上已经安全进入完全开放交易阶段”；是否恢复公开 swap 还要看实际 `changeStage()` 时间点加上固定 `24 hours` 保护窗口

### 3.9 Proxy 升级操作步骤

本节覆盖 UUPS 可升级合约和 `TransparentUpgradeableProxy` Hook 的升级操作规程。升级的本质是让 proxy 指向新的 implementation 合约，proxy 地址不变、storage 数据不变、用户无感知。部署记录还必须把不可升级但一等返回的 `lpTokenImplementation` 与 `preorderSettlementExecutor` 作为独立 artifacts 记录。

#### 3.9.1 可升级与可替换实现合约汇总

| 合约 | proxy 来源 / proxy salt label | implementation 部署来源 | 当前可证 implementation salt label | 授权门控 | 特殊约束 |
| --- | --- | --- | --- | --- | --- |
| **UUPS 可升级** | | | | | |
| `MemeverseLauncher` | `MemeverseScript._deployMemeverseLauncher`; proxy salt = `MemeverseLauncher + nonce` | `MemeverseScript._deployMemeverseLauncher` 内部署 | `MemeverseLauncherImplementation + nonce` | `onlyOwner` | 存储 `polend`/`polSplitter` proxy 地址，不可运行时替换 |
| `POLend` | `MemeverseScript._deployPOLend`; proxy salt = `POLend + nonce` | `MemeverseScript._deployPOLend` 内部署 | `POLendImplementation + nonce` | `onlyOwner` | 存储 `launcher`/`splitter` 地址；`leveragedDebtFactor` 技术上限 `uint128.max * 1e18` |
| `POLSplitter` | `MemeverseScript._deployPOLSplitter`; proxy salt = `POLSplitter + nonce` | `MemeverseScript._deployPOLSplitter` 内部署 | `POLSplitterImplementation + nonce` | `onlyOwner` | 存储 `launcher`/`polend` 地址；初始化时读 `launcher.polend()` |
| **透明代理可升级** | | | | | |
| `MemeverseUniswapHook` | `DeployMemeverseHookProxy.getPredictedProxy(..., nonce, hookOwner, hookTreasury, poolManager)`；内部 `_selectProxySalt` 使用 `keccak256(abi.encodePacked("MemeverseUniswapHookProxy", nonce, i))` 选择 nonce-scoped hook-flag proxy salt | `DeployMemeverseHookProxy` 通过 `new MemeverseUniswapHook(poolManager)` 部署 | `N/A` | Hook proxy admin slot 指向的 `ProxyAdmin.owner()` | `poolManager` 不在 proxy storage 中，是字节码级绑定；poolManager 匹配是 operator-side pre-check |
| **治理代理可升级** | | | | | |
| `MemecoinDaoGovernorUpgradeable` | `MemeverseProxyDeployer.deployGovernorAndIncentivizer`; proxy salt = `keccak256(abi.encode(uniqueId))` | `MemeverseScript._deployMemecoinGovernorImplementation` | `MemecoinDaoGovernorImplementation + nonce` | `onlyGovernance` | 需走 OZ Governor 提案流程；`_authorizeUpgrade` 由 Governor 合约内部 `_governanceCall` 放行 |
| `GovernanceCycleIncentivizerUpgradeable` | `MemeverseProxyDeployer.deployGovernorAndIncentivizer`; proxy salt = `keccak256(abi.encode(uniqueId))` | `MemeverseScript._deployImplementation` | `GovernanceCycleIncentivizerImplementation + nonce` | `onlyGovernance` | 实际校验 `msg.sender == _governor`（即 Governor proxy 地址） |
| **Facade delegatecall 目标（非 proxy，可替换实现）** | | | | | |
| `MemeverseBootstrap` | N/A（非 proxy，Launcher `delegatecall` 目标） | `MemeverseScript` 单角色模式 `new MemeverseBootstrap()` | N/A | `setBootstrapImpl`（`onlyOwner`） | 与 Launcher 共享 ERC-7201 namespace `outrun.storage.MemeverseLauncher` 与 `IMemeverseLauncherStorage` struct；替换方式为部署新 sibling + owner `setBootstrapImpl`（非 UUPS `upgradeToAndCall`）；sibling 读 proxy storage，被 EOA 直调时读自身空 storage 回退 |
| `MemeverseFeeDistributor` | N/A（非 proxy，Launcher `delegatecall` 目标） | `MemeverseScript` 单角色模式 `new MemeverseFeeDistributor()` | N/A | `setFeeDistributorImpl`（`onlyOwner`） | 与 Launcher/Bootstrap 共享 ERC-7201 namespace `outrun.storage.MemeverseLauncher` 与 `IMemeverseLauncherStorage` struct；替换方式为部署新 sibling + owner `setFeeDistributorImpl`；delegatecall-only by construction（自身 storage 永久未初始化，被 EOA 直调时读空 verse → 对 address(0) 外调回退） |
| `MemeversePOLMinter` | N/A（非 proxy，Launcher `delegatecall` 目标） | `MemeverseScript` 单角色模式 `new MemeversePOLMinter()` | N/A | `setPOLMinterImpl`（`onlyOwner`） | 与 Launcher/Bootstrap/FeeDistributor 共享 ERC-7201 namespace `outrun.storage.MemeverseLauncher` 与 `IMemeverseLauncherStorage` struct；替换方式为部署新 sibling + owner `setPOLMinterImpl`；delegatecall-only by construction（空 constructor、无 `Initializable`、自身 storage 永久未初始化，被 EOA 直调时读空 verse → 对 address(0) 外调回退） |
| **Staticcall view sibling（非 proxy，可替换实现）** | | | | | |
| `MemeverseFeePreviewReader` | N/A（非 proxy，独立 view 合约；通过 immutable `PROXY` staticcall 读 Launcher 状态） | `MemeverseScript` 单角色模式 `new MemeverseFeePreviewReader(launcherProxy)` | N/A | `setFeePreviewReader`（`onlyOwner`） | 不绑名域、不被 delegatecall、不可写 proxy storage；替换方式为部署新 reader + owner `setFeePreviewReader`；构造时 immutable 绑定 Launcher proxy，部署后无法 retarget 到其他 proxy；§3.9.7 readiness 要求未接线时阻断 registration 打开 |

#### 3.9.2 升级前：Storage 兼容性验证

下表所列合约均使用 ERC7201 名域存储（namespaced storage）。每个合约的自定义数据存在一个由 namespace 字符串计算出的固定槽位起始位置。下表列出各合约的 annotation（`@custom:storage-location`，含 `erc7201:` scheme 前缀）和实际参与 slot hash 的 namespace ID：

| 合约 | annotation（代码注解） | namespace ID（hash 输入） |
|---|---|---|
| `MemeverseLauncher` | `erc7201:outrun.storage.MemeverseLauncher` | `outrun.storage.MemeverseLauncher` |
| `POLend` | `erc7201:outrun.storage.POLend` | `outrun.storage.POLend` |
| `POLSplitter` | `erc7201:outrun.storage.POLSplitter` | `outrun.storage.POLSplitter` |
| `MemeverseUniswapHook` | `erc7201:outrun.storage.MemeverseUniswapHook` | `outrun.storage.MemeverseUniswapHook` |
| `MemecoinDaoGovernorUpgradeable` | `erc7201:outrun.storage.MemecoinDaoGovernor` | `outrun.storage.MemecoinDaoGovernor` |
| `GovernanceCycleIncentivizerUpgradeable` | `erc7201:outrun.storage.GovernanceCycleIncentivizer` | `outrun.storage.GovernanceCycleIncentivizer` |
| `MemeverseBootstrap` | `erc7201:outrun.storage.MemeverseLauncher` | `outrun.storage.MemeverseLauncher`（与 `MemeverseLauncher` 相同） |
| `MemeverseFeeDistributor` | `erc7201:outrun.storage.MemeverseLauncher` | `outrun.storage.MemeverseLauncher`（与 `MemeverseLauncher` 相同） |
| `MemeversePOLMinter` | `erc7201:outrun.storage.MemeverseLauncher` | `outrun.storage.MemeverseLauncher`（与 `MemeverseLauncher` 相同） |

`MemeverseBootstrap`、`MemeverseFeeDistributor` 与 `MemeversePOLMinter` **均为** `MemeverseLauncher` facade 的 delegatecall sibling，共享同一 namespace `outrun.storage.MemeverseLauncher` 与 `IMemeverseLauncherStorage` struct；升级 facade 或任一 sibling 的 storage layout 时，**所有**共享该 namespace 的合约必须用相同 struct 同步重编，否则 facade 经 delegatecall 调 sibling 时读写错位。三行 namespace 均经 `layout at erc7201("outrun.storage.MemeverseLauncher")` 绑定，`@custom:storage-location` 注解实际挂在 `src/verse/interfaces/IMemeverseLauncherStorage.sol::MemeverseLauncherStorage`。

ERC7201 槽位计算公式：`keccak256(abi.encode(uint256(keccak256(“outrun.storage.XXX”)) - 1)) & ~bytes32(uint256(0xff))`。注意：`erc7201:` 仅是 annotation scheme 前缀，用于标识 struct 使用 ERC7201 存储，**不参与** slot hash 计算。可以用 `cast storage <proxy> <slot>` 直接读链上数据验证。

**验证步骤：**

1. 导出旧 implementation 的 storage layout：
```bash
forge inspect <ContractName> storage-layout --pretty > old-layout.txt
```
2. 导出新 implementation 的 storage layout：
```bash
forge inspect <ContractName> storage-layout --pretty > new-layout.txt
```
3. 对比差异：
```bash
diff old-layout.txt new-layout.txt
```
4. 确认规则：
   - namespace 字符串不变（变了意味着整个 storage 重新映射，所有数据丢失）
   - struct 字段只能在末尾追加（additive），不能删除、不能重排、不能改类型
   - 继承链中的公共 storage（`OutrunOwnableInit`、`OutrunERC20Init` 等）布局不变
   - 如果 diff 显示字段顺序变化或类型变化，**停止升级**，修复 implementation 后重新编译部署

`[代码已证]`

#### 3.9.3 部署新 Implementation

UUPS 模式下，implementation 是一个独立的合约实例，proxy 通过 `delegatecall` 调用它的代码。升级就是让 proxy 的 implementation 指针从旧地址换成新地址。

**操作步骤：**

1. 编译新 implementation：
```bash
forge build
```
2. 部署到目标链。不要默认所有 UUPS 合约都有 implementation salt label；按 3.9.1 的 `implementation 部署来源` 执行：
   - `MemeverseLauncher`：使用 `MemeverseLauncherImplementation + nonce` 部署新的 implementation；不要重跑会重新部署同一 proxy salt 的完整 proxy 部署步骤。
   - `MemecoinDaoGovernorUpgradeable`：使用 `MemeverseScript._deployMemecoinGovernorImplementation` 的 deployment source，salt label 为 `MemecoinDaoGovernorImplementation + nonce`。
   - `GovernanceCycleIncentivizerUpgradeable`：使用 `MemeverseScript._deployImplementation` 中的 incentivizer implementation 部署逻辑，salt label 为 `GovernanceCycleIncentivizerImplementation + nonce`。
   - `MemeverseUniswapHook`：只复用 `DeployMemeverseHookProxy` 的 implementation 部署逻辑，不重跑 proxy 部署分支；必须传入与当前 proxy 一致的 `POOL_MANAGER`。
   - `POLend`：使用 `MemeverseScript._deployPOLend` 中的 implementation 部署逻辑，salt label 为 `POLendImplementation + nonce`。
   - `POLSplitter`：使用 `MemeverseScript._deployPOLSplitter` 中的 implementation 部署逻辑，salt label 为 `POLSplitterImplementation + nonce`。
3. 记录新 implementation 地址。后续 UUPS `upgradeToAndCall` 或 Hook `ProxyAdmin.upgradeAndCall(...)` 会把 proxy 指向这个地址。

**新 implementation 记录模板：**

```text
contract:
proxy:
oldImplementation:
newImplementation:
deploymentSource:
saltLabel:
nonce:
constructorArgs:
codeHash:
deploymentTx:
```

- `contract`：被升级的合约名。
- `proxy`：用户和其它合约继续访问的 proxy 地址。
- `oldImplementation`：升级前 proxy 指向的 implementation 地址。
- `newImplementation`：本次准备切换到的新 implementation 地址，即 `$NEW_IMPL`。
- `deploymentSource`：部署 `$NEW_IMPL` 的脚本或外部流程。
- `saltLabel`：如适用，记录 human-readable salt label；不适用写 `N/A`。
- `nonce`：如 salt 使用 nonce，记录 nonce；不适用写 `N/A`。
- `constructorArgs`：implementation constructor 参数；例如 Hook 必须记录 `POOL_MANAGER`。
- `codeHash`：用 `cast codehash $NEW_IMPL --rpc-url $RPC` 记录链上代码哈希。
- `deploymentTx`：部署 `$NEW_IMPL` 的交易哈希。

`[代码已证]`

#### 3.9.4 执行升级

UUPS 合约通过 `upgradeToAndCall(address newImplementation, bytes memory data)` 升级。它做两件事：
- 把 proxy 的 implementation 指针改成 `newImplementation`
- 可选：在新 implementation 上执行一段初始化调用，编码在 `data` 参数里

**当前项目中，可升级合约没有 `reinitialize` 函数，也没有 `__gap` 存储预留模式（ERC7201 不需要）。** 因此大多数升级场景下 `data` 传空 bytes 即可。

**UUPS 调用方式：**

```bash
# data 为空（最常见的升级场景，不需要额外初始化）
cast send $PROXY "upgradeToAndCall(address,bytes)" \
  $NEW_IMPL "" \
  --private-key $OWNER_KEY --rpc-url $RPC

# 如果未来新 implementation 增加了 reinitialize，用 abi 编码 data：
# cast calldata "reinitialize(uint8)" 2
# 然后把输出的 hex 作为 data 参数传入
```

**按授权门控分类：**

- `onlyOwner` UUPS 合约（Launcher, POLend, POLSplitter）：owner 地址（通常是多签）直接发起交易。
- `onlyGovernance` 合约（Governor, Incentivizer）：当前 Governor 没有 Timelock extension，OZ base `queue` 没有实现；升级必须通过 `propose` -> vote -> `execute`，把 `upgradeToAndCall` 的 calldata 包装成治理提案执行。如果未来增加 Timelock extension，`queue` 才放在成功投票和 `execute` 之间。owner 或多签直接调用不能通过 `onlyGovernance` UUPS 升级授权。
- `MemeverseUniswapHook` 透明代理：读取 Hook proxy ERC1967 admin slot 得到 `ProxyAdmin`，由 `ProxyAdmin.owner()` 调用 `ProxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(hookProxy), newImplementation, data)`。

```bash
# ERC1967 admin slot = bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1)
HOOK_ADMIN_SLOT=0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103

cast storage $HOOK_PROXY $HOOK_ADMIN_SLOT --rpc-url $RPC
# 返回值低 20 bytes 应解析为 ProxyAdmin 地址：$HOOK_PROXY_ADMIN

cast call $HOOK_PROXY_ADMIN "owner()(address)" --rpc-url $RPC
# 应等于预期 Hook admin owner

cast send $HOOK_PROXY_ADMIN "upgradeAndCall(address,address,bytes)" \
  $HOOK_PROXY $NEW_IMPL "$DATA" \
  --private-key $PROXY_ADMIN_OWNER_KEY --rpc-url $RPC
```

`[代码已证]`

#### 3.9.5 MemeverseUniswapHook 透明代理升级检查

Hook implementation 不提供 UUPS 升级入口。`poolManager` 一致性检查是 off-chain / operator-side pre-check，不是 Hook on-chain `_authorizeUpgrade`。

**Pre-check：**

```bash
cast call $HOOK_PROXY "poolManager()(address)" --rpc-url $RPC
# 记录当前 Hook proxy PoolManager

cast call $NEW_IMPL "poolManager()(address)" --rpc-url $RPC
# 必须等于当前 Hook proxy poolManager()
```

`poolManager` 地址不在 proxy storage 中，它是字节码级绑定（在 implementation constructor 中设置的 immutable 或 constructor 参数）。升级后 proxy 通过 `delegatecall` 使用新 implementation 的代码，如果新 implementation 指向了错误的 PoolManager，所有 swap 和流动性操作会永久失效。

**Post-check：**

```bash
cast call $HOOK_PROXY "poolManager()(address)" --rpc-url $RPC
# 应仍等于预期 PoolManager

cast call $HOOK_PROXY "dynamicFeeEngine()(address)" --rpc-url $RPC
# 应等于 Engine proxy 地址

cast call $ENGINE_PROXY "authorizedHook()(address)" --rpc-url $RPC
# 应等于 Hook proxy 地址

cast call $ENGINE_PROXY "owner()(address)" --rpc-url $RPC
# 应等于 Hook proxy 地址

cast call $HOOK_PROXY "lpTokenImplementation()(address)" --rpc-url $RPC
# 应等于记录的 LP token implementation

cast call $HOOK_PROXY "preorderSettlementExecutor()(address)" --rpc-url $RPC
# 应等于记录的 preorder settlement executor
```

完成后执行 swap / liquidity smoke tests，覆盖至少一次 swap 路径和一次 add/remove liquidity 路径。

Hook ownership transfer 必须同步 transfer ProxyAdmin ownership，保持 Hook `owner()` 与 `ProxyAdmin.owner()` 对齐；否则部署脚本 same-nonce / existing reuse validation 会拒绝 split-control 状态。

#### 3.9.6 POLSplitter 升级顺序约束

POLSplitter 的 storage 中保存了 `launcher` 和 `polend` 的 proxy 地址（在 `initialize` 时从 `launcher.polend()` 读取写入）。这些地址是 POLSplitter 运行时的核心依赖——`split`、`settle`、`redeemPT` 等函数都通过这些地址回调 Launcher 和 POLend。

**升级 POLSplitter 时的约束：**

1. 升级本身**不会**改变 storage 中的 `launcher`/`polend` 地址。`upgradeToAndCall` 只替换 implementation 指针，不碰 proxy storage
2. 确保 `launcher` 和 `polend` proxy 在升级前后都在线且地址未变
3. 如果新 POLSplitter implementation 的 `initialize` 逻辑有变化，不要误触发 re-initialization——`Initializable` modifier 会阻止，但要确认新 implementation 没有绕过 `initializer` 的路径
4. 升级完成后，验证 `launcher.polend()` 和 `launcher.polSplitter()` 返回值仍然正确（见 3.9.7）

**storage 地址不变：** 升级本身不会改变 proxy storage 中的 `launcher`/`polend`/`polSplitter` 地址。`upgradeToAndCall` 只替换 implementation 指针，三个合约的地址引用在升级前后保持一致。`[代码已证]`

**升级顺序建议：** 如果同时升级 Launcher + POLend + POLSplitter，建议先升级 POLend 和 POLSplitter，最后升级 Launcher。这样在升级窗口期内，Launcher 始终指向已更新的依赖。这是防御性运维建议，不是代码强制约束——因为 storage 地址不变，任何顺序都不会破坏运行时回调链。

#### 3.9.7 升级后 Readiness Checks

升级完成后必须验证 proxy 的功能正常。以下是按合约分类的检查清单：

**通用检查（所有 UUPS 合约）：**

```bash
# 确认 proxy 的 implementation 指针已更新
# ERC1967 implementation slot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc
cast storage $PROXY \
  0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc \
  --rpc-url $RPC
# 返回值应等于 $NEW_IMPL 地址

# 确认 new implementation 的 UUPS UUID
cast call $NEW_IMPL "proxiableUUID()(bytes32)" --rpc-url $RPC
# 返回值应等于 ERC1967 implementation slot:
# 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc

# 可选 guard：通过 proxy 调用 proxiableUUID 应因 UUPS notDelegated guard revert
# 该 revert 不应导致 readiness 失败
cast call $PROXY "proxiableUUID()(bytes32)" --rpc-url $RPC
```

**MemeverseLauncher：**

```bash
cast call $LAUNCHER_PROXY "owner()(address)" --rpc-url $RPC
# 应等于预期 owner 地址

cast call $LAUNCHER_PROXY "polend()(address)" --rpc-url $RPC
# 应等于 POLend proxy 地址

cast call $LAUNCHER_PROXY "polSplitter()(address)" --rpc-url $RPC
# 应等于 POLSplitter proxy 地址

cast call $LAUNCHER_PROXY "memeverseUniswapHook()(address)" --rpc-url $RPC
# 应等于 Hook proxy 地址

cast call $LAUNCHER_PROXY "memeverseRegistrar()(address)" --rpc-url $RPC
# 应等于 Registrar 地址

# bootstrapImpl：getLauncherContracts() 返回的 LauncherContracts 第 8 字段
cast call $LAUNCHER_PROXY "getLauncherContracts()" --rpc-url $RPC
# 返回的 LauncherContracts 中 bootstrapImpl 字段应为非零地址且有代码（即当前接线的 MemeverseBootstrap sibling）
# 可用 cast codehash $BOOTSTRAP_IMPL --rpc-url $RPC 二次确认非空
```

fee sibling 进 readiness check：`feeDistributorImpl`（`LauncherContracts` 第 10 字段）、`polMinterImpl`（第 12 字段）与 `feePreviewReader`（第 11 字段）由脚本 `_readLauncherImplSiblings` 取值后 `_requireContractCode` 校验非零且有代码，与 `bootstrapImpl` 对称（均为用户路径上使用的 delegatecall/view sibling：`::redeemAndDistributeFees` / `changeStage` Locked→Unlocked 会 delegatecall `feeDistributorImpl`，`::mintPOLToken` 会 delegatecall `polMinterImpl`，`feePreviewReader` 供链下预览）；未接线时 readiness 失败（`FEE_DISTRIBUTOR_IMPL_NOT_READY` / `POL_MINTER_IMPL_NOT_READY` / `FEE_PREVIEW_READER_NOT_READY`）、阻断 registration 打开，运行时 `FeeDistributorImplNotSet` / `POLMinterImplNotSet` 守卫仅作兜底。`[代码已证]`

**MemeverseUniswapHook：**

```bash
cast call $HOOK_PROXY "poolManager()(address)" --rpc-url $RPC
# 应等于 Uniswap V4 PoolManager 地址

cast call $HOOK_PROXY "launcher()(address)" --rpc-url $RPC
# 应等于 Launcher proxy 地址

cast call $HOOK_PROXY "owner()(address)" --rpc-url $RPC
# 应等于预期 owner 地址

cast storage $HOOK_PROXY \
  0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103 \
  --rpc-url $RPC
# 返回值低 20 bytes 应解析为 ProxyAdmin 地址

cast call $HOOK_PROXY_ADMIN "owner()(address)" --rpc-url $RPC
# 应等于 Hook owner 地址
```

**POLend：**

```bash
cast call $POLEND_PROXY "owner()(address)" --rpc-url $RPC
cast call $POLEND_PROXY "launcher()(address)" --rpc-url $RPC
# 应等于 Launcher proxy 地址

cast call $POLEND_PROXY "splitter()(address)" --rpc-url $RPC
# 应等于 POLSplitter proxy 地址
```

**POLSplitter：**

```bash
cast call $SPLITTER_PROXY "owner()(address)" --rpc-url $RPC
cast call $SPLITTER_PROXY "launcher()(address)" --rpc-url $RPC
# 应等于 Launcher proxy 地址
```

**Governor / Incentivizer：**

```bash
# Governor: 这些检查证明当前 proxy 仍连接到预期的治理模型。
cast call $GOVERNOR_PROXY "name()(string)" --rpc-url $RPC
# 返回预期 DAO 名称，证明读到的是目标 Governor proxy。

cast call $GOVERNOR_PROXY "token()(address)" --rpc-url $RPC
# 返回预期投票 token 地址，证明投票权来源未漂移。

cast call $GOVERNOR_PROXY "votingDelay()(uint256)" --rpc-url $RPC
# 返回预期投票延迟，证明提案创建后到投票开始的等待期正确。

cast call $GOVERNOR_PROXY "votingPeriod()(uint256)" --rpc-url $RPC
# 返回预期投票周期，证明投票窗口长度正确。

cast call $GOVERNOR_PROXY "proposalThreshold()(uint256)" --rpc-url $RPC
# 返回预期提案门槛，证明发起提案所需投票权正确。

cast call $GOVERNOR_PROXY "governanceCycleIncentivizer()(address)" --rpc-url $RPC
# 返回 Incentivizer proxy 地址，证明 Governor 指向正确的激励合约。

cast call $GOVERNOR_PROXY "upgradeSupermajorityRatio()(uint256)" --rpc-url $RPC
# 返回预期升级超级多数比例，证明 Governor 自升级提案的更高通过门槛未漂移。

cast call $GOVERNOR_PROXY "state(uint256)(uint8)" $PROPOSAL_ID --rpc-url $RPC
# Governor 升级提案执行完成后应返回 Executed，即 OpenZeppelin Governor enum 值 7。

# Incentivizer
cast call $INCENTIVIZER_PROXY "governor()(address)" --rpc-url $RPC
# 应等于 Governor proxy 地址
```

**功能性冒烟测试（可选但建议）：**

- 对 FeePreviewReader 调用 `quoteDistributionLzFee(verseId)`（地址取 `getLauncherContracts().feePreviewReader`）确认 fee 计算逻辑正常
- 对 Hook 调用 `getHookPermissions()` 确认 hook 权限配置正确
- 对 Governor 调用 `state(proposalId)` 确认治理状态机正常

`[代码已证]`

### 3.10 Hook + Engine 部署流程

部署脚本 `script/DeployMemeverseHookProxy.s.sol` 通过 OutrunDeployer（CREATE3）按序部署核心 proxy 与 helper artifacts：

1. LP token implementation（`UniswapLP`，无依赖 helper artifact）
2. Preorder settlement executor（`MemeversePreorderSettlementExecutor`，无依赖 helper artifact）
3. Engine 实现（`MemeverseDynamicFeeEngine`）
4. Engine proxy（`ERC1967Proxy`，initialize 绑定 hook owner + authorized hook，均为预测的 hook proxy 地址）
5. Hook 实现（`MemeverseUniswapHook`）
6. Hook proxy（`TransparentUpgradeableProxy`，initialize 绑定 owner/treasury/engine/lpTokenImplementation/preorderSettlementExecutor）

这些地址由 `(deployer, DEPLOYMENT_NONCE)` 唯一确定。同一 nonce 重跑是幂等的：已部署的同配置 proxy 与 helper artifact 会被复用，中间合约若已存在则 revert。

**所需环境变量**：

> 下表最后 5 个 `EXPECTED_*_CODEHASH` 仅在 **same-nonce 复用部署**（目标 nonce 的 hook proxy 已存在）时必需，任一未设脚本 `revert`（`Expected*CodehashNotSet`）；fresh 部署可全部省略。其余变量任何部署模式都必需。

| 变量 | 说明 |
| --- | --- |
| `PRIVATE_KEY` | 部署者私钥 |
| `OUTRUN_DEPLOYER` | 目标链 OutrunDeployer 地址 |
| `POOL_MANAGER` | 目标链 Uniswap v4 PoolManager 地址 |
| `HOOK_OWNER` | Hook proxy owner |
| `HOOK_TREASURY` | protocol fee 接收地址 |
| `DEPLOYMENT_NONCE` | 部署版本号，首次用 `0`，每次新部署递增 |
| `EXPECTED_HOOK_PROXY_CODEHASH` | 同 nonce 复用部署时校验 Hook proxy runtime 字节码 |
| `EXPECTED_HOOK_IMPLEMENTATION_CODEHASH` | 同 nonce 复用部署时校验 hook 实现字节码 |
| `EXPECTED_ENGINE_IMPLEMENTATION_CODEHASH` | 同 nonce 复用部署时校验 engine 实现字节码 |
| `EXPECTED_LP_TOKEN_IMPLEMENTATION_CODEHASH` | 同 nonce 复用部署时校验 `lpTokenImplementation` 字节码 |
| `EXPECTED_PREORDER_SETTLEMENT_EXECUTOR_CODEHASH` | 同 nonce 复用部署时校验 `preorderSettlementExecutor` 字节码 |

**`DEPLOYMENT_NONCE` 语义**：

- 嵌入所有 CREATE3 salt，决定 proxy、implementation 与 helper artifacts 的最终地址
- 同 nonce + 同配置 → 幂等复用
- 同 nonce + 不同配置 → revert（中间合约不可复用）
- 不同 nonce → 全新地址集
- same-nonce 复用验证必须覆盖 `lpTokenImplementation` 与 `preorderSettlementExecutor`。`DeploymentResult.lpTokenImplementation`、`DeploymentResult.preorderSettlementExecutor` 必须等于同 nonce 预测地址，且地址非零、有代码。
- `lpTokenImplementation` 与 `preorderSettlementExecutor` 的运行期 codehash 都必须等于预期值（分别对应 `EXPECTED_LP_TOKEN_IMPLEMENTATION_CODEHASH` 与 `EXPECTED_PREORDER_SETTLEMENT_EXECUTOR_CODEHASH`）；二者 readiness 只要求 codehash、地址与代码存在性匹配，不包含 pool-manager getter 检查。

**原子性保证**：

`run()` 和 `deployHookProxy()` 在单笔交易中执行全部 CREATE3 部署。任一步失败则整笔交易回滚，不会留下中间部署的僵尸合约，CREATE3 salt 也不会被消耗。

**⚠️ 禁止拆分部署步骤到多笔交易**。Engine proxy 在部署时立即以预测的 hook proxy 地址初始化（owner 和 authorizedHook 均为 hook proxy 地址）。这是因为 hook 的 `initialize()` 会验证 `engine.authorizedHook() == address(this)`，所以 engine 必须先于 hook 初始化。Hook proxy 地址在部署前已通过 CREATE3 salt 挖矿确定。

若将 engine proxy 部署和 hook proxy 部署拆成两笔交易，且第二笔失败，engine proxy 将永久绑定到一个不存在的 owner，无法恢复。

**失败恢复**：

在单笔交易的原子部署中，失败不会消耗 salt。若通过非标准方式（如手动拆分步骤）导致中间部署残留，该 nonce 下的 CREATE3 salt 已消耗，恢复方式为递增 `DEPLOYMENT_NONCE` 重新执行。残留的中间合约地址不会被新 nonce 覆盖，不影响新部署。

脚本为每个失败路径提供明确的错误类型（`Create3SaltConsumed`、`ExistingIntermediateDeploymentNotReusable`、`EngineImplementationCreate3SaltConsumed` 等），而非 solmate 默认的 `DEPLOYMENT_FAILED`。

### 3.11 返佣（Referral Rebate）运维

普通 swap 携带 referrer 时，protocol fee 切 rebate 到 engine custody；rebate 配置与领取独立于 hook 业务路径。

- **领取 rebate（referrer 主动）**：`MemeverseDynamicFeeEngine::claimRebate(currency, recipient)`。无 modifier，任何地址可作为 `recipient`；caller 是 referrer（`pendingRebate` 按 `msg.sender` 索引），`recipient` 非零。engine 无 `ReentrancyGuard`，`pendingRebate` 在 external transfer 前清零（CEI）。currency 与该 referrer 累计 rebate 的 protocol fee currency 一致（in-kind）。`pendingRebate` 是 `[referrer][token]` 二级 mapping 记账，engine 无批量 claim 入口；referrer 若在多 token 累积 rebate 须逐 token 调用 `claimRebate`。前端/SDK 应先从 `ReferralRebateAccrued` 事件历史聚合 distinct currency（`currency` 未 indexed，须扫全表），再对每个 currency 逐次调用 `claimRebate`。
- **查询未领 rebate**：`MemeverseDynamicFeeEngine::pendingRebateOf(referrer, currency)`（view）。注意 engine 持有的 token 余额 ≥ Σ 所有 referrer 的 `pendingRebate` 是返佣偿付能力不变量（见 [docs/spec/invariants.md](spec/invariants.md) INV-20）。
- **改返佣率**：`MemeverseUniswapHook::setReferrerRebateBps(bps)`（hook wrapper，`onlyOwner`）转发到 `MemeverseDynamicFeeEngine::setReferrerRebateBps`。engine 的 `onlyOwner` 是 hook proxy，因此 human governance owner 经 hook wrapper 调整。约束 `bps <= FeeMath.PROTOCOL_FEE_SHARE_BPS`（`3500`），否则 engine revert `RebateExceedsProtocolShare`。触发 `ReferrerRebateBpsUpdated(oldBps, newBps)`。
- **查询当前返佣率**：`MemeverseDynamicFeeEngine::referrerRebateBps()`（view）。engine `initialize` 默认 `1000`（10%）。
- **engine implementation 升级（`upgradeDynamicFeeEngineImplementation`）**：UUPS proxy storage 保留，`referrerRebateBps` 与 `pendingRebate` mapping 跨升级不丢。但若把一个老部署的 engine（在不含返佣逻辑的实现下 `initialize` 过，其 `referrerRebateBps == 0`）升级到含返佣的实现，`referrerRebateBps` 保留旧值 `0`，rebate 实际禁用（`_collectProtocolFee` 内 `rebateBps != 0` 检查不通过），须经 `data` migration calldata 或升级后调 `hook.setReferrerRebateBps(1000)` 显式激活。推荐升级 calldata：`abi.encodeCall(IMemeverseDynamicFeeEngine.setReferrerRebateBps, (1000))`。
- **engine pointer 替换（`upgradeDynamicFeeEngine`）**：换 engine proxy 实例，新 engine 的 dynamic fee state 从零开始（EWVWAP / volatility / short-impact 全 reset）。旧 engine 的 `pendingRebate` 不随之迁移：旧 engine 仍独立部署，其 `claimRebate` 不经 hook，referrer 仍可直接对旧 engine 调 `claimRebate` 领取存量 rebate。运维替换 engine 前应提示 referrer 先领旧 engine 上的 pending rebate，或接受存量 rebate 仍可经旧 engine claim（不会被销毁，只是不再增长）。`upgradeDynamicFeeEngine` 无 on-chain pending-rebate migration 守卫；这是接受的 trade-off（见设计 spec Trade-offs）。前端/SDK 默认读 `hook.dynamicFeeEngine()` 得到当前 engine 地址，对旧 engine 上的存量 rebate 不可见；要领取旧 engine 上的 pending rebate，须从 `DynamicFeeEngineUpdated(oldEngine, newEngine)` 事件历史回溯找旧 engine 地址（每次替换产生一条事件，多轮替换需沿事件链回溯），再直接对旧 engine 调 `claimRebate(currency, recipient)`。建议 engine 替换后前端缓存全部历史 engine 地址列表（含替换前的初始 engine）。
- **coverage**：返佣只在普通 swap（`_beforeSwap` / `_afterSwap`）路径触发；preorder settlement（`executePreorderSettlement`）不携带 referrer，不参与返佣。

#### 3.11.1 返佣相关 revert 条件

- `RebateExceedsProtocolShare`：`MemeverseUniswapHook::setReferrerRebateBps(bps)`（转发到 `MemeverseDynamicFeeEngine::setReferrerRebateBps`）当 `bps > FeeMath.PROTOCOL_FEE_SHARE_BPS`（`3500`）时触发，保证单次 swap 的 rebate ≤ protocol fee，不会透支 protocol share。`[代码已证]`
- `ERC20TransferFailed`：`MemeverseDynamicFeeEngine::claimRebate(currency, recipient)` 在 rebate token 的 `IERC20Minimal.transfer(recipient, amount)` 返回 `false`（非标准 ERC20 返回值或拒绝）时触发；CEI 下 `pendingRebate` 已先清零，整笔 revert 回滚清零，账本与余额同步。`[代码已证]`

#### 3.11.2 treasury 必须非零配置

- `treasury` 必须在 hook 上非零配置；`MemeverseUniswapHook::setTreasury` 已 reject 零地址。若 treasury 未配置或在运行期被清零（当前实现无 zero-address 清零路径，但运维侧若错误 retarget 到零地址），普通 swap 在 `_collectProtocolFee → _takeToTreasury` 处 `transfer` 到零地址会按非标准 ERC20 行为 revert；preorder settlement 在 `_collectPreorderSettlementInputFees` 直接 `transferFrom` 到 treasury，零地址同样 revert。`[代码已证]`

#### 3.11.3 `accrueRebate` 只在 swap unlock session 内可调

- `MemeverseDynamicFeeEngine::accrueRebate` 受 `onlyAuthorizedCaller` 保护，且 hook 仅在 `_beforeSwap` / `_afterSwap` 内调用该函数——此时 PoolManager 处于 unlock session。修复后 `accrueRebate` 是纯记账（`pendingRebate[referrer][currency] += amount` + emit，无 PoolManager 调用、无外部调用），不再有"engine 内部 `poolManager.take` 在非 unlock 上下文 revert"的问题；take 由 hook 在 `_collectProtocolFee` 内的 unlock session 中执行（v4 `PoolManager.take` delta 记调用者 hook，被 beforeSwap specifiedDelta credit 抵消），故 rebate accrual 仍与 swap 生命周期严格绑定（`onlyAuthorizedCaller` + hook 调用点均在 unlock 内）。`[代码已证]`

`[代码已证]`

## 4. 治理周期相关操作语义

- `finalizeCurrentCycle()` 是对外开放入口，时间到即可执行，不要求 `onlyGovernance`。`[代码已证]`
- `claimReward()`、`accumCycleVotes()`、token 注册/注销、reward ratio 修改等由 governor 路径调用（`onlyGovernance`）。`[代码已证]`

## 5. 观察与告警建议（最小集）

- 阶段机：`ChangeStage` + `RegisterMemeverse`
- 资金分发：`RedeemAndDistributeFees`、`OFTProcessed`
- 跨链 staking：`OmnichainMemecoinStaking`、`OmnichainMemecoinStakingProcessed`
- 配置变更：Launcher/Hook/RegistrationCenter 的 `Set*` 事件
- unlock 后保护：当前缺少专用事件，需结合 stage、时间与 swap/赎回行为联合判断

## 6. EVM 兼容性要求

- 部署链必须支持 **Cancun 硬分叉（EIP-1153 transient storage）** 或更新版本（Prague）。`[代码已证]`
- 编译目标：`foundry.toml` 中 `evm_version = "prague"`，`pragma solidity ^0.8.28`。编译器对 `transient` 关键字生成 `tload`/`tstore` 操作码，部署到 pre-Cancun 链上将导致所有涉及 `nonReentrant` 修饰符的函数直接 `invalid opcode` 回退。`[代码已证]`
- 受影响合约及使用点：
  - `ReentrancyGuard.nonReentrant`（`src/common/access/ReentrancyGuard.sol`：`bool private transient locked`）
  - `TokenHelper._transferOut`（`src/common/token/TokenHelper.sol::_transferOut`）
  - `MemeverseLauncher` 继承 `TokenHelper`（`src/verse/MemeverseLauncher.sol`）
  - `POLend` 直接继承 `ReentrancyGuard`（`src/polend/POLend.sol`）
  - `POLSplitter` 直接继承 `ReentrancyGuard`（`src/polend/POLSplitter.sol`）
  - `MemeverseUniswapHook` 直接继承 `ReentrancyGuard`（`src/swap/MemeverseUniswapHook.sol`）
- 行业对齐：OpenZeppelin v5.5+ 的 `ReentrancyGuardTransient` 同样声明 "This variant only works on networks where EIP-1153 is available"，v6.0 将把 transient 实现作为唯一 `ReentrancyGuard` 实现。本项目的自研 `ReentrancyGuard` 与 OZ 方向一致。`[代码已证]`
- `[未知]` 不在此文档范围内的目标链 Cancun 支持状态，需由部署方在部署前确认。

## 7. 确定性边界

- `[未知]`：生产环境 keeper 调度频率、告警阈值、重试策略、密钥托管方案，不在仓库代码内。
