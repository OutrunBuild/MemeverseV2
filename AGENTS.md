# Agent Operating Contract

本文件是仓库的主要操作入口，面向人工开发者与各类 agent / workflow。它负责说明必须遵守的完成定义、路径触发规则、关键入口命令，以及理解 Memeverse 协议时最值得优先查看的代码位置。更细的流程结构、机器可读策略与脚本实现继续保留在 `docs/process/` 与 `script/process/`。

## 1. Project Overview

这是一个以 Foundry 为主的 Solidity 仓库，核心实现围绕 Memeverse 协议，组合了：

- LayerZero OApp / OFT：跨链注册、跨链消息与跨链 memecoin 流转
- Uniswap v4 Hook + Router：Memeverse 专用 swap / LP / anti-snipe 交易入口
- 启动与发行流程：注册 symbol、创建 verse、Genesis 募资、Locked 阶段、流动性与费用分发
- 治理与收益：治理合约、激励器、Yield Vault、跨链 staking

## 2. Required Commands

- 初次 clone 后执行：`git submodule update --init --recursive`
- 每个工作副本只需执行一次：`npm install`
- 每个工作副本只需执行一次：`npm run hooks:install`
- 任意准备提交的变更，唯一 finish gate：`npm run quality:gate`
- 不要把单独的 `forge build`、`forge test`、`npm run docs:check` 视为 finish gate 替代品

常用命令：

- 构建与格式化：`forge build`、`forge fmt --check`、`npm run compile`
- 测试：`forge test -vvv`、`forge test --match-path <path>`、`forge test --match-test <name>`
- 文档与流程检查：`npm run docs:check`、`bash ./script/process/check-natspec.sh`、`bash ./script/process/check-slither.sh`、`bash ./script/process/check-gas-report.sh`、`bash ./script/process/check-solidity-review-note.sh`
- 部署入口：`forge script script/MemeverseScript.s.sol:MemeverseScript --rpc-url <alias> --broadcast --ffi -vvvv`、`bash ./script/deploy.sh`

## 3. Workflow Model

- `npm run quality:gate` 是唯一 finish gate。
- `src/**/*.sol` 命中后，只要实现已经完成并进入 review、收尾、准备 `git add` / commit，或准备运行 `npm run quality:gate`，就必须先执行 `skills/solidity-post-coding-flow/SKILL.md`。
- `skills/solidity-post-coding-flow/SKILL.md` 负责把 `Code Simplifier`、`Solidity Security`、gas 审查、review note 证据与最终 gate 串成一次可重复的后编码流程。
- 如果完成一轮 post-coding / `quality:gate` 后又继续修改 `src/**/*.sol`，必须基于最新 diff 重新执行该 skill，并更新 review note 与验证证据。
- `docs/contracts/` 是生成产物；验证它依赖 `npm run docs:check`，而不是手工编辑或直接提交生成内容。

## 4. Change Matrix

- `src/**/*.sol`
  - 命中该路径时，agent/workflow 应优先调用 `skills/solidity-post-coding-flow/SKILL.md`
  - 一旦 `src/**/*.sol` 变更已完成实现，并进入 review、收尾、准备 `git add` / commit，或准备运行 `npm run quality:gate`，上述 skill 视为必选触发，不得跳过
  - 代码编写完成后，必须按顺序执行 `Code Simplifier`、`Solidity Security`；其中 `Solidity Security` 负责同时完成安全检查与 gas 优化审查
  - 必须通过 Solidity gate：`forge fmt --check`、`forge build`、`forge test -vvv`
  - 必须通过 NatSpec gate：`bash ./script/process/check-natspec.sh`
  - 必须通过 security gate：`bash ./script/process/check-slither.sh`
  - 必须通过 gas gate：`bash ./script/process/check-gas-report.sh`
  - 如果在一次已完成的 post-coding / `quality:gate` 之后又新增、修改任意 `src/**/*.sol`，必须基于最新 diff 重新执行 `skills/solidity-post-coding-flow/SKILL.md`，并重新更新 review note 与验证证据
  - 本地提交前必须提供 review note 证据：`bash ./script/process/check-solidity-review-note.sh`
  - 必须通过 docs gate：`npm run docs:check`
- `src/swap/**/*.sol`
  - 如果命中 `docs/process/rule-map.json` 中的模块规则，变更集中必须同时包含至少 1 个匹配的测试文件
- `test/**/*.t.sol`
  - 必须通过：`forge fmt --check`、`forge build`、`forge test -vvv`
- `script/**/*.sh` 或 `.githooks/*`
  - 必须通过：`bash -n`

## 5. Pull Request Contract

- 仓库提供标准模板：`.github/pull_request_template.md`
- 当前机械校验的是 PR body 必须包含以下标题：
  - `## Summary`
  - `## Impact`
  - `## Docs`
  - `## Tests`
  - `## Verification`
  - `## Risks`
  - `## Security`
  - `## Simplification`
  - `## Gas`

