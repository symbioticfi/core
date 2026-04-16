// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IVault} from "../../../src/interfaces/vault/IVault.sol";
import {IUniversalSlasher} from "../../../src/interfaces/slasher/IUniversalSlasher.sol";
import {Logs} from "../../utils/Logs.sol";
import {ScriptBase} from "../../utils/ScriptBase.s.sol";

contract SyncOwedSlashBaseScript is ScriptBase {
    function runBase(address vault, bytes32 subnetwork, address operator)
        public
        virtual
        returns (bytes memory data, address target)
    {
        target = IVault(vault).slasher();
        data = abi.encodeCall(IUniversalSlasher.syncOwedSlash, (subnetwork, operator));
        sendTransaction(target, data);

        Logs.log(
            string.concat(
                "Sync owed slash",
                "\n    vault:",
                vm.toString(vault),
                "\n    subnetwork:",
                vm.toString(subnetwork),
                "\n    operator:",
                vm.toString(operator)
            )
        );
        Logs.logSimulationLink(target, data);

        return (data, target);
    }
}
