# MemeverseCommonInfo
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/f6152b6dbfadcd8a23a2d518905418243cf2a5e1/src/verse/MemeverseCommonInfo.sol)

**Inherits:**
[IMemeverseCommonInfo](/src/verse/interfaces/IMemeverseCommonInfo.sol/interface.IMemeverseCommonInfo.md), Ownable

**Title:**
Memeverse Common Info Contract


## State Variables
### lzEndpointIdMap

```solidity
mapping(uint32 chainId => uint32) public lzEndpointIdMap
```


## Functions
### constructor


```solidity
constructor(address _owner) Ownable(_owner);
```

### setLzEndpointIdMap


```solidity
function setLzEndpointIdMap(LzEndpointIdPair[] calldata pairs) external override onlyOwner;
```

