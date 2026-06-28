// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IVaultV2} from "../../../../src/interfaces/vault/IVaultV2.sol";
import {Logs} from "../../../utils/Logs.sol";
import {ScriptBase} from "../../../utils/ScriptBase.s.sol";

contract SetDepositLimitBaseScript is ScriptBase {
    function runBase(address vault, uint256 limit) public virtual returns (bytes memory data, address target) {
        target = vault;
        data = abi.encodeCall(IVaultV2.setDepositLimit, (limit));
        sendTransaction(target, data);

        Logs.log(
            string.concat("Set deposit limit", "\n    vault:", vm.toString(vault), "\n    limit:", vm.toString(limit))
        );
        Logs.logSimulationLink(target, data);
    }
}
