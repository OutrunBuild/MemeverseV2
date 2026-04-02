# 2026-03-19-launcher-swap-test-reorg-review

## Scope（范围）
- 说明：用简体中文概述本次改动和实际审阅范围。
- Change summary: 1) 将原先散落在 `test/` 根目录下的 swap、launcher、yield、price calculator 等测试迁移到与源码目录一致的子目录，并同步更新 `docs/process/rule-map.json`，避免路径门禁继续引用已删除测试；2) 为 `MemeverseLauncher`、`MemeverseSwapRouter`、`MemeverseUniswapHook` 补充行为分支测试并重构测试结构，重点覆盖 launcher 生命周期/费用分发/POL mint、router swap 与 add/remove liquidity、hook remove-liquidity recipient 路径；3) 修复 `MemeverseUniswapHook.removeLiquidityCore` 在 `recipient != msg.sender` 时把底层资产错误先发给调用者、再尝试从 hook 二次转发的 bug，并对若干测试做了只影响可维护性的简化。
- Files reviewed: docs/process/rule-map.json, src/swap/MemeverseSwapRouter.sol, src/swap/MemeverseUniswapHook.sol, src/verse/MemeverseLauncher.sol, test/swap/MemeverseSwapRouter.t.sol, test/swap/MemeverseSwapRouterPermit2.t.sol, test/swap/MemeverseSwapRouterInterface.t.sol, test/swap/MemeverseUniswapHookLiquidity.t.sol, test/swap/MemeverseDynamicFeeSimulation.t.sol, test/verse/MemeverseLauncherLifecycle.t.sol, test/verse/MemeverseLauncherConfig.t.sol, test/verse/MemeverseLauncherRegistration.t.sol, test/verse/MemeverseLauncherViews.t.sol, test/verse/libraries/InitialPriceCalculator.t.sol, test/yield/MemecoinYieldVault.t.sol, test/yield/libraries/OutrunSafeERC20.t.sol
- Task Brief path: docs/task-briefs/2026-03-31-follow-up-router-refund-simplification-fixed-unlock-window.md
- Agent Report path: docs/agent-reports/2026-03-31-solidity-implementer-follow-up-router-refund-simplification-fixed-unlock-window.md
- Implementation owner: solidity-implementer
- Writer dispatch confirmed: yes
- Semantic dimensions reviewed: swap settlement semantics, liquidity recipient semantics, launcher lifecycle / fee distribution semantics, rule-map evidence alignment
- Source-of-truth docs checked: docs/spec/protocol.md, docs/spec/state-machines.md, docs/spec/accounting.md, docs/spec/access-control.md, docs/spec/implementation-map.md
- External facts checked: not needed; this review pass only depended on local Memeverse control flow and rule-map coverage facts
- Local control-flow facts checked: `MemeverseUniswapHook.removeLiquidityCore` now routes the recipient directly through `_modifyLiquidity(...)`; launcher/router refactors were checked to preserve access control, fee distribution entrypoints, slippage guards, and revert-path behavior
- Evidence chain complete: yes
- Semantic alignment summary: local code paths, mapped tests, and review-note evidence all align on “hook recipient bug fixed, launcher/router semantics preserved, rule-map paths updated to the new test layout”

## Impact（影响）
- 说明：保持 `yes` / `no` 取值不变，其余解释使用简体中文。
- Behavior change: yes
- ABI change: no
- Storage layout change: no
- Config change: yes

## Findings（发现）
- 说明：如果没有问题，保留 `- None: none`，其他发现可用简体中文补充。
- High findings: none
- Medium findings: none
- Low findings: `test/swap/MemeverseDynamicFeeSimulation.t.sol` 仍保留大量 `console.log` 诊断输出，会增加本地阅读噪音，但不影响协议行为或 gate 结果。
- None: none
- Logic review summary: 本次生产代码改动的语义主线只有两类：一是 `MemeverseSwapRouter` / `MemeverseLauncher` 的内部流程拆分和测试重组；二是 `MemeverseUniswapHook.removeLiquidityCore` 在差异接收者场景下的真实资金接收者修正。按 Task Brief 里的语义维度回扫后，控制流仍保持“预算校验/授权校验先于状态推进或外部交互”的顺序，hook 的 liquidity 赎回资产现在直接按 `params.recipient` 落地，不再依赖中间余额二次转发；新增和迁移后的测试也继续对齐这个语义。
- Logic residual risks: launcher / router 的分支仍然偏多，后续如果继续改 quote、settlement、register 或 distribute 相关路径，最容易漏的是“路径虽然仍 revert/通过，但 revert 原因或接收者语义漂移”；因此后续改动仍应保留针对具体状态转移和 recipient 行为的定向测试。
- Logic evidence source: logic-reviewer: docs/reviews/CI_REVIEW_NOTE.md
- Security review summary: `MemeverseSwapRouter.sol` 与 `MemeverseLauncher.sol` 的生产改动本质上是内部流程拆分与职责下沉，没有改变访问控制、可调用入口、参数校验顺序或资金流向约束；对应新增测试确认 exact-liquidity 预算保护、pause/owner 权限、slippage/revert 原因和费用路径仍符合预期。`MemeverseUniswapHook.sol` 的改动则是实质 bugfix：`removeLiquidityCore` 现在直接在 `_modifyLiquidity(...)` 时把接收者设为 `params.recipient`，避免 `recipient != msg.sender` 时先把资产发送给调用者、再从 hook 余额二次转发导致错误或资产走向不符的问题。该路径已由 `test/swap/MemeverseUniswapHookLiquidity.t.sol` 的差异接收者用例覆盖。
- Security residual risks: 当前 worktree 里与本次提交一起收尾的 Solidity 改动主要是 refactor + 单点 bugfix，未发现新的高风险授权或重入面；残余风险主要在业务分支仍然复杂，后续如继续改 launcher/redeem/distribute 或 router quote/swap 路径，仍需维持行为测试而不是依赖覆盖率数字。
- Open safety mismatches assessed: SAFE-UNLOCK-01: still open
- Security evidence source: security-reviewer: docs/reviews/CI_REVIEW_NOTE.md

