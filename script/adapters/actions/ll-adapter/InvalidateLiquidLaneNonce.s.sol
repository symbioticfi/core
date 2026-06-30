// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/InvalidateLiquidLaneNonceBase.s.sol";

contract InvalidateLiquidLaneNonceScript is InvalidateLiquidLaneNonceBaseScript {
    address constant ADAPTER = 0x0000000000000000000000000000000000000000;
    address constant TOKEN_TO_REDEEM = 0x0000000000000000000000000000000000000000;
    uint256 constant NONCE = 0;

    function run() public {
        runBase(ADAPTER, TOKEN_TO_REDEEM, NONCE);
    }
}
