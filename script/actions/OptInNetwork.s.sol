// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/OptInNetworkBase.s.sol";

import {console2} from "forge-std/Test.sol";

// forge script script/actions/OptInNetwork.s.sol:OptInNetworkScript --rpc-url=RPC --private-key PRIVATE_KEY --broadcast

contract OptInNetworkScript is OptInNetworkBaseScript {
    // Configuration constants - UPDATE THESE BEFORE EXECUTING

    // Address of the OperatorNetworkOptInService contract
    address constant OPERATOR_NETWORK_OPT_IN_SERVICE = address(0);
    // Address of the network being opted into
    address constant NETWORK = address(0);

    function run() public {
        run(OPERATOR_NETWORK_OPT_IN_SERVICE, NETWORK);
    }
}
