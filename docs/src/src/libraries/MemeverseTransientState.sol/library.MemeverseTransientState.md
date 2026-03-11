# MemeverseTransientState
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/f6152b6dbfadcd8a23a2d518905418243cf2a5e1/src/libraries/MemeverseTransientState.sol)

**Title:**
MemeverseTransientState

Thin wrapper around transient storage used by Memeverse swap flows.

Keeps raw `tstore` / `tload` isolated from hook business logic while still supporting
dynamic same-transaction anti-snipe ticket slots.


## State Variables
### SWAP_FEE_BPS_SLOT

```solidity
bytes32 internal constant SWAP_FEE_BPS_SLOT = bytes32(uint256(keccak256("memeverse.transient.swap-fee-bps")) - 1)
```


### PRE_SWAP_SQRT_PRICE_SLOT

```solidity
bytes32 internal constant PRE_SWAP_SQRT_PRICE_SLOT =
    bytes32(uint256(keccak256("memeverse.transient.pre-swap-sqrt-price")) - 1)
```


### REQUESTED_INPUT_BUDGET_SLOT

```solidity
bytes32 internal constant REQUESTED_INPUT_BUDGET_SLOT =
    bytes32(uint256(keccak256("memeverse.transient.requested-input-budget")) - 1)
```


### ANTI_SNIPE_TICKET_SEED

```solidity
bytes32 internal constant ANTI_SNIPE_TICKET_SEED = keccak256("memeverse.anti-snipe.ticket")
```


### ANTI_SNIPE_REQUEST_LATCH_SEED

```solidity
bytes32 internal constant ANTI_SNIPE_REQUEST_LATCH_SEED = keccak256("memeverse.anti-snipe.request-latch")
```


## Functions
### storeSwapContext


```solidity
function storeSwapContext(uint256 feeBps, uint160 preSqrtPriceX96) internal;
```

### loadSwapFeeBps


```solidity
function loadSwapFeeBps() internal view returns (uint256 feeBps);
```

### loadPreSwapSqrtPriceX96


```solidity
function loadPreSwapSqrtPriceX96() internal view returns (uint160 preSqrtPriceX96);
```

### armAntiSnipeTicket


```solidity
function armAntiSnipeTicket(PoolId poolId, address caller, SwapParams calldata params, uint256 inputBudget)
    internal;
```

### consumeAntiSnipeTicket


```solidity
function consumeAntiSnipeTicket(PoolId poolId, address caller, SwapParams calldata params)
    internal
    returns (uint256 inputBudget);
```

### storeRequestedInputBudget


```solidity
function storeRequestedInputBudget(uint256 inputBudget) internal;
```

### loadRequestedInputBudget


```solidity
function loadRequestedInputBudget() internal view returns (uint256 inputBudget);
```

### markAntiSnipeRequestForPool


```solidity
function markAntiSnipeRequestForPool(PoolId poolId) internal returns (bool firstRequest);
```

### antiSnipeTicketSlot


```solidity
function antiSnipeTicketSlot(PoolId poolId, address caller, SwapParams calldata params)
    internal
    pure
    returns (bytes32);
```

### antiSnipeRequestLatchSlot


```solidity
function antiSnipeRequestLatchSlot(PoolId poolId) internal pure returns (bytes32);
```

