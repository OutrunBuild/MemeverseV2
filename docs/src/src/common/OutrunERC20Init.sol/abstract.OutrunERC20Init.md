# OutrunERC20Init
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/f6152b6dbfadcd8a23a2d518905418243cf2a5e1/src/common/OutrunERC20Init.sol)

**Inherits:**
IERC20, [Initializable](/src/common/Initializable.sol/abstract.Initializable.md), IERC20Metadata, IERC20Errors

**Title:**
Outrun's ERC20Init implementation, modified from @openzeppelin implementation (Just for minimal proxy)


## State Variables
### ERC20_STORAGE_LOCATION

```solidity
bytes32 private constant ERC20_STORAGE_LOCATION =
    0xae36c519e2a406a79e4c05a9c40dc957f3757904fff7f6a4d18b68c3b12f9300
```


## Functions
### _getERC20Storage


```solidity
function _getERC20Storage() private pure returns (ERC20Storage storage $);
```

### __OutrunERC20_init

Sets the values for [name](/src/common/OutrunERC20Init.sol/abstract.OutrunERC20Init.md#name) and [symbol](/src/common/OutrunERC20Init.sol/abstract.OutrunERC20Init.md#symbol).
All two of these values are immutable: they can only be set once during
construction.


```solidity
function __OutrunERC20_init(string memory name_, string memory symbol_) internal onlyInitializing;
```

### __ERC20_init_unchained


```solidity
function __ERC20_init_unchained(string memory name_, string memory symbol_) internal onlyInitializing;
```

### name

Returns the name of the token.


```solidity
function name() public view virtual returns (string memory);
```

### symbol

Returns the symbol of the token, usually a shorter version of the
name.


```solidity
function symbol() public view virtual returns (string memory);
```

### decimals

Returns the number of decimals used to get its user representation.
For example, if `decimals` equals `2`, a balance of `505` tokens should
be displayed to a user as `5.05` (`505 / 10 ** 2`).
Tokens usually opt for a value of 18, imitating the relationship between
Ether and Wei. This is the default value returned by this function, unless
it's overridden.
NOTE: This information is only used for _display_ purposes: it in
no way affects any of the arithmetic of the contract, including
[IERC20-balanceOf](/lib/v4-periphery/lib/v4-core/src/types/Currency.sol/library.CurrencyLibrary.md#balanceof) and [IERC20-transfer](/lib/v4-periphery/lib/v4-core/src/types/Currency.sol/library.CurrencyLibrary.md#transfer).


```solidity
function decimals() public view virtual returns (uint8);
```

### totalSupply

See [IERC20-totalSupply](/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol/interface.IERC20.md#totalsupply).


```solidity
function totalSupply() public view virtual returns (uint256);
```

### balanceOf

See [IERC20-balanceOf](/lib/v4-periphery/lib/v4-core/src/types/Currency.sol/library.CurrencyLibrary.md#balanceof).


```solidity
function balanceOf(address account) public view virtual returns (uint256);
```

### transfer

See [IERC20-transfer](/lib/v4-periphery/lib/v4-core/src/types/Currency.sol/library.CurrencyLibrary.md#transfer).
Requirements:
- `to` cannot be the zero address.
- the caller must have a balance of at least `value`.


```solidity
function transfer(address to, uint256 value) public virtual returns (bool);
```

### allowance

See [IERC20-allowance](/lib/v4-periphery/lib/permit2/src/interfaces/IAllowanceTransfer.sol/interface.IAllowanceTransfer.md#allowance).


```solidity
function allowance(address owner, address spender) public view virtual returns (uint256);
```

### approve

See [IERC20-approve](/lib/v4-periphery/lib/permit2/src/interfaces/IAllowanceTransfer.sol/interface.IAllowanceTransfer.md#approve).
NOTE: If `value` is the maximum `uint256`, the allowance is not updated on
`transferFrom`. This is semantically equivalent to an infinite approval.
Requirements:
- `spender` cannot be the zero address.


```solidity
function approve(address spender, uint256 value) public virtual returns (bool);
```

### transferFrom

See [IERC20-transferFrom](/lib/v4-periphery/lib/permit2/src/interfaces/IAllowanceTransfer.sol/interface.IAllowanceTransfer.md#transferfrom).
Emits an {Approval} event indicating the updated allowance. This is not
required by the EIP. See the note at the beginning of {ERC20}.
NOTE: Does not update the allowance if the current allowance
is the maximum `uint256`.
Requirements:
- `from` and `to` cannot be the zero address.
- `from` must have a balance of at least `value`.
- the caller must have allowance for ``from``'s tokens of at least
`value`.


```solidity
function transferFrom(address from, address to, uint256 value) public virtual returns (bool);
```

### _transfer

Moves a `value` amount of tokens from `from` to `to`.
This internal function is equivalent to [transfer](/src/common/OutrunERC20Init.sol/abstract.OutrunERC20Init.md#transfer), and can be used to
e.g. implement automatic token fees, slashing mechanisms, etc.
Emits a {Transfer} event.
NOTE: This function is not virtual, [_update](/src/common/OutrunERC20Init.sol/abstract.OutrunERC20Init.md#_update) should be overridden instead.


```solidity
function _transfer(address from, address to, uint256 value) internal virtual;
```

### _update

Transfers a `value` amount of tokens from `from` to `to`, or alternatively mints (or burns) if `from`
(or `to`) is the zero address. All customizations to transfers, mints, and burns should be done by overriding
this function.
Emits a {Transfer} event.


```solidity
function _update(address from, address to, uint256 value) internal virtual;
```

### _mint

Creates a `value` amount of tokens and assigns them to `account`, by transferring it from address(0).
Relies on the `_update` mechanism
Emits a {Transfer} event with `from` set to the zero address.
NOTE: This function is not virtual, [_update](/src/common/OutrunERC20Init.sol/abstract.OutrunERC20Init.md#_update) should be overridden instead.


```solidity
function _mint(address account, uint256 value) internal;
```

### _burn

Destroys a `value` amount of tokens from `account`, lowering the total supply.
Relies on the `_update` mechanism.
Emits a {Transfer} event with `to` set to the zero address.
NOTE: This function is not virtual, [_update](/src/common/OutrunERC20Init.sol/abstract.OutrunERC20Init.md#_update) should be overridden instead


```solidity
function _burn(address account, uint256 value) internal;
```

### _approve

Sets `value` as the allowance of `spender` over the `owner` s tokens.
This internal function is equivalent to `approve`, and can be used to
e.g. set automatic allowances for certain subsystems, etc.
Emits an {Approval} event.
Requirements:
- `owner` cannot be the zero address.
- `spender` cannot be the zero address.
Overrides to this logic should be done to the variant with an additional `bool emitEvent` argument.


```solidity
function _approve(address owner, address spender, uint256 value) internal;
```

### _approve

Variant of [_approve](/src/common/OutrunERC20Init.sol/abstract.OutrunERC20Init.md#_approve) with an optional flag to enable or disable the {Approval} event.
By default (when calling [_approve](/src/common/OutrunERC20Init.sol/abstract.OutrunERC20Init.md#_approve)) the flag is set to true. On the other hand, approval changes made by
`_spendAllowance` during the `transferFrom` operation set the flag to false. This saves gas by not emitting any
`Approval` event during `transferFrom` operations.
Anyone who wishes to continue emitting `Approval` events on the`transferFrom` operation can force the flag to
true using the following override:
```
function _approve(address owner, address spender, uint256 value, bool) internal virtual override {
super._approve(owner, spender, value, true);
}
```
Requirements are the same as [_approve](/src/common/OutrunERC20Init.sol/abstract.OutrunERC20Init.md#_approve).


```solidity
function _approve(address owner, address spender, uint256 value, bool emitEvent) internal virtual;
```

### _spendAllowance

Updates `owner` s allowance for `spender` based on spent `value`.
Does not update the allowance value in case of infinite allowance.
Revert if not enough allowance is available.
Does not emit an {Approval} event.


```solidity
function _spendAllowance(address owner, address spender, uint256 value) internal virtual;
```

## Structs
### ERC20Storage
**Note:**
storage-location: erc7201:openzeppelin.storage.ERC20


```solidity
struct ERC20Storage {
    mapping(address account => uint256) _balances;

    mapping(address account => mapping(address spender => uint256)) _allowances;

    uint256 _totalSupply;

    string _name;
    string _symbol;
}
```

