// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/SetConvertersBase.s.sol";

contract SetConvertersScript is SetConvertersBaseScript {
    address constant ADAPTER = 0x0000000000000000000000000000000000000000;
    address constant CONVERTER = 0x0000000000000000000000000000000000000000;

    function run() public {
        address[] memory converters = new address[](1);
        converters[0] = CONVERTER;
        runBase(ADAPTER, converters);
    }
}
