// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IVault} from "../../../src/interfaces/vault/IVault.sol";
import {INetworkRestakeDelegator} from "../../../src/interfaces/delegator/INetworkRestakeDelegator.sol";
import {Logs} from "../../utils/Logs.sol";
import {ScriptBase} from "../../utils/ScriptBase.s.sol";

contract SetOperatorNetworkSharesBaseScript is ScriptBase {
    function run(address vault, bytes32 subnetwork, address operator, uint256 operatorNetworkShares, bool send) public returns (bytes memory data, address target) {
        target = IVault(vault).delegator();
        data = abi.encodeCall(INetworkRestakeDelegator(IVault(vault).delegator()).setOperatorNetworkShares, (subnetwork, operator, operatorNetworkShares));
        if (send) {
            sendTransaction(target, data);
        }

        Logs.log(
            string.concat(
                "Set operator network shares ", "\n    vault:", vm.toString(vault), "\n    subnetwork:", vm.toString(subnetwork), "\n    operator:", vm.toString(operator), "\n    operatorNetworkShares:", vm.toString(operatorNetworkShares)
            )
        );
        Logs.logSimulationLink(target, data);

        return (data, target);
    }
}
