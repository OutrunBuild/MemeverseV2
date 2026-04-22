# MemeverseV2 集成边界：LayerZero OApp / OFT

## 1. 范围

本文描述 MemeverseV2 与 LayerZero v2 的边界，不复述 LayerZero 通用协议原理。  
标签：

- `[代码已证]`
- `[未知]`

## 2. 使用面总览（代码落点）

- OApp 路径：
 - `MemeverseRegistrationCenter`（中心链 fan-out）
 - `MemeverseRegistrarOmnichain`（异链向中心链注册）
 - `OutrunOApp*` 初始化基类（peer/delegate）
- OFT 路径：
 - `Memecoin`、`MemePol`（基于 `OutrunOFTInit`）
 - `MemeverseLauncher`（`IOFT.quoteSend/send` 分发 fee）
 - `MemeverseOmnichainInteroperation`（跨链 staking）
 - `YieldDispatcher`、`OmnichainMemecoinStaker`（compose 接收处理）

以上为 `[代码已证]`。

## 3. 边界与职责

### 3.1 peer / endpoint 映射边界

- `launcher.registerMemeverse` 时会对 memecoin/POL 执行 `IOAppCore.setPeer`。
- endpointId 通过 `LzEndpointRegistry.lzEndpointIdOfChain` 查询。
- 未配置 endpointId（返回 0）会回退注册。

`[代码已证]`

### 3.2 注册跨链消息边界

- `MemeverseRegistrationCenter` 负责中心链注册参数校验与多链 fan-out。
- 远端回调 `_lzReceive` 要求 `_origin.sender == MEMEVERSE_REGISTRAR`。
- `MemeverseRegistrarOmnichain` 负责异链到中心链注册发送，gas 预算由 `registrationGasLimit` 组合。

`[代码已证]`

### 3.3 收益分发与 staking 边界

- Launcher fee 分发：
 - 本链治理：调用 `YieldDispatcher.lzCompose(...)` 本地直达
 - 异链治理：调用 `IOFT.send(...)` 远程发送
- Memecoin staking：
 - 本链治理：直接 deposit 到 yieldVault
 - 异链治理：OFT 发送到 `OmnichainMemecoinStaker`，compose 后 deposit/transfer

`[代码已证]`

## 4. 安全与执行约束

- compose 回调授权：
 - `YieldDispatcher.lzCompose` 仅 `localEndpoint` 或 `memeverseLauncher`
 - `OmnichainMemecoinStaker.lzCompose` 仅 `localEndpoint`
- replay 防护：
 - endpoint 路径检查 `getComposeTxExecutedStatus(guid)`，并 `notifyComposeExecuted(guid)`
- 费用约束：
 - 多条远端路径要求 `msg.value` 与 quote 精确相等（不是“大于等于”）

以上均为 `[代码已证]`。

## 5. 与本仓库外系统的边界

- DVN、消息库、endpoint 级配置由链外部署与 LayerZero 基础设施决定。`[未知]`
- 各链实际 endpoint 地址、EID 与 peer 配置最终值不在仓库内固定。`[未知]`

## 6. 已知实现差异提醒

- 注册“天数”换算：`RegistrationCenter.DAY=180` 秒，而 `RegistrarAtLocal.quoteRegister` 使用 `24*3600`；最终写入以中心链为准。`[代码已证]`
