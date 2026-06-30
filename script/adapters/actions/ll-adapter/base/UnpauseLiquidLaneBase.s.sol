// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ILiquidLaneAdapter} from "../../../../../src/interfaces/adapters/ILiquidLaneAdapter.sol";
import {Logs} from "../../../../utils/Logs.sol";
import {ScriptBase} from "../../../../utils/ScriptBase.s.sol";

contract UnpauseLiquidLaneBaseScript is ScriptBase {
    function runBase(address adapter) public virtual returns (bytes memory data, address target) {
        target = adapter;
        data = abi.encodeCall(ILiquidLaneAdapter.unpause, ());
        sendTransaction(target, data);

        Logs.log(string.concat("Unpause LiquidLane", "\n    adapter:", vm.toString(adapter)));
        Logs.logSimulationLink(target, data);
    }
}
