# IMemeverseCommonInfo
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/f6152b6dbfadcd8a23a2d518905418243cf2a5e1/src/verse/interfaces/IMemeverseCommonInfo.sol)

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

