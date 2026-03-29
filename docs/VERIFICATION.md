# Verification Guide

## 1. 文档目的

本文档定义当前仓库的验证入口，服务对象是人工开发者与 AI coding agent。目标不是“改完就声称完成”，而是先收集可复验的命令证据，再给出结论。

## 2. 基本原则

- 证据先于结论。
- `npm run quality:quick` 只用于本地快速反馈，不是 finish gate。
- `npm run quality:gate` 是唯一 finish gate。
- 改动命中 `src/**/*.sol` 时，不能跳过 review note。
- 语义敏感改动不能跳过 source-of-truth、外部事实与关键假设收敛。
- 文档修改也至少要跑对应的最低验证命令。

## 3. 按改动类型选择命令

### 3.1 只改自然语言文档

最少运行：

```bash
npm run docs:check
```

建议补充：

```bash
rg --files docs | sort
git diff --stat
```

### 3.2 改 Harness / Process 文档或脚本

最少运行：

```bash
npm run docs:check
```

按需补充：

```bash
bash -n <changed-shell-scripts>
npm run process:selftest
```

说明：

- 命中 `AGENTS.md`、`docs/process/**`、`docs/reviews/TEMPLATE.md`、`.codex/**`、`.github/**`、`script/process/**` 时，不要只看文档表述，还要确认脚本入口和机器真源没有被文档改动带偏。
- 若仓库启用了额外机器真源（例如 `docs/process/rule-map.json`），验证时也必须确认它和人类文档没有漂移。

### 3.3 改 `src/**/*.sol`

默认要求：

- 先看 `AGENTS.md`、`docs/process/change-matrix.md` 与 `docs/process/policy.json`。
- 准备提交前，至少满足当前仓库 `quality:gate` 所要求的全部检查。
- 如果本次先跑定向命令做迭代，也必须在最终结论前补齐 finish gate 证据。

常见验证面：

```bash
forge fmt --check
bash ./script/process/check-natspec.sh <changed-src-solidity-files>
forge build
forge test -vvv
bash ./script/process/check-coverage.sh
bash ./script/process/check-slither.sh
bash ./script/process/check-gas-report.sh
bash ./script/process/check-solidity-review-note.sh
npm run docs:check
```

另外还要确认：

- 非直观方法已经补充适量的方法内注释，重点解释状态迁移、金额计算、权限前提与外部调用意图。
- 测试不只覆盖 happy path；至少覆盖失败路径与关键边界，高风险路径补齐适用的 fuzz、invariant、adversarial、integration 或 upgrade tests。
- 若仓库启用了额外证据映射（例如 `rule-map.json`），`Existing tests exercised` 等字段也已满足该映射规则。

### 3.4 改 `test/**/*.sol`

最少运行：

```bash
forge fmt --check
forge build
forge test -vvv
bash ./script/process/check-coverage.sh
```

还应确认：

- 本次测试覆盖了哪些风险边界。
- 是否已经包含适用的 unit、fuzz、invariant、integration、upgrade、adversarial 测试维度。
- 当前 `src/**` 的 coverage 是否仍满足仓库门禁。

### 3.5 改 `package.json`、CI 或工具链入口

最少运行：

```bash
npm ci
npm run docs:check
```

按需补充：

```bash
npm run process:selftest
```

## 4. 输出要求

验证结论至少要说明：

- 运行了哪些命令。
- 哪些通过，哪些失败。
- 如果失败，失败归因是什么。
- 本次是否达到 finish gate。

不要只写“已验证”或“测试通过”，必须给出具体命令。

## 5. 何时不能声称完成

以下任一情况存在时，不能把任务表述为“完成”：

- 必跑命令未执行。
- 命令失败但未解释。
- Solidity 改动缺 `security-reviewer` 或 `gas-reviewer` 结论。
- 语义敏感改动缺 source-of-truth、external facts、critical assumptions 的收敛结论。
- review note 缺失、字段不完整，或仍保留占位值。
- 结论与命令输出不一致。

## 6. Source of Truth

- 主流程契约：`AGENTS.md`
- 变更矩阵：`docs/process/change-matrix.md`
- review note 规范：`docs/process/review-notes.md`
- 机器可读策略源：`docs/process/policy.json`
- 质量门禁脚本：`script/process/*`
- 若仓库启用了额外流程真源（例如 `docs/process/rule-map.json`），以该文件及其消费脚本的实际行为为准
