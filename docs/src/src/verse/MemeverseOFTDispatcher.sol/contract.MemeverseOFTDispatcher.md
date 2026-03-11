# MemeverseOFTDispatcher
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/f6152b6dbfadcd8a23a2d518905418243cf2a5e1/src/verse/MemeverseOFTDispatcher.sol)

**Inherits:**
[IMemeverseOFTDispatcher](/src/verse/interfaces/IMemeverseOFTDispatcher.sol/interface.IMemeverseOFTDispatcher.md), [TokenHelper](/src/common/TokenHelper.sol/abstract.TokenHelper.md), Ownable

**Title:**
Memeverse OFT Dispatcher

The contract is designed to interact with LayerZero's Omnichain Fungible Token (OFT) Standard,
accepts Memecoin Yield from other chains and then forwards it to the corresponding yield vault.


## State Variables
### localEndpoint

```solidity
address public immutable localEndpoint
```


### memeverseLauncher

```solidity
address public immutable memeverseLauncher
```


## Functions
### constructor


```solidity
constructor(address _owner, address _localEndpoint, address _memeverseLauncher) Ownable(_owner);
```

### lzCompose

Redirect the yields of different Memecoins to their yield vault.


```solidity
function lzCompose(
    address token,
    bytes32 guid,
    bytes calldata message,
    address,
    /*executor*/
    bytes calldata /*extraData*/
)
    external
    payable
    override;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`token`|`address`|- The token address initiating the composition, typically the OFT where the lzReceive was called.|
|`guid`|`bytes32`|The unique identifier for the received LayerZero message.|
|`message`|`bytes`|- The composed message payload in bytes. NOT necessarily the same payload passed via lzReceive.|
|`<none>`|`address`||
|`<none>`|`bytes`||


