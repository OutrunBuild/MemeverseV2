// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.30;

import {IMemeverseLauncher} from "../../src/verse/interfaces/IMemeverseLauncher.sol";
import {MockPOLendForTask5} from "../mocks/verse/LauncherPOLendIntegrationMocks.sol";
import {MemeverseLauncherPOLendIntegrationTest} from "./MemeverseLauncherPOLendIntegration.t.sol";

contract MemeverseLauncherGenesisThresholdRegressionTest is MemeverseLauncherPOLendIntegrationTest {
    function testChangeStage_RefundsWhenOnlyCombinedDebtAndNormalFundsMeetThreshold() external {
        _setGenesisVerse(uint128(block.timestamp + 1 days), false);
        setGenesisFundForTest(launcherProxy, VERSE_ID, 6 ether);
        polend.setTotalLeveragedInterest(VERSE_ID, 4 ether);
        polend.setTotalLeveragedDebt(VERSE_ID, 40 ether);

        vm.warp(block.timestamp + 1 days + 1);

        assertEq(
            uint256(launcher.changeStage(VERSE_ID)),
            uint256(IMemeverseLauncher.Stage.Refund),
            "combined deployable funds do not satisfy launch gate"
        );
        assertEq(
            uint256(launcher.getStageByVerseId(VERSE_ID)), uint256(IMemeverseLauncher.Stage.Refund), "stored stage"
        );
        assertEq(MockPOLendForTask5(address(polend)).lastRefundedVerse(), VERSE_ID, "mark refundable");
    }
}
