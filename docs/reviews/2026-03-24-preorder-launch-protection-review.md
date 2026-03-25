# 2026-03-24-preorder-launch-protection-review

> 本模板用于本地可选的 review 草稿。
> review note 正文默认使用简体中文。
> 为兼容现有 gate，请保留下列英文 section / field key，并只填写冒号后的内容。

## Scope（范围）
- 说明：用简体中文概述本次改动和实际审阅范围。
- Change summary: 该分支围绕 preorder / launch settlement 主流程继续收尾并补强文档质量：`MemeverseLauncher` 新增 preorder 入金、结算、退款和线性解锁领取；`MemeverseUniswapHook` 删除 anti-snipe 失败收费路径，改为按 launch 时间衰减的 fee floor，并允许受限 caller 走固定 1% 的 launch settlement 路径；`MemeverseSwapRouter` 改为 swap 只返回执行 delta，同时新增 launch settlement operator 约束；`registration`、`common`、`swap`、`yield`、`governance` 多个公开接口的 NatSpec 已按最终语义重新手工整理，去除了模板化说明并统一到可直接给集成方阅读的文案。
- Files reviewed: src/verse/MemeverseLauncher.sol; src/verse/interfaces/IMemeverseLauncher.sol; src/verse/interfaces/IMemeverseRegistrar.sol; src/verse/interfaces/IMemeverseRegistrarAtLocal.sol; src/verse/interfaces/IMemeverseRegistrarOmnichain.sol; src/verse/registration/MemeverseRegistrarAtLocal.sol; src/verse/registration/MemeverseRegistrarOmnichain.sol; src/verse/registration/MemeverseRegistrationCenter.sol; src/interoperation/MemeverseOmnichainInteroperation.sol; src/interoperation/OmnichainMemecoinStaker.sol; src/interoperation/interfaces/IMemeverseOmnichainInteroperation.sol; src/swap/MemeverseUniswapHook.sol; src/swap/MemeverseSwapRouter.sol; src/swap/interfaces/IMemeverseUniswapHook.sol; src/swap/interfaces/IMemeverseSwapRouter.sol; src/swap/tokens/UniswapLP.sol; src/governance/MemecoinDaoGovernorUpgradeable.sol; src/yield/MemecoinYieldVault.sol; src/yield/interfaces/IMemecoinYieldVault.sol; src/common/access/OutrunOwnableInit.sol; src/common/cryptography/OutrunEIP712Init.sol; src/common/interfaces/IBurnable.sol; src/common/omnichain/LzEndpointRegistry.sol; src/common/omnichain/interfaces/ILzEndpointRegistry.sol; src/common/omnichain/oapp/OutrunOAppCoreInit.sol; src/common/omnichain/oapp/OutrunOAppInit.sol; src/common/omnichain/oapp/OutrunOAppOptionsType3Init.sol; src/common/omnichain/oapp/OutrunOAppPreCrimeSimulatorInit.sol; src/common/omnichain/oapp/OutrunOAppReceiverInit.sol; src/common/omnichain/oft/IOFTCompose.sol; src/common/omnichain/oft/OutrunOFTCoreInit.sol; src/common/omnichain/oft/OutrunOFTInit.sol; src/common/token/OutrunERC20Init.sol; src/common/token/OutrunERC20PermitInit.sol; src/common/token/OutrunNoncesInit.sol; src/common/token/TokenHelper.sol; src/common/token/extensions/governance/OutrunERC20VotesInit.sol; src/common/token/extensions/governance/OutrunVotesInit.sol; src/token/MemeLiquidProof.sol; src/token/Memecoin.sol; src/verse/MemeverseOFTDispatcher.sol; src/verse/deployment/MemeverseProxyDeployer.sol; script/MemeverseScript.s.sol; test/swap/MemeverseSwapRouter.t.sol; test/swap/MemeverseSwapRouterInterface.t.sol; test/swap/MemeverseSwapRouterPermit2.t.sol; test/swap/MemeverseSwapRouterPermit2Invariant.t.sol; test/swap/MemeverseSwapRouterSettlementInvariant.t.sol; test/swap/MemeverseUniswapHookLaunchFeeInvariant.t.sol; test/swap/MemeverseUniswapHookLiquidity.t.sol; test/verse/MemeverseLauncherAssetFlowInvariant.t.sol; test/verse/MemeverseLauncherConfig.t.sol; test/verse/MemeverseLauncherEndToEndInvariant.t.sol; test/verse/MemeverseLauncherLifecycle.t.sol; test/verse/MemeverseLauncherPreorderIntegration.t.sol; test/verse/MemeverseLauncherPreorderInvariant.t.sol; test/verse/MemeverseLauncherRegistration.t.sol; test/verse/MemeverseLauncherViews.t.sol

