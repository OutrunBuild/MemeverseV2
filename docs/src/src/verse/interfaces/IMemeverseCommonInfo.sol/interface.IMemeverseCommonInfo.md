# IMemeverseCommonInfo
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/5f1e475fc32b5b93b8a81ca9d545cacad2f7567c/src/verse/interfaces/IMemeverseCommonInfo.sol)

Interface for the Memeverse Registrar.


## Functions
### lzEndpointIdMap


```solidity
function lzEndpointIdMap(uint32 chainId) external view returns (uint32);
```

### setLzEndpointIdMap


```solidity
function setLzEndpointIdMap(LzEndpointIdPair[] calldata pairs) external;
```

## Events
### SetLzEndpointIdMap

```solidity
event SetLzEndpointIdMap(LzEndpointIdPair[] pairs);
```

## Structs
### LzEndpointIdPair

```solidity
struct LzEndpointIdPair {
    uint32 chainId;
    uint32 endpointId;
}
```

