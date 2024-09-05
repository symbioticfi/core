// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "forge-std/Script.sol";

import {VaultFactory} from "../../src/contracts/VaultFactory.sol";

contract VaultFactoryScript is Script {
    function run(
        address owner
    ) public {
        vm.startBroadcast();

        new VaultFactory(owner);

        vm.stopBroadcast();
    }
}
