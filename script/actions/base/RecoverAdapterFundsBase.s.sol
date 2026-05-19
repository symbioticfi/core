// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAdapter} from "../../../src/interfaces/adapters/IAdapter.sol";
import {Logs} from "../../utils/Logs.sol";
import {ScriptBase} from "../../utils/ScriptBase.s.sol";

contract RecoverAdapterFundsBaseScript is ScriptBase {
    function runBase(address adapter, uint256 amount) public virtual returns (bytes memory data, address target) {
        target = adapter;
        data = abi.encodeCall(IAdapter.recover, (amount));
        sendTransaction(target, data);

        Logs.log(
            string.concat(
                "Recover adapter funds", "\n    adapter:", vm.toString(adapter), "\n    amount:", vm.toString(amount)
            )
        );
        Logs.logSimulationLink(target, data);
    }
}
