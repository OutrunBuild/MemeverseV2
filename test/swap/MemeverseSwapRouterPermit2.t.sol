// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IPoolManager, ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta, BalanceDeltaLibrary, toBalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {BaseHook} from "@uniswap/v4-hooks-public/src/base/BaseHook.sol";
import {ISignatureTransfer} from "lib/v4-periphery/lib/permit2/src/interfaces/ISignatureTransfer.sol";
import {IPermit2} from "lib/v4-periphery/lib/permit2/src/interfaces/IPermit2.sol";

import {LiquidityAmounts} from "../../src/swap/libraries/LiquidityAmounts.sol";
import {MemeverseUniswapHook} from "../../src/swap/MemeverseUniswapHook.sol";
import {MemeverseSwapRouter} from "../../src/swap/MemeverseSwapRouter.sol";
import {IMemeverseSwapRouter} from "../../src/swap/interfaces/IMemeverseSwapRouter.sol";
import {IMemeverseUniswapHook} from "../../src/swap/interfaces/IMemeverseUniswapHook.sol";
import {UniswapLP} from "../../src/swap/tokens/UniswapLP.sol";

contract MockPoolManagerForPermit2RouterTest {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using BeforeSwapDeltaLibrary for BeforeSwapDelta;

    error ManagerLocked();
    error PriceLimitAlreadyExceeded(uint160 sqrtPriceCurrentX96, uint160 sqrtPriceLimitX96);
    error PriceLimitOutOfBounds(uint160 sqrtPriceLimitX96);

    struct Slot0State {
        uint160 sqrtPriceX96;
        int24 tick;
        uint24 protocolFee;
        uint24 lpFee;
    }

    bytes internal constant ZERO_BYTES = bytes("");
    bytes32 internal constant POOLS_SLOT = bytes32(uint256(6));
    uint256 internal constant LIQUIDITY_OFFSET = 3;
    uint160 internal constant SQRT_PRICE_LOWER_X96 = 4_310_618_292;
    uint160 internal constant SQRT_PRICE_UPPER_X96 = 1_456_195_216_270_955_103_206_513_029_158_776_779_468_408_838_535;

    bool internal unlocked;
    bool internal enforceV4PriceLimitValidation;
    address internal lastUnlockCallbackPayer;
    mapping(bytes32 => bytes32) internal extStorage;
    mapping(PoolId => Slot0State) internal slot0State;
    mapping(PoolId => uint128) internal liquidityState;

    struct RouterCallbackPreview {
        address payer;
        address recipient;
        PoolKey key;
        SwapParams params;
        bytes hookData;
    }

    /// @notice Seeds mock pool state and calls the hook initialize callback.
    /// @dev Mimics the minimal pool-manager behavior the router expects during bootstrap.
    /// @param key The pool key being initialized.
    /// @param sqrtPriceX96 The starting pool price.
    /// @return tick The mocked initialized tick, always zero.
    function initialize(PoolKey memory key, uint160 sqrtPriceX96) external returns (int24 tick) {
        PoolId poolId = key.toId();
        slot0State[poolId] = Slot0State({sqrtPriceX96: sqrtPriceX96, tick: 0, protocolFee: 0, lpFee: 0});
        liquidityState[poolId] = 1e24;
        _syncPoolStorage(poolId);
        key.hooks.beforeInitialize(msg.sender, key, sqrtPriceX96);
        tick = 0;
    }

    /// @notice Opens the mock unlock window and forwards the callback payload.
    /// @dev Mirrors the pool manager's unlock callback flow used by the router.
    /// @param data The callback payload forwarded to `unlockCallback`.
    /// @return result The callback return data.
    function unlock(bytes calldata data) external returns (bytes memory result) {
        bytes32 headWord;
        assembly {
            headWord := calldataload(data.offset)
        }
        if (headWord == bytes32(uint256(0x20))) {
            RouterCallbackPreview memory preview = abi.decode(data, (RouterCallbackPreview));
            lastUnlockCallbackPayer = preview.payer;
        }
        unlocked = true;
        result = IUnlockCallbackLike(msg.sender).unlockCallback(data);
        unlocked = false;
    }

    function setEnforceV4PriceLimitValidation(bool enabled) external {
        enforceV4PriceLimitValidation = enabled;
    }

    /// @notice Applies a mocked liquidity modification and returns deterministic deltas.
    /// @dev Uses full-range liquidity math to approximate manager deltas for router tests.
    /// @param key The pool key being modified.
    /// @param params The mocked liquidity modification parameters.
    /// @param hookData Unused hook data forwarded by the router test harness.
    /// @return delta The principal amount delta.
    /// @return feesAccrued The mocked fee delta, always zero here.
    function modifyLiquidity(PoolKey memory key, ModifyLiquidityParams memory params, bytes calldata hookData)
        external
        returns (BalanceDelta delta, BalanceDelta feesAccrued)
    {
        hookData;
        if (!unlocked) revert ManagerLocked();
        uint256 amount0Used;
        uint256 amount1Used;

        if (params.liquidityDelta > 0) {
            key.hooks.beforeAddLiquidity(msg.sender, key, params, ZERO_BYTES);
            liquidityState[key.toId()] += uint128(uint256(params.liquidityDelta));
            _syncPoolStorage(key.toId());
            (amount0Used, amount1Used) = LiquidityAmounts.getAmountsForLiquidity(
                slot0State[key.toId()].sqrtPriceX96,
                SQRT_PRICE_LOWER_X96,
                SQRT_PRICE_UPPER_X96,
                uint128(uint256(params.liquidityDelta))
            );
            delta = toBalanceDelta(-int128(int256(amount0Used)), -int128(int256(amount1Used)));
            return (delta, feesAccrued);
        }

        liquidityState[key.toId()] -= uint128(uint256(-params.liquidityDelta));
        _syncPoolStorage(key.toId());
        (amount0Used, amount1Used) = LiquidityAmounts.getAmountsForLiquidity(
            slot0State[key.toId()].sqrtPriceX96,
            SQRT_PRICE_LOWER_X96,
            SQRT_PRICE_UPPER_X96,
            uint128(uint256(-params.liquidityDelta))
        );
        delta = toBalanceDelta(int128(int256(amount0Used)), int128(int256(amount1Used)));
    }

    /// @notice Executes a mocked swap against the configured hook callbacks.
    /// @dev Simulates hook-before/hook-after accounting with deterministic price impact.
    /// @param key The pool key being swapped against.
    /// @param params The swap parameters.
    /// @param hookData Opaque hook payload forwarded through the mock.
    /// @return delta The resulting swap delta after hook adjustments.
    function swap(PoolKey memory key, SwapParams memory params, bytes calldata hookData)
        external
        returns (BalanceDelta delta)
    {
        if (!unlocked) revert ManagerLocked();

        PoolId poolId = key.toId();
        (, BeforeSwapDelta beforeSwapDelta,) = key.hooks.beforeSwap(msg.sender, key, params, hookData);
        int256 amountToSwap = params.amountSpecified + beforeSwapDelta.getSpecifiedDelta();

        if (enforceV4PriceLimitValidation) {
            Slot0State memory state = slot0State[poolId];
            if (params.zeroForOne) {
                if (params.sqrtPriceLimitX96 >= state.sqrtPriceX96) {
                    revert PriceLimitAlreadyExceeded(state.sqrtPriceX96, params.sqrtPriceLimitX96);
                }
                if (params.sqrtPriceLimitX96 <= SQRT_PRICE_LOWER_X96) {
                    revert PriceLimitOutOfBounds(params.sqrtPriceLimitX96);
                }
            } else {
                if (params.sqrtPriceLimitX96 <= state.sqrtPriceX96) {
                    revert PriceLimitAlreadyExceeded(state.sqrtPriceX96, params.sqrtPriceLimitX96);
                }
                if (params.sqrtPriceLimitX96 >= SQRT_PRICE_UPPER_X96) {
                    revert PriceLimitOutOfBounds(params.sqrtPriceLimitX96);
                }
            }
        }

        BalanceDelta poolDelta = BalanceDeltaLibrary.ZERO_DELTA;
        if (amountToSwap != 0) {
            if (params.amountSpecified < 0) {
                uint256 inputAmount = uint256(-amountToSwap);
                uint256 outputAmount = inputAmount / 2;
                if (params.zeroForOne) {
                    poolDelta = toBalanceDelta(-int128(int256(inputAmount)), int128(int256(outputAmount)));
                } else {
                    poolDelta = toBalanceDelta(int128(int256(outputAmount)), -int128(int256(inputAmount)));
                }
            } else {
                uint256 outputAmount = uint256(amountToSwap);
                uint256 inputAmount = outputAmount * 2;
                if (params.zeroForOne) {
                    poolDelta = toBalanceDelta(-int128(int256(inputAmount)), int128(int256(outputAmount)));
                } else {
                    poolDelta = toBalanceDelta(int128(int256(outputAmount)), -int128(int256(inputAmount)));
                }
            }
        }

        (, int128 afterSwapUnspecifiedDelta) = key.hooks.afterSwap(msg.sender, key, params, poolDelta, hookData);

        int128 hookDeltaSpecified = beforeSwapDelta.getSpecifiedDelta();
        int128 hookDeltaUnspecified = beforeSwapDelta.getUnspecifiedDelta() + afterSwapUnspecifiedDelta;
        if (hookDeltaSpecified != 0 || hookDeltaUnspecified != 0) {
            BalanceDelta hookDelta = (params.amountSpecified < 0 == params.zeroForOne)
                ? toBalanceDelta(hookDeltaSpecified, hookDeltaUnspecified)
                : toBalanceDelta(hookDeltaUnspecified, hookDeltaSpecified);
            delta = poolDelta - hookDelta;
        } else {
            delta = poolDelta;
        }
    }

    /// @notice Transfers out a mocked currency amount from the manager.
    /// @dev Supports both native and ERC20 settlement paths used by router tests.
    /// @param currency The currency to transfer out.
    /// @param to The recipient address.
    /// @param amount The amount to transfer.
    function take(Currency currency, address to, uint256 amount) external {
        if (currency.isAddressZero()) {
            (bool success,) = to.call{value: amount}("");
            require(success, "native take");
        } else {
            require(MockERC20(Currency.unwrap(currency)).transfer(to, amount), "erc20 take");
        }
    }

    /// @notice No-op sync entrypoint for the test harness.
    /// @dev Preserves the pool-manager interface shape expected by the router.
    /// @param currency The currency being synced.
    function sync(Currency currency) external pure {
        currency;
    }

    /// @notice Accepts native settlement and returns the supplied amount.
    /// @dev Matches the pool-manager settle interface used by router settlement helpers.
    /// @return amount The received native amount.
    function settle() external payable returns (uint256) {
        return msg.value;
    }

    /// @notice Returns the mock extsload value for a storage slot.
    /// @dev Allows the hook to read mocked pool-manager storage slots.
    /// @param slot The storage slot to read.
    /// @return value The mocked word stored at `slot`.
    function extsload(bytes32 slot) external view returns (bytes32) {
        return extStorage[slot];
    }

    /// @notice Returns the mocked slot0 tuple for a pool.
    /// @dev Exposes price and fee state to the router and hook tests.
    /// @param poolId The pool identifier.
    /// @return sqrtPriceX96 The mocked square-root price.
    /// @return tick The mocked current tick.
    /// @return protocolFee The mocked protocol fee.
    /// @return lpFee The mocked LP fee.
    function getSlot0(PoolId poolId) external view returns (uint160, int24, uint24, uint24) {
        Slot0State memory state = slot0State[poolId];
        return (state.sqrtPriceX96, state.tick, state.protocolFee, state.lpFee);
    }

    /// @notice Returns the mocked liquidity value for a pool.
    /// @dev Exposes pool liquidity to the router and hook tests.
    /// @param poolId The pool identifier.
    /// @return liquidity The mocked active liquidity for the pool.
    function getLiquidity(PoolId poolId) external view returns (uint128) {
        return liquidityState[poolId];
    }

    function lastUnlockPayer() external view returns (address payer) {
        return lastUnlockCallbackPayer;
    }

    function _syncPoolStorage(PoolId poolId) internal {
        bytes32 stateSlot = keccak256(abi.encodePacked(PoolId.unwrap(poolId), POOLS_SLOT));
        Slot0State memory state = slot0State[poolId];
        extStorage[stateSlot] = bytes32(uint256(state.sqrtPriceX96));
        extStorage[bytes32(uint256(stateSlot) + LIQUIDITY_OFFSET)] = bytes32(uint256(liquidityState[poolId]));
    }

    /// @notice Accepts native refunds that the router routes back through the manager.
    /// @dev Gives the mock manager a payable fallback to mirror real routing settlement behavior.
    receive() external payable {}
}

