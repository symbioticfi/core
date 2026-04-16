// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/RecoverAdapterFundsBase.s.sol";

contract RecoverAdapterFundsScript is RecoverAdapterFundsBaseScript {
    address constant ADAPTER = address(0);
    address constant VAULT = address(0);
    uint256 constant AMOUNT = 0;

    function run() public {
        runBase(ADAPTER, VAULT, AMOUNT);
    }
}
