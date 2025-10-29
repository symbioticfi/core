// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {Logs} from "../../utils/Logs.sol";

import {OptInService} from "../../../src/contracts/service/OptInService.sol";

contract DeployOptInServiceBaseScript is Script {
    function run(address whoRegistry, address whereRegistry, string memory name) public virtual {
        vm.startBroadcast();
        OptInService optInService = new OptInService(whoRegistry, whereRegistry, name);
        vm.stopBroadcast();

        Logs.log(string.concat("Deployed OptInService: ", vm.toString(address(optInService))));
    }
}
