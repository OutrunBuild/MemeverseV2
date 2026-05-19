# MemeverseV2 跨模块不变量（产品真相层）

## 1. 说明

本文只记录跨模块不变量（跨合约/跨子系统），用于测试与审计。  
标签说明：

- `[代码已证]`：可直接由当前 `src/**` 证明
- `[未知]`：仓库内缺少部署级证据

## 2. 不变量清单

### INV-01 注册写入链路是单入口

- 约束：`MemeverseLauncher.registerMemeverse(...)` 只能由 `memeverseRegistrar` 调用；注册中心与 registrar 只能作为上游入口。`[代码已证]`
- 价值：保证 verse 创建不会被任意地址绕过中心化校验路径。
- 主要锚点：`src/verse/MemeverseLauncher.sol:946`，`src/verse/registration/MemeverseRegistrarAbstract.sol:31-44`，`src/verse/registration/MemeverseRegistrationCenter.sol:150`

### INV-02 `memecoin -> verseId` 映射在注册时建立且后续不重写

- 约束：注册时写入 `memecoinToIds[memecoin] = uniqueId`，后续无 setter 可改该映射。`[代码已证]`
- 价值：跨模块按 memecoin 反查 verse 的主键语义稳定。
- 主要锚点：`src/verse/MemeverseLauncher.sol:962`

### INV-03 治理链统一取 `omnichainIds[0]`

- 约束：launcher 费用分发与 interoperation staking 都把 `omnichainIds[0]` 解释为治理链。`[代码已证]`
- 价值：避免“治理链”在不同模块使用不同索引。
- 主要锚点：`src/verse/MemeverseLauncher.sol:288`，`src/verse/MemeverseLauncher.sol:750`，`src/interoperation/MemeverseOmnichainInteroperation.sol:68`

### INV-04 启动结算必须走显式 `Launcher -> Hook` 结算路径

- 约束：
  - Launcher 在 preorder 结算时直接使用已配置且 write-once 的 `memeverseUniswapHook`，并显式调用 `executeLaunchSettlement(...)`。`[代码已证]`
  - Hook 侧要求 `msg.sender == launcher`，不再依赖 Router 特殊 `hookData` marker 或双调用者兼容接线。`[代码已证]`
  - Launcher 配置 router / hook 时会做 set-time 三重校验：`router.hook() == hook`、`hook.launcher() == launcher`、`hook.poolInitializer() == router`；同时 launcher 侧 hook 绑定是 write-once。`Genesis -> Locked` 执行建池前会做 launch-time preflight 复核，避免配置漂移到运行建池时才失败。`[代码已证]`
- 价值：防止任意调用者伪造启动结算路径，并避免 router / hook / launcher 绑定失配或 unlock 保护漂移到错误 hook namespace。
- 主要锚点：`src/verse/MemeverseLauncher.sol:594-608`，`src/swap/MemeverseUniswapHook.sol:572-627`，`src/verse/MemeverseLauncher.sol:1224-1240`

### INV-05 Locked 费用分发恒等式

- 约束：主池 `memecoin/uAsset` 的 `uAssetFee = executorReward + govFee`，其中 `executorReward` 必须按 full-precision `mulDiv` 或等价 overflow-safe 语义计算：`fullPrecisionMulDiv(uAssetFee, executorRewardRate, 10000)`，`govFee = uAssetFee - executorReward` 且减法保持 checked arithmetic 语义；quote/redeem 路径必须共享同一分账算术语义。主池 `memecoin` fee 进入 yield 路径。辅助池 fee 按 POLend 四池目标规则分流：POL fee burn，普通侧 `uAsset/PT` fee 进入普通领取账本，杠杆侧 `uAsset` fee 进入 governor treasury 路径，杠杆侧 `PT` fee 在 settle 前按固定 PT backing ratio 预兑付或 settle 后 redeem 后分发。`liquidProofFee` / `UPTFee` 仅作为 legacy alias。`[目标规范]`
- 价值：保证主池与辅助池 fee 分账守恒、burn 顺序和 PT fee pending/settle 语义可审计。
- 主要真源：[docs/spec/polend/polend.md](polend/polend.md)，[docs/spec/verse/accounting.md](verse/accounting.md)

