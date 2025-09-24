// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IVault} from "../../../src/interfaces/vault/IVault.sol";
import {IFullRestakeDelegator} from "../../../src/interfaces/delegator/IFullRestakeDelegator.sol";
import {Logs} from "../../utils/Logs.sol";
import {ScriptBase} from "../../utils/ScriptBase.s.sol";

contract SetOperatorNetworkLimitBaseScript is ScriptBase {
    function run(address vault, bytes32 subnetwork, address operator, uint256 amount, bool send) public returns (bytes memory data, address target) {
        target = IVault(vault).delegator();
        data = abi.encodeCall(IFullRestakeDelegator(IVault(vault).delegator()).setOperatorNetworkLimit, (subnetwork, operator, amount));
        if (send) {
            sendTransaction(target, data);
        }

        Logs.log(
            string.concat(
                "Set operator network limit ", "\n    vault:", vm.toString(vault), "\n    subnetwork:", vm.toString(subnetwork), "\n    operator:", vm.toString(operator), "\n    amount:", vm.toString(amount)
            )
        );
        Logs.logSimulationLink(target, data);

        return (data, target);
    }
}
