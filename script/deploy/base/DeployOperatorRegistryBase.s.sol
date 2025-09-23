// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {Logs} from "../../utils/Logs.sol";

import {OperatorRegistry} from "../../../src/contracts/OperatorRegistry.sol";

contract DeployOperatorRegistryBaseScript is Script {
    function run() public virtual {
        vm.startBroadcast();
        OperatorRegistry operatorRegistry = new OperatorRegistry();
        vm.stopBroadcast();

        Logs.log(string.concat("Deployed OperatorRegistry: ", vm.toString(address(operatorRegistry))));
    }
}