interface IUnlockCallbackLike {
    /// @notice Executes the mock unlock callback.
    /// @dev Matches the callback interface expected by the pool-manager mock.
    /// @param data The callback payload.
    /// @return result The callback return data.
    function unlockCallback(bytes calldata data) external returns (bytes memory);
}

contract TestableMemeverseUniswapHookForPermit2Router is MemeverseUniswapHook {
    constructor(IPoolManager _manager, address _owner, address _treasury)
        MemeverseUniswapHook(_manager, _owner, _treasury)
    {}

    function seedActiveLiquidityShares(PoolKey memory key, address owner, uint256 activeShares) external {
        PoolId id = key.toId();
        address liquidityToken = poolInfo[id].liquidityToken;
        if (liquidityToken == address(0)) revert PoolNotInitialized();

        if (cachedLpTotalSupply[id] == 0) {
            UniswapLP(liquidityToken).mint(address(0), MINIMUM_LIQUIDITY);
            cachedLpTotalSupply[id] = MINIMUM_LIQUIDITY;
        }

        UniswapLP(liquidityToken).mint(owner, activeShares);
        cachedLpTotalSupply[id] += activeShares;
    }

    function validateHookAddress(BaseHook) internal pure override {}
}

contract MockPermit2ForRouterTest {
    using SafeERC20 for IERC20;

    address public lastOwner;
    address public lastRecipient;
    address public lastToken;
    uint256 public lastRequestedAmount;
    address public lastBatchOwner;
    uint256 public lastBatchLength;
    bytes32 public lastWitness;
    string public lastWitnessTypeString;
    bytes public lastSignature;

    /// @notice Mocks Permit2 single-token witness transfers and records the last request.
    /// @dev This test double trusts the payload and focuses on observability rather than signature checks.
    /// @param permit The signed Permit2 transfer payload.
    /// @param transferDetails The requested transfer details.
    /// @param owner The signer and funding account.
    /// @param witness The witness hash supplied by the router.
    /// @param witnessTypeString The witness type string supplied by the router.
    /// @param signature The mocked signature bytes.
    function permitWitnessTransferFrom(
        ISignatureTransfer.PermitTransferFrom memory permit,
        ISignatureTransfer.SignatureTransferDetails calldata transferDetails,
        address owner,
        bytes32 witness,
        string calldata witnessTypeString,
        bytes calldata signature
    ) external {
        lastOwner = owner;
        lastRecipient = transferDetails.to;
        lastToken = permit.permitted.token;
        lastRequestedAmount = transferDetails.requestedAmount;
        lastWitness = witness;
        lastWitnessTypeString = witnessTypeString;
        lastSignature = signature;

        IERC20(permit.permitted.token).safeTransferFrom(owner, transferDetails.to, transferDetails.requestedAmount);
    }

    /// @notice Mocks Permit2 batch witness transfers and records the last request.
    /// @dev This test double trusts the payload and focuses on observability rather than signature checks.
    /// @param permit The signed Permit2 batch payload.
    /// @param transferDetails The requested transfer details.
    /// @param owner The signer and funding account.
    /// @param witness The witness hash supplied by the router.
    /// @param witnessTypeString The witness type string supplied by the router.
    /// @param signature The mocked signature bytes.
    function permitWitnessTransferFrom(
        ISignatureTransfer.PermitBatchTransferFrom memory permit,
        ISignatureTransfer.SignatureTransferDetails[] calldata transferDetails,
        address owner,
        bytes32 witness,
        string calldata witnessTypeString,
        bytes calldata signature
    ) external {
        lastBatchOwner = owner;
        lastBatchLength = transferDetails.length;
        lastWitness = witness;
        lastWitnessTypeString = witnessTypeString;
        lastSignature = signature;

        for (uint256 i = 0; i < transferDetails.length; ++i) {
            IERC20(permit.permitted[i].token)
                .safeTransferFrom(owner, transferDetails[i].to, transferDetails[i].requestedAmount);
        }
    }
}

