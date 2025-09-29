// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IOptInService} from "../../../src/interfaces/service/IOptInService.sol";
import {Logs} from "../../utils/Logs.sol";
import {ScriptBase} from "../../utils/ScriptBase.s.sol";

contract OptInNetworkBaseScript is ScriptBase {
    function run(
        address operatorNetworkOptInService,
        address network
    ) public returns (bytes memory data, address target) {
        target = operatorNetworkOptInService;
        data = abi.encodeWithSignature("optIn(address)", network);
        sendTransaction(target, data);

        Logs.log(string.concat("Opt in network ", "\n    network:", vm.toString(network)));
        Logs.logSimulationLink(target, data);

        return (data, target);
    }
}
