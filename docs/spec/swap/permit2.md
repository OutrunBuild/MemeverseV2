# MemeverseV2 集成边界：Permit2

## 1. 范围

本文只覆盖 `MemeverseSwapRouter` 中的 Permit2 并行入口。  
标签：

- `[代码已证]`
- `[未知]`

## 2. 支持入口

Router 暴露 4 组 Permit2 入口（与普通入口并行，不替代）：

- `swapWithPermit2(...)`
- `addLiquidityWithPermit2(...)`
- `removeLiquidityWithPermit2(...)`
- `createPoolAndAddLiquidityWithPermit2(...)`

`[代码已证]`

## 3. 验签与拉资边界

### 3.1 单 token 路径（swap/remove）

- 校验 `permit.permitted.token` 必须等于预期 token
- 校验 `transferDetails.to` 必须是 `address(this)`（Router）
- 校验 `transferDetails.requestedAmount` 必须等于业务预算

### 3.2 双 token 路径（add/create）

- 仅接受 ERC20/ERC20 pair，期望 batch 长度固定为 2
- 逐项校验 token 顺序、接收地址、请求金额

以上为 `[代码已证]`。

## 4. Witness 绑定语义

Router 为每条 Permit2 入口构造独立 witness：

- `SWAP_WITNESS_TYPEHASH`
- `ADD_LIQUIDITY_WITNESS_TYPEHASH`
- `REMOVE_LIQUIDITY_WITNESS_TYPEHASH`
- `CREATE_POOL_WITNESS_TYPEHASH`

witness 绑定了关键业务参数（池子、方向、预算、截止时间等），签名不可跨业务复用。`[代码已证]`

## 5. 与普通入口一致/不一致点

- 一致：Permit2 只改变 ERC20 资金准备方式，后续 slippage、deadline、hook 语义一致。`[代码已证]`
- 不一致：swap 栈 fail-close；任一侧为 `address(0)` 直接 `revert NativeCurrencyUnsupported`，Permit2 不为 native 提供任何兜底路径。`[代码已证]`

## 6. 安全边界

- Permit2 spender 语义由 Router 作为调用方固定下来；签名目标应与 Router 地址一致。`[代码已证]`
- Permit2 失败会导致整笔交易回退，不存在“部分生效”路径。`[代码已证]`

## 7. 明确未知项

- `[未知]` 生产环境实际 Permit2 合约地址；仓库仅体现“构造注入 + `permit2()` 只读暴露”，不含最终部署清单。
