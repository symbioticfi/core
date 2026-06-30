// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IVaultV2} from "../../../../src/interfaces/vault/IVaultV2.sol";
import {IUniversalDelegator} from "../../../../src/interfaces/delegator/IUniversalDelegator.sol";
import {Logs} from "../../../utils/Logs.sol";
import {ScriptBase} from "../../../utils/ScriptBase.s.sol";

contract AllocateAdapterExactBaseScript is ScriptBase {
    function runBase(address vault, address adapter, uint256 amount)
        public
        virtual
        returns (bytes memory data, address target)
    {
        target = IVaultV2(vault).delegator();
        data = abi.encodeCall(IUniversalDelegator.allocateExact, (adapter, amount));
        sendTransaction(target, data);

        Logs.log(
            string.concat(
                "Allocate adapter exact",
                "\n    vault:",
                vm.toString(vault),
                "\n    adapter:",
                vm.toString(adapter),
                "\n    amount:",
                vm.toString(amount)
            )
        );
        Logs.logSimulationLink(target, data);
    }
}
