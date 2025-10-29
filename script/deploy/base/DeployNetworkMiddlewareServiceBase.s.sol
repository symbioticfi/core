// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {Logs} from "../../utils/Logs.sol";

import {NetworkMiddlewareService} from "../../../src/contracts/service/NetworkMiddlewareService.sol";

contract DeployNetworkMiddlewareServiceBaseScript is Script {
    function run(address networkRegistry) public virtual {
        vm.startBroadcast();
        NetworkMiddlewareService networkMiddlewareService = new NetworkMiddlewareService(networkRegistry);
        vm.stopBroadcast();

        Logs.log(string.concat("Deployed NetworkMiddlewareService: ", vm.toString(address(networkMiddlewareService))));
    }
}
