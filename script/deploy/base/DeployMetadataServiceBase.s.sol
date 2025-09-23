// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {Logs} from "../../utils/Logs.sol";

import {MetadataService} from "../../../src/contracts/service/MetadataService.sol";

contract DeployMetadataServiceBaseScript is Script {
    function run(
        address registry
    ) public virtual {
        vm.startBroadcast();
        MetadataService metadataService = new MetadataService(registry);
        vm.stopBroadcast();

        Logs.log(string.concat("Deployed MetadataService: ", vm.toString(address(metadataService))));
    }
}