### INV-06 远端分发与远端 staking 要求 `msg.value` 精确匹配报价

- 约束：跨链分发与跨链 staking 都不是“至少足额”，而是“严格等于报价”。`[代码已证]`
- 价值：调用方与脚本必须先 quote，再按精确值提交交易。
- 主要锚点：`src/verse/MemeverseLauncher.sol:791`，`src/interoperation/MemeverseOmnichainInteroperation.sol:123`

### INV-07 关键业务动作受阶段机约束

- 约束：`genesis/preorder` 仅 `Genesis`；`refund/refundPreorder` 仅 `Refund`；`claimNormalYT/claimNormalFees/mintPOLToken/redeemAndDistributeFees` 至少 `Locked`；LP 赎回仅 `Unlocked`。`[代码已证]`
- 价值：跨模块资金动作不会越阶段执行。
- 主要锚点：`src/verse/MemeverseLauncher.sol:326`，`:362`，`:627`，`:654`，`:729`，`:823`，`:849`

### INV-07A unlock settlement 期间普通赎回必须被 launcher 侧结算门阻断

- 约束：`changeStage()` 执行 `Locked -> Unlocked` 时，launcher 会在同一笔交易内先置 `unlockSettlementActive[verseId] = true`，完成 `POLSplitter.settle(...)`、可选 `POLend.executeGlobalSettlement(...)`、以及 hook 的公开 swap 保护写入后再清回 `false`。在该标志为 `true` 时：
  - `redeemAuxiliaryLiquidity` 必须回退；
  - `redeemMemecoinLiquidity` 对普通外部调用者必须回退；
  - 仅 `polSplitter` 与 `polend` 作为协议内 settlement caller 可继续走主池赎回路径。
- 价值：防止用户在 unlock settlement 正处理中抢先提取普通侧流动性，破坏结算与剩余份额基准。
- 主要锚点：`src/verse/MemeverseLauncher.sol:117`，`:441-447`，`:856`，`:1027-1061`

### INV-08 Router/Hook 只操作动态费池且固定 tickSpacing

- 约束：Router 构造的池 key 固定 `LPFeeLibrary.DYNAMIC_FEE_FLAG` 与 `tickSpacing=200`；Hook 初始化也要求同样约束。`[代码已证]`
- 价值：防止同一对资产被错误路由到非预期费率池。
- 主要锚点：`src/swap/MemeverseSwapRouter.sol:831-843`，`src/swap/MemeverseUniswapHook.sol:323-324`

### INV-09 代币增发权限集中在 Launcher

- 约束：`Memecoin.mint`、`MemePol.mint`、`MemePol.setPoolId` 仅 launcher 可调用。`[代码已证]`
- 价值：保证发行与 LP 凭证配置只通过 launcher 生命周期执行。
- 主要锚点：`src/token/Memecoin.sol:41-42`，`src/token/MemePol.sol:22`，`:54`，`:62`

### INV-10 OFT compose 回调具备 replay 防护

- 约束：`YieldDispatcher` 与 `OmnichainMemecoinStaker` 都在 endpoint 路径下检查 `guid` 未执行，再标记执行。`[代码已证]`
- 价值：跨链到账处理不可重复记账。
- 主要锚点：`src/verse/YieldDispatcher.sol:47-48`，`:60`，`src/interoperation/OmnichainMemecoinStaker.sol:40`，`:50`

### INV-11 注册时间权威值来自注册中心写入

- 约束：launcher 不自行重算 `endTime/unlockTime`，以 registrar 传入值为准；本地报价读取注册中心 `DAY`，中心写入为最终来源，并写入固定 `unlockTime = endTime + 365 days`。`[代码已证]`
- 价值：链上最终时间语义由中心写入决定，报价仅供参考。
- 主要锚点：`src/verse/MemeverseLauncher.sol:956-958`，`src/verse/registration/MemeverseRegistrarAtLocal.sol:12`，`:38-43`，`src/verse/registration/MemeverseRegistrationCenter.sol:22`，`:130`，`:135`

