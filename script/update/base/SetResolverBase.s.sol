// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IVault} from "../../../src/interfaces/vault/IVault.sol";
import {IVetoSlasher} from "../../../src/interfaces/slasher/IVetoSlasher.sol";
import {Logs} from "../../utils/Logs.sol";
import {ScriptBase} from "../../utils/ScriptBase.s.sol";

contract SetResolverBaseScript is ScriptBase {
    function run(address vault, uint96 identifier, address resolver, bool send) public returns (bytes memory data, address target) {
        target = IVault(vault).slasher();
        data = abi.encodeCall(IVetoSlasher(IVault(vault).slasher()).setResolver, (identifier, resolver, new bytes(0)));
        if (send) {
            sendTransaction(target, data);
        }

        Logs.log(
            string.concat(
                "Set resolver ", "\n    vault:", vm.toString(vault), "\n    identifier:", vm.toString(identifier), "\n    resolver:", vm.toString(resolver)
            )
        );
        Logs.logSimulationLink(target, data);

        return (data, target);
    }
}
