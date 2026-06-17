// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {StorageSlotPrimitives} from "../StorageSlotPrimitives.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";

import {MemeverseDynamicFeeEngine} from "../../../src/swap/MemeverseDynamicFeeEngine.sol";
import {MemeverseUniswapHook} from "../../../src/swap/MemeverseUniswapHook.sol";
import {UniswapLP} from "../../../src/swap/tokens/UniswapLP.sol";

/// @notice Standalone white-box helper for MemeverseUniswapHook proxy storage and flag-address deployment.
/// @dev Does NOT inherit MemeverseUniswapHook; only inherits Test. Two responsibilities:
///      1. `deployHookAtFlagAddress`: deploys a REAL MemeverseUniswapHook behind a CREATE2-mined ERC1967Proxy
///         whose address carries the v4 hook permission flags (low 14 bits == 0x28CC). This lets tests drop
///         the `Testable*` hook subclasses that previously disabled address validation.
///      2. `seedActiveLiquiditySharesForTest`: seeds `cachedLpTotalSupply[poolId]` and mints the matching LP
///         tokens via vm.store + vm.prank, replicating the test-only `seedActiveLiquidityShares` previously
///         exposed on Testable hooks. LP.mint is `onlyOwner` (the hook), so the mint must be pranked as the
///         proxy while the cached-supply write is done directly via vm.store.
///      Inherit with `is Test, HookStorageHelper`.
abstract contract HookStorageHelper is StorageSlotPrimitives {
    using PoolIdLibrary for PoolId;

    // ── Hook permission flags (must mirror MemeverseUniswapHook.getHookPermissions) ──
    // Bits set: beforeInitialize(13) | beforeAddLiquidity(11) | beforeSwap(7) | afterSwap(6)
    //         | beforeSwapReturnDelta(3) | afterSwapReturnDelta(2) == 0x28CC.
    uint160 internal constant HOOK_REQUIRED_FLAGS =
        uint160((1 << 13) | (1 << 11) | (1 << 7) | (1 << 6) | (1 << 3) | (1 << 2));
    uint160 internal constant HOOK_FLAG_MASK = uint160((1 << 14) - 1);

    // erc7201:outrun.storage.MemeverseUniswapHook namespace location
    // (src/swap/MemeverseUniswapHook.sol:147).
    bytes32 internal constant HOOK_SLOT = 0x9f27a56b97c42ac08d93ff5a852851d11eb052b06dc4c041fc6bfa4414f7e000;

    // Struct field offsets in MemeverseUniswapHookStorage
    // (src/swap/MemeverseUniswapHook.sol:131-144).
    uint256 internal constant OFF_TREASURY = 0;
    uint256 internal constant OFF_LAUNCHER = 1;
    uint256 internal constant OFF_SUPPORTED_FEE_CURRENCIES = 2; // mapping(address => bool)
    uint256 internal constant OFF_POOL_INFO = 3; // mapping(PoolId => PoolInfo)
    uint256 internal constant OFF_CACHED_LP_TOTAL_SUPPLY = 4; // mapping(PoolId => uint256)
    uint256 internal constant OFF_POOL_INITIALIZER = 9;
    uint256 internal constant OFF_DYNAMIC_FEE_ENGINE = 11;

    // ── Slot computation helpers ──

    /// @dev Slot for mapping(PoolId => T) at struct field offset `fieldOffset` keyed by poolId.
    ///      PoolId is a bytes32 user-type; abi.encode on it encodes the raw bytes32 value.
    function _poolIdMappingSlot(uint256 fieldOffset, PoolId poolId) internal pure returns (bytes32) {
        return keccak256(abi.encode(PoolId.unwrap(poolId), bytes32(uint256(HOOK_SLOT) + fieldOffset)));
    }

    /// @notice Reads the production hook's `cachedLpTotalSupply[poolId]` directly from storage.
    /// @dev Replaces the test-only `exposedCachedLpTotalSupply` previously exposed on Testable hook subclasses.
    ///      Used by fee-accounting tests to assert the cached LP supply stays in sync with the LP token contract.
    function getCachedLpTotalSupplyForTest(address proxy, PoolId poolId) internal view returns (uint256) {
        return uint256(_loadSlot(proxy, _poolIdMappingSlot(OFF_CACHED_LP_TOTAL_SUPPLY, poolId)));
    }

    // ── Flag-address deployment ──

    /// @notice Deploys a REAL MemeverseUniswapHook behind a CREATE2-mined ERC1967Proxy whose low 14 bits
    ///         equal 0x28CC, so the production `_validateProxyHookAddress()` passes at `initialize`.
    /// @dev Verbatim copy of the validated HookAddressFlagPoC deployment sequence. Chicken-egg resolution:
    ///      predicted hook proxy address is mined against (deployer, salt, proxyInitCode) where proxyInitCode
    ///      embeds the engine PROXY address (a CREATE we precompute) and the hook impl address (also
    ///      precomputed). The engine proxy is then deployed with owner = authorizedHook = predictedProxy.
    /// @param manager Uniswap v4 pool manager.
    /// @param hookOwner Initial hook owner (typically the test contract).
    /// @param treasury Treasury set at initialize.
    /// @return hookProxy Address of the deployed hook proxy (carries flag bits).
    /// @return engineProxy The engine proxy bound to the hook (owner = authorizedHook = hookProxy).
    function deployHookAtFlagAddress(IPoolManager manager, address hookOwner, address treasury)
        internal
        returns (address hookProxy, address engineProxy)
    {
        // (a) Predict engine proxy address: next CREATE after engine impl.
        uint256 nonceBeforeEngineImpl = vm.getNonce(address(this));
        MemeverseDynamicFeeEngine engineImpl = new MemeverseDynamicFeeEngine(manager);
        address predictedEngineProxy = vm.computeCreateAddress(address(this), nonceBeforeEngineImpl + 1);

        // (b) Predict hook impl address: CREATE order is engine impl, engine proxy, hook impl.
        address predictedHookImpl = vm.computeCreateAddress(address(this), nonceBeforeEngineImpl + 2);

        // (c) Assemble hook proxy initCode. The engine reference must be the engine PROXY (not impl),
        //     since hook.initialize reads engine.owner/authorizedHook behind the proxy.
        bytes memory hookInitData = abi.encodeCall(
            MemeverseUniswapHook.initialize, (hookOwner, treasury, MemeverseDynamicFeeEngine(predictedEngineProxy))
        );
        bytes memory proxyInitCode =
            abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(predictedHookImpl, hookInitData));

        // (d) Mine CREATE2 salt so the hook proxy lands at an address whose low 14 bits == 0x28CC.
        bytes32 salt;
        address predictedProxy;
        bytes32 initCodeHash = keccak256(proxyInitCode);
        for (uint256 i = 0; i < type(uint256).max; i++) {
            salt = bytes32(i);
            bytes32 digest = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, initCodeHash));
            predictedProxy = address(uint160(uint256(digest)));
            if (uint160(predictedProxy) & HOOK_FLAG_MASK == HOOK_REQUIRED_FLAGS) {
                break;
            }
        }
        require(uint160(predictedProxy) & HOOK_FLAG_MASK == HOOK_REQUIRED_FLAGS, "no mined salt");

        // (e) Deploy engine proxy with owner = authorizedHook = predictedProxy. Lands at predictedEngineProxy.
        MemeverseDynamicFeeEngine engine = MemeverseDynamicFeeEngine(
            address(
                new ERC1967Proxy(
                    address(engineImpl),
                    abi.encodeCall(MemeverseDynamicFeeEngine.initialize, (predictedProxy, predictedProxy))
                )
            )
        );

        // (f) Deploy hook implementation (the REAL production contract).
        MemeverseUniswapHook hookImpl = new MemeverseUniswapHook(manager);

        // (g) CREATE2-deploy hook proxy at the mined predictedProxy address; initialize runs here.
        ERC1967Proxy proxy = new ERC1967Proxy{salt: salt}(address(hookImpl), hookInitData);

        require(address(proxy) == predictedProxy, "CREATE2 proxy drifted");
        require(address(engine) == predictedEngineProxy, "engine proxy drifted");
        require(address(hookImpl) == predictedHookImpl, "hook impl drifted");

        return (address(proxy), address(engine));
    }

    // ── Seed methods ──

    /// @notice Seeds active LP shares for a pool without going through the liquidity callback.
    /// @dev Replicates the test-only `seedActiveLiquidityShares` previously on Testable hooks:
    ///      `cachedLpTotalSupply[poolId] += activeShares` and `UniswapLP.mint(owner, activeShares)`.
    ///      LP.mint is restricted to the hook (`onlyOwner`), so the mint is performed via `vm.prank(proxy)`.
    ///      The cached supply write is performed directly via vm.store on the cachedLpTotalSupply slot.
    ///      Requires the pool to already be initialized (liquidityToken != address(0)).
    function seedActiveLiquiditySharesForTest(address proxy, PoolId poolId, address owner, uint256 activeShares)
        internal
    {
        (address liquidityToken,,) = MemeverseUniswapHook(proxy).poolInfo(poolId);
        require(liquidityToken != address(0), "pool not initialized");

        // cachedLpTotalSupply[poolId] += activeShares
        bytes32 slot = _poolIdMappingSlot(OFF_CACHED_LP_TOTAL_SUPPLY, poolId);
        uint256 current = uint256(_loadSlot(proxy, slot));
        _writeSlot(proxy, slot, bytes32(current + activeShares));

        // LP.mint is onlyOwner == hook proxy; prank as the proxy to satisfy the access check.
        vm.prank(proxy);
        UniswapLP(liquidityToken).mint(owner, activeShares);
    }
}
