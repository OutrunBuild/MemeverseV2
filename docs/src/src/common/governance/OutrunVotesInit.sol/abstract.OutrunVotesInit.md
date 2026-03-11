# OutrunVotesInit
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/f6152b6dbfadcd8a23a2d518905418243cf2a5e1/src/common/governance/OutrunVotesInit.sol)

**Inherits:**
Context, [OutrunEIP712Init](/src/common/cryptography/OutrunEIP712Init.sol/abstract.OutrunEIP712Init.md), [OutrunNoncesInit](/src/common/OutrunNoncesInit.sol/abstract.OutrunNoncesInit.md), IERC5805

This is a base abstract contract that tracks voting units, which are a measure of voting power that can be
transferred, and provides a system of vote delegation, where an account can delegate its voting units to a sort of
"representative" that will pool delegated voting units from different accounts and can then use it to vote in
decisions. In fact, voting units _must_ be delegated in order to count as actual votes, and an account has to
delegate those votes to itself if it wishes to participate in decisions and does not have a trusted representative.
This contract is often combined with a token contract such that voting units correspond to token units. For an
example, see {ERC721Votes}.
The full history of delegate votes is tracked on-chain so that governance protocols can consider votes as distributed
at a particular block number to protect against flash loans and double voting. The opt-in delegate system makes the
cost of this history tracking optional.
When using this module the derived contract must implement [_getVotingUnits](/src/common/governance/OutrunVotesInit.sol/abstract.OutrunVotesInit.md#_getvotingunits) (for example, make it return
[ERC721-balanceOf](/lib/v4-periphery/lib/v4-core/src/types/Currency.sol/library.CurrencyLibrary.md#balanceof)), and can use [_transferVotingUnits](/src/common/governance/OutrunVotesInit.sol/abstract.OutrunVotesInit.md#_transfervotingunits) to track a change in the distribution of those units (in the
previous example, it would be included in [ERC721-_update](/src/common/governance/OutrunERC20VotesInit.sol/abstract.OutrunERC20VotesInit.md#_update)).


## State Variables
### DELEGATION_TYPEHASH

```solidity
bytes32 private constant DELEGATION_TYPEHASH =
    keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)")
```


### VOTES_STORAGE_LOCATION

```solidity
bytes32 private constant VOTES_STORAGE_LOCATION =
    0x208f5ae36e3aa0934f277adce61242847ae71fe37b1a71ca90478a975291f400
```


## Functions
### _getVotesStorage


```solidity
function _getVotesStorage() private pure returns (VotesStorage storage $);
```

### __OutrunVotes_init


```solidity
function __OutrunVotes_init() internal onlyInitializing;
```

### __OutrunVotes_init_unchained


```solidity
function __OutrunVotes_init_unchained() internal onlyInitializing;
```

### clock

Clock used for flagging checkpoints. Can be overridden to implement timestamp based
checkpoints (and voting), in which case [CLOCK_MODE](/src/common/governance/OutrunVotesInit.sol/abstract.OutrunVotesInit.md#clock_mode) should be overridden as well to match.


```solidity
function clock() public view virtual returns (uint48);
```

### CLOCK_MODE

Machine-readable description of the clock as specified in ERC-6372.


```solidity
function CLOCK_MODE() public view virtual returns (string memory);
```

### _validateTimepoint

Validate that a timepoint is in the past, and return it as a uint48.


```solidity
function _validateTimepoint(uint256 timepoint) internal view returns (uint48);
```

### getVotes

Returns the current amount of votes that `account` has.


```solidity
function getVotes(address account) public view virtual returns (uint256);
```

### getPastVotes

Returns the amount of votes that `account` had at a specific moment in the past. If the `clock()` is
configured to use block numbers, this will return the value at the end of the corresponding block.
Requirements:
- `timepoint` must be in the past. If operating using block numbers, the block must be already mined.


```solidity
function getPastVotes(address account, uint256 timepoint) public view virtual returns (uint256);
```

### getPastTotalSupply

Returns the total supply of votes available at a specific moment in the past. If the `clock()` is
configured to use block numbers, this will return the value at the end of the corresponding block.
NOTE: This value is the sum of all available votes, which is not necessarily the sum of all delegated votes.
Votes that have not been delegated are still part of total supply, even though they would not participate in a
vote.
Requirements:
- `timepoint` must be in the past. If operating using block numbers, the block must be already mined.


```solidity
function getPastTotalSupply(uint256 timepoint) public view virtual returns (uint256);
```

### _getTotalSupply

Returns the current total supply of votes.


```solidity
function _getTotalSupply() internal view virtual returns (uint256);
```

### delegates

Returns the delegate that `account` has chosen.


```solidity
function delegates(address account) public view virtual returns (address);
```

### delegate

Delegates votes from the sender to `delegatee`.


```solidity
function delegate(address delegatee) public virtual;
```

### delegateBySig

Delegates votes from signer to `delegatee`.


```solidity
function delegateBySig(address delegatee, uint256 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s)
    public
    virtual;
```

### _delegate

Delegate all of `account`'s voting units to `delegatee`.
Emits events [IVotes-DelegateChanged](/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/governance/utils/IVotes.sol/interface.IVotes.md#delegatechanged) and [IVotes-DelegateVotesChanged](/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/governance/utils/IVotes.sol/interface.IVotes.md#delegatevoteschanged).


```solidity
function _delegate(address account, address delegatee) internal virtual;
```

### _transferVotingUnits

Transfers, mints, or burns voting units. To register a mint, `from` should be zero. To register a burn, `to`
should be zero. Total supply of voting units will be adjusted with mints and burns.


```solidity
function _transferVotingUnits(address from, address to, uint256 amount) internal virtual;
```

### _moveDelegateVotes

Moves delegated votes from one delegate to another.


```solidity
function _moveDelegateVotes(address from, address to, uint256 amount) internal virtual;
```

### _numCheckpoints

Get number of checkpoints for `account`.


```solidity
function _numCheckpoints(address account) internal view virtual returns (uint32);
```

### _checkpoints

Get the `pos`-th checkpoint for `account`.


```solidity
function _checkpoints(address account, uint32 pos)
    internal
    view
    virtual
    returns (Checkpoints.Checkpoint208 memory);
```

### _push


```solidity
function _push(
    Checkpoints.Trace208 storage store,
    function(uint208, uint208) view returns (uint208) op,
    uint208 delta
) private returns (uint208 oldValue, uint208 newValue);
```

### _add


```solidity
function _add(uint208 a, uint208 b) private pure returns (uint208);
```

### _subtract


```solidity
function _subtract(uint208 a, uint208 b) private pure returns (uint208);
```

### _getVotingUnits

Must return the voting units held by an account.


```solidity
function _getVotingUnits(address) internal view virtual returns (uint256);
```

## Errors
### ERC6372InconsistentClock
The clock was incorrectly modified.


```solidity
error ERC6372InconsistentClock();
```

### ERC5805FutureLookup
Lookup to future votes is not available.


```solidity
error ERC5805FutureLookup(uint256 timepoint, uint48 clock);
```

## Structs
### VotesStorage

```solidity
struct VotesStorage {
    mapping(address account => address) _delegatee;

    mapping(address delegatee => Checkpoints.Trace208) _delegateCheckpoints;

    Checkpoints.Trace208 _totalCheckpoints;
}
```

