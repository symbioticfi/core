// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IVaultV2} from "../../../../src/interfaces/vault/IVaultV2.sol";
import {IUniversalDelegator} from "../../../../src/interfaces/delegator/IUniversalDelegator.sol";
import {Logs} from "../../../utils/Logs.sol";
import {ScriptBase} from "../../../utils/ScriptBase.s.sol";

contract SweepPendingBaseScript is ScriptBase {
    function runBase(address vault) public virtual returns (bytes memory data, address target) {
        target = IVaultV2(vault).delegator();
        data = abi.encodeCall(IUniversalDelegator.sweepPending, ());
        sendTransaction(target, data);

        Logs.log(string.concat("Sweep pending", "\n    vault:", vm.toString(vault)));
        Logs.logSimulationLink(target, data);
    }
}
