// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import {OperatorRegistry} from "src/contracts/OperatorRegistry.sol";

contract OperatorRegistryScript is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        new OperatorRegistry();

        vm.stopBroadcast();
    }
}
