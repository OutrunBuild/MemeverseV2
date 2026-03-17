# 2026-03-17-outrunsafeerc20-review

## Scope（范围）
- 说明：用简体中文概述本次改动和实际审阅范围。
- Change summary: 将 `src/yield/libraries/OutrunSafeERC20.sol` 从旧的 `Address.functionCall` 路径改为对齐 OpenZeppelin v5.5 的 assembly `safeTransfer` / `safeTransferFrom` 实现，并把生产代码里仅依赖 `safeTransfer` / `safeTransferFrom` 的调用点从 OZ `SafeERC20` 切换到 `OutrunSafeERC20`；新增定向回归测试覆盖无代码 token 地址的失败语义；为通过仓库 NatSpec gate，补齐了两份 governance 合约中这次触达函数周边缺失的 NatSpec。
- Files reviewed: src/yield/libraries/OutrunSafeERC20.sol, src/common/token/TokenHelper.sol, src/governance/MemecoinDaoGovernorUpgradeable.sol, src/governance/GovernanceCycleIncentivizerUpgradeable.sol, src/common/omnichain/oapp/OutrunOAppSenderInit.sol, src/swap/MemeverseSwapRouter.sol, test/OutrunSafeERC20.t.sol, test/MemeverseSwapRouterInterface.t.sol

## Impact（影响）
- 说明：保持 `yes` / `no` 取值不变，其余解释使用简体中文。
- Behavior change: yes
- ABI change: no
- Storage layout change: no
- Config change: no

## Findings（发现）
- 说明：如果没有问题，保留 `- None: none`，其他发现可用简体中文补充。
- High findings: none
- Medium findings: none
- Low findings: 失败语义从 `AddressEmptyCode` 对齐为 `SafeERC20FailedOperation`，属于预期兼容性调整，已由回归测试覆盖；生产调用点同步切换后，若链下工具曾按旧 error selector 做精细分类，需要一起更新。
- None: none
- Security review summary: 本次改动仅替换 ERC20 低层调用库与 import/`using` 绑定，不改变业务授权、外部调用顺序、状态写入路径、升级入口或资金流向。`TokenHelper`、Governor、Incentivizer、OApp sender 与 Router 的调用位点仍然只使用 `safeTransfer` / `safeTransferFrom`，与当前 `OutrunSafeERC20` 暴露的能力完全一致。assembly 逻辑直接对齐 OZ v5.5 的两条核心路径，保留对返回值为空、返回 `true`、返回 `false` 与目标无代码地址的安全判定。
- Security residual risks: `OutrunSafeERC20` 目前仍未实现 `forceApprove`、`safeIncreaseAllowance`、`safeDecreaseAllowance` 等扩展接口，因此后续若有新调用点需要这些能力，不能机械继续替换；本次已切换文件不受该限制。

## Simplification（简化评估）
- 说明：说明考虑过哪些更简单方案、最终采用什么、为什么拒绝其他方案。
- Candidate simplifications considered: 1) 继续保留 `abi.encodeCall + Address.functionCall`；2) 直接在两个公开函数内联 assembly；3) 一次性把整个 OZ v5.5 `SafeERC20` API 全量搬入；4) 保留 OZ `SafeERC20` 与 `OutrunSafeERC20` 双栈并存。
- Applied: 采用两个私有 assembly helper 复用 `safeTransfer` / `safeTransferFrom` 的判定逻辑，移除 `Address` 依赖；同时把生产代码里仅依赖这两个接口的调用点统一切到 `OutrunSafeERC20`，减少双栈并存。
- Rejected (with reason): 拒绝继续使用 `Address.functionCall`，因为目标是对齐当前 OZ v5.5 的汇编路径；拒绝在公开函数内联重复 assembly，因为可读性更差；拒绝全量扩展全部 OZ API，因为当前仓库未使用那些接口，会扩大本次 diff 和审阅面；拒绝继续长期保留双栈并存，因为当前生产调用面已经满足统一条件，保留双栈只会增加维护成本。

