# MemeverseV2

MemeverseV2 是一个以 Foundry 为主的 Solidity 仓库，包含 verse 启动与生命周期、跨链注册、swap/hook、治理、收益与跨链互操作模块。

## 快速开始

```bash
git submodule update --init --recursive
npm install
npm run hooks:install
```

常用命令：

- `forge build`
- `forge test -vvv`
- `npm run quality:quick`
- `npm run quality:gate`
- `npm run docs:check`
- `npm run process:selftest`

## 文档导航（推荐顺序）

1. 主流程契约：`AGENTS.md`
2. 架构总览：`docs/ARCHITECTURE.md`
3. 产品真相核心规则：`docs/spec/*`（升级性规则主文档为 `docs/spec/upgradeability.md`）
   - 建议补充细读：`docs/spec/lifecycle-details.md`
   - 建议补充细读：`docs/spec/registration-details.md`
   - 建议补充细读：`docs/spec/governance-yield-details.md`
   - 建议补充细读：`docs/spec/interoperation-details.md`
   - 建议补充细读：`docs/spec/common-foundations.md`
4. 术语基线：`docs/GLOSSARY.md`
5. 规则追溯与验证：`docs/TRACEABILITY.md`、`docs/VERIFICATION.md`
6. 文档治理决策背景：`docs/adr/0001-universalvault-style-harness-migration.md`
7. Subagent Harness 与流程细则：`docs/process/subagent-workflow.md`、`docs/process/*`
