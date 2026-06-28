// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ILiquidLaneAdapter} from "../../../../../src/interfaces/adapters/ILiquidLaneAdapter.sol";
import {Logs} from "../../../../utils/Logs.sol";
import {ScriptBase} from "../../../../utils/ScriptBase.s.sol";

contract WithdrawToAcquireBaseScript is ScriptBase {
    function runBase(address adapter, address tokenToRedeem, uint256 amount)
        public
        virtual
        returns (bytes memory data, address target)
    {
        target = adapter;
        data = abi.encodeCall(ILiquidLaneAdapter.withdrawToAcquire, (tokenToRedeem, amount));
        sendTransaction(target, data);

        Logs.log(
            string.concat(
                "Withdraw to acquire",
                "\n    adapter:",
                vm.toString(adapter),
                "\n    tokenToRedeem:",
                vm.toString(tokenToRedeem),
                "\n    amount:",
                vm.toString(amount)
            )
        );
        Logs.logSimulationLink(target, data);
    }
}