## Simplification（简化评估）
- 说明：说明考虑过哪些更简单方案、最终采用什么、为什么拒绝其他方案。
- Candidate simplifications considered: 1) 保留根目录测试文件不动，只继续叠加新测试；2) 继续用大量裸 `vm.expectRevert()` 追求写测试速度；3) 为减少样板引入低层 `call`/selector 驱动的“万能测试 helper”；4) 只按 coverage 缺口机械补测。
- Applied: 采用“按源码目录分组、每个主合约单文件测试”的结构；将多个关键测试里的裸 `expectRevert()` 收紧为明确 selector；在不损失可读性的前提下，抽取小型 setup/helper，例如 launcher views 的 `_baseVerse(...)`、interoperation 的本地/远程 verse setup，以及 launcher config 的地址 setter 公共断言 helper。
- Rejected (with reason): 拒绝继续保留根目录旧文件，因为会与路径门禁和源码目录结构脱节；拒绝把任意 revert 都写成“只要 revert 就算通过”，因为会掩盖错误原因漂移；拒绝使用过度抽象的动态 helper，因为会降低测试直观性；拒绝只为刷 branch coverage 写无业务价值测试，因为用户目标是防止 bug、漏洞和回归。

## Gas（Gas 评估）
- 说明：聚焦 gas-sensitive 路径、已做优化与剩余风险，命令、路径、selector 保持英文。
- Gas-sensitive paths reviewed: MemeverseSwapRouter._addLiquidity / addLiquidityCore settlement path, MemeverseUniswapHook.removeLiquidityCore, MemeverseLauncher.mintPOLToken / registerMemeverse
- Gas changes applied: 本次 Solidity 改动没有刻意做微观 gas 优化，重点是把长函数拆成可审阅的内部 helper 并修正 hook recipient 语义；router 与 launcher 的重构理论上引入少量内部调用跳转，但没有新增外部调用或额外存储写路径。
- Gas snapshot/result: 在 `QUALITY_GATE_MODE=ci` + 完整 changed file list 下，`bash ./script/process/quality-gate.sh` 已执行 through `check-gas-report.sh` 并最终 PASS。gas report 过程中出现的是 Foundry lint 级别 warning / note（例如测试里的 unchecked ERC20 transfer 与 unused import），没有把本次变更判为 gas gate 失败。
- Gas residual risks: 本次没有额外维护逐函数前后 snapshot 表，gas 结论主要来自仓库统一 gas gate 的通过结果；若后续要继续做性能优化，仍建议单独以 snapshot diff 为中心。
- Gas evidence source: gas-reviewer: docs/reviews/CI_REVIEW_NOTE.md

## Docs（文档）
- 说明：路径、命令、文件名保持英文，原因说明使用简体中文。
- Docs updated: docs/process/rule-map.json, docs/reviews/CI_REVIEW_NOTE.md
- Why these docs: `rule-map.json` 必须跟随测试迁移更新，否则 `quality:quick` / `quality:gate` 会继续要求已删除路径；`CI_REVIEW_NOTE.md` 是本仓库 CI 默认读取的 review note，当前 diff 触达 `src/**/*.sol` 时必须同步更新。
- No-doc reason: none

