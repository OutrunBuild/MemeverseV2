# CurrencySettler
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/5f1e475fc32b5b93b8a81ca9d545cacad2f7567c/src/libraries/CurrencySettler.sol)

**Title:**
CurrencySettler

Production helper for settling and taking PoolManager deltas.

Mirrors the standard Uniswap v4 settle/take behavior without depending on upstream test utilities.


## Functions
### settle

Settles an amount owed to the PoolManager.


```solidity
function settle(Currency currency, IPoolManager manager, address payer, uint256 amount, bool burn) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`currency`|`Currency`|The currency being settled.|
|`manager`|`IPoolManager`|The pool manager receiving settlement.|
|`payer`|`address`|The address paying the amount.|
|`amount`|`uint256`|The amount to settle.|
|`burn`|`bool`|If true, burns ERC-6909 balance instead of transferring ERC20/native.|


### take

Takes an amount owed from the PoolManager.


```solidity
function take(Currency currency, IPoolManager manager, address recipient, uint256 amount, bool claims) internal;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`currency`|`Currency`|The currency being taken.|
|`manager`|`IPoolManager`|The pool manager paying out.|
|`recipient`|`address`|The address receiving the payout.|
|`amount`|`uint256`|The amount to receive.|
|`claims`|`bool`|If true, mints ERC-6909 claim tokens instead of transferring out underlying currency.|


