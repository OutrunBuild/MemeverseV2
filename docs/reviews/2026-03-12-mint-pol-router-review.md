# 2026-03-12-mint-pol-router-review

## Scope（范围）
- 说明：用简体中文概述本次改动和实际审阅范围。
- Change summary: 为 `MemeverseSwapRouter` 与 `IMemeverseSwapRouter` 新增 `quoteAmountsForLiquidity(address,address,uint128)` 只读接口；在 `MemeverseLauncher.mintPOLToken` 中恢复 Router 化的预算型与 exact-liquidity 两条铸造路径；补充 Router quote 测试与 Launcher `mintPOLToken` 回归测试，并修正本次触达函数的 NatSpec。
- Files reviewed: `src/swap/interfaces/IMemeverseSwapRouter.sol`, `src/swap/MemeverseSwapRouter.sol`, `src/verse/MemeverseLauncher.sol`, `test/MemeverseSwapRouter.t.sol`, `test/MemeverseLauncherPreviewFees.t.sol`, `docs/memeverse-swap/memeverse-swap-integration.md`

## Impact（影响）
- 说明：保持 `yes` / `no` 取值不变，其余解释使用简体中文。
- Behavior change: yes
- ABI change: yes
- Storage layout change: no
- Config change: no

## Findings（发现）
- 说明：如果没有问题，保留 `- None: none`，其他发现可用简体中文补充。
- High findings:
- Medium findings:
- Low findings:
- None: none

## Simplification（简化评估）
- 说明：说明考虑过哪些更简单方案、最终采用什么、为什么拒绝其他方案。
- Candidate simplifications considered: 让 Launcher 直接读取 Hook / `poolManager` 自己做 exact-liquidity quote；只恢复 `amountOutDesired == 0` 的预算型路径，不支持 exact-liquidity；在 Router 上新增新的 exact-liquidity 写接口而不是只读 quote。
- Applied: 仅在 Router 增加 `quoteAmountsForLiquidity(...)` 只读接口，继续复用现有 `addLiquidity(...)` 写入口，让 pair 归一化、当前池价读取和 liquidity 数学保持单一事实来源。
- Rejected (with reason): 不让 Launcher 直接拼 `PoolKey` 或读取 `poolManager`，避免把 Hook 细节重新泄漏到业务层；不新增额外写接口，因为 Launcher 真正缺的是 quote 能力，不是第二套 add-liquidity 执行入口。

## Docs（文档）
- 说明：路径、命令、文件名保持英文，原因说明使用简体中文。
- Docs updated: `docs/memeverse-swap/memeverse-swap-integration.md`
- Why these docs: `src/swap/` 发生行为与 ABI 变更，且 Launcher 新恢复的 `mintPOLToken` exact-liquidity 路径依赖 Router 新增的 pair helper，适合在现有 Router 集成文档中补充说明。
- No-doc reason: none

## Tests（测试）
- 说明：测试路径、selector、命令保持英文，说明文字使用简体中文。
- Tests updated: `test/MemeverseSwapRouter.t.sol|test/MemeverseLauncherPreviewFees.t.sol`
- Existing tests exercised: `test/MemeverseSwapRouter.t.sol`, `test/MemeverseLauncherPreviewFees.t.sol`, `test/MemeverseSwapRouterInterface.t.sol`
- No-test-change reason: none

## Verification（验证）
- 说明：命令保持英文；结果总结使用简体中文。
- Commands run: `forge test --match-test testRouterQuoteAmountsForLiquidity_ReturnsRequiredPairAmounts -vvv`; `forge test --match-path test/MemeverseLauncherPreviewFees.t.sol`; `forge test --match-path test/MemeverseSwapRouterInterface.t.sol`; `forge fmt --check src/swap/MemeverseSwapRouter.sol src/swap/interfaces/IMemeverseSwapRouter.sol src/verse/MemeverseLauncher.sol test/MemeverseSwapRouter.t.sol test/MemeverseLauncherPreviewFees.t.sol`; `forge build`; `bash ./script/process/check-natspec.sh src/swap/MemeverseSwapRouter.sol src/swap/interfaces/IMemeverseSwapRouter.sol src/verse/MemeverseLauncher.sol test/MemeverseSwapRouter.t.sol test/MemeverseLauncherPreviewFees.t.sol`; `npm run docs:check`; `forge test -vvv`; `npm run quality:gate`
- Results: Router 定向 quote 测试、Launcher `mintPOLToken` 回归测试和 Router interface 测试通过；`forge fmt --check`、`forge build`、`check-natspec.sh`、`npm run docs:check`、`forge test -vvv` 全部通过；在把本次变更集暂存后运行 `npm run quality:gate`，结果为 `PASS`。

## Decision（结论）
- 说明：`Ready to commit` 只能填写 `yes` 或 `no`，风险描述使用简体中文。
- Ready to commit: yes
- Residual risks: exact-liquidity 路径依赖“quote 与 add 使用同一套 full-range 数学且同一交易内池价不变化”的前提；当前回归测试与全量 gate 已覆盖主路径，但未来若 Router 的 quote/add 数学分叉，需要同步补充一致性断言与测试。
