// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IVault} from "../../../src/interfaces/vault/IVault.sol";
import {IVetoSlasher} from "../../../src/interfaces/slasher/IVetoSlasher.sol";
import {Logs} from "../../utils/Logs.sol";
import {ScriptBase} from "../../utils/ScriptBase.s.sol";

contract VetoSlashBaseScript is ScriptBase {
    function runBase(address vault, uint256 slashIndex) public virtual returns (bytes memory data, address target) {
        target = IVault(vault).slasher();
        data = abi.encodeCall(IVetoSlasher.vetoSlash, (slashIndex, new bytes(0)));
        sendTransaction(target, data);

        Logs.log(
            string.concat(
                "Veto slash ", "\n    vault:", vm.toString(vault), "\n    slashIndex:", vm.toString(slashIndex)
            )
        );
        Logs.logSimulationLink(target, data);

        return (data, target);
    }
}
