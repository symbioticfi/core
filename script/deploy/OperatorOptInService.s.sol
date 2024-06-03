// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import "forge-std/Script.sol";

import {OperatorOptInService} from "src/contracts/OperatorOptInService.sol";

contract OperatorOptInServiceScript is Script {
    function run(address operatorRegistry, address whereRegistry) public {
        vm.startBroadcast();

        new OperatorOptInService(operatorRegistry, whereRegistry);

        vm.stopBroadcast();
    }
}
