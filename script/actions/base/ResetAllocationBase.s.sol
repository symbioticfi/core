// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IVault} from "../../../src/interfaces/vault/IVault.sol";
import {IUniversalDelegator} from "../../../src/interfaces/delegator/IUniversalDelegator.sol";
import {Logs} from "../../utils/Logs.sol";
import {ScriptBase} from "../../utils/ScriptBase.s.sol";

contract ResetAllocationBaseScript is ScriptBase {
    function runBase(address vault, bytes32 subnetwork) public virtual returns (bytes memory data, address target) {
        target = IVault(vault).delegator();
        data = abi.encodeCall(IUniversalDelegator.resetAllocation, (subnetwork));
        sendTransaction(target, data);

        Logs.log(
            string.concat(
                "Reset allocation", "\n    vault:", vm.toString(vault), "\n    subnetwork:", vm.toString(subnetwork)
            )
        );
        Logs.logSimulationLink(target, data);

        return (data, target);
    }
}
