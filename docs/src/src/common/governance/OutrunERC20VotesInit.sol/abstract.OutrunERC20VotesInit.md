# OutrunERC20VotesInit
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/f6152b6dbfadcd8a23a2d518905418243cf2a5e1/src/common/governance/OutrunERC20VotesInit.sol)

**Inherits:**
[OutrunERC20Init](/src/common/OutrunERC20Init.sol/abstract.OutrunERC20Init.md), [OutrunVotesInit](/src/common/governance/OutrunVotesInit.sol/abstract.OutrunVotesInit.md)

Extension of ERC-20 to support Compound-like voting and delegation. This version is more generic than Compound's,
and supports token supply up to 2^208^ - 1, while COMP is limited to 2^96^ - 1.
NOTE: This contract does not provide interface compatibility with Compound's COMP token.
This extension keeps a history (checkpoints) of each account's vote power. Vote power can be delegated either
by calling the [Votes-delegate](/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/governance/utils/IVotes.sol/interface.IVotes.md#delegate) function directly, or by providing a signature to be used with [Votes-delegateBySig](/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/governance/utils/IVotes.sol/interface.IVotes.md#delegatebysig). Voting
power can be queried through the public accessors [Votes-getVotes](/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/governance/IGovernor.sol/interface.IGovernor.md#getvotes) and [Votes-getPastVotes](/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/governance/utils/IVotes.sol/interface.IVotes.md#getpastvotes).
By default, token balance does not account for voting power. This makes transfers cheaper. The downside is that it
requires users to delegate to themselves in order to activate checkpoints and have their voting power tracked.


## Functions
### __OutrunERC20Votes_init


```solidity
function __OutrunERC20Votes_init() internal onlyInitializing;
```

### __OutrunERC20Votes_init_unchained


```solidity
function __OutrunERC20Votes_init_unchained() internal onlyInitializing;
```

### _maxSupply

Maximum token supply. Defaults to `type(uint208).max` (2^208^ - 1).
This maximum is enforced in [_update](/src/common/governance/OutrunERC20VotesInit.sol/abstract.OutrunERC20VotesInit.md#_update). It limits the total supply of the token, which is otherwise a uint256,
so that checkpoints can be stored in the Trace208 structure used by {Votes}. Increasing this value will not
remove the underlying limitation, and will cause [_update](/src/common/governance/OutrunERC20VotesInit.sol/abstract.OutrunERC20VotesInit.md#_update) to fail because of a math overflow in
{Votes-_transferVotingUnits}. An override could be used to further restrict the total supply (to a lower value) if
additional logic requires it. When resolving override conflicts on this function, the minimum should be
returned.


```solidity
function _maxSupply() internal view virtual returns (uint256);
```

### _update

Move voting power when tokens are transferred.
Emits a [IVotes-DelegateVotesChanged](/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/governance/utils/IVotes.sol/interface.IVotes.md#delegatevoteschanged) event.


```solidity
function _update(address from, address to, uint256 value) internal virtual override;
```

### _getVotingUnits

Returns the voting units of an `account`.
WARNING: Overriding this function may compromise the internal vote accounting.
`ERC20Votes` assumes tokens map to voting units 1:1 and this is not easy to change.


```solidity
function _getVotingUnits(address account) internal view virtual override returns (uint256);
```

### numCheckpoints

Get number of checkpoints for `account`.


```solidity
function numCheckpoints(address account) public view virtual returns (uint32);
```

### checkpoints

Get the `pos`-th checkpoint for `account`.


```solidity
function checkpoints(address account, uint32 pos) public view virtual returns (Checkpoints.Checkpoint208 memory);
```

## Errors
### ERC20ExceededSafeSupply
Total supply cap has been exceeded, introducing a risk of votes overflowing.


```solidity
error ERC20ExceededSafeSupply(uint256 increasedSupply, uint256 cap);
```

