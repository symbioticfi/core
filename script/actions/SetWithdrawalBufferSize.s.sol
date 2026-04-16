// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/SetWithdrawalBufferSizeBase.s.sol";

contract SetWithdrawalBufferSizeScript is SetWithdrawalBufferSizeBaseScript {
    address constant DELEGATOR = address(0);
    uint128 constant SIZE = 0;

    function run() public {
        runBase(DELEGATOR, SIZE);
    }
}
