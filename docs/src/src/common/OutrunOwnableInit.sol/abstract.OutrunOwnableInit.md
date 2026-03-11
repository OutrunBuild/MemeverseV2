# OutrunOwnableInit
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/f6152b6dbfadcd8a23a2d518905418243cf2a5e1/src/common/OutrunOwnableInit.sol)

**Inherits:**
[Initializable](/src/common/Initializable.sol/abstract.Initializable.md)

Outrun's OwnableInit implementation, modified from openzeppelin implementation (Just for minimal proxy)


## State Variables
### OWNABLE_STORAGE_LOCATION

```solidity
bytes32 private constant OWNABLE_STORAGE_LOCATION =
    0x7f241041d6960443a72c6e46e3b41069d0f1a8933ddb434b1da86a3f3cba9f00
```


## Functions
### _getOwnableStorage


```solidity
function _getOwnableStorage() private pure returns (OwnableStorage storage $);
```

### __OutrunOwnable_init

Initializes the contract setting the address provided by the deployer as the initial owner.


```solidity
function __OutrunOwnable_init(address initialOwner) internal onlyInitializing;
```

### __OutrunOwnable_init_unchained


```solidity
function __OutrunOwnable_init_unchained(address initialOwner) internal onlyInitializing;
```

### onlyOwner

Throws if called by any account other than the owner.


```solidity
modifier onlyOwner() ;
```

### owner

Returns the address of the current owner.


```solidity
function owner() public view virtual returns (address);
```

### _checkOwner

Throws if the sender is not the owner.


```solidity
function _checkOwner() internal view virtual;
```

### renounceOwnership

Leaves the contract without owner. It will not be possible to call
`onlyOwner` functions. Can only be called by the current owner.
NOTE: Renouncing ownership will leave the contract without an owner,
thereby disabling any functionality that is only available to the owner.


```solidity
function renounceOwnership() public virtual onlyOwner;
```

### transferOwnership

Transfers ownership of the contract to a new account (`newOwner`).
Can only be called by the current owner.


```solidity
function transferOwnership(address newOwner) public virtual onlyOwner;
```

### _transferOwnership

Transfers ownership of the contract to a new account (`newOwner`).
Internal function without access restriction.


```solidity
function _transferOwnership(address newOwner) internal virtual;
```

## Events
### OwnershipTransferred

```solidity
event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
```

## Errors
### OwnableUnauthorizedAccount
The caller account is not authorized to perform an operation.


```solidity
error OwnableUnauthorizedAccount(address account);
```

### OwnableInvalidOwner
The owner is not a valid owner account. (eg. `address(0)`)


```solidity
error OwnableInvalidOwner(address owner);
```

## Structs
### OwnableStorage
**Note:**
storage-location: erc7201:openzeppelin.storage.Ownable


```solidity
struct OwnableStorage {
    address _owner;
}
```