## Impact（影响）
- 说明：保持 `yes` / `no` 取值不变，其余解释使用简体中文。
- Behavior change: yes
- ABI change: yes
- Storage layout change: yes
- Config change: yes

## Findings（发现）
- 说明：如果没有问题，保留 `- None: none`，其他发现可用简体中文补充。
- High findings: none
- Medium findings: none
- Low findings: none
- None: none
- Security review summary: 重点审阅了 preorder 资金归集、launch settlement caller 授权、claim vesting 线性释放、hook 费用结算与 router 的 exact-input/exact-output 约束。当前实现对 launch settlement 使用 hash marker 与双侧 caller/operator 限制，避免普通用户绕过公开 fee floor；preorder 领取依赖结算时间戳和累计已领数量，未见重复领取或提前领取路径；Genesis 失败后 preorder refund 与原 Genesis refund 分离，资金方向清晰。未发现新的权限绕过、重入、余额记账失衡或明显 DoS 面。
- Security residual risks: preorder 容量上限基于 `genesisFunds[verseId].totalMemecoinFunds` 的实时值，接入方如果在前端缓存旧容量，仍可能在链上因后续 Genesis/Preorder 并发写入而回滚；launch settlement 仍依赖部署时将 router/hook/launcher 的 settlement 相关地址配置一致，任何部署误配都会在 Genesis 结算时直接回滚。

## Simplification（简化评估）
- 说明：说明考虑过哪些更简单方案、最终采用什么、为什么拒绝其他方案。
- Candidate simplifications considered: 评估过是否保留 anti-snipe 分支并额外叠加 preorder 结算；评估过是否把 preorder 结算逻辑下沉到 router/hook；评估过是否把 vesting 改成一次性解锁。
- Applied: 当前方案删除 anti-snipe 请求/失败收费的多分支状态机，router `swap` 回到 execute-or-revert 语义，hook 只保留 launch fee floor 与受限 settlement 特例，整体调用面更收敛；preorder 账本集中在 launcher，便于复用现有 Genesis 生命周期。
- Rejected (with reason): 保留 anti-snipe 与 preorder 双轨会扩大 router/hook 的状态面并提高测试复杂度；把 preorder 结算下沉到 swap 层会让业务状态分散，难以直接复用 verse 生命周期；一次性解锁虽然更简单，但会改变设计目标，无法满足 preorder 的线性释放要求。

## Gas（Gas 评估）
- 说明：聚焦 gas-sensitive 路径、已做优化与剩余风险，命令、路径、selector 保持英文。
- Gas-sensitive paths reviewed: `MemeverseLauncher.preorder`; `MemeverseLauncher.claimablePreorderMemecoin`; `MemeverseLauncher.claimUnlockedPreorderMemecoin`; `MemeverseLauncher._settleLaunchPreorder`; `MemeverseUniswapHook._beforeSwap`; `MemeverseUniswapHook._afterSwap`; `MemeverseUniswapHook._applyLaunchFeeFloor`; `MemeverseSwapRouter._swap`
- Gas changes applied: 删除 anti-snipe per-block attempt 记录、失败收费 quote 和 router soft-fail 三元返回后，swap 路径的分支和状态写入显著减少；preorder 采用聚合 `PreorderState` 与用户累计 claim 计数，避免逐次 settlement 记录；本轮 NatSpec 精修仅调整注释文本，不引入额外运行时 gas 变化。
- Gas snapshot/result: `npm run quality:gate` 已通过，其中包含 `bash ./script/process/check-gas-report.sh`；本次变更未暴露新的 gas gate 失败项。
- Gas residual risks: launch fee 衰减使用 `wadExp`，在 launch 初期 quote/beforeSwap 的数学成本高于固定费率；preorder claim 每次都需要读取 settlement 状态并做比例计算，但该路径是用户主动领取路径，频率可接受。

