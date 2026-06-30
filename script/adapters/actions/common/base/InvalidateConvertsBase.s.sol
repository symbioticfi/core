// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ICoWSwapConverter} from "../../../../../src/interfaces/adapters/common/ICoWSwapConverter.sol";
import {Logs} from "../../../../utils/Logs.sol";
import {ScriptBase} from "../../../../utils/ScriptBase.s.sol";

contract InvalidateConvertsBaseScript is ScriptBase {
    function runBase(address adapter, address tokenIn) public virtual returns (bytes memory data, address target) {
        target = adapter;
        data = abi.encodeCall(ICoWSwapConverter.invalidateConverts, (tokenIn));
        sendTransaction(target, data);

        Logs.log(
            string.concat(
                "Invalidate adapter converts",
                "\n    adapter:",
                vm.toString(adapter),
                "\n    tokenIn:",
                vm.toString(tokenIn)
            )
        );
        Logs.logSimulationLink(target, data);
    }
}
