// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IVault} from "../../../src/interfaces/vault/IVault.sol";
import {IBaseDelegator} from "../../../src/interfaces/delegator/IBaseDelegator.sol";
import {Logs} from "../../utils/Logs.sol";
import {ScriptBase} from "../../utils/ScriptBase.s.sol";

contract SetHookBaseScript is ScriptBase {
    function runBase(address vault, address hook) public virtual returns (bytes memory data, address target) {
        target = IVault(vault).delegator();
        data = abi.encodeCall(IBaseDelegator.setHook, (hook));
        sendTransaction(target, data);

        Logs.log(string.concat("Set hook ", "\n    vault:", vm.toString(vault), "\n    hook:", vm.toString(hook)));
        Logs.logSimulationLink(target, data);

        return (data, target);
    }
}
