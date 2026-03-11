# MemeverseUniswapHook
[Git Source](https://github.com/OutrunBuild/MemeverseV2/blob/f6152b6dbfadcd8a23a2d518905418243cf2a5e1/src/swap/MemeverseUniswapHook.sol)

**Inherits:**
[IMemeverseUniswapHook](/src/swap/interfaces/IMemeverseUniswapHook.sol/interface.IMemeverseUniswapHook.md), IUnlockCallback, BaseHook, [ReentrancyGuard](/src/common/ReentrancyGuard.sol/abstract.ReentrancyGuard.md), Ownable

**Title:**
MemeverseUniswapHook

A Uniswap v4 hook implementing:
- Full-range liquidity management (single position from MIN_TICK to MAX_TICK)
- A custom ERC20 LP token per pool
- Dynamic fees for adverse swaps (based on projected price impact, an EWMA volatility signal,
and a linearly decayed short-term cumulative impact signal)
- Anti-sniping protection during the initial blocks after pool initialization

High-level flow:
- This contract is the Core engine for the Memeverse v4 integration.
- End-user and SDK-facing flows are expected to enter via `MemeverseSwapRouter`.
- The external Core APIs on this contract remain intentionally open for custom routers and advanced integrators.
- The configured `treasury` is expected to be a passive fee receiver. In particular, when protocol fees may be
paid in native currency, the treasury must be able to receive ETH and must not use `receive` / `fallback` to
trigger reentrant swap or liquidity actions.
- `beforeInitialize`: validates pool settings and deploys the pool-specific LP token.
- `beforeSwap`: enforces anti-snipe rules, computes a dynamic fee, and accrues fees.
- `afterSwap`: updates ewVWAP, reference-price volatility state, and short-term impact state, and optionally takes protocol fees.
- `addLiquidityCore` / `removeLiquidityCore`: mint/burn LP tokens while adding/removing full-range liquidity.
- `claimFeesCore`: allows LPs or routers with signatures to claim accrued fees (tracked via per-share accounting).


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


### Q96

```solidity
uint256 internal constant Q96 = 1 << 96
```


### Q96_SQUARED

```solidity
uint256 internal constant Q96_SQUARED = Q96 * Q96
```


### PROTOCOL_FEE_RATIO_BPS

```solidity
uint256 public constant PROTOCOL_FEE_RATIO_BPS = 3000
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


### FEE_ALPHA

```solidity
uint24 internal constant FEE_ALPHA = 500_000
```


### FEE_DFF_MAX_PPM

```solidity
uint24 internal constant FEE_DFF_MAX_PPM = 800_000
```


### FEE_BASE_BPS

```solidity
uint24 internal constant FEE_BASE_BPS = 100
```


### FEE_MAX_BPS

```solidity
uint24 internal constant FEE_MAX_BPS = 10_000
```


### PIF_CAP_PPM

```solidity
uint24 internal constant PIF_CAP_PPM = 60_000
```


### VOL_DEVIATION_STEP_BPS

```solidity
uint24 internal constant VOL_DEVIATION_STEP_BPS = 1
```


### VOL_FILTER_PERIOD_SEC

```solidity
uint24 internal constant VOL_FILTER_PERIOD_SEC = 10
```


### VOL_DECAY_PERIOD_SEC

```solidity
uint24 internal constant VOL_DECAY_PERIOD_SEC = 60
```


### VOL_DECAY_FACTOR_BPS

```solidity
uint24 internal constant VOL_DECAY_FACTOR_BPS = 5_000
```


### VOL_QUADRATIC_FEE_CONTROL

```solidity
uint24 internal constant VOL_QUADRATIC_FEE_CONTROL = 4_500_000
```


### VOL_MAX_DEVIATION_ACCUMULATOR

```solidity
uint24 internal constant VOL_MAX_DEVIATION_ACCUMULATOR = 350_000
```


### SHORT_DECAY_WINDOW_SEC

```solidity
uint24 internal constant SHORT_DECAY_WINDOW_SEC = 15
```


### SHORT_COEFF_BPS

```solidity
uint24 internal constant SHORT_COEFF_BPS = 2_000
```


### SHORT_FLOOR_PPM

```solidity
uint24 internal constant SHORT_FLOOR_PPM = 20_000
```


### SHORT_CAP_PPM

```solidity
uint24 internal constant SHORT_CAP_PPM = 150_000
```


### CLAIM_FEES_TYPEHASH

```solidity
bytes32 internal constant CLAIM_FEES_TYPEHASH =
    keccak256("ClaimFees(address owner,address recipient,bytes32 poolId,uint256 nonce,uint256 deadline)")
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


### supportedProtocolFeeCurrencies

```solidity
mapping(address => bool) public supportedProtocolFeeCurrencies
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


### INITIAL_CHAIN_ID

```solidity
uint256 internal immutable INITIAL_CHAIN_ID
```


### INITIAL_DOMAIN_SEPARATOR

```solidity
bytes32 internal immutable INITIAL_DOMAIN_SEPARATOR
```


### claimNonces

```solidity
mapping(address => uint256) public claimNonces
```


### emergencyFlag

```solidity
bool public emergencyFlag
```


### poolEWVWAPParams

```solidity
mapping(PoolId => EWVWAPParams) public poolEWVWAPParams
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


### getHookPermissions

Declares which hook callbacks are enabled for this hook.


```solidity
function getHookPermissions() public pure override returns (Hooks.Permissions memory);
```

### requestSwapAttempt

Records an anti-snipe attempt and, when allowed, arms a same-transaction swap ticket for the caller.

This function is permissionless so any router or advanced integrator may request an anti-snipe ticket.
The armed ticket is transient, bound to `msg.sender` plus the swap params, and is consumed by `beforeSwap`
during the same transaction. During the protection window, failed attempts are charged an input-side failure
fee derived from the current dynamic fee quote. `inputBudget` represents the single total input budget that the
caller is willing to use for either failure-fee settlement or the eventual successful swap.


```solidity
function requestSwapAttempt(
    PoolKey calldata key,
    SwapParams calldata params,
    address trader,
    uint256 inputBudget,
    address refundRecipient
) external payable override returns (bool allowed, AntiSnipeFailureReason failureReason);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`key`|`PoolKey`|The pool key for the attempted swap.|
|`params`|`SwapParams`|The attempted swap parameters.|
|`trader`|`address`|The end user on whose behalf the router is acting.|
|`inputBudget`|`uint256`|The single total input budget attached to this attempt.|
|`refundRecipient`|`address`|The address receiving any refunded native failure-fee budget when the attempt succeeds.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`allowed`|`bool`|Whether the attempt passed anti-snipe checks.|
|`failureReason`|`AntiSnipeFailureReason`|The anti-snipe failure reason when `allowed` is false, otherwise `None`.|


### isAntiSnipeActive

Returns whether a pool is still inside its anti-snipe protection window.

Routers can use this to skip `requestSwapAttempt` entirely outside the launch window.


```solidity
function isAntiSnipeActive(PoolId poolId) external view override returns (bool active);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`poolId`|`PoolId`|The pool id to query.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`active`|`bool`|Whether anti-snipe checks are active for the pool at the current block.|


### quoteFailedAttempt

Returns the current anti-snipe failure-fee quote for an attempted swap.

The failure fee is always charged on the input side during the protection window. Outside the protection
window this returns a zero fee amount. For exact-output swaps, `inputBudget` acts as an upper bound while the
fee itself is still based on the currently estimated actual input.


```solidity
function quoteFailedAttempt(PoolKey calldata key, SwapParams calldata params, uint256 inputBudget)
    external
    view
    override
    returns (FailedAttemptQuote memory quote);
```

### quoteSwap

Returns the current swap fee preview under the hook's latest state.

The preview separates LP-fee and protocol-fee amounts because they may settle in different currencies:
LP fees always accrue in the input currency, while protocol fees settle in the supported fee currency selected
for this swap path (input side preferred, otherwise output side). For exact-output swaps, `estimatedUserInputAmount` is the intended router-side
guardrail candidate for `amountInMaximum`.


```solidity
function quoteSwap(PoolKey calldata key, SwapParams calldata params)
    external
    view
    override
    returns (SwapQuote memory quote);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`key`|`PoolKey`|The pool key being quoted.|
|`params`|`SwapParams`|The swap parameters being quoted.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`quote`|`SwapQuote`|The projected fee side, user flows, and fee split.|


### _beforeInitialize


```solidity
function _beforeInitialize(address, PoolKey calldata key, uint160) internal override returns (bytes4);
```

### _beforeSwap

Enforces anti-snipe ticket checks, computes the dynamic fee, collects any exact-input input-side fees,
and stores swap context for `afterSwap`.


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

### addLiquidityCore

Adds full-range liquidity using the caller as payer and mints LP shares to `params.to`.

This is the low-level liquidity entrypoint intended for routers and other on-chain integrators.
It omits deadline and min-amount checks, requires exact native funding when one side is native, and returns the
settled delta to the caller. Callers are expected to pre-compute the required native amount from the same
full-range quote inputs before invoking this Core entrypoint.


```solidity
function addLiquidityCore(AddLiquidityCoreParams calldata params)
    external
    payable
    override
    nonReentrant
    returns (uint128 liquidity, BalanceDelta delta);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`params`|`AddLiquidityCoreParams`|The core liquidity-add parameters.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`liquidity`|`uint128`|The LP liquidity minted by the operation.|
|`delta`|`BalanceDelta`|The balance delta settled against the caller.|


### _addLiquidityCore


```solidity
function _addLiquidityCore(AddLiquidityCoreParams memory params, address payer)
    internal
    returns (uint128 liquidity, BalanceDelta addedDelta);
```

### removeLiquidityCore

Removes full-range liquidity owned by the caller and sends the underlying assets to `params.recipient`.

This is the low-level liquidity exit entrypoint intended for routers and other on-chain integrators.
It omits deadline and min-amount checks.


```solidity
function removeLiquidityCore(RemoveLiquidityCoreParams calldata params)
    external
    override
    nonReentrant
    returns (BalanceDelta delta);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`params`|`RemoveLiquidityCoreParams`|The core liquidity-remove parameters.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`delta`|`BalanceDelta`|The balance delta returned by the liquidity removal.|


### _removeLiquidityCore


```solidity
function _removeLiquidityCore(RemoveLiquidityCoreParams memory params) internal returns (BalanceDelta delta);
```

### claimFeesCore

Claims pending LP fees on behalf of an owner using either direct ownership or a signed authorization.


```solidity
function claimFeesCore(ClaimFeesCoreParams calldata params)
    external
    override
    nonReentrant
    returns (uint256 fee0Amount, uint256 fee1Amount);
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`params`|`ClaimFeesCoreParams`|The core fee-claim parameters.|

**Returns**

|Name|Type|Description|
|----|----|-----------|
|`fee0Amount`|`uint256`|The claimed amount of currency0 fees.|
|`fee1Amount`|`uint256`|The claimed amount of currency1 fees.|


### _modifyLiquidity


```solidity
function _modifyLiquidity(address sender, PoolKey memory key, ModifyLiquidityParams memory params)
    internal
    returns (BalanceDelta delta);
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

### _forwardLiquidityOutputs


```solidity
function _forwardLiquidityOutputs(address recipient, PoolKey memory key, BalanceDelta delta) internal;
```

### _claimFees


```solidity
function _claimFees(PoolKey memory key, address owner, address recipient)
    internal
    returns (uint256 fee0Amount, uint256 fee1Amount);
```

### _authorizeClaim


```solidity
function _authorizeClaim(ClaimFeesCoreParams calldata params) internal;
```

### DOMAIN_SEPARATOR


```solidity
function DOMAIN_SEPARATOR() public view returns (bytes32);
```

### _computeDomainSeparator


```solidity
function _computeDomainSeparator() internal view returns (bytes32);
```

### _poolKey


```solidity
function _poolKey(Currency currency0, Currency currency1) internal view returns (PoolKey memory key);
```

### _resolveSwapFeeContext


```solidity
function _resolveSwapFeeContext(PoolKey calldata key, bool zeroForOne)
    internal
    view
    returns (SwapFeeContext memory ctx);
```

### _collectProtocolFee


```solidity
function _collectProtocolFee(PoolId poolId, Currency feeCurrency, uint256 protocolFeeAmount) internal;
```

### _collectLpFee


```solidity
function _collectLpFee(PoolId poolId, Currency feeCurrency, bool feeCurrencyIsCurrency0, uint256 lpFeeAmount)
    internal;
```

### _quoteFailedAttempt


```solidity
function _quoteFailedAttempt(PoolId poolId, PoolKey calldata key, SwapParams calldata params, uint256 inputBudget)
    internal
    view
    returns (FailedAttemptQuote memory quote);
```

### _validateAttemptFeeFunding


```solidity
function _validateAttemptFeeFunding(FailedAttemptQuote memory quote, uint256 inputBudget, address refundRecipient)
    internal
    view;
```

### _collectFailedAttemptFee


```solidity
function _collectFailedAttemptFee(PoolId poolId, PoolKey calldata key, FailedAttemptQuote memory quote) internal;
```

### _isAntiSnipeActive


```solidity
function _isAntiSnipeActive(PoolId poolId) internal view returns (bool);
```

### _takeToTreasury


```solidity
function _takeToTreasury(Currency feeCurrency, uint256 amount) internal;
```

### _transferFromCallerToTreasury


```solidity
function _transferFromCallerToTreasury(Currency feeCurrency, uint256 amount) internal;
```

### _setProtocolFeeCurrencySupport


```solidity
function _setProtocolFeeCurrencySupport(Currency currency, bool supported) internal;
```

### _isProtocolFeeCurrencySupported


```solidity
function _isProtocolFeeCurrencySupported(Currency currency) internal view returns (bool);
```

### _creditLpFee


```solidity
function _creditLpFee(
    PoolId poolId,
    Currency feeCurrency,
    bool feeCurrencyIsCurrency0,
    uint256 lpFeeAmount,
    uint256 totalSupply
) internal;
```

### _actualInputAmount


```solidity
function _actualInputAmount(BalanceDelta delta, bool zeroForOne) internal pure returns (uint256);
```

### _actualOutputAmount


```solidity
function _actualOutputAmount(BalanceDelta delta, bool zeroForOne) internal pure returns (uint256);
```

### _protocolFeeBps


```solidity
function _protocolFeeBps(uint256 feeBps) internal pure returns (uint256);
```

### _lpFeeBps


```solidity
function _lpFeeBps(uint256 feeBps) internal pure returns (uint256);
```

### _consumeAntiSnipeTicket


```solidity
function _consumeAntiSnipeTicket(PoolId poolId, address caller, SwapParams calldata params) internal;
```

### updateUserSnapshot

Updates the user fee accounting snapshot for a pool.

Requires the pool LP token to exist. Accrues newly earned fees into `pendingFee0/1`
and updates per-share offsets for `user`.


```solidity
function updateUserSnapshot(PoolId id, address user) public override;
```

### setTreasury

Updates the treasury address.

Only callable by the owner. Zero address is rejected because protocol fees require a concrete recipient.
The configured treasury is expected to be a passive receiver and must not use fee receipts to trigger
reentrant swap or liquidity actions.


```solidity
function setTreasury(address _treasury) external onlyOwner;
```

### setProtocolFeeCurrency

Enables a currency as a supported protocol-fee settlement currency.

This is a convenience wrapper for `setProtocolFeeCurrencySupport(currency, true)`.


```solidity
function setProtocolFeeCurrency(Currency currency) external onlyOwner;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`currency`|`Currency`|The currency to enable for protocol-fee settlement.|


### setProtocolFeeCurrencySupport

Updates whether a currency is eligible to receive protocol fees.

If both pool sides are supported, the swap path will prefer charging protocol fees on the input side.
Native currency support is represented by `address(0)`.


```solidity
function setProtocolFeeCurrencySupport(Currency currency, bool supported) external onlyOwner;
```

### setAntiSnipeDuration

Sets the default anti-snipe duration, in blocks, used for newly initialized pools.


```solidity
function setAntiSnipeDuration(uint256 _durationBlocks) external onlyOwner;
```

### setMaxAntiSnipeProbabilityBase

Sets the max probability base used by anti-snipe randomness.


```solidity
function setMaxAntiSnipeProbabilityBase(uint256 _maxBase) external onlyOwner;
```

### setEmergencyFlag

Emergency switch: if enabled, dynamic fee charging falls back to base fee only.


```solidity
function setEmergencyFlag(bool flag) external onlyOwner;
```

### _quoteDynamicFee

Dynamic fee quote. Returns base fee in emergency mode, for zero-sized/zero-liquidity
cases, or when an ewVWAP history marks the swap as non-adverse. Does not move funds.


```solidity
function _quoteDynamicFee(PoolId poolId, SwapParams calldata params, uint160 preSqrtPriceX96, bool feeOnInput)
    internal
    view
    returns (DynamicFeeQuote memory quote);
```

### _estimateDynamicFeeQuote


```solidity
function _estimateDynamicFeeQuote(
    EWVWAPParams memory state,
    uint128 liquidity,
    uint160 preSqrtPriceX96,
    bool zeroForOne,
    int256 amountSpecified,
    bool feeOnInput
) internal view returns (DynamicFeeQuote memory quote);
```

### _populateDynamicFeeQuoteFromState


```solidity
function _populateDynamicFeeQuoteFromState(DynamicFeeQuote memory quote, EWVWAPParams memory state) internal view;
```

### _estimateSwapFlowAndPostPrice


```solidity
function _estimateSwapFlowAndPostPrice(
    uint128 liquidity,
    uint160 preSqrtPriceX96,
    bool zeroForOne,
    int256 amountSpecified
)
    internal
    pure
    returns (uint256 inputAmount, uint256 outputAmount, uint256 grossOutputAmount, uint160 postSqrtPriceX96);
```

### _grossUpFeeFromNetOutput


```solidity
function _grossUpFeeFromNetOutput(uint256 netOutputAmount, uint256 feeBps)
    internal
    pure
    returns (uint256 feeAmount);
```

### _updateDynamicStateAfterSwap

Updates ewVWAP, reference-price volatility state, and short-term impact state using the realized swap outcome.


```solidity
function _updateDynamicStateAfterSwap(PoolId poolId, BalanceDelta delta) internal;
```

### _decayLinearPpm


```solidity
function _decayLinearPpm(uint256 accumulatorPpm, uint256 lastTs, uint256 windowSec)
    internal
    view
    returns (uint256);
```

### _refreshVolatilityAnchorAndCarry


```solidity
function _refreshVolatilityAnchorAndCarry(PoolId poolId, uint160 preSqrtPriceX96) internal;
```

### _updateVolatilityDeviationAccumulatorAfterSwap


```solidity
function _updateVolatilityDeviationAccumulatorAfterSwap(EWVWAPParams storage state, uint160 postSqrtPriceX96)
    internal;
```

### _volatilityQuadraticFeeBps


```solidity
function _volatilityQuadraticFeeBps(uint256 accumulator, uint256 stepBps, uint256 feeControl)
    internal
    pure
    returns (uint256);
```

### _volatilityDeltaSteps


```solidity
function _volatilityDeltaSteps(uint160 referenceSqrtPriceX96, uint160 currentSqrtPriceX96, uint256 stepBps)
    internal
    pure
    returns (uint256);
```

### _spotX18FromSqrtPrice


```solidity
function _spotX18FromSqrtPrice(uint160 sqrtPriceX96) internal pure returns (uint256);
```

### _absDiff


```solidity
function _absDiff(uint256 a, uint256 b) internal pure returns (uint256);
```

### _priceMovePpm


```solidity
function _priceMovePpm(uint160 preSqrtPrice, uint160 postSqrtPrice) internal pure returns (uint256);
```

### _currencySymbol


```solidity
function _currencySymbol(Currency currency) internal view returns (string memory);
```

### receive


```solidity
receive() external payable;
```

## Structs
### EWVWAPParams
Per-pool exponentially weighted state used by dynamic fee computation.


```solidity
struct EWVWAPParams {
    uint256 weightedVolume0; // EW token0 volume.
    uint256 weightedPriceVolume0; // EW(price * token0 volume) at 1e18 spot precision.
    uint256 ewVWAPX18; // EWVWAP spot in X18 precision.
    uint160 volAnchorSqrtPriceX96; // Anchor sqrt price used to measure reference-price deviation.
    uint40 volLastMoveTs; // Last timestamp when the volatility deviation accumulator observed a non-zero move.
    uint24 volDeviationAccumulator; // Accumulated reference-price deviation state.
    uint24 volCarryAccumulator; // Carried-over accumulator after filter/decay handling.
    uint24 shortImpactPpm; // Short-term cumulative impact accumulator (decay applied on read/update).
    uint40 shortLastTs; // Last timestamp for short-term impact decay.
}
```

### DynamicFeeQuote

```solidity
struct DynamicFeeQuote {
    uint256 feeBps;
    uint256 pifPpm;
    uint256 dynamicPartBps;
    uint256 volPartBps;
    uint256 shortPartBps;
    uint256 estimatedInputAmount;
    uint256 estimatedOutputAmount;
    uint256 estimatedGrossOutputAmount;
    uint256 spotBeforeX18;
    uint256 spotAfterX18;
    bool isAdverse;
}
```

### ModifyLiquidityCallbackData

```solidity
struct ModifyLiquidityCallbackData {
    address sender;
    PoolKey key;
    ModifyLiquidityParams params;
}
```

### SwapFeeContext

```solidity
struct SwapFeeContext {
    Currency currencyIn;
    Currency currencyOut;
    bool protocolFeeOnInput;
    bool inputIsCurrency0;
}
```

