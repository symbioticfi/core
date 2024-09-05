// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "forge-std/Script.sol";

import {MetadataService} from "../../src/contracts/service/MetadataService.sol";

contract MetadataServiceScript is Script {
    function run(
        address registry
    ) public {
        vm.startBroadcast();

        new MetadataService(registry);

        vm.stopBroadcast();
    }
}
