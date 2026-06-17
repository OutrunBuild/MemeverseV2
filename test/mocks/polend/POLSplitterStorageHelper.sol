// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {StorageSlotPrimitives} from "../StorageSlotPrimitives.sol";

import {PrincipalToken} from "../../../src/polend/tokens/PrincipalToken.sol";
import {YieldToken} from "../../../src/polend/tokens/YieldToken.sol";

/// @notice Standalone white-box accessor for POLSplitter proxy storage.
///         Does not inherit any src/ contract. Reads/writes proxy storage slots via vm.load/vm.store
///         and replays the privileged mint path (PT/YT mint is only callable by the splitter proxy),
///         replicating the writes previously performed by the test-only POLSplitterHarness.
///         Your test contract should inherit this helper (`is Test, POLSplitterStorageHelper`).
abstract contract POLSplitterStorageHelper is StorageSlotPrimitives {
    // erc7201:outrun.storage.POLSplitter namespace location (src/polend/POLSplitter.sol:35-36).
    bytes32 internal constant POL_SPLITTER_SLOT = 0xab504a6dee30096d32ccac13a30a002829c5eeb4c38a0196ed16a6c4e9faca00;

    // Struct field slot offsets in POLSplitterStorage (src/polend/POLSplitter.sol:25-32).
    uint256 internal constant OFF_SPLIT_INFOS = 0; // mapping(uint256 => SplitInfo)
    uint256 internal constant OFF_PRE_REDEEMED = 1; // mapping(uint256 => PreRedeemedState)
    uint256 internal constant OFF_LAUNCHER = 2; // address
    uint256 internal constant OFF_POLEND = 3; // address
    uint256 internal constant OFF_PT_IMPL = 4; // address
    uint256 internal constant OFF_YT_IMPL = 5; // address

    // SplitInfo sub-field offsets (src/polend/interfaces/IPOLSplitter.sol:5-17).
    // Order: pt, yt, pol, memecoin, uAsset, totalPOLCollateral, settlementUAsset,
    //        settlementMemecoin, ptBackingNumerator, ptBackingDenominator, settled(bool).
    uint256 internal constant OFF_SI_PT = 0;
    uint256 internal constant OFF_SI_YT = 1;
    uint256 internal constant OFF_SI_SETTLEMENT_UASSET = 6;
    uint256 internal constant OFF_SI_SETTLEMENT_MEMECOIN = 7;
    uint256 internal constant OFF_SI_SETTLED = 10;

    // ── Slot computation helpers ──

    /// @dev Slot for $.splitInfos[verseId] (mapping(uint256 => SplitInfo) at struct field offset 0).
    function _splitInfoSlot(uint256 verseId) internal pure returns (bytes32) {
        return keccak256(abi.encode(verseId, POL_SPLITTER_SLOT));
    }

    // ── Seed methods (mirror POLSplitterHarness, field-by-field equivalent) ──

    /// @notice Write $.splitInfos[verseId].settlementUAsset, .settlementMemecoin and .settled=true.
    /// @dev Equivalent to POLSplitterHarness.mockSettled; settled occupies its own 32-byte slot at off+10.
    function mockSettledForTest(address proxy, uint256 verseId, uint256 settlementUAsset, uint256 settlementMemecoin)
        internal
    {
        bytes32 base = _splitInfoSlot(verseId);
        _writeSlot(proxy, bytes32(uint256(base) + OFF_SI_SETTLEMENT_UASSET), bytes32(settlementUAsset));
        _writeSlot(proxy, bytes32(uint256(base) + OFF_SI_SETTLEMENT_MEMECOIN), bytes32(settlementMemecoin));
        _writeSlot(proxy, bytes32(uint256(base) + OFF_SI_SETTLED), bytes32(uint256(1)));
    }

    /// @notice Read $.splitInfos[verseId].pt from storage (avoids a wide multi-return public getter).
    function _readPT(address proxy, uint256 verseId) internal view returns (address) {
        return address(uint160(uint256(_loadSlot(proxy, bytes32(uint256(_splitInfoSlot(verseId)) + OFF_SI_PT)))));
    }

    /// @notice Read $.splitInfos[verseId].yt from storage.
    function _readYT(address proxy, uint256 verseId) internal view returns (address) {
        return address(uint160(uint256(_loadSlot(proxy, bytes32(uint256(_splitInfoSlot(verseId)) + OFF_SI_YT)))));
    }

    /// @notice Mint PT to `to`. PT.mint is gated by `onlySplitter`, so the call must come from the
    ///         splitter proxy itself (matches POLSplitterHarness.mintPT, which inherited POLSplitter).
    function mintPTForTest(address proxy, uint256 verseId, address to, uint256 amount) internal {
        address pt = _readPT(proxy, verseId);
        vm.prank(proxy);
        PrincipalToken(pt).mint(to, amount);
    }

    /// @notice Mint YT to `to`. Same onlySplitter gating as mintPTForTest.
    function mintYTForTest(address proxy, uint256 verseId, address to, uint256 amount) internal {
        address yt = _readYT(proxy, verseId);
        vm.prank(proxy);
        YieldToken(yt).mint(to, amount);
    }
}

// ── Inline sanity test ──
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {POLSplitter} from "../../../src/polend/POLSplitter.sol";

/// @dev Minimal launcher stand-in so POLSplitter.initialize + initializeVerse succeed without the real launcher.
contract _PolSplitterHelperFakeLauncher {
    address private _polend;

    function setPolend(address p) external {
        _polend = p;
    }

    function polend() external view returns (address) {
        return _polend;
    }
}

contract POLSplitterStorageHelperSanityTest is Test, POLSplitterStorageHelper {
    function test_slotRoundTrip_mockSettledAndMints() external {
        _PolSplitterHelperFakeLauncher fakeLauncher = new _PolSplitterHelperFakeLauncher();
        POLSplitter impl = new POLSplitter();
        address proxy = address(
            new ERC1967Proxy(
                address(impl), abi.encodeCall(POLSplitter.initialize, (address(this), address(fakeLauncher)))
            )
        );

        // Initialize a verse so splitInfos[verseId] has real pt/yt addresses.
        vm.prank(address(fakeLauncher));
        POLSplitter(proxy).initializeVerse(7, address(0xA1), address(0xA2), address(0xA3), "Verse", "VRS");

        // mockSettledForTest writes the three harness fields; verify via the public splitInfos getter.
        mockSettledForTest(proxy, 7, 900 ether, 400 ether);
        (,,,,,, uint256 settlementUAsset, uint256 settlementMemecoin,,, bool settled) = POLSplitter(proxy).splitInfos(7);
        assertEq(settlementUAsset, 900 ether, "settlement uAsset round-trip");
        assertEq(settlementMemecoin, 400 ether, "settlement memecoin round-trip");
        assertTrue(settled, "settled round-trip");

        // mintPTForTest / mintYTForTest must drive PT/YT mint through the splitter proxy (onlySplitter).
        address to = address(0xBEEF);
        mintPTForTest(proxy, 7, to, 12 ether);
        mintYTForTest(proxy, 7, to, 34 ether);
        (address pt, address yt) = POLSplitter(proxy).getPTAndYT(7);
        assertEq(PrincipalToken(pt).balanceOf(to), 12 ether, "pt minted");
        assertEq(YieldToken(yt).balanceOf(to), 34 ether, "yt minted");
    }
}
