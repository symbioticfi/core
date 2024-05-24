// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import {MetadataService} from "src/contracts/MetadataService.sol";

contract MetadataServiceScript is Script {
    function run(address registry) public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        new MetadataService(registry);

        vm.stopBroadcast();
    }
}
