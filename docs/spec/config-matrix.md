# MemeverseV2 配置矩阵（代码面 vs PRD 假设）

## 1. 说明

标签说明：

- `[代码已证]`：当前代码可直接验证
- `[PRD假设]`：文档叙事存在，但当前实现未完全对应
- `[未知]`：仓库内没有部署级最终值

## 2. 代码可配置面（当前真实生效）

| 模块 | 参数 | 写入方式 | 主要约束 | 作用范围 | 来源 |
| --- | --- | --- | --- | --- | --- |
| `MemeverseLauncher` | `memeverseSwapRouter` | `setMemeverseSwapRouter` | 非零；且必须满足 launch-settlement 双校验 | 启动建池、swap、LP、fee 路由 | `[代码已证]` |
| `MemeverseLauncher` | `lzEndpointRegistry` | `setLzEndpointRegistry` | 非零 | 注册 peer 配置、跨链 endpoint 映射 | `[代码已证]` |
| `MemeverseLauncher` | `memeverseRegistrar` | `setMemeverseRegistrar` | 非零 | 注册入口权限边界 | `[代码已证]` |
| `MemeverseLauncher` | `memeverseProxyDeployer` | `setMemeverseProxyDeployer` | 非零 | per-verse token/vault/governor 部署 | `[代码已证]` |
| `MemeverseLauncher` | `oftDispatcher` | `setOFTDispatcher` | 非零 | 本地费用分发落地 | `[代码已证]` |
| `MemeverseLauncher` | `fundMetaDatas[UPT] = {minTotalFund,fundBasedAmount}` | `setFundMetaData` | 两者非零；`fundBasedAmount <= 2^64-1` | Genesis 达标判断、首发 memecoin 量与初始价格 | `[代码已证]` |
| `MemeverseLauncher` | `executorRewardRate` | `setExecutorRewardRate` | `< 10000` | fee 分账（执行者奖励） | `[代码已证]` |
| `MemeverseLauncher` | `preorderCapRatio`,`preorderVestingDuration` | `setPreorderConfig` | 非零；`capRatio <= 10000` | preorder 容量和线性释放 | `[代码已证]` |
| `MemeverseLauncher` | `oftReceiveGasLimit`,`oftDispatcherGasLimit` | `setGasLimits` | 两者 `>0` | 远端分发 OFT options | `[代码已证]` |
| `MemeverseRegistrationCenter` | `supportedUPTs` | `setSupportedUPT` | UPT 非零 | 注册可用募资币种白名单 | `[代码已证]` |
| `MemeverseRegistrationCenter` | `min/maxDurationDays` | `setDurationDaysRange` | 非零，且 min < max | 注册 durationDays 校验 | `[代码已证]` |
| `MemeverseRegistrationCenter` | `min/maxLockupDays` | `setLockupDaysRange` | 非零，且 min < max | 注册 lockupDays 校验 | `[代码已证]` |
| `MemeverseRegistrationCenter` | `registerGasLimit` | `setRegisterGasLimit` | `>0` | center 向远端 registrar fan-out 的 receive gas | `[代码已证]` |
| `MemeverseRegistrarAtLocal` | `registrationCenter` | `setRegistrationCenter` | 非零 | 本地 registrar 信任中心地址 | `[代码已证]` |
| `MemeverseRegistrarOmnichain` | `registrationGasLimit`（base/local/omnichain） | `setRegistrationGasLimit` | owner-only（数值不做额外边界） | remote registrar -> center 的 quote/send gas 预算 | `[代码已证]` |
| `MemeverseUniswapHook` | `treasury` | `setTreasury` | 非零 | protocol fee 接收地址 | `[代码已证]` |
| `MemeverseUniswapHook` | `supportedProtocolFeeCurrencies[currency]` | `setProtocolFeeCurrency` / `setProtocolFeeCurrencySupport` | owner-only | 协议费币种选择（输入侧优先） | `[代码已证]` |
| `MemeverseUniswapHook` | `emergencyFlag` | `setEmergencyFlag` | owner-only | 动态费退化到 base fee | `[代码已证]` |
| `MemeverseUniswapHook` | `launchSettlementCaller` | `setLaunchSettlementCaller` | 非零 | hook 侧 launch-settlement 调用者授权 | `[代码已证]` |
| `MemeverseUniswapHook` | `defaultLaunchFeeConfig={start,min,decaySeconds}` | `setDefaultLaunchFeeConfig` | 全部非零；`min<=start<=10000` | 启动窗口费率衰减 | `[代码已证]` |
| `MemeverseOmnichainInteroperation` | `oftReceiveGasLimit`,`omnichainStakingGasLimit` | `setGasLimits` | 两者 `>0` | memecoin 远端 staking OFT options | `[代码已证]` |
| `MemeverseProxyDeployer` | `quorumNumerator` | `setQuorumNumerator` | 非零 | 仅影响后续新部署 governor 初始化 | `[代码已证]` |
| `GovernanceCycleIncentivizerUpgradeable` | `rewardRatio` | `updateRewardRatio` | `<=10000` | 周期结算时 treasury->reward 划拨比例 | `[代码已证]` |