contract SignatureVerifyingPermit2ForRouterTest {
    using SafeERC20 for IERC20;

    error InvalidAmount(uint256 maxAmount);
    error InvalidNonce();
    error InvalidSigner();
    error LengthMismatch();
    error SignatureExpired(uint256 deadline);

    bytes32 internal constant TOKEN_PERMISSIONS_TYPEHASH = keccak256("TokenPermissions(address token,uint256 amount)");
    string internal constant PERMIT_SINGLE_WITNESS_TYPEHASH_STUB =
        "PermitWitnessTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline,";
    string internal constant PERMIT_BATCH_WITNESS_TYPEHASH_STUB =
        "PermitBatchWitnessTransferFrom(TokenPermissions[] permitted,address spender,uint256 nonce,uint256 deadline,";
    bytes32 internal constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");
    bytes32 internal constant EIP712_NAME_HASH = keccak256("Permit2");

    mapping(address => mapping(uint256 => uint256)) public nonceBitmap;

    /// @notice Returns the EIP-712 domain separator used by the mock Permit2 implementation.
    /// @dev The separator binds signatures to the current chain and mock Permit2 address.
    /// @return separator The computed EIP-712 domain separator.
    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return keccak256(abi.encode(EIP712_DOMAIN_TYPEHASH, EIP712_NAME_HASH, block.chainid, address(this)));
    }

    /// @notice Verifies and executes a mocked single-token witness transfer.
    /// @dev Enforces nonce, deadline, amount, and EIP-712 signature validity before transfer.
    /// @param permit The signed Permit2 transfer payload.
    /// @param transferDetails The requested transfer details.
    /// @param owner The signer and funding account.
    /// @param witness The witness hash supplied by the router.
    /// @param witnessTypeString The witness type string supplied by the router.
    /// @param signature The signed permit bytes.
    function permitWitnessTransferFrom(
        ISignatureTransfer.PermitTransferFrom memory permit,
        ISignatureTransfer.SignatureTransferDetails calldata transferDetails,
        address owner,
        bytes32 witness,
        string calldata witnessTypeString,
        bytes calldata signature
    ) external {
        if (block.timestamp > permit.deadline) revert SignatureExpired(permit.deadline);
        if (transferDetails.requestedAmount > permit.permitted.amount) revert InvalidAmount(permit.permitted.amount);

        _useUnorderedNonce(owner, permit.nonce);
        bytes32 typeHash = keccak256(abi.encodePacked(PERMIT_SINGLE_WITNESS_TYPEHASH_STUB, witnessTypeString));
        bytes32 tokenPermissionsHash =
            keccak256(abi.encode(TOKEN_PERMISSIONS_TYPEHASH, permit.permitted.token, permit.permitted.amount));
        bytes32 dataHash =
            keccak256(abi.encode(typeHash, tokenPermissionsHash, msg.sender, permit.nonce, permit.deadline, witness));
        _verifySignature(signature, owner, dataHash);
        IERC20(permit.permitted.token).safeTransferFrom(owner, transferDetails.to, transferDetails.requestedAmount);
    }

    /// @notice Verifies and executes a mocked batch witness transfer.
    /// @dev Enforces nonce, deadline, amount, and EIP-712 signature validity before transfer.
    /// @param permit The signed Permit2 batch payload.
    /// @param transferDetails The requested transfer details.
    /// @param owner The signer and funding account.
    /// @param witness The witness hash supplied by the router.
    /// @param witnessTypeString The witness type string supplied by the router.
    /// @param signature The signed permit bytes.
    function permitWitnessTransferFrom(
        ISignatureTransfer.PermitBatchTransferFrom memory permit,
        ISignatureTransfer.SignatureTransferDetails[] calldata transferDetails,
        address owner,
        bytes32 witness,
        string calldata witnessTypeString,
        bytes calldata signature
    ) external {
        if (block.timestamp > permit.deadline) revert SignatureExpired(permit.deadline);
        if (permit.permitted.length != transferDetails.length) revert LengthMismatch();

        _useUnorderedNonce(owner, permit.nonce);
        bytes32[] memory tokenPermissionHashes = new bytes32[](permit.permitted.length);
        for (uint256 i = 0; i < permit.permitted.length; ++i) {
            if (transferDetails[i].requestedAmount > permit.permitted[i].amount) {
                revert InvalidAmount(permit.permitted[i].amount);
            }
            tokenPermissionHashes[i] = keccak256(
                abi.encode(TOKEN_PERMISSIONS_TYPEHASH, permit.permitted[i].token, permit.permitted[i].amount)
            );
        }

        bytes32 typeHash = keccak256(abi.encodePacked(PERMIT_BATCH_WITNESS_TYPEHASH_STUB, witnessTypeString));
        bytes32 dataHash = keccak256(
            abi.encode(
                typeHash,
                keccak256(abi.encodePacked(tokenPermissionHashes)),
                msg.sender,
                permit.nonce,
                permit.deadline,
                witness
            )
        );
        _verifySignature(signature, owner, dataHash);

        for (uint256 i = 0; i < transferDetails.length; ++i) {
            IERC20(permit.permitted[i].token)
                .safeTransferFrom(owner, transferDetails[i].to, transferDetails[i].requestedAmount);
        }
    }

    /// @notice Claims a nonce inside the unordered Permit2 nonce bitmap.
    /// @dev Reproduces Permit2's unordered nonce validation so tests can reject duplicates.
    function _useUnorderedNonce(address from, uint256 nonce) private {
        uint256 wordPos = uint248(nonce >> 8);
        uint256 bitPos = uint8(nonce);
        // forge-lint: disable-next-line(incorrect-shift)
        uint256 bit = 1 << bitPos;
        uint256 flipped = nonceBitmap[from][wordPos] ^= bit;
        if (flipped & bit == 0) revert InvalidNonce();
    }

    /// @notice Checks that the caller-supplied signature recovers the expected owner.
    /// @dev Detects invalid lengths or recovery values just like the production Permit2 reference.
    function _verifySignature(bytes calldata signature, address owner, bytes32 dataHash) private view {
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), dataHash));
        if (signature.length != 65) revert InvalidSigner();
        (bytes32 r, bytes32 s) = abi.decode(signature, (bytes32, bytes32));
        uint8 v = uint8(signature[64]);
        address signer = ecrecover(digest, v, r, s);
        if (signer == address(0) || signer != owner) revert InvalidSigner();
    }
}

contract MockLauncherForPermit2ProtectionTest {
    mapping(bytes32 => bool) internal blockedPairs;

    function setPublicSwapBlocked(address tokenA, address tokenB, bool blocked) external {
        blockedPairs[_pairKey(tokenA, tokenB)] = blocked;
    }

    function isPublicSwapAllowed(address tokenA, address tokenB) external view returns (bool) {
        return !blockedPairs[_pairKey(tokenA, tokenB)];
    }

    function _pairKey(address tokenA, address tokenB) internal pure returns (bytes32) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        return keccak256(abi.encode(token0, token1));
    }
}

