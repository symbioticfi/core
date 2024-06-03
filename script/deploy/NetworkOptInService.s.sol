// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import "forge-std/Script.sol";

import {NetworkOptInService} from "src/contracts/NetworkOptInService.sol";

contract NetworkOptInServiceScript is Script {
    function run(address networkRegistry, address vaultFactory) public {
        vm.startBroadcast();

        new NetworkOptInService(networkRegistry, vaultFactory);

        vm.stopBroadcast();
    }
}
