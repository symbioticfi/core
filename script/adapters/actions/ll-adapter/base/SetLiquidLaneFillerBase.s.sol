// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ILiquidLaneAdapter} from "../../../../../src/interfaces/adapters/ILiquidLaneAdapter.sol";
import {Logs} from "../../../../utils/Logs.sol";
import {ScriptBase} from "../../../../utils/ScriptBase.s.sol";

contract SetLiquidLaneFillerBaseScript is ScriptBase {
    function runBase(address adapter, address filler, bool isAuthorized)
        public
        virtual
        returns (bytes memory data, address target)
    {
        target = adapter;
        data = abi.encodeCall(ILiquidLaneAdapter.setFiller, (filler, isAuthorized));
        sendTransaction(target, data);

        Logs.log(
            string.concat(
                "Set LiquidLane filler",
                "\n    adapter:",
                vm.toString(adapter),
                "\n    filler:",
                vm.toString(filler),
                "\n    isAuthorized:",
                vm.toString(isAuthorized)
            )
        );
        Logs.logSimulationLink(target, data);
    }
}
