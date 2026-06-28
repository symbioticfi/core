// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/SetMarketMakerBase.s.sol";

contract SetMarketMakerScript is SetMarketMakerBaseScript {
    address constant ADAPTER = 0x0000000000000000000000000000000000000000;
    address constant MARKET_MAKER = 0x0000000000000000000000000000000000000000;
    bool constant CAN_ACQUIRE = false;

    function run() public {
        runBase(ADAPTER, MARKET_MAKER, CAN_ACQUIRE);
    }
}
