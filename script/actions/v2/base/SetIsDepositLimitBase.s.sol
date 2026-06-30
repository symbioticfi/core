// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IVaultV2} from "../../../../src/interfaces/vault/IVaultV2.sol";
import {Logs} from "../../../utils/Logs.sol";
import {ScriptBase} from "../../../utils/ScriptBase.s.sol";

contract SetIsDepositLimitBaseScript is ScriptBase {
    function runBase(address vault, bool status) public virtual returns (bytes memory data, address target) {
        target = vault;
        data = abi.encodeCall(IVaultV2.setIsDepositLimit, (status));
        sendTransaction(target, data);

        Logs.log(
            string.concat(
                "Set is deposit limit", "\n    vault:", vm.toString(vault), "\n    status:", vm.toString(status)
            )
        );
        Logs.logSimulationLink(target, data);
    }
}
