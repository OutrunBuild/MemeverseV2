# OutrunNoncesInit
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/5f1e475fc32b5b93b8a81ca9d545cacad2f7567c/src/common/OutrunNoncesInit.sol)

**Inherits:**
[Initializable](/src/common/Initializable.sol/abstract.Initializable.md)

Provides tracking nonces for addresses. Nonces will only increment.


## State Variables
### NONCES_STORAGE_LOCATION

```solidity
bytes32 private constant NONCES_STORAGE_LOCATION =
    0xbc43161bd6c888bfd7c69c0710419a94949c687678098a4e6d8f37f01804b400
```


## Functions
### _getNoncesStorage


```solidity
function _getNoncesStorage() private pure returns (NoncesStorage storage $);
```

### __OutrunNonces_init


```solidity
function __OutrunNonces_init() internal onlyInitializing;
```

### __OutrunNonces_init_unchained


```solidity
function __OutrunNonces_init_unchained() internal onlyInitializing;
```

### nonces

Returns the next unused nonce for an address.


```solidity
function nonces(address owner) public view virtual returns (uint256);
```

### _useNonce

Consumes a nonce.
Returns the current value and increments nonce.


```solidity
function _useNonce(address owner) internal virtual returns (uint256);
```

### _useCheckedNonce

Same as [_useNonce](/src/common/OutrunNoncesInit.sol/abstract.OutrunNoncesInit.md#_usenonce) but checking that `nonce` is the next valid for `owner`.


```solidity
function _useCheckedNonce(address owner, uint256 nonce) internal virtual;
```

## Errors
### InvalidAccountNonce
The nonce used for an `account` is not the expected current nonce.


```solidity
error InvalidAccountNonce(address account, uint256 currentNonce);
```

## Structs
### NoncesStorage
**Note:**
storage-location: erc7201:openzeppelin.storage.Nonces


```solidity
struct NoncesStorage {
    mapping(address account => uint256) _nonces;
}
```