## 3. 代码常量/不可变面（常被当作“默认配置”）

| 模块 | 参数 | 当前值 | 说明 | 来源 |
| --- | --- | --- | --- | --- |
| `MemeverseLauncher` | `RATIO` | `10000` | 比率基数 | `[代码已证]` |
| `MemeverseRegistrationCenter` | `DAY` | `180` 秒 | 注册时间单位（中心链实际生效） | `[代码已证]` |
| `MemeverseRegistrarAtLocal` | `DAY` | `24*3600` 秒 | 本地报价使用，不是最终权威写入 | `[代码已证]` |
| `MemeverseUniswapHook` | `PROTOCOL_FEE_RATIO_BPS` | `3000` | `feeBps` 中 protocol fee 占比 30% | `[代码已证]` |
| `MemeverseUniswapHook` | `TICK_SPACING` | `200` | 只接受该 tick spacing | `[代码已证]` |
| `MemeverseUniswapHook` | `LAUNCH_SETTLEMENT_FEE_BPS` | `100` | 启动结算固定 1% | `[代码已证]` |
| `MemeverseUniswapHook` | `defaultLaunchFeeConfig` 初始值 | `start=5000,min=100,decay=900s` | 构造时初始化，可后续改 | `[代码已证]` |
| `MemeverseSwapRouter` | `launchSettlementOperator` | 构造注入（immutable） | Router 侧 launch marker 权限 | `[代码已证]` |
| `MemeverseSwapRouter` | `hook`,`permit2` | 构造注入（immutable） | 外部依赖地址，部署后不可改 | `[代码已证]` |
| `GovernanceCycleIncentivizerUpgradeable` | `CYCLE_DURATION` | `90 days` | 治理周期长度 | `[代码已证]` |
| `MemecoinYieldVault` | `REDEEM_DELAY` | `1 days` | 赎回延迟 | `[代码已证]` |
| `MemecoinYieldVault` | `MAX_REDEEM_REQUESTS` | `5` | 每地址最大排队赎回数 | `[代码已证]` |

## 4. PRD 默认/假设与当前实现差异

| 主题 | PRD/衍生文档叙事 | 当前实现事实 | 结论 |
| --- | --- | --- | --- |
| anti-snipe request/soft-fail | 文档描述 `requestSwapAttemptWithQuote(...)`、soft-fail 及失败费路径 | Router/Hook 当前无该 request API，主路径为 execute-or-revert + launch fee 衰减 + launch-settlement marker | `[PRD假设]` 与实现不一致 |
| anti-snipe 时间单位 | PRD常以“区块窗口”叙述 | 代码使用 `decayDurationSeconds`（秒） | `[PRD假设]` 需按秒语义解读 |
| 注册天数语义 | PRD通常按自然日理解 | 中心链写入用 `DAY=180` 秒；本地 quote 用 24h | `[PRD假设]` 与当前链上存在偏差 |
| 异链 fee 判定 | PRD多处写“少于报价回退” | 关键路径要求 `msg.value == quotedFee` | 以代码为准 |

## 5. 确定性边界

- `[未知]`：每条链的真实部署地址、真实 owner/delegate、是否已改过上述配置，仓库内未提供最终清单。
- 本文中的“当前值”仅指仓库实现默认/构造参数语义，不等同于生产环境实时值。
