# MemeverseV2 Codex Agents

本目录存放 `MemeverseV2` 项目级 subagent 定义，是仓库 Harness 的核心组成。

## 双文件模型

每个角色由同名文件对构成：

- `*.toml`
  - Codex manifest / 入口定义
  - 只承载最小元数据和入口级 `developer_instructions`
- `*.md`
  - 仓库运行时契约（行为真源）
  - 定义输入契约、读写边界、执行清单、block 语义、输出契约和升级规则

同名 `*.toml` 与 `*.md` 冲突时，以 `*.md` 为准。

## Canonical References

- Harness 真源与 generated-docs 边界：以 `AGENTS.md` 的 `Source of Truth` 章节为准
- 阶段流、证据链、block 规则：以 `docs/process/subagent-workflow.md` 为准
- 本文件仅提供角色索引与目录说明，不重复定义仓库级规范

## 角色清单

- `main-orchestrator`
- `process-implementer`
- `solidity-implementer`
- `security-reviewer`
- `gas-reviewer`
- `security-test-writer`
- `solidity-explorer`
- `verifier`
