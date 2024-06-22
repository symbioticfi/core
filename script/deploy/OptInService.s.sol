// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import "forge-std/Script.sol";

import {OptInService} from "src/contracts/OptInService.sol";

contract OperatorOptInServiceScript is Script {
    function run(address operatorRegistry, address whereRegistry) public {
        vm.startBroadcast();

        new OptInService(operatorRegistry, whereRegistry);

        vm.stopBroadcast();
    }
}
