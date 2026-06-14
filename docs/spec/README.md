# MemeverseV2 规格文档索引

本文档是 `docs/spec/` 的入口索引：按 region 列出全部规格文档及其职责，供编辑者快速定位"每类规则在哪个文件"。**OCLPAR canonical-home 表（每条原子规则的权威主页）属 Phase 2 去冗余审计产物，待该审计确立每个 home 后单独写入，不在本索引。**

文档分层（Product Truth / Implementation Evidence / Topic Guides）与冲突处理顺序见 [docs/ARCHITECTURE.md §2](../ARCHITECTURE.md)，本文不重定义层级。术语定义见 [docs/GLOSSARY.md](../GLOSSARY.md)。

标签约定：`[目标规范]` = 目标产品规则（可能尚未在代码实现）；`[代码已证]` = 当前代码可直接验证；`[未知]` = 仓库内无部署级最终值。

## 1. 文档地图（按 region）

### 跨模块（`docs/spec/` 根）

| 文件 | 行数 | 职责 |
| --- | --- | --- |
| [protocol.md](protocol.md) | 100 | 协议总览、组件清单、文档分层 |
| [access-control.md](access-control.md) | 81 | 访问控制边界（authority / evidence） |
| [events.md](events.md) | 114 | 事件面（用户 / 索引器 / 运维） |
| [invariants.md](invariants.md) | 147 | 跨模块不变量 |
| [upgradeability.md](upgradeability.md) | 118 | 升级性与初始化约束 |

### 公共基础（`common/`）

| 文件 | 行数 | 职责 |
| --- | --- | --- |
| [common/common-foundations.md](common/common-foundations.md) | 104 | 公共基础层说明 |

### Verse 生命周期（`verse/`）

| 文件 | 行数 | 职责 |
| --- | --- | --- |
| [verse/accounting.md](verse/accounting.md) | 246 | 记账与资金语义 |
| [verse/state-machines.md](verse/state-machines.md) | 111 | 状态机 |
| [verse/lifecycle-details.md](verse/lifecycle-details.md) | 272 | 生命周期细化说明 |
| [verse/registration-details.md](verse/registration-details.md) | 178 | 注册链路细化说明 |
| [verse/deployment.md](verse/deployment.md) | 144 | 部署拓扑与初始化事实 |
| [verse/config-matrix.md](verse/config-matrix.md) | 99 | 配置矩阵（可配置面 / 常量面） |

### Swap（`swap/`）

| 文件 | 行数 | 职责 |
| --- | --- | --- |
| [swap/swap-flow.md](swap/swap-flow.md) | 172 | Swap 流程图 |
| [swap/swap-integration.md](swap/swap-integration.md) | 279 | Swap 集成说明 |
| [swap/uniswap-v4.md](swap/uniswap-v4.md) | 101 | Uniswap v4 集成边界 |
| [swap/permit2.md](swap/permit2.md) | 60 | Permit2 集成边界 |

### 跨链互操作（`interoperation/`）

| 文件 | 行数 | 职责 |
| --- | --- | --- |
| [interoperation/interoperation-details.md](interoperation/interoperation-details.md) | 109 | 跨链互操作细化说明 |
| [interoperation/layerzero-oapp-oft.md](interoperation/layerzero-oapp-oft.md) | 73 | LayerZero OApp / OFT 集成边界 |

### 治理与收益（`governance/`）

| 文件 | 行数 | 职责 |
| --- | --- | --- |
| [governance/governance-yield-details.md](governance/governance-yield-details.md) | 176 | 治理与收益细化说明 |

### POLend（`polend/`）

| 文件 | 行数 | 职责 |
| --- | --- | --- |
| [polend/polend.md](polend/polend.md) | 1960 | POLend 规格（四池模型 + PT/YT + settlement + 杠杆创世） |

`polend/polend.md` 单文件占 `docs/spec/` 总行数 4644 的 42%，是 Phase 3 拆分目标。

## 2. 相关真源

- 分层与冲突顺序：[docs/ARCHITECTURE.md](../ARCHITECTURE.md)
- 术语：[docs/GLOSSARY.md](../GLOSSARY.md)
- 控制文件与产物位置：[docs/TRACEABILITY.md](../TRACEABILITY.md)
- 实现证据（规则落地）：`src/**`、`test/**`
