// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniversalDelegator} from "../../../src/interfaces/delegator/IUniversalDelegator.sol";
import {Logs} from "../../utils/Logs.sol";
import {ScriptBase} from "../../utils/ScriptBase.s.sol";

contract SetSizeBaseScript is ScriptBase {
    function runBase(address delegator, uint64 index, uint128 size)
        public
        virtual
        returns (bytes memory data, address target)
    {
        target = delegator;
        data = abi.encodeCall(IUniversalDelegator.setSize, (index, size));
        sendTransaction(target, data);

        Logs.log(
            string.concat(
                "Set slot size",
                "\n    delegator:",
                vm.toString(delegator),
                "\n    index:",
                vm.toString(uint256(index)),
                "\n    size:",
                vm.toString(uint256(size))
            )
        );
        Logs.logSimulationLink(target, data);
    }
}