## 6. Review Note Contract

- 模板文件：`docs/reviews/TEMPLATE.md`
- `docs/reviews/*.md` 默认仍是本地草稿；但当命中 `src/**/*.sol` 变更时，本地 `quality:gate` 必须能找到一份有效 review note
- 以下固定字段不能为空、不能写 `TBD`、不能保留模板占位：
  - `Change summary`
  - `Files reviewed`
  - `Behavior change`
  - `ABI change`
  - `Storage layout change`
  - `Config change`
  - `Security review summary`
  - `Security residual risks`
  - `Gas-sensitive paths reviewed`
  - `Gas changes applied`
  - `Gas snapshot/result`
  - `Gas residual risks`
  - `Docs updated`
  - `Tests updated`
  - `Existing tests exercised`
  - `Commands run`
  - `Results`
  - `Residual risks`
- `Ready to commit` 只能填写 `yes` 或 `no`
- `Findings`、`Simplification` 及其子字段保留在模板中作为建议补充，但当前 gate 不单独校验其具体内容

## 7. Generated Docs and Local-Only Files

- `docs/contracts/` 是生成产物，不手工编辑，不提交到 git
- `npm run docs:check` 的职责是验证生成流程可运行且输出结构符合预期
- `docs/plans/` 仅用于本地规划，不提交到 git
- `docs/reviews/` 默认作为本地 review 草稿目录，不提交到 git

## 8. Documentation Language

- 新增的自然语言文档默认使用简体中文
- `docs/reviews/*.md` 如果本地使用，固定 section / field key 与 `yes`、`no` 取值保持英文，其余说明与正文使用简体中文
- 命令、路径、代码标识、协议名、库名保持英文原文

## 9. High-Level Architecture

### 9.1 Verse 启动主流程

核心入口是 `src/verse/MemeverseLauncher.sol`。它维护 verse 生命周期、Genesis 募资、POL 与流动性相关状态，并负责把 launcher、router、yield vault、governor、跨链 dispatcher 等外围模块串起来。理解协议整体行为时，优先从这里入手，因为大多数“创建 verse → 募资 → 锁仓/解锁 → 费用分发/领取”的问题最终都会回到它维护的状态与阶段转换。

重点关注：

- `memeverses`：每个 verse 的核心元数据与阶段信息
- `genesisFunds` / `userGenesisData`：Genesis 募资总量与用户参与记录
- `memecoinToIds`：memecoin 到 verseId 的映射
- `totalClaimablePOL` / `totalPolLiquidity`：POL 领取与协议流动性相关状态

如果改动的是阶段流转、募资、claim、费用预览、POL、治理装配或路由联动，先看 `MemeverseLauncher.sol` 及其相关测试，再决定是否继续下钻到 swap、yield、governance 或 interoperation 模块。

### 9.2 注册与跨链注册

注册逻辑集中在 `src/verse/registration/`。这里不是单一合约完成所有事情，而是由注册中心和不同 registrar 分层协作：

- `MemeverseRegistrationCenter.sol`：注册总入口，维护 symbol 当前注册态与历史记录，并负责向目标链发送跨链注册消息
- `MemeverseRegistrarAtLocal.sol`：当前链上的本地注册逻辑
- `MemeverseRegistrarOmnichain.sol`：跨链侧注册逻辑
- `MemeverseRegistrarAbstract.sol`：共享注册逻辑与复用代码

排查注册问题时，先分清这是“当前链本地注册”还是“跨链注册消息同步”问题。前者通常先看 center + local registrar，后者通常还要继续看 LayerZero/OApp 相关调用链与 endpoint 配置。只盯一个 registrar 往往不够，因为真正的状态入口仍然在 registration center。

### 9.3 Token / Yield / Governance

`src/token/`、`src/yield/`、`src/governance/` 共同承接 verse 创建后的资产、收益和治理能力：

- `src/token/Memecoin.sol`：可初始化的 OFT memecoin，通常由 launcher 在 verse 创建流程中装配并负责 mint 权限
- `src/token/MemeLiquidProof.sol`：协议中的 liquid proof token
- `src/yield/MemecoinYieldVault.sol`：memecoin 收益金库
- `src/governance/MemecoinDaoGovernorUpgradeable.sol` 与 `GovernanceCycleIncentivizerUpgradeable.sol`：治理与周期激励逻辑

如果你改动的是 verse 创建时的模块装配、治理权限、收益归集、vault 对接，通常不能只看单个模块，要同时确认 launcher / proxy deployer 如何初始化和串联这些合约。很多看似是 token 或 governor 的问题，实际根因是创建时的配置、初始化顺序或地址注入。

### 9.4 Swap 与 Uniswap v4 Hook

