// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniversalDelegator} from "../../../src/interfaces/delegator/IUniversalDelegator.sol";
import {Logs} from "../../utils/Logs.sol";
import {ScriptBase} from "../../utils/ScriptBase.s.sol";

contract CreateSlotBaseScript is ScriptBase {
    function runBase(address delegator, bytes32 subnetwork, address operator, uint128 size)
        public
        virtual
        returns (bytes memory data, address target)
    {
        target = delegator;
        data = abi.encodeCall(IUniversalDelegator.createSlot, (subnetwork, operator, size));
        sendTransaction(target, data);

        Logs.log(
            string.concat(
                "Create slot",
                "\n    delegator:",
                vm.toString(delegator),
                "\n    operator:",
                vm.toString(operator),
                "\n    size:",
                vm.toString(uint256(size))
            )
        );
        Logs.logSimulationLink(target, data);
    }
}
