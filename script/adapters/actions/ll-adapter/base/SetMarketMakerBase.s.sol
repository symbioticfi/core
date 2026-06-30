// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ILiquidLaneAdapter} from "../../../../../src/interfaces/adapters/ILiquidLaneAdapter.sol";
import {Logs} from "../../../../utils/Logs.sol";
import {ScriptBase} from "../../../../utils/ScriptBase.s.sol";

contract SetMarketMakerBaseScript is ScriptBase {
    function runBase(address adapter, address marketMaker, bool canAcquire)
        public
        virtual
        returns (bytes memory data, address target)
    {
        target = adapter;
        data = abi.encodeCall(ILiquidLaneAdapter.setMarketMaker, (marketMaker, canAcquire));
        sendTransaction(target, data);

        Logs.log(
            string.concat(
                "Set LiquidLane market maker",
                "\n    adapter:",
                vm.toString(adapter),
                "\n    marketMaker:",
                vm.toString(marketMaker),
                "\n    canAcquire:",
                vm.toString(canAcquire)
            )
        );
        Logs.logSimulationLink(target, data);
    }
}