contract MemeverseSwapRouterPermit2Test is Test {
    using PoolIdLibrary for PoolKey;

    uint160 internal constant SQRT_PRICE_1_1 = 79228162514264337593543950336;
    uint256 internal constant ALICE_PK = 0xA11CE;
    bytes32 internal constant TOKEN_PERMISSIONS_TYPEHASH = keccak256("TokenPermissions(address token,uint256 amount)");
    string internal constant PERMIT_SINGLE_WITNESS_TYPEHASH_STUB =
        "PermitWitnessTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline,";
    string internal constant PERMIT_BATCH_WITNESS_TYPEHASH_STUB =
        "PermitBatchWitnessTransferFrom(TokenPermissions[] permitted,address spender,uint256 nonce,uint256 deadline,";
    bytes32 internal constant SWAP_WITNESS_TYPEHASH = keccak256(
        "MemeverseSwapWitness(bytes32 poolId,bool zeroForOne,int256 amountSpecified,uint160 sqrtPriceLimitX96,address recipient,uint256 deadline,uint256 amountOutMinimum,uint256 amountInMaximum,bytes32 hookDataHash)"
    );
    bytes32 internal constant ADD_LIQUIDITY_WITNESS_TYPEHASH = keccak256(
        "MemeverseAddLiquidityWitness(address currency0,address currency1,uint256 amount0Desired,uint256 amount1Desired,uint256 amount0Min,uint256 amount1Min,address to,uint256 deadline)"
    );
    bytes32 internal constant REMOVE_LIQUIDITY_WITNESS_TYPEHASH = keccak256(
        "MemeverseRemoveLiquidityWitness(address currency0,address currency1,uint128 liquidity,uint256 amount0Min,uint256 amount1Min,address to,uint256 deadline)"
    );
    bytes32 internal constant CREATE_POOL_WITNESS_TYPEHASH = keccak256(
        "MemeverseCreatePoolWitness(address tokenA,address tokenB,uint256 amountADesired,uint256 amountBDesired,uint160 startPrice,address recipient,uint256 deadline)"
    );
    string internal constant SWAP_WITNESS_TYPE_STRING =
        "MemeverseSwapWitness witness)MemeverseSwapWitness(bytes32 poolId,bool zeroForOne,int256 amountSpecified,uint160 sqrtPriceLimitX96,address recipient,uint256 deadline,uint256 amountOutMinimum,uint256 amountInMaximum,bytes32 hookDataHash)TokenPermissions(address token,uint256 amount)";
    string internal constant ADD_LIQUIDITY_WITNESS_TYPE_STRING =
        "MemeverseAddLiquidityWitness witness)MemeverseAddLiquidityWitness(address currency0,address currency1,uint256 amount0Desired,uint256 amount1Desired,uint256 amount0Min,uint256 amount1Min,address to,uint256 deadline)TokenPermissions(address token,uint256 amount)";
    string internal constant REMOVE_LIQUIDITY_WITNESS_TYPE_STRING =
        "MemeverseRemoveLiquidityWitness witness)MemeverseRemoveLiquidityWitness(address currency0,address currency1,uint128 liquidity,uint256 amount0Min,uint256 amount1Min,address to,uint256 deadline)TokenPermissions(address token,uint256 amount)";
    string internal constant CREATE_POOL_WITNESS_TYPE_STRING =
        "MemeverseCreatePoolWitness witness)MemeverseCreatePoolWitness(address tokenA,address tokenB,uint256 amountADesired,uint256 amountBDesired,uint160 startPrice,address recipient,uint256 deadline)TokenPermissions(address token,uint256 amount)";
    bytes4 internal constant PUBLIC_SWAP_DISABLED_SELECTOR = bytes4(keccak256("PublicSwapDisabled()"));

    /// @notice Moves the block timestamp beyond the launch window threshold.
    /// @dev Ensures the Permit2 tests can exercise post-launch paths without real wait.
    function _matureLaunchWindow() internal {
        vm.warp(block.timestamp + 900);
    }

    function _validExecutionPriceLimit(bool zeroForOne) internal pure returns (uint160) {
        return zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1;
    }

    function _dynamicPoolKeyForHook(address hookAddress, Currency currency0, Currency currency1)
        internal
        pure
        returns (PoolKey memory)
    {
        return PoolKey({
            currency0: currency0, currency1: currency1, fee: 0x800000, tickSpacing: 200, hooks: IHooks(hookAddress)
        });
    }

    MockPoolManagerForPermit2RouterTest internal manager;
    TestableMemeverseUniswapHookForPermit2Router internal hook;
    MockPermit2ForRouterTest internal mockPermit2;
    SignatureVerifyingPermit2ForRouterTest internal realPermit2;
    MemeverseSwapRouter internal router;
    MemeverseSwapRouter internal realPermit2Router;
    MockERC20 internal token0;
    MockERC20 internal token1;
    address internal treasury;
    address internal alice;
    PoolKey internal key;
    PoolId internal poolId;

    function _setPublicSwapResumeTime(address targetHook, address tokenA, address tokenB, uint40 resumeTime)
        internal
        returns (bool ok, bytes memory data)
    {
        return targetHook.call(
            abi.encodeWithSignature("setPublicSwapResumeTime(address,address,uint40)", tokenA, tokenB, resumeTime)
        );
    }

    /// @notice Deploys the permit2 test harness, mocks, and seeded pool state.
    /// @dev Initializes both mock and signature-verifying Permit2 flows against the same pool setup.
    function setUp() public {
        manager = new MockPoolManagerForPermit2RouterTest();
        treasury = makeAddr("treasury");
        alice = vm.addr(ALICE_PK);
        hook = new TestableMemeverseUniswapHookForPermit2Router(IPoolManager(address(manager)), address(this), treasury);
        mockPermit2 = new MockPermit2ForRouterTest();
        router = new MemeverseSwapRouter(
            IPoolManager(address(manager)), IMemeverseUniswapHook(address(hook)), IPermit2(address(mockPermit2))
        );
        realPermit2 = new SignatureVerifyingPermit2ForRouterTest();
        realPermit2Router = new MemeverseSwapRouter(
            IPoolManager(address(manager)), IMemeverseUniswapHook(address(hook)), IPermit2(address(realPermit2))
        );

        token0 = new MockERC20("Token0", "TK0", 18);
        token1 = new MockERC20("Token1", "TK1", 18);
        token0.mint(alice, 1_000_000 ether);
        token1.mint(alice, 1_000_000 ether);
        token0.mint(address(manager), 1_000_000 ether);
        token1.mint(address(manager), 1_000_000 ether);

        vm.prank(alice);
        token0.approve(address(mockPermit2), type(uint256).max);
        vm.prank(alice);
        token1.approve(address(mockPermit2), type(uint256).max);
        vm.prank(alice);
        token0.approve(address(realPermit2), type(uint256).max);
        vm.prank(alice);
        token1.approve(address(realPermit2), type(uint256).max);

        key = _dynamicPoolKey(Currency.wrap(address(token0)), Currency.wrap(address(token1)));
        poolId = key.toId();
        manager.initialize(key, SQRT_PRICE_1_1);
        hook.seedActiveLiquidityShares(key, address(this), 1e18);
    }

    /// @notice Verifies single-permit swaps pull input and execute successfully.
    /// @dev Confirms the router requests the expected Permit2 transfer and completes the swap path.
    function testSwapWithPermit2_TransfersInputAndExecutes() external {
        hook.setProtocolFeeCurrency(key.currency0);
        _matureLaunchWindow();

        IMemeverseSwapRouter.Permit2SingleParams memory singlePermit = _singlePermit(address(token0), 100 ether);
        uint256 balance0Before = token0.balanceOf(alice);
        uint256 balance1Before = token1.balanceOf(alice);
        uint160 priceLimit = uint160((uint256(SQRT_PRICE_1_1) * 99) / 100);

        vm.prank(alice);
        BalanceDelta delta = router.swapWithPermit2(
            singlePermit,
            key,
            SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: priceLimit}),
            alice,
            block.timestamp,
            40 ether,
            100 ether,
            ""
        );

        assertEq(address(router.permit2()), address(mockPermit2), "permit2");
        assertEq(mockPermit2.lastOwner(), alice, "owner");
        assertEq(mockPermit2.lastRecipient(), address(router), "recipient");
        assertEq(mockPermit2.lastToken(), address(token0), "token");
        assertEq(mockPermit2.lastRequestedAmount(), 100 ether, "amount");
        assertEq(manager.lastUnlockPayer(), address(router), "router should prefund permit2 swaps");
        assertLt(int256(delta.amount0()), 0, "delta0");
        assertGt(int256(delta.amount1()), 0, "delta1");
        assertLt(token0.balanceOf(alice), balance0Before, "token0 spent");
        assertGt(token1.balanceOf(alice), balance1Before, "token1 received");
    }

    /// @notice Verifies the Permit2 swap path stays below the current gas ceiling.
    /// @dev This keeps the Permit2 witness and prefund flow from regressing after router-only refactors.
    function testSwapWithPermit2_GasStaysBelowCeiling() external {
        hook.setProtocolFeeCurrency(key.currency0);
        _matureLaunchWindow();

        IMemeverseSwapRouter.Permit2SingleParams memory singlePermit = _singlePermit(address(token0), 100 ether);
        uint160 priceLimit = uint160((uint256(SQRT_PRICE_1_1) * 99) / 100);

        vm.prank(alice);
        uint256 gasBefore = gasleft();
        BalanceDelta delta = router.swapWithPermit2(
            singlePermit,
            key,
            SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: priceLimit}),
            alice,
            block.timestamp,
            40 ether,
            100 ether,
            ""
        );
        uint256 gasUsed = gasBefore - gasleft();

        assertLt(int256(delta.amount0()), 0, "delta0");
        assertGt(int256(delta.amount1()), 0, "delta1");
        assertLt(gasUsed, 935_000, "swapWithPermit2 gas ceiling");
    }

    /// @notice Verifies Permit2 swaps also respect the post-unlock protection window.
    /// @dev Uses hook-local pool protection while still funding the input through Permit2 first.
    function testSwapWithPermit2_RevertsDuringPostUnlockProtectionWindow() external {
        MockPoolManagerForPermit2RouterTest guardedManager = new MockPoolManagerForPermit2RouterTest();
        TestableMemeverseUniswapHookForPermit2Router guardedHook = new TestableMemeverseUniswapHookForPermit2Router(
            IPoolManager(address(guardedManager)), address(this), treasury
        );
        MemeverseSwapRouter guardedRouter = new MemeverseSwapRouter(
            IPoolManager(address(guardedManager)),
            IMemeverseUniswapHook(address(guardedHook)),
            IPermit2(address(mockPermit2))
        );
        PoolKey memory guardedKey = _dynamicPoolKeyForHook(
            address(guardedHook), Currency.wrap(address(token0)), Currency.wrap(address(token1))
        );

        guardedHook.setLauncher(address(this));
        guardedManager.initialize(guardedKey, SQRT_PRICE_1_1);
        guardedHook.setProtocolFeeCurrency(guardedKey.currency0);
        (bool setOk, bytes memory setData) = _setPublicSwapResumeTime(
            address(guardedHook), address(token0), address(token1), uint40(block.timestamp + 1 hours)
        );
        assertTrue(setOk, string(setData));
        token0.mint(address(guardedManager), 1_000_000 ether);
        token1.mint(address(guardedManager), 1_000_000 ether);

        IMemeverseSwapRouter.Permit2SingleParams memory singlePermit = IMemeverseSwapRouter.Permit2SingleParams({
            permit: ISignatureTransfer.PermitTransferFrom({
                permitted: ISignatureTransfer.TokenPermissions({token: address(token0), amount: 100 ether}),
                nonce: 77,
                deadline: block.timestamp
            }),
            transferDetails: ISignatureTransfer.SignatureTransferDetails({
                to: address(guardedRouter), requestedAmount: 100 ether
            }),
            signature: hex"1234"
        });
        uint160 priceLimit = uint160((uint256(SQRT_PRICE_1_1) * 99) / 100);

        vm.prank(alice);
        vm.expectRevert(PUBLIC_SWAP_DISABLED_SELECTOR);
        guardedRouter.swapWithPermit2(
            singlePermit,
            guardedKey,
            SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: priceLimit}),
            alice,
            block.timestamp,
            0,
            100 ether,
            ""
        );
    }

    /// @notice Verifies Permit2 execution swaps also reject a zero price limit under real v4 semantics.
    /// @dev The Permit2 prefund path still forwards the swap params into manager execution, so `0` must revert.
    function testSwapWithPermit2_RevertsWhenExecutionPriceLimitIsZero() external {
        hook.setProtocolFeeCurrency(key.currency0);
        _matureLaunchWindow();
        manager.setEnforceV4PriceLimitValidation(true);

        IMemeverseSwapRouter.Permit2SingleParams memory singlePermit = _singlePermit(address(token0), 100 ether);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(MockPoolManagerForPermit2RouterTest.PriceLimitOutOfBounds.selector, uint160(0))
        );
        router.swapWithPermit2(
            singlePermit,
            key,
            SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}),
            alice,
            block.timestamp,
            0,
            100 ether,
            ""
        );
    }

    /// @notice Verifies Permit2 exact-output swaps prefund `amountInMaximum` and refund the unused input.
    /// @dev This keeps Permit2 aligned with the regular router path's single prefunded `_swap()` model.
    function testSwapWithPermit2_ExactOutputRefundsUnusedPrefundedInput() external {
        hook.setProtocolFeeCurrency(key.currency0);
        uint256 balance0Before = token0.balanceOf(alice);
        uint256 amountInMaximum = 500 ether;
        IMemeverseSwapRouter.Permit2SingleParams memory singlePermit = _singlePermit(address(token0), amountInMaximum);

        vm.prank(alice);
        router.swapWithPermit2(
            singlePermit,
            key,
            SwapParams({
                zeroForOne: true, amountSpecified: 100 ether, sqrtPriceLimitX96: _validExecutionPriceLimit(true)
            }),
            alice,
            block.timestamp,
            0,
            amountInMaximum,
            ""
        );

        assertEq(mockPermit2.lastRequestedAmount(), amountInMaximum, "prefunded amountInMaximum");
        assertEq(manager.lastUnlockPayer(), address(router), "router should pay exact-output input");
        assertEq(balance0Before - token0.balanceOf(alice), 300 ether, "unused input refunded");
        assertEq(token0.balanceOf(address(router)), 0, "router should not retain refunded input");
    }

    /// @notice Verifies the single Permit2 path now surfaces Permit2's own amount check.
    function testSwapWithPermit2_RevertsWhenPermittedAmountBelowRequestedAmount() external {
        hook.setProtocolFeeCurrency(key.currency0);
        _matureLaunchWindow();

        uint256 amountIn = 100 ether;
        uint256 deadline = block.timestamp + 1 hours;
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(amountIn),
            sqrtPriceLimitX96: uint160((uint256(SQRT_PRICE_1_1) * 99) / 100)
        });
        ISignatureTransfer.PermitTransferFrom memory permit = ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({token: address(token0), amount: 50 ether}),
            nonce: 21,
            deadline: deadline
        });
        ISignatureTransfer.SignatureTransferDetails memory transferDetails =
            ISignatureTransfer.SignatureTransferDetails({to: address(realPermit2Router), requestedAmount: amountIn});
        bytes32 witness = _swapWitnessHash(key, params, alice, deadline, 40 ether, amountIn, bytes(""));
        bytes memory signature =
            _signSingleWitnessPermit(permit, address(realPermit2Router), witness, SWAP_WITNESS_TYPE_STRING);
        IMemeverseSwapRouter.Permit2SingleParams memory permitParams = IMemeverseSwapRouter.Permit2SingleParams({
            permit: permit, transferDetails: transferDetails, signature: signature
        });

        vm.expectRevert(abi.encodeWithSelector(SignatureVerifyingPermit2ForRouterTest.InvalidAmount.selector, 50 ether));
        vm.prank(alice);
        realPermit2Router.swapWithPermit2(permitParams, key, params, alice, deadline, 40 ether, amountIn, "");
    }

    /// @notice Verifies the batch Permit2 path now surfaces Permit2's own amount check.
    function testAddLiquidityWithPermit2_RevertsWhenPermittedAmountBelowRequestedAmount() external {
        uint256 amount0Desired = 100 ether;
        uint256 amount1Desired = 100 ether;
        uint256 deadline = block.timestamp + 1 hours;

        ISignatureTransfer.PermitBatchTransferFrom memory permit;
        permit.permitted = new ISignatureTransfer.TokenPermissions[](2);
        permit.permitted[0] = ISignatureTransfer.TokenPermissions({token: address(token0), amount: 50 ether});
        permit.permitted[1] = ISignatureTransfer.TokenPermissions({token: address(token1), amount: amount1Desired});
        permit.nonce = 22;
        permit.deadline = deadline;
        ISignatureTransfer.SignatureTransferDetails[] memory transferDetails =
            new ISignatureTransfer.SignatureTransferDetails[](2);
        transferDetails[0] = ISignatureTransfer.SignatureTransferDetails({
            to: address(realPermit2Router), requestedAmount: amount0Desired
        });
        transferDetails[1] = ISignatureTransfer.SignatureTransferDetails({
            to: address(realPermit2Router), requestedAmount: amount1Desired
        });
        bytes32 witness = _addLiquidityWitnessHash(
            key.currency0, key.currency1, amount0Desired, amount1Desired, 90 ether, 90 ether, alice, deadline
        );
        bytes memory signature =
            _signBatchWitnessPermit(permit, address(realPermit2Router), witness, ADD_LIQUIDITY_WITNESS_TYPE_STRING);
        IMemeverseSwapRouter.Permit2BatchParams memory permitParams = IMemeverseSwapRouter.Permit2BatchParams({
            permit: permit, transferDetails: transferDetails, signature: signature
        });

        vm.expectRevert(abi.encodeWithSelector(SignatureVerifyingPermit2ForRouterTest.InvalidAmount.selector, 50 ether));
        vm.prank(alice);
        realPermit2Router.addLiquidityWithPermit2(
            permitParams,
            key.currency0,
            key.currency1,
            amount0Desired,
            amount1Desired,
            90 ether,
            90 ether,
            alice,
            deadline
        );
    }

    /// @notice Verifies Permit2-routed swaps still fail closed for native pairs.
    /// @dev The exact revert source depends on the Permit2 implementation in front of the router, so this locks only
    /// fail-closed behavior rather than a mock-specific error selector.
    function testSwapWithPermit2FailsClosed_WhenPairUsesNativeCurrency() external {
        PoolKey memory nativeKey = _dynamicPoolKey(CurrencyLibrary.ADDRESS_ZERO, Currency.wrap(address(token1)));
        IMemeverseSwapRouter.Permit2SingleParams memory singlePermit = _singlePermit(address(0), 100 ether);

        vm.expectRevert();
        vm.prank(alice);
        router.swapWithPermit2(
            singlePermit,
            nativeKey,
            SwapParams({zeroForOne: true, amountSpecified: -100 ether, sqrtPriceLimitX96: 0}),
            alice,
            block.timestamp,
            40 ether,
            100 ether,
            ""
        );
    }

    /// @notice Verifies batch Permit2 funding supports two-ERC20 liquidity adds.
    /// @dev Exercises the two-token batch funding path used by liquidity adds.
    function testAddLiquidityWithPermit2_TwoErc20Inputs() external {
        IMemeverseSwapRouter.Permit2BatchParams memory batchPermit =
            _batchPermit(address(token0), 100 ether, address(token1), 100 ether);

        vm.prank(alice);
        uint128 liquidity = router.addLiquidityWithPermit2(
            batchPermit, key.currency0, key.currency1, 100 ether, 100 ether, 90 ether, 90 ether, alice, block.timestamp
        );

        (address liquidityToken,,) = hook.poolInfo(poolId);
        assertGt(liquidity, 0, "liquidity");
        assertEq(mockPermit2.lastBatchOwner(), alice, "owner");
        assertEq(mockPermit2.lastBatchLength(), 2, "batch length");
        assertGt(MockERC20(liquidityToken).balanceOf(alice), 0, "lp balance");
    }

    /// @notice Verifies addLiquidityWithPermit2 fails closed for native pairs.
    function testAddLiquidityWithPermit2Reverts_WhenPairUsesNativeCurrency() external {
        PoolKey memory nativeKey = _dynamicPoolKey(CurrencyLibrary.ADDRESS_ZERO, Currency.wrap(address(token1)));
        IMemeverseSwapRouter.Permit2BatchParams memory batchPermit = _batchPermitSingle(address(token1), 100 ether);

        vm.expectRevert(IMemeverseUniswapHook.NativeCurrencyUnsupported.selector);
        vm.prank(alice);
        router.addLiquidityWithPermit2(
            batchPermit,
            nativeKey.currency0,
            nativeKey.currency1,
            100 ether,
            100 ether,
            90 ether,
            90 ether,
            alice,
            block.timestamp
        );
    }

    /// @notice Verifies Permit2 native pairs fail closed before token-mismatch logic.
    function testAddLiquidityWithPermit2Reverts_WhenPairUsesNativeCurrencyEvenWithWrongToken() external {
        PoolKey memory nativeKey = _dynamicPoolKey(CurrencyLibrary.ADDRESS_ZERO, Currency.wrap(address(token1)));
        IMemeverseSwapRouter.Permit2BatchParams memory batchPermit = _batchPermitSingle(address(0xBEEF), 100 ether);

        vm.expectRevert(IMemeverseUniswapHook.NativeCurrencyUnsupported.selector);
        vm.prank(alice);
        router.addLiquidityWithPermit2(
            batchPermit,
            nativeKey.currency0,
            nativeKey.currency1,
            100 ether,
            100 ether,
            90 ether,
            90 ether,
            alice,
            block.timestamp
        );
    }

    /// @notice Verifies single-permit liquidity removal burns LP and returns both assets.
    /// @dev Exercises the LP-token Permit2 flow used by liquidity removals.
    function testRemoveLiquidityWithPermit2() external {
        uint128 liquidity = _mintAliceLiquidity();
        (address liquidityToken,,) = hook.poolInfo(poolId);

        vm.prank(alice);
        MockERC20(liquidityToken).approve(address(mockPermit2), type(uint256).max);

        IMemeverseSwapRouter.Permit2SingleParams memory singlePermit = _singlePermit(liquidityToken, uint256(liquidity));
        uint256 balance0Before = token0.balanceOf(alice);
        uint256 balance1Before = token1.balanceOf(alice);

        vm.prank(alice);
        BalanceDelta delta = router.removeLiquidityWithPermit2(
            singlePermit, key.currency0, key.currency1, liquidity, 1, 1, alice, block.timestamp
        );

        assertGt(int256(delta.amount0()), 0, "delta0");
        assertGt(int256(delta.amount1()), 0, "delta1");
        assertGt(token0.balanceOf(alice), balance0Before, "token0 returned");
        assertGt(token1.balanceOf(alice), balance1Before, "token1 returned");
        assertEq(MockERC20(liquidityToken).balanceOf(alice), 0, "lp burned");
    }

    /// @notice Verifies LP-token Permit2 removals resolve pool metadata only once.
    /// @dev The Permit2 path already loads the LP token before entering the shared remove-liquidity flow.
    function testRemoveLiquidityWithPermit2_ReadsPoolInfoOnce() external {
        uint128 liquidity = _mintAliceLiquidity();
        (address liquidityToken,,) = hook.poolInfo(poolId);

        vm.prank(alice);
        MockERC20(liquidityToken).approve(address(mockPermit2), type(uint256).max);

        IMemeverseSwapRouter.Permit2SingleParams memory singlePermit = _singlePermit(liquidityToken, uint256(liquidity));

        vm.expectCall(address(hook), abi.encodeCall(IMemeverseUniswapHook.poolInfo, (poolId)), uint64(1));

        vm.prank(alice);
        BalanceDelta delta = router.removeLiquidityWithPermit2(
            singlePermit, key.currency0, key.currency1, liquidity, 1, 1, alice, block.timestamp
        );

        assertGt(int256(delta.amount0()), 0, "delta0");
        assertGt(int256(delta.amount1()), 0, "delta1");
    }

    /// @notice Verifies batch Permit2 funding can create a pool and seed liquidity.
    /// @dev Confirms the create-pool witness path includes the explicit `startPrice`.
    function testCreatePoolAndAddLiquidityWithPermit2() external {
        MockERC20 tokenA = new MockERC20("A", "A", 18);
        MockERC20 tokenB = new MockERC20("B", "B", 18);
        tokenA.mint(alice, 1_000_000 ether);
        tokenB.mint(alice, 1_000_000 ether);
        vm.prank(alice);
        tokenA.approve(address(mockPermit2), type(uint256).max);
        vm.prank(alice);
        tokenB.approve(address(mockPermit2), type(uint256).max);

        IMemeverseSwapRouter.Permit2BatchParams memory batchPermit =
            _batchPermit(address(tokenA), 100 ether, address(tokenB), 100 ether);

        vm.prank(alice);
        (uint128 liquidity, PoolKey memory createdKey) = router.createPoolAndAddLiquidityWithPermit2(
            batchPermit, address(tokenA), address(tokenB), 100 ether, 100 ether, SQRT_PRICE_1_1, alice, block.timestamp
        );

        (address liquidityToken,,) = hook.poolInfo(createdKey.toId());
        assertGt(liquidity, 0, "liquidity");
        assertEq(address(createdKey.hooks), address(hook), "hook");
        assertGt(MockERC20(liquidityToken).balanceOf(alice), 0, "lp balance");
    }

    /// @notice Verifies create-pool Permit2 calls reject mismatched batch lengths.
    /// @dev Pool creation should fail before any transfer when the batch payload shape is wrong.
    function testCreatePoolAndAddLiquidityWithPermit2_InvalidBatchLengthReverts() external {
        MockERC20 tokenA = new MockERC20("A", "A", 18);
        MockERC20 tokenB = new MockERC20("B", "B", 18);
        tokenA.mint(alice, 1_000_000 ether);
        tokenB.mint(alice, 1_000_000 ether);
        vm.prank(alice);
        tokenA.approve(address(mockPermit2), type(uint256).max);

        IMemeverseSwapRouter.Permit2BatchParams memory batchPermit = _batchPermitSingle(address(tokenA), 100 ether);

        vm.expectRevert(IMemeverseSwapRouter.InvalidPermit2Length.selector);
        vm.prank(alice);
        router.createPoolAndAddLiquidityWithPermit2(
            batchPermit, address(tokenA), address(tokenB), 100 ether, 100 ether, SQRT_PRICE_1_1, alice, block.timestamp
        );
    }

    /// @notice Verifies add-liquidity Permit2 calls reject mismatched token ordering.
    /// @dev The router must reject batch entries that do not match the expected pool currencies.
    function testAddLiquidityWithPermit2_TokenMismatchReverts() external {
        IMemeverseSwapRouter.Permit2BatchParams memory batchPermit =
            _batchPermit(address(token0), 100 ether, address(0xBEEF), 100 ether);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMemeverseSwapRouter.InvalidPermit2Token.selector, 1, address(token1), address(0xBEEF)
            )
        );
        vm.prank(alice);
        router.addLiquidityWithPermit2(
            batchPermit, key.currency0, key.currency1, 100 ether, 100 ether, 90 ether, 90 ether, alice, block.timestamp
        );
    }

    /// @notice Verifies Permit2 liquidity adds use the shared prepared-budget executor without leaving router residue.
    /// @dev The runtime size check makes the internal `budgetsPrepared` branch removal observable to this regression.
    function testAddLiquidityWithPermit2_UsesPreparedBudgetExecutorWithoutResidualBudget() external {
        uint256 amount0Desired = 100 ether;
        uint256 amount1Desired = 100 ether;
        IMemeverseSwapRouter.Permit2BatchParams memory batchPermit =
            _batchPermit(address(token0), amount0Desired, address(token1), amount1Desired);

        uint256 aliceToken0Before = token0.balanceOf(alice);
        uint256 aliceToken1Before = token1.balanceOf(alice);

        vm.prank(alice);
        uint128 liquidity = router.addLiquidityWithPermit2(
            batchPermit,
            key.currency0,
            key.currency1,
            amount0Desired,
            amount1Desired,
            90 ether,
            90 ether,
            alice,
            block.timestamp
        );

        uint256 token0Spent = aliceToken0Before - token0.balanceOf(alice);
        uint256 token1Spent = aliceToken1Before - token1.balanceOf(alice);
        assertGt(liquidity, 0, "liquidity");
        assertGt(token0Spent, 0, "token0 spent");
        assertGt(token1Spent, 0, "token1 spent");
        assertLt(token0Spent, amount0Desired, "token0 refund");
        assertLt(token1Spent, amount1Desired, "token1 refund");
        assertEq(token0.balanceOf(address(router)), 0, "token0 residual");
        assertEq(token1.balanceOf(address(router)), 0, "token1 residual");
        assertLt(address(router).code.length, 25_400, "runtime should shrink after removing budgetsPrepared");
    }

    /// @notice Verifies canonical Permit2 witness signing works for swaps.
    /// @dev Uses the signature-verifying Permit2 mock to cover the canonical witness format.
    function testSwapWithPermit2_RealPermit2CanonicalWitnessExecutes() external {
        hook.setProtocolFeeCurrency(key.currency0);
        _matureLaunchWindow();

        uint256 amountIn = 100 ether;
        uint256 amountOutMinimum = 40 ether;
        uint256 deadline = block.timestamp + 1 hours;
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(amountIn),
            sqrtPriceLimitX96: uint160((uint256(SQRT_PRICE_1_1) * 99) / 100)
        });

        ISignatureTransfer.PermitTransferFrom memory permit = ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({token: address(token0), amount: amountIn}),
            nonce: 11,
            deadline: deadline
        });
        ISignatureTransfer.SignatureTransferDetails memory transferDetails =
            ISignatureTransfer.SignatureTransferDetails({to: address(realPermit2Router), requestedAmount: amountIn});
        bytes32 witness = _swapWitnessHash(key, params, alice, deadline, amountOutMinimum, amountIn, bytes(""));
        bytes memory signature =
            _signSingleWitnessPermit(permit, address(realPermit2Router), witness, SWAP_WITNESS_TYPE_STRING);
        IMemeverseSwapRouter.Permit2SingleParams memory permitParams = IMemeverseSwapRouter.Permit2SingleParams({
            permit: permit, transferDetails: transferDetails, signature: signature
        });

        vm.prank(alice);
        BalanceDelta delta = realPermit2Router.swapWithPermit2(
            permitParams, key, params, alice, deadline, amountOutMinimum, amountIn, bytes("")
        );

        assertLt(int256(delta.amount0()), 0, "delta0");
        assertGt(int256(delta.amount1()), 0, "delta1");
    }

    /// @notice Verifies canonical Permit2 batch witness signing works for liquidity adds.
    /// @dev Uses the signature-verifying Permit2 mock to cover canonical batch witnesses.
    function testAddLiquidityWithPermit2_RealPermit2CanonicalBatchWitnessExecutes() external {
        uint256 amount0Desired = 100 ether;
        uint256 amount1Desired = 100 ether;
        uint256 deadline = block.timestamp + 1 hours;

        ISignatureTransfer.PermitBatchTransferFrom memory permit;
        permit.permitted = new ISignatureTransfer.TokenPermissions[](2);
        permit.permitted[0] = ISignatureTransfer.TokenPermissions({token: address(token0), amount: amount0Desired});
        permit.permitted[1] = ISignatureTransfer.TokenPermissions({token: address(token1), amount: amount1Desired});
        permit.nonce = 12;
        permit.deadline = deadline;

        ISignatureTransfer.SignatureTransferDetails[] memory transferDetails =
            new ISignatureTransfer.SignatureTransferDetails[](2);
        transferDetails[0] = ISignatureTransfer.SignatureTransferDetails({
            to: address(realPermit2Router), requestedAmount: amount0Desired
        });
        transferDetails[1] = ISignatureTransfer.SignatureTransferDetails({
            to: address(realPermit2Router), requestedAmount: amount1Desired
        });

        bytes32 witness = _addLiquidityWitnessHash(
            key.currency0, key.currency1, amount0Desired, amount1Desired, 90 ether, 90 ether, alice, deadline
        );
        bytes memory signature =
            _signBatchWitnessPermit(permit, address(realPermit2Router), witness, ADD_LIQUIDITY_WITNESS_TYPE_STRING);
        IMemeverseSwapRouter.Permit2BatchParams memory permitParams = IMemeverseSwapRouter.Permit2BatchParams({
            permit: permit, transferDetails: transferDetails, signature: signature
        });

        vm.prank(alice);
        uint128 liquidity = realPermit2Router.addLiquidityWithPermit2(
            permitParams,
            key.currency0,
            key.currency1,
            amount0Desired,
            amount1Desired,
            90 ether,
            90 ether,
            alice,
            deadline
        );

        assertGt(liquidity, 0, "liquidity");
    }

    /// @notice Verifies canonical Permit2 witness signing works for liquidity removal.
    /// @dev Uses the signature-verifying Permit2 mock to cover LP-token witness removals.
    function testRemoveLiquidityWithPermit2_RealPermit2CanonicalWitnessExecutes() external {
        uint128 liquidity = _mintAliceLiquidity();
        (address liquidityToken,,) = hook.poolInfo(poolId);
        uint256 deadline = block.timestamp + 1 hours;

        vm.prank(alice);
        MockERC20(liquidityToken).approve(address(realPermit2), type(uint256).max);

        ISignatureTransfer.PermitTransferFrom memory permit = ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({token: liquidityToken, amount: uint256(liquidity)}),
            nonce: 13,
            deadline: deadline
        });
        ISignatureTransfer.SignatureTransferDetails memory transferDetails = ISignatureTransfer.SignatureTransferDetails({
            to: address(realPermit2Router), requestedAmount: uint256(liquidity)
        });
        bytes32 witness = _removeLiquidityWitnessHash(key.currency0, key.currency1, liquidity, 1, 1, alice, deadline);
        bytes memory signature =
            _signSingleWitnessPermit(permit, address(realPermit2Router), witness, REMOVE_LIQUIDITY_WITNESS_TYPE_STRING);
        IMemeverseSwapRouter.Permit2SingleParams memory permitParams = IMemeverseSwapRouter.Permit2SingleParams({
            permit: permit, transferDetails: transferDetails, signature: signature
        });

        vm.prank(alice);
        BalanceDelta delta = realPermit2Router.removeLiquidityWithPermit2(
            permitParams, key.currency0, key.currency1, liquidity, 1, 1, alice, deadline
        );

        assertGt(int256(delta.amount0()), 0, "delta0");
        assertGt(int256(delta.amount1()), 0, "delta1");
    }

    /// @notice Verifies canonical Permit2 batch witness signing works for create-pool flows.
    /// @dev Uses the signature-verifying Permit2 mock to cover create-pool batch witnesses.
    function testCreatePoolAndAddLiquidityWithPermit2_RealPermit2CanonicalBatchWitnessExecutes() external {
        MockERC20 tokenA = new MockERC20("A", "A", 18);
        MockERC20 tokenB = new MockERC20("B", "B", 18);
        tokenA.mint(alice, 1_000_000 ether);
        tokenB.mint(alice, 1_000_000 ether);
        uint256 deadline = block.timestamp + 1 hours;

        vm.prank(alice);
        tokenA.approve(address(realPermit2), type(uint256).max);
        vm.prank(alice);
        tokenB.approve(address(realPermit2), type(uint256).max);

        ISignatureTransfer.PermitBatchTransferFrom memory permit;
        permit.permitted = new ISignatureTransfer.TokenPermissions[](2);
        permit.permitted[0] = ISignatureTransfer.TokenPermissions({token: address(tokenA), amount: 100 ether});
        permit.permitted[1] = ISignatureTransfer.TokenPermissions({token: address(tokenB), amount: 100 ether});
        permit.nonce = 14;
        permit.deadline = deadline;

        ISignatureTransfer.SignatureTransferDetails[] memory transferDetails =
            new ISignatureTransfer.SignatureTransferDetails[](2);
        transferDetails[0] =
            ISignatureTransfer.SignatureTransferDetails({to: address(realPermit2Router), requestedAmount: 100 ether});
        transferDetails[1] =
            ISignatureTransfer.SignatureTransferDetails({to: address(realPermit2Router), requestedAmount: 100 ether});

        bytes32 witness = _createPoolWitnessHash(
            address(tokenA), address(tokenB), 100 ether, 100 ether, SQRT_PRICE_1_1, alice, deadline
        );
        bytes memory signature =
            _signBatchWitnessPermit(permit, address(realPermit2Router), witness, CREATE_POOL_WITNESS_TYPE_STRING);
        IMemeverseSwapRouter.Permit2BatchParams memory permitParams = IMemeverseSwapRouter.Permit2BatchParams({
            permit: permit, transferDetails: transferDetails, signature: signature
        });

        vm.prank(alice);
        (uint128 liquidity, PoolKey memory createdKey) = realPermit2Router.createPoolAndAddLiquidityWithPermit2(
            permitParams, address(tokenA), address(tokenB), 100 ether, 100 ether, SQRT_PRICE_1_1, alice, deadline
        );

        assertGt(liquidity, 0, "liquidity");
        assertEq(address(createdKey.hooks), address(hook), "hook");
    }

    /// @notice Builds the normalized pool key wired to the test hook.
    /// @dev Reuses the same hook address and fee configuration for all Permit2 cases.
    function _dynamicPoolKey(Currency currency0, Currency currency1) internal view returns (PoolKey memory) {
        return PoolKey({
            currency0: currency0, currency1: currency1, fee: 0x800000, tickSpacing: 200, hooks: IHooks(address(hook))
        });
    }

    /// @notice Mints liquidity on Alice's behalf through the router.
    /// @dev Covers the shared liquidity creation path used by Permit2 removal tests.
    function _mintAliceLiquidity() internal returns (uint128 liquidity) {
        vm.prank(alice);
        token0.approve(address(router), type(uint256).max);
        vm.prank(alice);
        token1.approve(address(router), type(uint256).max);

        vm.prank(alice);
        liquidity = router.addLiquidity(
            key.currency0, key.currency1, 100 ether, 100 ether, 90 ether, 90 ether, alice, block.timestamp
        );
    }

    /// @notice Fabricates a minimal single-token Permit2 payload for router tests.
    /// @dev Keeps the signature bytes constant because the router test harness skips verification.
    function _singlePermit(address token, uint256 amount)
        internal
        view
        returns (IMemeverseSwapRouter.Permit2SingleParams memory permitParams)
    {
        permitParams = IMemeverseSwapRouter.Permit2SingleParams({
            permit: ISignatureTransfer.PermitTransferFrom({
                permitted: ISignatureTransfer.TokenPermissions({token: token, amount: amount}),
                nonce: 1,
                deadline: block.timestamp
            }),
            transferDetails: ISignatureTransfer.SignatureTransferDetails({
                to: address(router), requestedAmount: amount
            }),
            signature: hex"1234"
        });
    }

    /// @notice Fabricates a Permit2 batch payload containing two token legs.
    /// @dev Populates the minimal fields the router expects when bulk funding liquidity.
    function _batchPermit(address token0_, uint256 amount0_, address token1_, uint256 amount1_)
        internal
        view
        returns (IMemeverseSwapRouter.Permit2BatchParams memory permitParams)
    {
        permitParams.permit.permitted = new ISignatureTransfer.TokenPermissions[](2);
        permitParams.permit.permitted[0] = ISignatureTransfer.TokenPermissions({token: token0_, amount: amount0_});
        permitParams.permit.permitted[1] = ISignatureTransfer.TokenPermissions({token: token1_, amount: amount1_});
        permitParams.permit.nonce = 2;
        permitParams.permit.deadline = block.timestamp;
        permitParams.transferDetails = new ISignatureTransfer.SignatureTransferDetails[](2);
        permitParams.transferDetails[0] =
            ISignatureTransfer.SignatureTransferDetails({to: address(router), requestedAmount: amount0_});
        permitParams.transferDetails[1] =
            ISignatureTransfer.SignatureTransferDetails({to: address(router), requestedAmount: amount1_});
        permitParams.signature = hex"1234";
    }

    /// @notice Fabricates a Permit2 batch payload with a single token leg.
    /// @dev Mirrors the native-plus-ERC20 funding branch that uses only one batch entry.
    function _batchPermitSingle(address token, uint256 amount)
        internal
        view
        returns (IMemeverseSwapRouter.Permit2BatchParams memory permitParams)
    {
        permitParams.permit.permitted = new ISignatureTransfer.TokenPermissions[](1);
        permitParams.permit.permitted[0] = ISignatureTransfer.TokenPermissions({token: token, amount: amount});
        permitParams.permit.nonce = 3;
        permitParams.permit.deadline = block.timestamp;
        permitParams.transferDetails = new ISignatureTransfer.SignatureTransferDetails[](1);
        permitParams.transferDetails[0] =
            ISignatureTransfer.SignatureTransferDetails({to: address(router), requestedAmount: amount});
        permitParams.signature = hex"1234";
    }

    /// @notice Computes the canonical witness hash for swap operations.
    /// @dev Matches the Property-based witness format used by the real Permit2 router.
    function _swapWitnessHash(
        PoolKey memory poolKey,
        SwapParams memory params,
        address recipient,
        uint256 deadline,
        uint256 amountOutMinimum,
        uint256 amountInMaximum,
        bytes memory hookData
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                SWAP_WITNESS_TYPEHASH,
                poolKey.toId(),
                params.zeroForOne,
                params.amountSpecified,
                params.sqrtPriceLimitX96,
                recipient,
                deadline,
                amountOutMinimum,
                amountInMaximum,
                keccak256(hookData)
            )
        );
    }

    /// @notice Computes the witness hash used for liquidity adds.
    /// @dev Includes the ordered liquidity parameters that the router signs.
    function _addLiquidityWitnessHash(
        Currency currency0,
        Currency currency1,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        address to,
        uint256 deadline
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                ADD_LIQUIDITY_WITNESS_TYPEHASH,
                Currency.unwrap(currency0),
                Currency.unwrap(currency1),
                amount0Desired,
                amount1Desired,
                amount0Min,
                amount1Min,
                to,
                deadline
            )
        );
    }

    /// @notice Computes the witness hash used for liquidity removals.
    /// @dev Covers the signed view that authorizes Permit2 LP withdrawals.
    function _removeLiquidityWitnessHash(
        Currency currency0,
        Currency currency1,
        uint128 liquidity,
        uint256 amount0Min,
        uint256 amount1Min,
        address to,
        uint256 deadline
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                REMOVE_LIQUIDITY_WITNESS_TYPEHASH,
                Currency.unwrap(currency0),
                Currency.unwrap(currency1),
                liquidity,
                amount0Min,
                amount1Min,
                to,
                deadline
            )
        );
    }

    /// @notice Computes the witness hash for pool creation.
    /// @dev Ensures the signature matches the router's create-pool witness semantics.
    function _createPoolWitnessHash(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint160 startPrice,
        address recipient,
        uint256 deadline
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                CREATE_POOL_WITNESS_TYPEHASH,
                tokenA,
                tokenB,
                amountADesired,
                amountBDesired,
                startPrice,
                recipient,
                deadline
            )
        );
    }

    /// @notice Signs a swap or LP permit witness with the mock Permit2 key.
    /// @dev Uses the canonical signer key to keep signature-dependent flows deterministic.
    function _signSingleWitnessPermit(
        ISignatureTransfer.PermitTransferFrom memory permit,
        address spender,
        bytes32 witness,
        string memory witnessTypeString
    ) internal view returns (bytes memory signature) {
        bytes32 typeHash = keccak256(abi.encodePacked(PERMIT_SINGLE_WITNESS_TYPEHASH_STUB, witnessTypeString));
        bytes32 tokenPermissionsHash =
            keccak256(abi.encode(TOKEN_PERMISSIONS_TYPEHASH, permit.permitted.token, permit.permitted.amount));
        bytes32 permitHash =
            keccak256(abi.encode(typeHash, tokenPermissionsHash, spender, permit.nonce, permit.deadline, witness));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", realPermit2.DOMAIN_SEPARATOR(), permitHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ALICE_PK, digest);
        return bytes.concat(r, s, bytes1(v));
    }

    /// @notice Signs a batch witness permit using the canonical mock signer.
    /// @dev Reuses the same signer so multi-token witnesses remain consistent across tests.
    function _signBatchWitnessPermit(
        ISignatureTransfer.PermitBatchTransferFrom memory permit,
        address spender,
        bytes32 witness,
        string memory witnessTypeString
    ) internal view returns (bytes memory signature) {
        bytes32[] memory tokenPermissionHashes = new bytes32[](permit.permitted.length);
        for (uint256 i = 0; i < permit.permitted.length; ++i) {
            tokenPermissionHashes[i] = keccak256(
                abi.encode(TOKEN_PERMISSIONS_TYPEHASH, permit.permitted[i].token, permit.permitted[i].amount)
            );
        }

        bytes32 typeHash = keccak256(abi.encodePacked(PERMIT_BATCH_WITNESS_TYPEHASH_STUB, witnessTypeString));
        bytes32 permitHash = keccak256(
            abi.encode(
                typeHash,
                keccak256(abi.encodePacked(tokenPermissionHashes)),
                spender,
                permit.nonce,
                permit.deadline,
                witness
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", realPermit2.DOMAIN_SEPARATOR(), permitHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ALICE_PK, digest);
        return bytes.concat(r, s, bytes1(v));
    }
}
