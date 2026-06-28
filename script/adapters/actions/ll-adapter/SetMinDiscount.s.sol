// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/SetMinDiscountBase.s.sol";

contract SetMinDiscountScript is SetMinDiscountBaseScript {
    address constant ADAPTER = 0x0000000000000000000000000000000000000000;
    address constant TOKEN_TO_REDEEM = 0x0000000000000000000000000000000000000000;
    uint256 constant MIN_DISCOUNT = 0;

    function run() public {
        runBase(ADAPTER, TOKEN_TO_REDEEM, MIN_DISCOUNT);
    }
}
