// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Logs} from "../../../utils/Logs.sol";
import {ScriptBase} from "../../../utils/ScriptBase.s.sol";
import {SymbioticCoreConstants} from "../../../../test/integration/SymbioticCoreConstants.sol";

interface IOptInVaultServiceSelf {
    function optIn(address where) external;
}

contract OptInVaultBaseScript is ScriptBase {
    function runBase(address vault) public virtual returns (bytes memory data, address target) {
        target = address(SymbioticCoreConstants.core().operatorVaultOptInService);
        data = abi.encodeCall(IOptInVaultServiceSelf.optIn, (vault));
        sendTransaction(target, data);

        Logs.log(string.concat("Opt in vault ", "\n    vault:", vm.toString(vault)));
        Logs.logSimulationLink(target, data);

        return (data, target);
    }
}