交易路径主要在 `src/swap/`，其中 `MemeverseSwapRouter.sol` 是面向用户与集成方的推荐公开入口，`MemeverseUniswapHook.sol` 则承接 Uniswap v4 hook 侧的扩展行为。设计上优先通过 router 暴露 quote、swap、add/remove liquidity、Permit2 等能力；hook 仍可能被更底层集成直接调用。

重点目录：

- `MemeverseSwapRouter.sol`：用户入口、报价、流动性操作、Permit2 入口
- `MemeverseUniswapHook.sol`：anti-snipe、池子侧扩展行为、与 v4 池生命周期耦合的逻辑
- `tokens/UniswapLP.sol`：LP token
- `libraries/`：流动性计算、报价、结算、瞬时状态等底层库

如果改的是 swap、hook、fee、流动性、报价路径，先同时看实现和映射测试，不要只改合约不看测试矩阵。优先查看：`test/MemeverseSwapRouter.t.sol`、`test/MemeverseSwapRouterPermit2.t.sol`、`test/MemeverseUniswapHookLiquidity.t.sol`、`test/MemeverseDynamicFeeSimulation.t.sol`。此外，`src/swap/**/*.sol` 命中后还要检查 `docs/process/rule-map.json` 对应的必需测试证据。

### 9.5 Omnichain Interoperation

跨链 staking 与治理链侧承接逻辑集中在 `src/interoperation/`：

- `MemeverseOmnichainInteroperation.sol`：从当前链发起 memecoin staking，必要时先通过 OFT 进行跨链转移
- `OmnichainMemecoinStaker.sol`：治理链侧 staking 承接逻辑

这部分通常依赖三个关键来源：

- `MemeverseLauncher` 提供 verse 元数据
- `LzEndpointRegistry` 提供 chainId → LayerZero endpoint id 映射
- `Memecoin` 的 OFT 能力完成跨链转移

排查跨链交互问题时，最常见的误区是只看 interoperation 合约本身，而忽略 launcher 元数据、endpoint registry 配置和 OFT 行为是否一致。遇到 staking、跨链转移、治理链落地相关问题，要把这三层一起核对。

### 9.6 Common 基础层

`src/common/` 提供协议级基础设施，主要包括 omnichain 封装、token 基类、访问控制与密码学组件。看到 `Outrun*Init` 前缀时，通常意味着这是对 OpenZeppelin 或 LayerZero 初始化模式的协议封装，而不是普通业务层逻辑。

重点子目录：

- `common/omnichain/`：OApp / OFT 初始化与 endpoint registry 相关封装
- `common/token/`：ERC20、permit、votes 及常用 helper
- `common/access/`：初始化 ownable、reentrancy guard 等基础能力
- `common/cryptography/`：EIP-712 相关基础组件

如果你在业务合约里看到大量初始化拼装、权限基类或跨链基类引用，通常要追到这里看清楚真实的继承与初始化契约，否则很容易误判 access control、initializer 或 endpoint 行为。

### 9.7 Tests, Scripts, and Environment

测试主要在 `test/*.t.sol`。当前重点覆盖 router、hook、动态费率、launcher 配置与价格计算。改 swap 或 hook 时，优先看 `MemeverseSwapRouter*.t.sol` 和 hook 相关测试；改 launcher、claim、费用预览或 verse 生命周期时，优先看 `MemeverseLauncher*.t.sol`。

脚本入口主要有：

- `script/BaseScript.s.sol`：统一从 `.env` 读取 `PRIVATE_KEY`，并开启 `vm.startBroadcast`
- `script/MemeverseScript.s.sol`：主部署脚本，串联 implementations、registration center、launcher、dispatcher、interoperation 等部署/查询流程
- `script/deploy.sh`：多链部署命令模板
- `script/process/*`：质量门禁、review note、PR body、NatSpec、安全与 gas 检查脚本

环境配置重点来自 `.env` 与 `foundry.toml`。部署或广播问题通常不是单点脚本 bug，而是 env 变量、rpc alias、endpoint/eid 配置或部署顺序不一致导致。Foundry 当前使用 Solidity `0.8.30`，并启用了 `via_ir = true`、`build_info = true`、`extra_output = ["storageLayout"]`，因此涉及编译、gas、storage layout 或部署差异时，要以这套编译配置为准。

## 10. Source of Truth

- 路径与 gate 细则：`docs/process/change-matrix.md`
- Review note 规范：`docs/process/review-notes.md`
- 机器可读策略源：`docs/process/policy.json`
- 规则到测试映射：`docs/process/rule-map.json`
- Solidity 后编码流程 skill：`skills/solidity-post-coding-flow/SKILL.md`
- skill 安装脚本：`script/process/install-repo-skill.sh`
- 质量门禁与相关检查脚本：`script/process/*`
