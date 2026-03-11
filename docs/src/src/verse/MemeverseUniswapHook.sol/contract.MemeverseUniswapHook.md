# MemeverseUniswapHook
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/162e33593b63cbed2f42e2c0d082c8afbd5ba111/src/verse/MemeverseUniswapHook.sol)

**Inherits:**
[IMemeverseUniswapHook](/src/verse/interfaces/IMemeverseUniswapHook.sol/interface.IMemeverseUniswapHook.md), IUnlockCallback, BaseHook, [ReentrancyGuard](/src/common/ReentrancyGuard.sol/abstract.ReentrancyGuard.md), Ownable

**Title:**
MemeverseUniswapHook

A Uniswap v4 hook implementing:
- Full-range liquidity management (single position from MIN_TICK to MAX_TICK)
- A custom ERC20 LP token per pool
- Dynamic fees for adverse swaps (based on projected price impact, an EWMA volatility signal,
  and a linearly decayed short-term cumulative impact signal)
- Anti-sniping protection during the initial blocks after pool initialization

High-level flow:
- `beforeInitialize`: validates pool config and deploys the pool-specific LP token.
- `beforeSwap`: enforces anti-snipe rules, computes a dynamic fee, and accrues fees.
- `afterSwap`: updates ewVWAP, EW volatility, and short-term impact state, and optionally takes protocol fees.
- `addLiquidity` / `removeLiquidity`: mint/burn LP tokens while adding/removing full-range liquidity.
- `claimFees`: allows LPs to claim accrued fees (tracked via per-share accounting).


## State Variables
### ZERO_BYTES

```solidity
bytes internal constant ZERO_BYTES = bytes("")
```


### MIN_TICK

```solidity
int24 internal constant MIN_TICK = -887200
```


### MAX_TICK

```solidity
int24 internal constant MAX_TICK = 887200
```


### TICK_SPACING

```solidity
int24 internal constant TICK_SPACING = 200
```


### MINIMUM_LIQUIDITY

```solidity
uint16 internal constant MINIMUM_LIQUIDITY = 1000
```


### PRECISION

```solidity
uint256 internal constant PRECISION = 1e18
```


### PROTOCOL_FEE_RATIO_BPS

```solidity
uint256 public constant PROTOCOL_FEE_RATIO_BPS = 3000
```


### LP_FEE_RATIO_BPS

```solidity
uint256 public constant LP_FEE_RATIO_BPS = 7000
```


### ANTI_SNIPE_MAX_SLIPPAGE_BPS

```solidity
uint256 public constant ANTI_SNIPE_MAX_SLIPPAGE_BPS = 200
```


### BPS_BASE

```solidity
uint256 public constant BPS_BASE = 10000
```


### PPM_BASE

```solidity
uint256 public constant PPM_BASE = 1_000_000
```


### treasury

```solidity
address public treasury
```


### antiSnipeDurationBlocks

```solidity
uint256 public antiSnipeDurationBlocks
```


### maxAntiSnipeProbabilityBase

```solidity
uint256 public maxAntiSnipeProbabilityBase
```


### isProtocolFeeCurrency

```solidity
mapping(Currency => bool) public isProtocolFeeCurrency
```


### poolInfo

```solidity
mapping(PoolId => PoolInfo) public poolInfo
```


### antiSnipeBlockData

```solidity
mapping(PoolId => mapping(uint256 => AntiSnipeBlockData)) public antiSnipeBlockData
```


### userFeeState

```solidity
mapping(PoolId => mapping(address => UserFeeState)) public userFeeState
```


### impactStatePpm
Decayed state impact (in ppm domain) used for state-driven fee surcharge.


```solidity
mapping(PoolId => uint256) public impactStatePpm
```


### burstStatePpm
Fast-decay state impact (in ppm domain) for short-horizon burst pressure.


```solidity
mapping(PoolId => uint256) public burstStatePpm
```


### lastTimestamp
Last timestamp when `impactStatePpm` was updated for a pool.


```solidity
mapping(PoolId => uint256) public lastTimestamp
```


### baseFeeBps
Base fee (in bps) used when there is insufficient state to compute a dynamic fee.


```solidity
uint24 public baseFeeBps = 100
```


### maxFeeBps
Upper bound for the dynamic fee (in bps).


```solidity
uint24 public maxFeeBps = 10000
```


### impactLinearFeeCoeffBps
Linear impact fee coefficient from impact-ppm to fee-bps:
impactLinearFeeBps = impactPpm * coeff / 1e6.


```solidity
uint256 public impactLinearFeeCoeffBps = 3_000
```


### impactQuadraticFeeCoeffBps
Quadratic impact fee coefficient from impact-ppm to fee-bps:
impactQuadraticFeeBps = coeff * impactPpm^2 / 1e12.


```solidity
uint256 public impactQuadraticFeeCoeffBps = 1_000
```


### stateFeeCoeffBps
State fee coefficient from state-ppm to fee-bps:
stateFeeRawBps = statePpm * coeff / 1e6.


```solidity
uint256 public stateFeeCoeffBps = 1_400
```


### stateFeeCapBps
Maximum state-driven surcharge (bps).


