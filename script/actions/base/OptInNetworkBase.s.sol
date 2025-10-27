// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IOptInService} from "../../../src/interfaces/service/IOptInService.sol";
import {Logs} from "../../utils/Logs.sol";
import {ScriptBase} from "../../utils/ScriptBase.s.sol";
import {SymbioticCoreConstants} from "../../../test/integration/SymbioticCoreConstants.sol";

contract OptInNetworkBaseScript is ScriptBase {
    function runBase(address network) public virtual returns (bytes memory data, address target) {
        target = address(SymbioticCoreConstants.core().operatorNetworkOptInService);
        data = abi.encodeWithSignature("optIn(address)", network);
        sendTransaction(target, data);

        Logs.log(string.concat("Opt in network ", "\n    network:", vm.toString(network)));
        Logs.logSimulationLink(target, data);

        return (data, target);
    }
}
