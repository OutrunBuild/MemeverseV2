# OutrunERC20PermitInit
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/5f1e475fc32b5b93b8a81ca9d545cacad2f7567c/src/common/OutrunERC20PermitInit.sol)

**Inherits:**
[OutrunERC20Init](/src/common/OutrunERC20Init.sol/abstract.OutrunERC20Init.md), IERC20Permit, [OutrunEIP712Init](/src/common/cryptography/OutrunEIP712Init.sol/abstract.OutrunEIP712Init.md), [OutrunNoncesInit](/src/common/OutrunNoncesInit.sol/abstract.OutrunNoncesInit.md)

(Just for minimal proxy)
Implementation of the ERC-20 Permit extension allowing approvals to be made via signatures, as defined in
https://eips.ethereum.org/EIPS/eip-2612[ERC-2612].
Adds the [permit](/src/common/OutrunERC20PermitInit.sol/abstract.OutrunERC20PermitInit.md#permit) method, which can be used to change an account's ERC-20 allowance (see [IERC20-allowance](/lib/v4-periphery/lib/permit2/src/interfaces/IAllowanceTransfer.sol/interface.IAllowanceTransfer.md#allowance)) by
presenting a message signed by the account. By not relying on `[IERC20-approve](/lib/v4-periphery/lib/permit2/src/interfaces/IAllowanceTransfer.sol/interface.IAllowanceTransfer.md#approve)`, the token holder account doesn't
need to send a transaction, and thus is not required to hold Ether at all.


## State Variables
### PERMIT_TYPEHASH

```solidity
bytes32 private constant PERMIT_TYPEHASH =
    keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)")
```


## Functions
### __OutrunERC20Permit_init

Initializes the {EIP712} domain separator using the `name` parameter, and setting `version` to `"1"`.
It's a good idea to use the same `name` that is defined as the ERC-20 token name.


```solidity
function __OutrunERC20Permit_init(string memory _name) internal onlyInitializing;
```

### __ERC20Permit_init_unchained


```solidity
function __ERC20Permit_init_unchained(string memory) internal onlyInitializing;
```

### permit

Sets `value` as the allowance of `spender` over ``owner``'s tokens,
given ``owner``'s signed approval.
IMPORTANT: The same issues {IERC20-approve} has related to transaction
ordering also applies here.
Emits an {Approval} event.
Requirements:
- `spender` cannot be the zero address.
- `deadline` must be a timestamp in the future.
- `v`, `r` and `s` must be a valid `secp256k1` signature from `owner`
over the EIP712-formatted function arguments.
- the signature must use ``owner``'s current nonce (see {nonces}).
For more information on the signature format, see the
https://eips.ethereum.org/EIPS/eip-2612#specification[relevant EIP
section].
CAUTION: See Security Considerations above.


```solidity
function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
    public
    virtual;
```

### nonces

Returns the current nonce for `owner`. This value must be
included whenever a signature is generated for {permit}.
Every successful call to {permit} increases ``owner``'s nonce by one. This
prevents a signature from being used multiple times.


```solidity
function nonces(address owner) public view virtual override(IERC20Permit, OutrunNoncesInit) returns (uint256);
```

### DOMAIN_SEPARATOR

Returns the domain separator used in the encoding of the signature for {permit}, as defined by {EIP712}.


```solidity
function DOMAIN_SEPARATOR() external view virtual returns (bytes32);
```

## Errors
### ERC2612ExpiredSignature
Permit deadline has expired.


```solidity
error ERC2612ExpiredSignature(uint256 deadline);
```

### ERC2612InvalidSigner
Mismatched signature.


```solidity
error ERC2612InvalidSigner(address signer, address owner);
```

