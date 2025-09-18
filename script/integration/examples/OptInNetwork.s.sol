// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../SymbioticCoreInit.sol";

import {console2} from "forge-std/Test.sol";

// forge script script/integration/examples/OptInNetwork.s.sol:OptInNetworkScript --rpc-url=RPC --private-key PRIVATE_KEY --broadcast

contract OptInNetworkScript is SymbioticCoreInit {
    address public NETWORK = address(0);

    function run() public {
        (,, address txOrigin) = vm.readCallers();
        address OPERATOR = txOrigin;

        _optInNetwork_SymbioticCore(symbioticCore, OPERATOR, NETWORK);
    }
}