## Gas（Gas 评估）
- 说明：聚焦 gas-sensitive 路径、已做优化与剩余风险，命令、路径、selector 保持英文。
- Gas-sensitive paths reviewed: OutrunSafeERC20.safeTransfer, OutrunSafeERC20.safeTransferFrom, TokenHelper token transfer helpers, MemecoinDaoGovernorUpgradeable treasury transfers, GovernanceCycleIncentivizerUpgradeable reward transfers, OutrunOAppSenderInit._payLzToken, MemeverseSwapRouter LP token pull path
- Gas changes applied: 用 OZ v5.5 风格的 assembly `call` 路径替换 `abi.encodeCall`、`Address.functionCall` 和 `bytes memory returndata` 分配，减少包装层与内存处理；生产调用点统一到同一轻量库实现，避免继续链接 OZ `SafeERC20` 路径。
- Gas snapshot/result: `forge test --match-path test/OutrunSafeERC20.t.sol` 中，`testSafeTransferRevertsWithSafeERC20FailedOperationForAddressWithoutCode` gas 从 12115 降到 11990；`testSafeTransferFromRevertsWithSafeERC20FailedOperationForAddressWithoutCode` gas 从 12123 降到 11973。全量 `quality:gate` 通过，未出现因替换导致的 gas gate 异常。
- Gas residual risks: 当前定量 gas 证据仍以库级失败路径为主，未额外产出各生产入口在成功路径上的逐函数前后基准。

## Docs（文档）
- 说明：路径、命令、文件名保持英文，原因说明使用简体中文。
- Docs updated: docs/reviews/README.md
- Why these docs: 补充 CI 专用 review note 的使用约定，避免后续再因 `.gitignore` 与 workflow 配置不一致导致 gate 失败。
- No-doc reason: none

## Tests（测试）
- 说明：测试路径、selector、命令保持英文，说明文字使用简体中文；如果命中 `rule-map.json` 的正式规则，`Existing tests exercised` 需要显式写出对应映射测试路径。
- Tests updated: test/OutrunSafeERC20.t.sol, test/MemeverseSwapRouterInterface.t.sol, script/process/tests/ci-workflow.sh
- Existing tests exercised: test/OutrunSafeERC20.t.sol, test/MemeverseSwapRouterInterface.t.sol, test/MemeverseSwapRouter.t.sol, test/MemeverseSwapRouterPermit2.t.sol, test/MemeverseUniswapHookLiquidity.t.sol, test/MemeverseLauncherPreviewFees.t.sol, test/MemecoinYieldVault.t.sol, script/process/tests/ci-workflow.sh
- No-test-change reason: none

## Verification（验证）
- 说明：命令保持英文；结果总结使用简体中文。
- Commands run: bash script/process/tests/ci-workflow.sh; forge test --match-path test/OutrunSafeERC20.t.sol; forge test --match-path test/MemeverseSwapRouterInterface.t.sol; forge build; QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST=/tmp/outrunsafeerc20-replace-files.txt QUALITY_GATE_REVIEW_NOTE=docs/reviews/2026-03-17-outrunsafeerc20-review.md npm run quality:gate
- Results: CI workflow 自检先红后绿，确认工作流已配置 `QUALITY_GATE_REVIEW_NOTE` 且 CI 专用 review note 可通过格式校验。`OutrunSafeERC20` 的库级回归测试与 router 接口稳定性测试均通过，`forge build` 通过，显式 file-list 模式下 `quality:gate` 全部通过。

## Decision（结论）
- 说明：`Ready to commit` 只能填写 `yes` 或 `no`，风险描述使用简体中文。
- Ready to commit: yes
- Residual risks: `docs/reviews/CI_REVIEW_NOTE.md` 现在是可跟踪文件，后续每次命中 `src/**/*.sol` 的变更都需要同步更新它；否则 CI 会继续失败。
