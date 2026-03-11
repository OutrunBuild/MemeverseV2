# UniswapLP
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/5f1e475fc32b5b93b8a81ca9d545cacad2f7567c/src/libraries/UniswapLP.sol)

**Inherits:**
Owned

LP Token For MemeverseUniswapHook


## State Variables
### name

```solidity
string public name
```


### symbol

```solidity
string public symbol
```


### decimals

```solidity
uint8 public immutable decimals
```


### totalSupply

```solidity
uint256 public totalSupply
```


### balanceOf

```solidity
mapping(address => uint256) public balanceOf
```


### allowance

```solidity
mapping(address => mapping(address => uint256)) public allowance
```


### INITIAL_CHAIN_ID

```solidity
uint256 internal immutable INITIAL_CHAIN_ID
```


### INITIAL_DOMAIN_SEPARATOR

```solidity
bytes32 internal immutable INITIAL_DOMAIN_SEPARATOR
```


### nonces

```solidity
mapping(address => uint256) public nonces
```


### poolId

```solidity
PoolId public immutable poolId
```


### memeverseUniswapHook

```solidity
address public immutable memeverseUniswapHook
```


## Functions
### constructor


```solidity
constructor(
    string memory _name,
    string memory _symbol,
    uint8 _decimals,
    PoolId _poolId,
    address _memeverseUniswapHook
) Owned(msg.sender);
```

### approve


```solidity
function approve(address spender, uint256 amount) public returns (bool);
```

### transfer


```solidity
function transfer(address to, uint256 amount) public returns (bool);
```

### transferFrom


```solidity
function transferFrom(address from, address to, uint256 amount) public returns (bool);
```

### mint


```solidity
function mint(address account, uint256 amount) external onlyOwner;
```

### burn


```solidity
function burn(address account, uint256 amount) external onlyOwner;
```

### permit


```solidity
function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
    public;
```

### DOMAIN_SEPARATOR


```solidity
function DOMAIN_SEPARATOR() public view returns (bytes32);
```

### computeDomainSeparator


```solidity
function computeDomainSeparator() internal view returns (bytes32);
```

### _mint


```solidity
function _mint(address to, uint256 amount) internal;
```

### _burn


```solidity
function _burn(address from, uint256 amount) internal;
```

### _beforeTokenTransfer


```solidity
function _beforeTokenTransfer(address from, address to) internal;
```

## Events
### Transfer

```solidity
event Transfer(address indexed from, address indexed to, uint256 amount);
```

### Approval

```solidity
event Approval(address indexed owner, address indexed spender, uint256 amount);
```

