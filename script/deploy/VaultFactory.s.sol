// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import {VaultFactory} from "src/contracts/VaultFactory.sol";

contract VaultFactoryScript is Script {
    function run(address owner) public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        new VaultFactory(owner);

        vm.stopBroadcast();
    }
}
