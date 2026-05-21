// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IVaultV2} from "../../../src/interfaces/vault/IVaultV2.sol";
import {Logs} from "../../utils/Logs.sol";
import {ScriptBase} from "../../utils/ScriptBase.s.sol";

contract DeallocateAdaptersBaseScript is ScriptBase {
    function runBase(address vault, uint256 amount) public virtual returns (bytes memory data, address target) {
        target = IVaultV2(vault).delegator();
        data = abi.encodeWithSignature("deallocate(uint256)", amount);
        sendTransaction(target, data);

        Logs.log(
            string.concat(
                "Deallocate adapters", "\n    vault:", vm.toString(vault), "\n    amount:", vm.toString(amount)
            )
        );
        Logs.logSimulationLink(target, data);
    }
}
