// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/ClaimWithdrawalBase.s.sol";

contract ClaimWithdrawalScript is ClaimWithdrawalBaseScript {
    address constant VAULT = 0x0000000000000000000000000000000000000000;
    uint256 constant TOKEN_ID = 0;
    address constant RECEIVER = 0x0000000000000000000000000000000000000000;

    function run() public {
        runBase(VAULT, TOKEN_ID, RECEIVER);
    }
}
