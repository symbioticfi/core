// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/OptInNetworkBase.s.sol";

import {console2} from "forge-std/Test.sol";

// forge script script/update/OptInNetwork.s.sol:OptInNetworkScript --rpc-url=RPC --private-key PRIVATE_KEY --broadcast

contract OptInNetworkScript is OptInNetworkBaseScript {
    address public OPERATOR_NETWORK_OPT_IN_SERVICE = address(0);
    address public NETWORK = address(0);

    function run() public {
        run(OPERATOR_NETWORK_OPT_IN_SERVICE, NETWORK, true);
    }
}
