// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ILiquidLaneAdapter} from "../../../../../src/interfaces/adapters/ILiquidLaneAdapter.sol";
import {Logs} from "../../../../utils/Logs.sol";
import {ScriptBase} from "../../../../utils/ScriptBase.s.sol";

contract SetMinDiscountBaseScript is ScriptBase {
    function runBase(address adapter, address tokenToRedeem, uint256 minDiscount)
        public
        virtual
        returns (bytes memory data, address target)
    {
        target = adapter;
        data = abi.encodeCall(ILiquidLaneAdapter.setMinDiscount, (tokenToRedeem, minDiscount));
        sendTransaction(target, data);

        Logs.log(
            string.concat(
                "Set LiquidLane min discount",
                "\n    adapter:",
                vm.toString(adapter),
                "\n    tokenToRedeem:",
                vm.toString(tokenToRedeem),
                "\n    minDiscount:",
                vm.toString(minDiscount)
            )
        );
        Logs.logSimulationLink(target, data);
    }
}
