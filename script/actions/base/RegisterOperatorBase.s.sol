// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IOperatorRegistry} from "../../../src/interfaces/IOperatorRegistry.sol";
import {Logs} from "../../utils/Logs.sol";
import {ScriptBase} from "../../utils/ScriptBase.s.sol";
import {SymbioticCoreConstants} from "../../../test/integration/SymbioticCoreConstants.sol";

contract RegisterOperatorBaseScript is ScriptBase {
    function runBase() public virtual returns (bytes memory data, address target) {
        target = address(SymbioticCoreConstants.core().operatorRegistry);
        data = abi.encodeCall(IOperatorRegistry.registerOperator, ());
        sendTransaction(target, data);

        Logs.log(string.concat("Register operator"));
        Logs.logSimulationLink(target, data);

        return (data, target);
    }
}
