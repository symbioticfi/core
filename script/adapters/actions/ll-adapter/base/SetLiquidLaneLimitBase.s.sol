// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ILiquidLaneAdapter} from "../../../../../src/interfaces/adapters/ILiquidLaneAdapter.sol";
import {Logs} from "../../../../utils/Logs.sol";
import {ScriptBase} from "../../../../utils/ScriptBase.s.sol";

contract SetLiquidLaneLimitBaseScript is ScriptBase {
    function runBase(address adapter, address tokenToRedeem, uint256 limit)
        public
        virtual
        returns (bytes memory data, address target)
    {
        target = adapter;
        data = abi.encodeCall(ILiquidLaneAdapter.setLimit, (tokenToRedeem, limit));
        sendTransaction(target, data);

        Logs.log(
            string.concat(
                "Set LiquidLane limit",
                "\n    adapter:",
                vm.toString(adapter),
                "\n    tokenToRedeem:",
                vm.toString(tokenToRedeem),
                "\n    limit:",
                vm.toString(limit)
            )
        );
        Logs.logSimulationLink(target, data);
    }
}
