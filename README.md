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
2. Subagent Harness：`docs/process/subagent-workflow.md`
3. 流程细则与机器可读规则：`docs/process/*`
4. 生成文档输出：`docs/contracts/**`（仅生成产物，不是流程/产品真源）
5. 规划中的产品规则层（下一阶段路径，当前任务阶段尚未提供）：`docs/spec/protocol.md`

## 关于 `docs/contracts`

- 生成入口：`script/process/generate-docs.sh`
- 输出目录：`docs/contracts/**`
- 说明：该目录是生成结果，不应手工编辑，也不作为主文档系统或流程真源
