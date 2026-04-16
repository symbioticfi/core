// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IVaultV2} from "../../../src/interfaces/vault/IVaultV2.sol";
import {Logs} from "../../utils/Logs.sol";
import {ScriptBase} from "../../utils/ScriptBase.s.sol";

contract SkimAdaptersBaseScript is ScriptBase {
    function runBase(address vault) public virtual returns (bytes memory data, address target) {
        target = vault;
        data = abi.encodeCall(IVaultV2.skimAdapters, ());
        sendTransaction(target, data);

        Logs.log(string.concat("Skim adapters", "\n    vault:", vm.toString(vault)));
        Logs.logSimulationLink(target, data);
    }
}
