// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IUniversalDelegator} from "../../../src/interfaces/delegator/IUniversalDelegator.sol";
import {Logs} from "../../utils/Logs.sol";
import {ScriptBase} from "../../utils/ScriptBase.s.sol";

contract SetWithdrawalBufferSizeBaseScript is ScriptBase {
    function runBase(address delegator, uint128 size) public virtual returns (bytes memory data, address target) {
        target = delegator;
        data = abi.encodeCall(IUniversalDelegator.setWithdrawalBufferSize, (size));
        sendTransaction(target, data);

        Logs.log(
            string.concat(
                "Set withdrawal buffer size",
                "\n    delegator:",
                vm.toString(delegator),
                "\n    size:",
                vm.toString(uint256(size))
            )
        );
        Logs.logSimulationLink(target, data);
    }
}
