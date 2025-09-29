// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IVetoSlasher} from "../../../src/interfaces/slasher/IVetoSlasher.sol";
import {IVault} from "../../../src/interfaces/vault/IVault.sol";
import {Logs} from "../../utils/Logs.sol";
import {ScriptBase} from "../../utils/ScriptBase.s.sol";

contract ExecuteSlashBaseScript is ScriptBase {
    function run(address vault, uint256 slashIndex) public returns (bytes memory data, address target) {
        target = IVault(vault).slasher();
        data = abi.encodeCall(IVetoSlasher(IVault(vault).slasher()).executeSlash, (slashIndex, new bytes(0)));
        sendTransaction(target, data);

        Logs.log(
            string.concat(
                "Executed slash ", "\n    slashIndex:", vm.toString(slashIndex), "\n    vault:", vm.toString(vault)
            )
        );
        Logs.logSimulationLink(target, data);

        return (data, target);
    }
}