```solidity
uint256 public stateFeeCapBps = 1_500
```


### stateInflowCapBps
Per-swap inflow cap into decayed state (in bps, internally converted to ppm).


```solidity
uint256 public stateInflowCapBps = 220
```


### timeDecayHalfLife
Half-life (seconds) controlling decay of the cumulative price-change signal.


```solidity
uint256 public timeDecayHalfLife = 300
```


### burstStateFeeCoeffBps
Fast-channel fee coefficient from burst-state-ppm to fee-bps.


```solidity
uint256 public burstStateFeeCoeffBps = 1_200
```


### burstStateFeeCapBps
Maximum fast-channel surcharge (bps).


```solidity
uint256 public burstStateFeeCapBps = 500
```


### burstStateInflowCapBps
Per-swap inflow cap into fast-decay state (in bps, converted to ppm internally).


```solidity
uint256 public burstStateInflowCapBps = 80
```


### burstTimeDecayHalfLife
Fast-channel half-life (seconds) for short-horizon density pressure.


```solidity
uint256 public burstTimeDecayHalfLife = 15
```


### TRANSIENT_FEE_SLOT
Transient storage slot used to pass the computed dynamic fee from `beforeSwap` to `afterSwap`.


```solidity
uint256 constant TRANSIENT_FEE_SLOT = 0x00
```


## Functions
### constructor


```solidity
constructor(
    IPoolManager _manager,
    address _owner,
    address _treasury,
    uint256 _antiSnipeDurationBlocks,
    uint256 _maxAntiSnipeProbabilityBase
) BaseHook(_manager) Ownable(_owner);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`_manager`|`IPoolManager`|Uniswap v4 pool manager.|
|`_owner`|`address`|Contract owner.|
|`_treasury`|`address`|Treasury receiving protocol fees (if enabled).|
|`_antiSnipeDurationBlocks`|`uint256`|Number of blocks after init where anti-snipe rules apply.|
|`_maxAntiSnipeProbabilityBase`|`uint256`|Upper bound for probability base used by anti-snipe randomness.|


### ensure


```solidity
modifier ensure(uint256 deadline) ;
```

### setTreasury

Updates the treasury address.

Only callable by the owner.


```solidity
function setTreasury(address _treasury) external onlyOwner;
```

### setProtocolFeeCurrency

Enables/disables a currency as the protocol fee currency selector.

If both currencies are enabled, `currency0` is preferred by `_getPoolProtocolFeeCurrency`.


```solidity
function setProtocolFeeCurrency(Currency currency, bool enabled) external onlyOwner;
```

### setAntiSnipeDuration

Sets the number of blocks anti-snipe protection remains active after pool initialization.


```solidity
function setAntiSnipeDuration(uint256 _durationBlocks) external onlyOwner;
```

### setMaxAntiSnipeProbabilityBase

Sets the max probability base used by anti-snipe randomness.


```solidity
function setMaxAntiSnipeProbabilityBase(uint256 _maxBase) external onlyOwner;
```

### setBaseFee

Sets the base dynamic fee in bps.


```solidity
function setBaseFee(uint24 _base) external onlyOwner;
```

### setMaxFee

Sets the maximum dynamic fee in bps.


```solidity
function setMaxFee(uint24 _max) external onlyOwner;
```

### setImpactLinearFeeCoeffBps

Sets linear impact coefficient with ppm-normalized impact and bps output.


```solidity
function setImpactLinearFeeCoeffBps(uint256 _coeff) external onlyOwner;
```

### setImpactQuadraticFeeCoeffBps

Sets quadratic impact coefficient with ppm-normalized impact and bps output.


```solidity
function setImpactQuadraticFeeCoeffBps(uint256 _coeff) external onlyOwner;
```

### setStateFeeCoeffBps

Sets state fee coefficient with ppm-normalized state and bps output.


```solidity
function setStateFeeCoeffBps(uint256 _coeff) external onlyOwner;
```

### setStateFeeCapBps

Sets state fee cap in bps.


```solidity
function setStateFeeCapBps(uint256 _cap) external onlyOwner;
```

### setStateInflowCapBps

Sets per-swap inflow cap into decayed state in bps.


```solidity
function setStateInflowCapBps(uint256 _cap) external onlyOwner;
```

### setTimeDecayHalfLife

Sets half-life (seconds) for decay of cumulative price-change signal.


```solidity
function setTimeDecayHalfLife(uint256 _halfLife) external onlyOwner;
```

### setBurstStateFeeCoeffBps

Sets fast-channel state fee coefficient with ppm-normalized burst state and bps output.


```solidity
function setBurstStateFeeCoeffBps(uint256 _coeff) external onlyOwner;
```

### setBurstStateFeeCapBps

Sets fast-channel state fee cap in bps.


```solidity
function setBurstStateFeeCapBps(uint256 _cap) external onlyOwner;
```

### setBurstStateInflowCapBps

Sets per-swap inflow cap into fast-decay state in bps.


```solidity
function setBurstStateInflowCapBps(uint256 _cap) external onlyOwner;
```

### setBurstTimeDecayHalfLife

Sets fast-channel half-life (seconds).


```solidity
function setBurstTimeDecayHalfLife(uint256 _halfLife) external onlyOwner;
```

### getHookPermissions

Declares which hook callbacks are enabled for this hook.


```solidity
function getHookPermissions() public pure override returns (Hooks.Permissions memory);
```

### _beforeInitialize


```solidity
function _beforeInitialize(address, PoolKey calldata key, uint160) internal override returns (bytes4);
```

### _beforeSwap

Enforces anti-snipe constraints, computes the dynamic fee, and accrues protocol/LP fees.
The computed dynamic fee is persisted in transient storage for use in `afterSwap`.


```solidity
function _beforeSwap(address sender, PoolKey calldata key, SwapParams calldata params, bytes calldata)
    internal
    override
    returns (bytes4, BeforeSwapDelta, uint24);
