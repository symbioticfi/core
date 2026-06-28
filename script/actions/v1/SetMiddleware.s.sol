// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/SetMiddlewareBase.s.sol";

contract SetMiddlewareScript is SetMiddlewareBaseScript {
    address constant SERVICE = 0x0000000000000000000000000000000000000000;
    address constant MIDDLEWARE = 0x0000000000000000000000000000000000000000;

    function run() public {
        runBase(SERVICE, MIDDLEWARE);
    }
}
