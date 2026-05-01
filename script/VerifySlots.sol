// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import {console2} from "forge-std/console2.sol";

contract VerifySlots {
    function run() external pure {
        bytes32 s1 =
            keccak256(abi.encode(uint256(keccak256("outrun.storage.GovernanceCycleIncentivizer")) - 1)) & ~bytes32(uint256(0xff));
        bytes32 s2 =
            keccak256(abi.encode(uint256(keccak256("outrun.storage.POLSplitter")) - 1)) & ~bytes32(uint256(0xff));
        bytes32 s3 =
            keccak256(abi.encode(uint256(keccak256("outrun.storage.POLend")) - 1)) & ~bytes32(uint256(0xff));
        console2.log("GovernanceCycleIncentivizer:");
        console2.logBytes32(s1);
        console2.log("POLSplitter:");
        console2.logBytes32(s2);
        console2.log("POLend:");
        console2.logBytes32(s3);
    }
}
