// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "forge-std/Script.sol";

import {NetworkRegistry} from "../../src/contracts/NetworkRegistry.sol";

contract NetworkRegistryScript is Script {
    function run() public {
        vm.startBroadcast();

        new NetworkRegistry();

        vm.stopBroadcast();
    }
}
