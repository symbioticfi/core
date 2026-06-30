// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ILiquidLaneAdapter} from "../../../../../src/interfaces/adapters/ILiquidLaneAdapter.sol";
import {Logs} from "../../../../utils/Logs.sol";
import {ScriptBase} from "../../../../utils/ScriptBase.s.sol";

contract SetPauserBaseScript is ScriptBase {
    function runBase(address adapter, address pauser) public virtual returns (bytes memory data, address target) {
        target = adapter;
        data = abi.encodeCall(ILiquidLaneAdapter.setPauser, (pauser));
        sendTransaction(target, data);

        Logs.log(
            string.concat(
                "Set LiquidLane pauser", "\n    adapter:", vm.toString(adapter), "\n    pauser:", vm.toString(pauser)
            )
        );
        Logs.logSimulationLink(target, data);
    }
}
