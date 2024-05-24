// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import {MiddlewareService} from "src/contracts/MiddlewareService.sol";

contract MiddlewareServiceScript is Script {
    function run(address registry) public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        new MiddlewareService(registry);

        vm.stopBroadcast();
    }
}
