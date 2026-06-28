// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IConverter} from "../../../../../src/interfaces/adapters/common/IConverter.sol";
import {Logs} from "../../../../utils/Logs.sol";
import {ScriptBase} from "../../../../utils/ScriptBase.s.sol";

contract ConvertBaseScript is ScriptBase {
    function runBase(address adapter, address tokenIn, uint256 amountIn, address tokenOut, bytes memory routeData)
        public
        virtual
        returns (bytes memory data, address target)
    {
        target = adapter;
        data = abi.encodeCall(IConverter.convert, (tokenIn, amountIn, tokenOut, routeData));
        sendTransaction(target, data);

        Logs.log(
            string.concat(
                "Convert adapter token",
                "\n    adapter:",
                vm.toString(adapter),
                "\n    tokenIn:",
                vm.toString(tokenIn),
                "\n    amountIn:",
                vm.toString(amountIn),
                "\n    tokenOut:",
                vm.toString(tokenOut)
            )
        );
        Logs.logSimulationLink(target, data);
    }
}
