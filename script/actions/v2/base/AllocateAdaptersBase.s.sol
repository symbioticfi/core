// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IVaultV2} from "../../../../src/interfaces/vault/IVaultV2.sol";
import {IUniversalDelegator} from "../../../../src/interfaces/delegator/IUniversalDelegator.sol";
import {Logs} from "../../../utils/Logs.sol";
import {ScriptBase} from "../../../utils/ScriptBase.s.sol";

contract AllocateAdaptersBaseScript is ScriptBase {
    function runBase(address vault, uint256 amount) public virtual returns (bytes memory data, address target) {
        target = IVaultV2(vault).delegator();
        data = abi.encodeCall(IUniversalDelegator.allocateAll, (amount));
        sendTransaction(target, data);

        Logs.log(
            string.concat("Allocate adapters", "\n    vault:", vm.toString(vault), "\n    amount:", vm.toString(amount))
        );
        Logs.logSimulationLink(target, data);
    }
}