```

### _checkAntiSnipe


```solidity
function _checkAntiSnipe(PoolId poolId, SwapParams calldata params)
    internal
    returns (bool pass, AntiSnipeFailureReason failureReason);
```

### _getHookPriceLimit


```solidity
function _getHookPriceLimit(uint160 sqrtPriceX96, bool zeroForOne) internal pure returns (uint160);
```

### _afterSwap


```solidity
function _afterSwap(address, PoolKey calldata key, SwapParams calldata params, BalanceDelta delta, bytes calldata)
    internal
    override
    returns (bytes4, int128);
```

### _beforeAddLiquidity

Restricts add-liquidity modifications to calls coming from this hook itself.


```solidity
function _beforeAddLiquidity(address sender, PoolKey calldata, ModifyLiquidityParams calldata, bytes calldata)
    internal
    view
    override
    returns (bytes4);
```

### addLiquidity

Adds full-range liquidity to the specified pool and mints the pool’s LP tokens.

This function relies on the PoolManager to pull the required token amounts from the caller.


```solidity
function addLiquidity(AddLiquidityParams calldata params)
    external
    ensure(params.deadline)
    nonReentrant
    returns (uint128 liquidity);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`params`|`AddLiquidityParams`|Parameters including desired/min amounts and recipient.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`liquidity`|`uint128`|Amount of liquidity minted (and LP tokens minted 1:1, minus MINIMUM_LIQUIDITY on first deposit).|


### removeLiquidity

Removes full-range liquidity from the specified pool by burning LP tokens.

Uses `PoolManager.unlock` to perform the liquidity removal and token settlement.


```solidity
function removeLiquidity(RemoveLiquidityParams calldata params)
    external
    ensure(params.deadline)
    nonReentrant
    returns (BalanceDelta delta);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`params`|`RemoveLiquidityParams`|Parameters including LP amount to burn and deadline.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`delta`|`BalanceDelta`|Net token amounts resulting from the liquidity removal.|


### claimFees

Claims accrued LP fees for `msg.sender` for the given pool.

Requires the pool to have been initialized (LP token deployed).


```solidity
function claimFees(PoolKey calldata key) external nonReentrant;
```

### unlockCallback

Callback invoked by the PoolManager during `unlock` flow.

Only callable by the PoolManager.


```solidity
function unlockCallback(bytes calldata rawData) external override onlyPoolManager returns (bytes memory);
```

### _transferCurrency

Transfers `amount` of `currency` to `to`. Supports native currency (address(0)) and ERC20.


```solidity
function _transferCurrency(Currency currency, address to, uint256 amount) internal;
```

### _settleDeltas


```solidity
function _settleDeltas(address sender, PoolKey memory key, BalanceDelta delta) internal;
```

### _takeDeltas


```solidity
function _takeDeltas(address recipient, PoolKey memory key, BalanceDelta delta) internal;
```

### _getPoolProtocolFeeCurrency

Selects which pool currency is used to charge protocol fees (if configured).


```solidity
function _getPoolProtocolFeeCurrency(Currency currency0, Currency currency1) internal view returns (Currency);
```

### updateUserSnapshot

Updates the user fee accounting snapshot for a pool.

Accrues any newly earned fees into `pendingFee0/1` and updates per-share offsets.


```solidity
function updateUserSnapshot(PoolId id, address user) public override;
```

### _calculateDynamicFee

Computes dynamic fee in bps with dual ppm-domain states:
fee = base + impactLinear + impactQuadratic + capped(slowStateFee) + capped(burstStateFee).


```solidity
function _calculateDynamicFee(PoolId poolId, PoolKey calldata, SwapParams calldata params)
    internal
    view
    returns (uint256 feeBps, uint256 projectedStatePpm, uint256 projectedBurstStatePpm);
```

### _priceMovePpm


```solidity
function _priceMovePpm(uint160 preSqrtPrice, uint160 postSqrtPrice) internal pure returns (uint256);
```

### _approxDecay

Approximates an exponential decay using a simple linear ramp to zero:
- returns 1e18 when deltaT == 0
- returns 0 when deltaT >= 2 * halfLife
- otherwise returns (1e18 * (1 - deltaT / (2 * halfLife)))


```solidity
function _approxDecay(uint256 deltaT, uint256 halfLife) internal pure returns (uint256);
```
