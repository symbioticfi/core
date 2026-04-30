// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniversalDelegator} from "../../../src/interfaces/delegator/IUniversalDelegator.sol";
import {Logs} from "../../utils/Logs.sol";
import {ScriptBase} from "../../utils/ScriptBase.s.sol";

contract SwapSlotsBaseScript is ScriptBase {
    function runBase(address delegator, uint64 index1, uint64 index2)
        public
        virtual
        returns (bytes memory data, address target)
    {
        target = delegator;
        data = abi.encodeCall(IUniversalDelegator.swapSlots, (index1, index2));
        sendTransaction(target, data);

        Logs.log(
            string.concat(
                "Swap slots",
                "\n    delegator:",
                vm.toString(delegator),
                "\n    index1:",
                vm.toString(uint256(index1)),
                "\n    index2:",
                vm.toString(uint256(index2))
            )
        );
        Logs.logSimulationLink(target, data);
    }
}
