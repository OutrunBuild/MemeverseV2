## Scope
- Task 1: Router 新增 `getHookPoolKey` 与 `previewClaimableFees` 只读入口
- Task 2: `MemeverseLauncher.previewGenesisMakerFees` 改为走 Router 预览并恢复校验
- 对应测试：
- `test/MemeverseSwapRouter.t.sol`
- `test/MemeverseLauncherPreviewFees.t.sol`

## Findings
- No issues found.

## Simplification
- Considered: 复用 `getHookPoolKey` 做内部调用以避免重复排序逻辑。
- Decision: 已采用（`getHookPoolKey` 设为 `public`，`previewClaimableFees` 直接调用）。

## Verification
- `forge test --match-test testRouterGetHookPoolKey_ReturnsDynamicHookKey -vvv`
- `forge test --match-test testRouterPreviewClaimableFees_MatchesHookClaimableFees -vvv`
- `forge test --match-test testPreviewGenesisMakerFees_MapsFeesCorrectly -vvv`
- `forge test --match-test testPreviewGenesisMakerFees_RevertsWhenNotLocked -vvv`

## Decision
- Approved for Task 1-2 changes.
