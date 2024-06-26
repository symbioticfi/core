// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import "forge-std/Script.sol";

import {NetworkMiddlewareService} from "src/contracts/service/NetworkMiddlewareService.sol";

contract NetworkMiddlewareServiceScript is Script {
    function run(address networkRegistry) public {
        vm.startBroadcast();

        new NetworkMiddlewareService(networkRegistry);

        vm.stopBroadcast();
    }
}
