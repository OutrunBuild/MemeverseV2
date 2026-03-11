# MemeverseCommonInfo
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/5f1e475fc32b5b93b8a81ca9d545cacad2f7567c/src/verse/MemeverseCommonInfo.sol)

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

