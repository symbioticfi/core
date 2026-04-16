// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/SetMiddlewareBase.s.sol";

contract SetMiddlewareScript is SetMiddlewareBaseScript {
    address constant SERVICE = address(0);
    address constant MIDDLEWARE = address(0);

    function run() public {
        runBase(SERVICE, MIDDLEWARE);
    }
}
