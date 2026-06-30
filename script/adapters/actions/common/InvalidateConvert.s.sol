// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/InvalidateConvertBase.s.sol";

contract InvalidateConvertScript is InvalidateConvertBaseScript {
    address constant ADAPTER = 0x0000000000000000000000000000000000000000;

    function run() public {
        runBase(ADAPTER, hex"");
    }
}
