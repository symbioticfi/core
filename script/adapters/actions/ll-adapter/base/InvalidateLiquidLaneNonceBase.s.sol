// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ILiquidLaneAdapter} from "../../../../../src/interfaces/adapters/ILiquidLaneAdapter.sol";
import {Logs} from "../../../../utils/Logs.sol";
import {ScriptBase} from "../../../../utils/ScriptBase.s.sol";

contract InvalidateLiquidLaneNonceBaseScript is ScriptBase {
    function runBase(address adapter, address tokenToRedeem, uint256 nonce)
        public
        virtual
        returns (bytes memory data, address target)
    {
        target = adapter;
        data = abi.encodeCall(ILiquidLaneAdapter.invalidateNonce, (tokenToRedeem, nonce));
        sendTransaction(target, data);

        Logs.log(
            string.concat(
                "Invalidate LiquidLane nonce",
                "\n    adapter:",
                vm.toString(adapter),
                "\n    tokenToRedeem:",
                vm.toString(tokenToRedeem),
                "\n    nonce:",
                vm.toString(nonce)
            )
        );
        Logs.logSimulationLink(target, data);
    }
}
