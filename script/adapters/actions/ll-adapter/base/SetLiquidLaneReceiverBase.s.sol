// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ILiquidLaneAdapter} from "../../../../../src/interfaces/adapters/ILiquidLaneAdapter.sol";
import {Logs} from "../../../../utils/Logs.sol";
import {ScriptBase} from "../../../../utils/ScriptBase.s.sol";

contract SetLiquidLaneReceiverBaseScript is ScriptBase {
    function runBase(address adapter, address receiver) public virtual returns (bytes memory data, address target) {
        target = adapter;
        data = abi.encodeCall(ILiquidLaneAdapter.setReceiver, (receiver));
        sendTransaction(target, data);

        Logs.log(
            string.concat(
                "Set LiquidLane receiver",
                "\n    adapter:",
                vm.toString(adapter),
                "\n    receiver:",
                vm.toString(receiver)
            )
        );
        Logs.logSimulationLink(target, data);
    }
}
