// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IOperatorRegistry} from "../../../src/interfaces/IOperatorRegistry.sol";
import {Logs} from "../../utils/Logs.sol";
import {ScriptBase} from "../../utils/ScriptBase.s.sol";

contract RegisterOperatorBaseScript is ScriptBase {
    function run(
        address operatorRegistry
    ) public returns (bytes memory data, address target) {
        target = operatorRegistry;
        data = abi.encodeCall(IOperatorRegistry(operatorRegistry).registerOperator, ());
        sendTransaction(target, data);

        Logs.log(string.concat("Register operator"));
        Logs.logSimulationLink(target, data);

        return (data, target);
    }
}
