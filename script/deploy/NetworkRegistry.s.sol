// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import {NetworkRegistry} from "src/contracts/NetworkRegistry.sol";

contract NetworkRegistryScript is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        new NetworkRegistry();

        vm.stopBroadcast();
    }
}
