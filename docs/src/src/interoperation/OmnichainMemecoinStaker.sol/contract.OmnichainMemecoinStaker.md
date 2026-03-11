# OmnichainMemecoinStaker
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/f6152b6dbfadcd8a23a2d518905418243cf2a5e1/src/interoperation/OmnichainMemecoinStaker.sol)

**Inherits:**
[IOmnichainMemecoinStaker](/src/interoperation/interfaces/IOmnichainMemecoinStaker.sol/interface.IOmnichainMemecoinStaker.md), [TokenHelper](/src/common/TokenHelper.sol/abstract.TokenHelper.md)

**Title:**
Omnichain Memecoin Staker

The contract is designed to interact with LayerZero's Omnichain Fungible Token (OFT) Standard,
accepts Memecoin and stakes to the yield vault.


## State Variables
### localEndpoint

```solidity
address public immutable localEndpoint
```


## Functions
### constructor


```solidity
constructor(address _localEndpoint) ;
```

### lzCompose

Redirect the yields of different Memecoins to their yield vault.


```solidity
function lzCompose(
    address memecoin,
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
|`memecoin`|`address`|- The token address initiating the composition, typically the OFT where the lzReceive was called.|
|`guid`|`bytes32`|The unique identifier for the received LayerZero message.|
|`message`|`bytes`|- The composed message payload in bytes. NOT necessarily the same payload passed via lzReceive.|
|`<none>`|`address`||
|`<none>`|`bytes`||


