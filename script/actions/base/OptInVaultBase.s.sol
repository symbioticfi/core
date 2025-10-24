// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IOptInService} from "../../../src/interfaces/service/IOptInService.sol";
import {Logs} from "../../utils/Logs.sol";
import {ScriptBase} from "../../utils/ScriptBase.s.sol";

contract OptInVaultBaseScript is ScriptBase {
    function run(address operatorVaultOptInService, address vault) public returns (bytes memory data, address target) {
        target = operatorVaultOptInService;
        data = abi.encodeWithSignature("optIn(address)", vault);
        sendTransaction(target, data);

        Logs.log(string.concat("Opt in vault ", "\n    vault:", vm.toString(vault)));
        Logs.logSimulationLink(target, data);

        return (data, target);
    }
}
