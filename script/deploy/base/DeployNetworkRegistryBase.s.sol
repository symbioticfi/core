// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {Logs} from "../../utils/Logs.sol";

import {NetworkRegistry} from "../../../src/contracts/NetworkRegistry.sol";

contract DeployNetworkRegistryBaseScript is Script {
    function run() public virtual {
        vm.startBroadcast();
        NetworkRegistry networkRegistry = new NetworkRegistry();
        vm.stopBroadcast();

        Logs.log(string.concat("Deployed NetworkRegistry: ", vm.toString(address(networkRegistry))));
    }
}
