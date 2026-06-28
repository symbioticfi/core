// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/RedeemThreeFRequestsBase.s.sol";

contract RedeemThreeFRequestsScript is RedeemThreeFRequestsBaseScript {
    address constant ADAPTER = 0x0000000000000000000000000000000000000000;
    address constant REQUEST = 0x0000000000000000000000000000000000000000;

    function run() public {
        address[] memory requests = new address[](1);
        requests[0] = REQUEST;
        runBase(ADAPTER, requests);
    }
}
