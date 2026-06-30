// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ILiquidLaneAdapter} from "../../../../../src/interfaces/adapters/ILiquidLaneAdapter.sol";
import {Logs} from "../../../../utils/Logs.sol";
import {ScriptBase} from "../../../../utils/ScriptBase.s.sol";

contract RemoveTokenToRedeemBaseScript is ScriptBase {
    function runBase(address adapter, address tokenToRedeem)
        public
        virtual
        returns (bytes memory data, address target)
    {
        target = adapter;
        data = abi.encodeCall(ILiquidLaneAdapter.removeTokenToRedeem, (tokenToRedeem));
        sendTransaction(target, data);

        Logs.log(
            string.concat(
                "Remove token to redeem",
                "\n    adapter:",
                vm.toString(adapter),
                "\n    tokenToRedeem:",
                vm.toString(tokenToRedeem)
            )
        );
        Logs.logSimulationLink(target, data);
    }
}
