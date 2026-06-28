// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/SetAdapterLimitsBase.s.sol";

contract SetAdapterLimitsScript is SetAdapterLimitsBaseScript {
    address constant VAULT = 0x0000000000000000000000000000000000000000;
    address constant ADAPTER = 0x0000000000000000000000000000000000000000;
    uint256 constant ABSOLUTE_LIMIT = 0;
    uint256 constant SHARE_LIMIT = 0;

    function run() public {
        runBase(VAULT, ADAPTER, ABSOLUTE_LIMIT, SHARE_LIMIT);
    }
}
