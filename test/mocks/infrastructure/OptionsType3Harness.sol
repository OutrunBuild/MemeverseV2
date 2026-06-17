// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.35;

import {OutrunOAppOptionsType3Init} from "../../../src/common/omnichain/oapp/OutrunOAppOptionsType3Init.sol";

contract OptionsType3Harness is OutrunOAppOptionsType3Init {
    /// @notice Initialize.
    /// @param owner_ See implementation.
    function initialize(address owner_) external initializer {
        __OutrunOwnable_init(owner_);
        __OutrunOAppOptionsType3_init();
    }
}
