// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import {NetworkOptInService} from "src/contracts/NetworkOptInService.sol";

contract NetworkOptInServiceScript is Script {
    function run(address networkRegistry, address vaultFactory) public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        new NetworkOptInService(networkRegistry, vaultFactory);

        vm.stopBroadcast();
    }
}
