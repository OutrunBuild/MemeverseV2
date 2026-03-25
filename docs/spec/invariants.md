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

### INV-04 启动结算特权路径必须双重通过

- 约束：`launch settlement` 需要同时满足：
  - Router 侧 `msg.sender == launchSettlementOperator`
  - Hook 侧 `sender == launchSettlementCaller`
  - Launcher 设置 router 时会校验 `launchSettlementOperator==launcher` 且 `launchSettlementCaller==router`。`[代码已证]`
- 价值：防止任意调用者伪造启动结算 marker。
- 主要锚点：`src/swap/MemeverseSwapRouter.sol:561-564`，`src/swap/MemeverseUniswapHook.sol:314-316`，`src/verse/MemeverseLauncher.sol:1164-1173`

### INV-05 Genesis 费用分发恒等式

- 约束：`UPTFee = executorReward + govFee`，其中 `executorReward = UPTFee * executorRewardRate / 10000`；`liquidProofFee` 必先 burn。`[代码已证]`
- 价值：保证 fee 分账守恒与 burn 顺序可审计。
- 主要锚点：`src/verse/MemeverseLauncher.sol:742-747`

### INV-06 远端分发与远端 staking 要求 `msg.value` 精确匹配报价

- 约束：跨链分发与跨链 staking 都不是“至少足额”，而是“严格等于报价”。`[代码已证]`
- 价值：调用方与脚本必须先 quote，再按精确值提交交易。
- 主要锚点：`src/verse/MemeverseLauncher.sol:791`，`src/interoperation/MemeverseOmnichainInteroperation.sol:123`

### INV-07 关键业务动作受阶段机约束

- 约束：`genesis/preorder` 仅 `Genesis`；`refund/refundPreorder` 仅 `Refund`；`claim/mint/fee-distribute` 至少 `Locked`；LP 赎回仅 `Unlocked`。`[代码已证]`
- 价值：跨模块资金动作不会越阶段执行。
- 主要锚点：`src/verse/MemeverseLauncher.sol:326`，`:362`，`:627`，`:654`，`:729`，`:823`，`:849`

### INV-08 Router/Hook 只操作动态费池且固定 tickSpacing

- 约束：Router 构造的池 key 固定 `LPFeeLibrary.DYNAMIC_FEE_FLAG` 与 `tickSpacing=200`；Hook 初始化也要求同样约束。`[代码已证]`
- 价值：防止同一对资产被错误路由到非预期费率池。
- 主要锚点：`src/swap/MemeverseSwapRouter.sol:1003-1010`，`src/swap/MemeverseUniswapHook.sol:289-290`

### INV-09 代币增发权限集中在 Launcher

- 约束：`Memecoin.mint`、`MemeLiquidProof.mint`、`MemeLiquidProof.setPoolId` 仅 launcher 可调用。`[代码已证]`
- 价值：保证发行与 LP 凭证配置只通过 launcher 生命周期执行。
- 主要锚点：`src/token/Memecoin.sol:41-42`，`src/token/MemeLiquidProof.sol:22`，`:54`，`:62`

### INV-10 OFT compose 回调具备 replay 防护

- 约束：`YieldDispatcher` 与 `OmnichainMemecoinStaker` 都在 endpoint 路径下检查 `guid` 未执行，再标记执行。`[代码已证]`
- 价值：跨链到账处理不可重复记账。
- 主要锚点：`src/verse/YieldDispatcher.sol:47-48`，`:60`，`src/interoperation/OmnichainMemecoinStaker.sol:40`，`:50`

### INV-11 注册时间权威值来自注册中心写入

- 约束：launcher 不自行重算 `endTime/unlockTime`，以 registrar 传入值为准；本地报价使用 `24*3600`，中心写入使用 `DAY=180` 秒常量。`[代码已证]`
- 价值：链上最终时间语义由中心写入决定，报价仅供参考。
- 主要锚点：`src/verse/MemeverseLauncher.sol:956-958`，`src/verse/registration/MemeverseRegistrarAtLocal.sol:12`，`:35-36`，`src/verse/registration/MemeverseRegistrationCenter.sol:22`，`:131`，`:145`

### INV-12 解锁后必须先经过保护窗口，再恢复公开 swap

- 约束：`unlockTime` 到达后，不得直接进入“可公开 swap + 可赎回”并存状态；必须先经过 `post-unlock liquidity protection period`。`[产品安全要求]`
- 价值：保证 POL / genesis liquidity 的赎回公平性，并为 POL Lend / PT-YT 语义提供一致的全局结算窗口。
- 违反后果：先行动者可通过先赎回并抛售底层资产，把损失外部化给后续赎回者，造成用户重大亏损。`[产品安全要求]`
- 当前实现状态：launcher 当前在 `unlockTime` 后直接进入 `Unlocked`，swap 层未见 unlock 后保护窗口，因此该不变量当前未落地。`[当前实现缺口]`
- 主要锚点：`src/verse/MemeverseLauncher.sol:397-399`，`src/verse/MemeverseLauncher.sol:823`，`src/verse/MemeverseLauncher.sol:849`，`src/swap/MemeverseSwapRouter.sol:544-564`

## 3. 确定性边界

- 高确定性：以上不变量均有函数级源码锚点。
- `[未知]`：生产环境是否额外加多签/时锁/脚本守护进程，不在仓库源码证据范围内。
