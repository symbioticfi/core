// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/RemoveTokenToRedeemBase.s.sol";

contract RemoveTokenToRedeemScript is RemoveTokenToRedeemBaseScript {
    address constant ADAPTER = 0x0000000000000000000000000000000000000000;
    address constant TOKEN_TO_REDEEM = 0x0000000000000000000000000000000000000000;

    function run() public {
        runBase(ADAPTER, TOKEN_TO_REDEEM);
    }
}
