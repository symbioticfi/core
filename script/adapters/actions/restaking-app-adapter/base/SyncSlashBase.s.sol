// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IRestakingAppAdapter} from "../../../../../src/interfaces/adapters/IRestakingAppAdapter.sol";
import {Logs} from "../../../../utils/Logs.sol";
import {ScriptBase} from "../../../../utils/ScriptBase.s.sol";

contract SyncSlashBaseScript is ScriptBase {
    function runBase(address adapter) public virtual returns (bytes memory data, address target) {
        target = adapter;
        data = abi.encodeCall(IRestakingAppAdapter.syncSlash, ());
        sendTransaction(target, data);

        Logs.log(string.concat("Sync restaking slash", "\n    adapter:", vm.toString(adapter)));
        Logs.logSimulationLink(target, data);
    }
}
