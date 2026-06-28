// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/RequestRedeemBase.s.sol";

contract RequestRedeemScript is RequestRedeemBaseScript {
    address constant VAULT = 0x0000000000000000000000000000000000000000;
    uint256 constant SHARES = 0;
    address constant RECEIVER = 0x0000000000000000000000000000000000000000;

    function run() public {
        runBase(VAULT, SHARES, RECEIVER);
    }
}
