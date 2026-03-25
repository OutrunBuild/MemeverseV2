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
4. 术语基线：`docs/GLOSSARY.md`
5. 规则追溯与验证：`docs/TRACEABILITY.md`、`docs/VERIFICATION.md`
6. 文档治理决策背景：`docs/adr/0001-universalvault-style-harness-migration.md`
7. Subagent Harness 与流程细则：`docs/process/subagent-workflow.md`、`docs/process/*`
8. 生成文档输出：`docs/contracts/**`（仅生成产物，不是产品/流程真源）

## 关于 `docs/contracts`

- 生成入口：`script/process/generate-docs.sh`
- 输出目录：`docs/contracts/**`
- 说明：该目录是生成结果，不应手工编辑，也不作为主文档系统或流程真源
