// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "forge-std/Script.sol";

import {OptInService} from "../../src/contracts/service/OptInService.sol";

contract OptInServiceScript is Script {
    function run(address whoRegistry, address whereRegistry, string calldata name) public {
        vm.startBroadcast();

        new OptInService(whoRegistry, whereRegistry, name);

        vm.stopBroadcast();
    }
}
