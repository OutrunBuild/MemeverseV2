// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

import {MemeverseLauncherLifecycleTest} from "./MemeverseLauncherLifecycle.t.sol";
import {IMemeverseLauncher} from "../../src/verse/interfaces/IMemeverseLauncher.sol";
import {MockOFTToken} from "../mocks/verse/LauncherLifecycleMocks.sol";
import {FullMath} from "@uniswap/v4-core/src/libraries/FullMath.sol";

/// @title MemeverseLauncherFeePreviewConsistencyTest
/// @notice Anti-drift sentinel: `MemeverseFeePreviewReader.quoteDistributionLzFee` must return exactly the
///         native fee that `MemeverseLauncher.redeemAndDistributeFees` requires, so a keeper funding the
///         quoted amount never hits `InvalidLzFee`.
/// @dev The preview reader and the fee distributor compute the same fee split / pair-fee mapping through
///      shared `MemeverseLauncherLib` helpers (`splitExecutorReward`, `mapPairFees`); the remaining mirrored
///      helpers (`_splitAuxiliaryGovFees`, `_buildSendParamAndMessagingFee`) are paired by source convention.
///      These tests wire the reader's preview fee source (`router.setPreviewQuote`) and the distributor's
///      runtime fee source (`router.setClaimQuote`) to identical amounts, then assert the quoted LZ fee
///      equals the runtime-required LZ fee across exact / underpay / overpay funding. If either side's
///      arithmetic drifts, the quoted amount diverges from the required amount and the exact-funding case
///      reverts — turning a silent preview/runtime mismatch into a red test.
contract MemeverseLauncherFeePreviewConsistencyTest is MemeverseLauncherLifecycleTest {
    /// @notice Remote verse with both main-pool and auxiliary fees: the quoted LZ fee funds an exact redeem.
    function testFeePreviewConsistency_QuoteEqualsRequiredLzFee_RemoteBothFees() external {
        uint256 verseId = 100;
        uint256 quoted = _setupRemoteFeeVerse(verseId, 9 ether, 4 ether, 6 ether, 0.15 ether, 0.25 ether);
        assertEq(quoted, 0.4 ether, "quoted lz fee");

        // Funding exactly the quoted amount must NOT revert — quote matches the runtime required LZ fee.
        launcher.redeemAndDistributeFees{value: quoted}(verseId, REWARD_RECEIVER);
    }

    /// @notice Underpaying the quoted LZ fee by 1 wei reverts with the required vs. provided amounts.
    function testFeePreviewConsistency_UnderpayReverts_RemoteBothFees() external {
        uint256 verseId = 101;
        uint256 quoted = _setupRemoteFeeVerse(verseId, 9 ether, 4 ether, 6 ether, 0.15 ether, 0.25 ether);

        vm.expectRevert(abi.encodeWithSelector(IMemeverseLauncher.InvalidLzFee.selector, quoted, quoted - 1));
        launcher.redeemAndDistributeFees{value: quoted - 1}(verseId, REWARD_RECEIVER);
    }

    /// @notice Overpaying the quoted LZ fee by 1 wei reverts — the launcher requires exact funding.
    function testFeePreviewConsistency_OverpayReverts_RemoteBothFees() external {
        uint256 verseId = 102;
        uint256 quoted = _setupRemoteFeeVerse(verseId, 9 ether, 4 ether, 6 ether, 0.15 ether, 0.25 ether);

        vm.expectRevert(abi.encodeWithSelector(IMemeverseLauncher.InvalidLzFee.selector, quoted, quoted + 1));
        launcher.redeemAndDistributeFees{value: quoted + 1}(verseId, REWARD_RECEIVER);
    }

    /// @notice Gov-only remote verse (memecoin fee zero): the quote still matches the required LZ fee when
    ///         only the uAsset OFT send fires, guarding the `_splitExecutorReward` / auxiliary split path.
    function testFeePreviewConsistency_QuoteEqualsRequiredLzFee_RemoteGovFeeOnly() external {
        uint256 verseId = 103;
        // Main-pool memecoin fee is zero; only the uAsset (gov) send fires.
        uint256 quoted = _setupRemoteFeeVerse(verseId, 0, 4 ether, 6 ether, 0.15 ether, 0.25 ether);
        assertEq(quoted, 0.15 ether, "quoted lz fee gov-only");

        launcher.redeemAndDistributeFees{value: quoted}(verseId, REWARD_RECEIVER);
    }

    /// @notice Exercises the still-mirrored `_splitAuxiliaryGovFees` arithmetic with `quoteSend` tracking
    ///         `amountLD`, so a magnitude drift in the auxiliary-gov split surfaces as a quote != required
    ///         mismatch. Seeds non-zero leverage and normal funds so the `mulDiv` gov-share branch executes
    ///         on BOTH the reader and the distributor, and enables amount-sensitive OFT quoting so the LZ fee
    ///         reflects the actual send amount — not a fixed mock fee.
    function testFeePreviewConsistency_AuxiliaryGovSplitDriftDetected_RemoteAmountSensitiveQuote() external {
        uint256 verseId = 110;
        uint256 mainMemecoinFee = 3 ether;
        uint256 mainUAssetFee = 4 ether;
        uint256 auxUAssetFee = 6 ether;
        // Non-trivial leverage ratio: gov takes the leveraged share of auxiliary fees.
        uint256 normalFunds = 30 ether;
        uint256 leveragedDebt = 70 ether;

        uint256 quoted = _setupRemoteFeeVerseWithLeverage(
            verseId, mainMemecoinFee, mainUAssetFee, auxUAssetFee, normalFunds, leveragedDebt
        );

        // Expected gov fee (reader and distributor must agree byte-for-byte):
        //   main-pool gov = mainUAssetFee - executorReward (executorRewardRate default 25 bps)
        //   auxiliary gov = auxUAssetFee * leveragedDebt / (normalFunds + leveragedDebt)
        // Quoted LZ fee (amount-sensitive) = govFee + memecoinFee, each equal to its OFT send amountLD.
        uint256 executorReward = FullMath.mulDiv(mainUAssetFee, 25, 10_000);
        uint256 mainGov = mainUAssetFee - executorReward;
        uint256 auxGov = FullMath.mulDiv(auxUAssetFee, leveragedDebt, normalFunds + leveragedDebt);
        uint256 expectedGov = mainGov + auxGov;
        uint256 expectedQuoted = expectedGov + mainMemecoinFee;
        assertEq(quoted, expectedQuoted, "quoted lz fee amount-sensitive");

        // Exact funding passes — reader and distributor agree on gov/memecoin amounts AND the LZ fee tracks
        // those amounts, so a magnitude drift in `_splitAuxiliaryGovFees` would make quoted diverge here.
        launcher.redeemAndDistributeFees{value: quoted}(verseId, REWARD_RECEIVER);
    }

    /// @notice Underpaying the amount-sensitive quoted fee reverts, confirming the sentinel is wired to the
    ///         real amountLD-dependent quote path (not a fixed-fee mock that masks drift).
    function testFeePreviewConsistency_UnderpayReverts_RemoteAmountSensitiveQuote() external {
        uint256 verseId = 111;
        uint256 quoted = _setupRemoteFeeVerseWithLeverage(verseId, 3 ether, 4 ether, 6 ether, 30 ether, 70 ether);

        vm.expectRevert(abi.encodeWithSelector(IMemeverseLauncher.InvalidLzFee.selector, quoted, quoted - 1));
        launcher.redeemAndDistributeFees{value: quoted - 1}(verseId, REWARD_RECEIVER);
    }

    /// @notice Sets up a remote (cross-chain) verse with identical preview and claim fee sources, funds the
    ///         launcher with the OFT tokens, and returns the quoted distribution LZ fee.
    /// @dev `setPreviewQuote` feeds the reader's `previewClaimableFees`; `setClaimQuote` feeds the
    ///      distributor's `claimFeesCore`. Setting both to the same amounts guarantees the two paths agree
    ///      on which OFT sends fire and thus on the required native fee — the precondition for the
    ///      quote-equals-required invariant under test. Uses a fixed mock LZ fee (`setQuoteFee`); the
    ///      amount-sensitive variant is `_setupRemoteFeeVerseWithLeverage`.
    function _setupRemoteFeeVerse(
        uint256 verseId,
        uint256 mainMemecoinFee,
        uint256 mainUAssetFee,
        uint256 auxUAssetFee,
        uint256 govQuoteFee,
        uint256 memecoinQuoteFee
    ) internal returns (uint256 quoted) {
        MockOFTToken remoteUAsset = new MockOFTToken("UASSET", "UASSET");
        MockOFTToken remoteMemecoin = new MockOFTToken("MEME", "MEME");
        IMemeverseLauncher.Memeverse memory verse;
        verse.uAsset = address(remoteUAsset);
        verse.memecoin = address(remoteMemecoin);
        verse.pol = address(liquidProof);
        verse.governor = address(0xCAFE);
        verse.yieldVault = address(0xD00D);
        verse.currentStage = IMemeverseLauncher.Stage.Locked;
        verse.omnichainIds = new uint32[](1);
        verse.omnichainIds[0] = 202;
        _writeMemeverse(verseId, verse);
        registry.setEndpoint(202, 302);

        // Reader (preview) and distributor (claim) read different mock setters; set BOTH to identical fee
        // amounts so preview accuracy and runtime settlement agree on which OFT sends fire.
        router.setPreviewQuote(
            address(remoteMemecoin), address(remoteUAsset), address(launcher), mainMemecoinFee, mainUAssetFee
        );
        router.setClaimQuote(
            address(remoteMemecoin), address(remoteUAsset), address(launcher), mainMemecoinFee, mainUAssetFee
        );
        router.setPreviewQuote(address(liquidProof), address(remoteUAsset), address(launcher), 0, auxUAssetFee);
        router.setClaimQuote(address(liquidProof), address(remoteUAsset), address(launcher), 0, auxUAssetFee);
        remoteUAsset.setQuoteFee(govQuoteFee);
        remoteMemecoin.setQuoteFee(memecoinQuoteFee);

        // The distributor's cross-chain send pulls OFT tokens from the launcher; fund it generously.
        remoteUAsset.mint(address(launcher), 100 ether);
        remoteMemecoin.mint(address(launcher), 100 ether);

        quoted = feePreviewReader.quoteDistributionLzFee(verseId);
    }

    /// @notice Amount-sensitive variant: enables `MockOFTToken.setQuoteAmountAsFee` so `quoteSend` returns
    ///         `nativeFee = sendParam.amountLD` (mirroring real LayerZero where the fee tracks the bridged
    ///         amount), and seeds non-zero normal funds + leveraged debt so `_splitAuxiliaryGovFees` executes
    ///         its `mulDiv` gov-share branch on both the reader and the distributor. This makes a magnitude
    ///         drift in the still-mirrored auxiliary-gov split observable: if either side computes a
    ///         different `govFee`, the quoted amount diverges from the required amount and exact funding
    ///         reverts.
    function _setupRemoteFeeVerseWithLeverage(
        uint256 verseId,
        uint256 mainMemecoinFee,
        uint256 mainUAssetFee,
        uint256 auxUAssetFee,
        uint256 normalFunds,
        uint256 leveragedDebt
    ) internal returns (uint256 quoted) {
        MockOFTToken remoteUAsset = new MockOFTToken("UASSET", "UASSET");
        MockOFTToken remoteMemecoin = new MockOFTToken("MEME", "MEME");
        IMemeverseLauncher.Memeverse memory verse;
        verse.uAsset = address(remoteUAsset);
        verse.memecoin = address(remoteMemecoin);
        verse.pol = address(liquidProof);
        verse.governor = address(0xCAFE);
        verse.yieldVault = address(0xD00D);
        verse.currentStage = IMemeverseLauncher.Stage.Locked;
        verse.omnichainIds = new uint32[](1);
        verse.omnichainIds[0] = 202;
        _writeMemeverse(verseId, verse);
        registry.setEndpoint(202, 302);

        // Non-zero genesis funds so `_splitAuxiliaryGovFees` reaches the `mulDiv` gov-share branch instead
        // of its `totalFunds == 0` early return. Both sides read the same fields.
        setGenesisFundForTest(launcherProxy, verseId, normalFunds);
        polend.setTotalLeveragedDebt(verseId, leveragedDebt);

        router.setPreviewQuote(
            address(remoteMemecoin), address(remoteUAsset), address(launcher), mainMemecoinFee, mainUAssetFee
        );
        router.setClaimQuote(
            address(remoteMemecoin), address(remoteUAsset), address(launcher), mainMemecoinFee, mainUAssetFee
        );
        router.setPreviewQuote(address(liquidProof), address(remoteUAsset), address(launcher), 0, auxUAssetFee);
        router.setClaimQuote(address(liquidProof), address(remoteUAsset), address(launcher), 0, auxUAssetFee);

        // Make the mock LZ fee track the bridged amount, so a magnitude drift in any fee split changes the
        // quoted fee — the sentinel property the fixed-fee variant lacks.
        remoteUAsset.setQuoteAmountAsFee(true);
        remoteMemecoin.setQuoteAmountAsFee(true);

        remoteUAsset.mint(address(launcher), 100 ether);
        remoteMemecoin.mint(address(launcher), 100 ether);

        quoted = feePreviewReader.quoteDistributionLzFee(verseId);
    }
}
