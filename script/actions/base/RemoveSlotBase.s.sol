// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniversalDelegator} from "../../../src/interfaces/delegator/IUniversalDelegator.sol";
import {Logs} from "../../utils/Logs.sol";
import {ScriptBase} from "../../utils/ScriptBase.s.sol";

contract RemoveSlotBaseScript is ScriptBase {
    function runBase(address delegator, uint96 index) public virtual returns (bytes memory data, address target) {
        target = delegator;
        data = abi.encodeCall(IUniversalDelegator.removeSlot, (index));
        sendTransaction(target, data);

        Logs.log(
            string.concat(
                "Remove slot", "\n    delegator:", vm.toString(delegator), "\n    index:", vm.toString(uint256(index))
            )
        );
        Logs.logSimulationLink(target, data);
    }
}