## Tests（测试）
- 说明：测试路径、selector、命令保持英文，说明文字使用简体中文；如果命中 `rule-map.json` 的正式规则，`Existing tests exercised` 需要显式写出对应映射测试路径。
- Tests updated: test/swap/MemeverseSwapRouter.t.sol, test/swap/MemeverseSwapRouterPermit2.t.sol, test/swap/MemeverseSwapRouterInterface.t.sol, test/swap/MemeverseUniswapHookLiquidity.t.sol, test/swap/MemeverseDynamicFeeSimulation.t.sol, test/verse/MemeverseLauncherLifecycle.t.sol, test/verse/MemeverseLauncherConfig.t.sol, test/verse/MemeverseLauncherRegistration.t.sol, test/verse/MemeverseLauncherViews.t.sol, test/verse/libraries/InitialPriceCalculator.t.sol, test/yield/MemecoinYieldVault.t.sol, test/yield/libraries/OutrunSafeERC20.t.sol
- Existing tests exercised: test/swap/MemeverseSwapRouter.t.sol, test/swap/MemeverseSwapRouterPermit2.t.sol, test/swap/MemeverseSwapRouterInterface.t.sol, test/swap/MemeverseUniswapHookLiquidity.t.sol, test/swap/MemeverseDynamicFeeSimulation.t.sol, test/verse/MemeverseLauncherLifecycle.t.sol, test/verse/MemeverseLauncherConfig.t.sol, test/verse/MemeverseLauncherRegistration.t.sol, test/verse/MemeverseLauncherViews.t.sol, test/verse/libraries/InitialPriceCalculator.t.sol, test/yield/MemecoinYieldVault.t.sol, test/yield/libraries/OutrunSafeERC20.t.sol
- No-test-change reason: none

## Verification（验证）
- 说明：命令保持英文；结果总结使用简体中文。
- Commands run: npm run codex:review; forge test --summary; forge test --match-path test/verse/MemeverseLauncherViews.t.sol --summary; forge test --match-path test/verse/registration/MemeverseRegistrarAtLocal.t.sol --summary; forge test --match-path test/interoperation/MemeverseOmnichainInteroperation.t.sol --summary; forge test --match-path test/verse/MemeverseLauncherConfig.t.sol --summary; QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST=/tmp/memeverse_changed_files.txt QUALITY_GATE_REVIEW_NOTE=docs/reviews/CI_REVIEW_NOTE.md npm run quality:gate; QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST=/tmp/memeverse_changed_files_full.txt QUALITY_GATE_REVIEW_NOTE=docs/reviews/CI_REVIEW_NOTE.md bash ./script/process/quality-gate.sh; forge fmt --check src/swap/MemeverseSwapRouter.sol src/swap/MemeverseUniswapHook.sol src/verse/MemeverseLauncher.sol; bash ./script/process/check-natspec.sh src/swap/MemeverseSwapRouter.sol src/swap/MemeverseUniswapHook.sol src/verse/MemeverseLauncher.sol; QUALITY_GATE_MODE=ci QUALITY_GATE_FILE_LIST=/tmp/memeverse_changed_files_full.txt QUALITY_GATE_REVIEW_NOTE=docs/reviews/CI_REVIEW_NOTE.md bash ./script/process/quality-gate.sh
- Results: `forge test --summary` 与多轮定向测试均通过。由于当前环境中的 `.git` 目录是只读文件系统，`git add -A` 无法创建 `.git/index.lock`，因此无法按仓库默认 staged 模式跑 gate，只能退回 `QUALITY_GATE_MODE=ci` + 完整 changed file list 的等价校验。收尾过程中先后修复了三类 gate 阻塞：1) file list 未覆盖未跟踪的新测试；2) 迁移后测试文件未执行 `forge fmt`；3) 大量迁移测试缺失 NatSpec。修复后，`bash ./script/process/quality-gate.sh` 已在 CI 模式下完整跑通 `check-rule-map`、`forge fmt --check`、`check-natspec.sh`、`forge build`、`forge test -vvv`、`check-slither.sh`、`check-gas-report.sh`、`check-solidity-review-note.sh` 和 `npm run docs:check`，最终 PASS。
- Codex review summary: `npm run codex:review` 已执行，用于在 writer / specialist review 之后再扫一轮逻辑缺陷、边界条件与可简化点；本次未新增需要阻断提交的独立 finding。
- Codex review evidence source: verifier: npm run codex:review
- Verification evidence source: verifier: docs/reviews/CI_REVIEW_NOTE.md

## Decision（结论）
- 说明：`Ready to commit` 只能填写 `yes` 或 `no`，风险描述使用简体中文。
- Ready to commit: no
- Residual risks: 代码层面的 CI 模式 gate 已通过，当前唯一阻塞已经收敛到环境层：`.git` 是只读文件系统，无法创建 `.git/index.lock`，因此不能在这个会话里真正 `git add` / `git commit`，也无法拿到 staged 模式的本地 gate 证据。换到一个可写 `.git` 的环境后，应重新 `git add -A` 并再跑一次仓库默认 `npm run quality:gate`，然后再提交。
- Decision evidence source: main-orchestrator: docs/reviews/CI_REVIEW_NOTE.md