### INV-12 解锁后必须先经过保护窗口，再恢复公开 swap

- 约束：verse 在实际执行 `Locked -> Unlocked` 的 `changeStage()` 交易中，会按当时区块时间为受保护池写入 `publicSwapResumeTime = block.timestamp + 24 hours`。在该时刻之前，受保护的公开 swap 必须继续被阻断。`[代码已证]`
- 价值：保证 POL / genesis liquidity 的赎回公平性，并为 POL Lend / PT-YT 语义提供一致的全局结算窗口。
- 违反后果：先行动者可通过先赎回并抛售底层资产，把损失外部化给后续赎回者，造成用户重大亏损。`[产品安全要求]`
- 当前实现状态：保护窗口没有单独阶段，而是通过 `Stage.Unlocked + hook 按 pool-level resume time 阻断公开 swap` 落地；赎回路径与公开 swap 可用性由不同模块分离控制。保护窗口为固定 `24 hours` 产品常量，不再存在 owner 配置面。`[代码已证]`
- 主要锚点：`src/verse/MemeverseLauncher.sol:132-142`，`src/verse/MemeverseLauncher.sol:996-1000`，`src/swap/MemeverseUniswapHook.sol:309-377`

### INV-13 POLend 全局结算只能用 bounded reserve 覆盖 dust

- 约束：`settlementDustStates[uAsset].reserve <= settlementDustStates[uAsset].maxReserve` 必须始终成立。`maxReserve == 0` 表示该 `uAsset` 未完成 POLend reserve 配置，`POLend.registerLendMarket` 必须拒绝使用该 `uAsset` 的 verse。`[目标规范]`
- 约束：`POLend.executeGlobalSettlement(verseId)` 的债务偿还必须满足 `recoveredUAsset + consumedSettlementDustReserve >= verseDebt`。若 `recoveredUAsset < verseDebt`，则 `consumedSettlementDustReserve == verseDebt - recoveredUAsset`，且必须满足 `consumedSettlementDustReserve <= reserveBeforeSettlement`，其中 `reserveBeforeSettlement` 是执行前读取的 `settlementDustStates[uAsset].reserve` 快照。settlement 成功后只扣减实际消耗量，不清零该 `uAsset` 的全局 reserve。`[目标规范]`
- 约束：settlement dust reserve 只来自 `finalizeLeveragedGenesis` 已支付杠杆利息、`fundSettlementDustReserve(address,uint256)` 手动注入、Launcher bootstrap unused `uAsset` 注入；不得通过 mint、残值扣减、普通侧 LP 扣减或 treasury 隐式透支产生。`[目标规范]`
- 约束：settlement dust reserve 只覆盖正确执行 `previewPTToUAsset` 固定 backing ratio 转换后的整数舍入 dust；不得覆盖 PT backing ratio / 模型错误。`[目标规范]`
- 价值：C1 只允许 wei 级整数舍入缺口通过 reserve 解决，不把真实资不抵债、价格模型错误、PT backing ratio 错误或资金流错误伪装成 dust。
- 主要真源：[docs/spec/polend/polend.md](polend/polend.md)

### INV-14 POLend PT raw 与 uAsset backing 必须分离

- 约束：raw-unit identity 固定为 `POL raw = main pool LP raw`，`PT raw = POL raw`，`YT raw = POL raw`。`1 raw PT` 不等于 `1 raw uAsset`。`PT` 的 uAsset backing 必须使用 verse 固定 ratio：`FullMath.mulDiv(ptAmount, ptBackingNumerator, ptBackingDenominator)`。`[目标规范]`
- 约束：`preRedeemPTFee`、`redeemPT`、`redeemYT` 的 PT reserve、settle 时预兑付 backing burn、`POLend.executeGlobalSettlement` 回收 PT settlement 都必须使用转换后的 `uAsset` 数量，不得直接用 `ptAmount`。`[目标规范]`
- 约束：`Locked` 后 `mintPOLToken` 的实际 `uAsset` 输入必须等于 `previewPTToUAsset(newPOLRaw)`，误差 `<= 1 wei`；不得允许额外 backing。`[目标规范]`
- 价值：保证 `fundBasedAmount > 1` 等自然路径下 PT/YT 经济不被 raw 数量误当 uAsset 数量破坏。
- 主要真源：[docs/spec/polend/polend.md](polend/polend.md)