## Docs（文档）
- 说明：路径、命令、文件名保持英文，原因说明使用简体中文。
- Docs updated: none
- Why these docs: 本次没有新增仓库文档，接口与行为变化主要通过 NatSpec、测试和本地 review note 说明。
- No-doc reason: 本次不需要额外生成文档目录；最终通过 `npm run docs:check` 验证文档链即可。

## Tests（测试）
- 说明：测试路径、selector、命令保持英文，说明文字使用简体中文；如果命中 `rule-map.json` 的正式规则，`Existing tests exercised` 需要显式写出对应映射测试路径。
- Tests updated: test/swap/MemeverseSwapRouter.t.sol; test/swap/MemeverseSwapRouterInterface.t.sol; test/swap/MemeverseSwapRouterPermit2.t.sol; test/swap/MemeverseSwapRouterPermit2Invariant.t.sol; test/swap/MemeverseSwapRouterSettlementInvariant.t.sol; test/swap/MemeverseUniswapHookLaunchFeeInvariant.t.sol; test/swap/MemeverseUniswapHookLiquidity.t.sol; test/verse/MemeverseLauncherAssetFlowInvariant.t.sol; test/verse/MemeverseLauncherConfig.t.sol; test/verse/MemeverseLauncherEndToEndInvariant.t.sol; test/verse/MemeverseLauncherLifecycle.t.sol; test/verse/MemeverseLauncherPreorderIntegration.t.sol; test/verse/MemeverseLauncherPreorderInvariant.t.sol; test/verse/MemeverseLauncherRegistration.t.sol; test/verse/MemeverseLauncherViews.t.sol
- Existing tests exercised: test/swap/MemeverseSwapRouter.t.sol; test/swap/MemeverseSwapRouterPermit2.t.sol; test/swap/MemeverseSwapRouterInterface.t.sol; test/swap/MemeverseUniswapHookLiquidity.t.sol; test/verse/MemeverseLauncherLifecycle.t.sol; test/verse/MemeverseLauncherConfig.t.sol; test/verse/MemeverseLauncherRegistration.t.sol; test/verse/MemeverseLauncherViews.t.sol; test/swap/MemeverseSwapRouterPermit2Invariant.t.sol; test/swap/MemeverseSwapRouterSettlementInvariant.t.sol; test/swap/MemeverseUniswapHookLaunchFeeInvariant.t.sol; test/verse/MemeverseLauncherAssetFlowInvariant.t.sol; test/verse/MemeverseLauncherEndToEndInvariant.t.sol; test/verse/MemeverseLauncherPreorderIntegration.t.sol; test/verse/MemeverseLauncherPreorderInvariant.t.sol
- No-test-change reason: 已补充 router/hook/launcher 的单测、集成测试与 invariant，不属于无测试改动。

## Verification（验证）
- 说明：命令保持英文；结果总结使用简体中文。
- Commands run: `git diff --name-only main..preorder-launch-protection`; `git merge --no-commit --no-ff preorder-launch-protection`; `bash ./script/process/check-natspec.sh test/swap/MemeverseSwapRouter.t.sol test/swap/MemeverseSwapRouterPermit2.t.sol test/swap/MemeverseSwapRouterInterface.t.sol test/swap/MemeverseUniswapHookLiquidity.t.sol test/verse/MemeverseLauncherLifecycle.t.sol test/verse/MemeverseLauncherConfig.t.sol test/verse/MemeverseLauncherRegistration.t.sol test/verse/MemeverseLauncherViews.t.sol`; `npm run quality:gate`
- Results: 分支可无冲突合并到 `main`；定向 NatSpec 检查确认 rule-map 要求的 8 个测试文件已满足 gate；最新一轮 `npm run quality:gate` 通过，覆盖了 changed-file `forge fmt --check`、`check-natspec.sh`、`forge build`、`forge test -vvv`、`check-slither.sh`、`check-gas-report.sh`、`check-solidity-review-note.sh` 和 `npm run docs:check`。

## Decision（结论）
- 说明：`Ready to commit` 只能填写 `yes` 或 `no`，风险描述使用简体中文。
- Ready to commit: yes
- Residual risks: 运行时仍依赖部署时的 preorder 参数、router operator 与 hook settlement caller 配置保持一致；这属于环境配置风险，不是当前代码 gate 暴露的问题。NatSpec 已统一到最新实现语义，但后续如果继续改公开接口行为，仍需要同步维护说明文本避免再次漂移。