### INV-15 预兑付 PT fee 必须由真实 PT supply 结清

- 约束：`Locked` 阶段 `preRedeemPTFee` 的 `PT fee` 必须来自真实 `PT` supply；`Splitter.preRedeemPTFee` 必须 burn `Launcher` 持有的该部分 `PT`，并记录同一笔 `{ ptAmount, uAssetBacking }`。`[目标规范]`
- 约束：被 burn 的 `PT` 必须从后续 `PT.totalSupply()` 中移除；settlement 只为剩余 `PT.totalSupply()` 保留 backing。`settle()` 中扣 `preRedeemedPT.uAssetBacking` 是把已经提前 mint / distributed 给 governor 路径的 backing 从 `totalRedeemedUAsset` 中结清 / repay，不是重复扣 backing。`[目标规范]`
- 约束：settlement 必须满足 `totalRedeemedUAsset >= preRedeemedPT.uAssetBacking + previewPTToUAsset(PT.totalSupply())`；扣除 `preRedeemedPT.uAssetBacking` 后，才推出 `settlementUAsset >= previewPTToUAsset(PT.totalSupply())`。自然产品模型下，`preRedeemedPT.uAssetBacking > totalRedeemedUAsset` 或主池 `POL -> uAsset` 回收低于固定 PT backing 总需求属于 solvency / backing boundary failure，必须 revert / 被测试捕获，不能归类为合法预兑付缺口，也不是由 `preRedeemPTFee` 自身制造。`[目标规范]`
- 约束：`_captureLockedAuxiliaryFees` 在 unlock transaction 捕获的 pending `PT fee` 不进入 `preRedeemedPT`；该 `PT fee` 在 settled 后走 `redeemPT`，不得增加 settle 前扣减。`[目标规范]`
- 价值：保证提前分发给 governor 路径的 PT backing 与 settlement 结清一一对应，防止把伪造 supply 或主池回收不足解释为合法预兑付缺口。
- 测试证据：`testRealPathLockedPreRedeemPTFeeSettlementBacking` 覆盖 `genesis + leveragedGenesis -> Locked -> mintPOLToken -> split -> real PT transferred to hook -> redeemAndDistributeFees -> preRedeemPTFee -> unlock settlement`。
- 主要真源：[docs/spec/polend/polend.md](polend/polend.md)

### INV-16 normal fee entitlement 与 zero-backing dust 必须保持可领取语义

- 约束：普通侧 `claimNormalFees` 计算 `entitledUAsset` 与 `entitledPT` 时必须使用 full-precision `mulDiv`，不能因中间乘法溢出把已可表示的累计账本变成不可领取。`[代码已证]`
- 约束：普通侧 PT fee 在 `settled=false` 时直接转 `PT`；在 `settled=true` 时改走 `previewPTToUAsset -> redeemPT -> uAsset`。若 `previewPTToUAsset(...) == 0`，本次不得把该 PT 份额标记为已领，而要保持未领取状态等待后续重试。`[代码已证]`
- 约束：governor 路径的 `pending auxiliary gov PT fee` 也必须遵守同样的 zero-backing 保留语义；可分发的其它 `uAsset/memecoin/POL` fee 不因此被阻断。`[代码已证]`
- 价值：保证 normal fee 账本在大数情况下可领取，并保证 settling 后的 PT dust 不会被错误吞掉或提前记为已处理。
- 主要锚点：`src/verse/MemeverseLauncher.sol:808-842`，`:1588-1613`

## 3. 确定性边界

- 高确定性：以上不变量均有函数级源码锚点。
- `[未知]`：生产环境是否额外加多签/时锁/脚本守护进程，不在仓库源码证据范围内。
