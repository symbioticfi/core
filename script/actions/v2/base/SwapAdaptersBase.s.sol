// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IVaultV2} from "../../../../src/interfaces/vault/IVaultV2.sol";
import {IUniversalDelegator} from "../../../../src/interfaces/delegator/IUniversalDelegator.sol";
import {Logs} from "../../../utils/Logs.sol";
import {ScriptBase} from "../../../utils/ScriptBase.s.sol";

contract SwapAdaptersBaseScript is ScriptBase {
    function runBase(address vault, address adapter1, address adapter2)
        public
        virtual
        returns (bytes memory data, address target)
    {
        target = IVaultV2(vault).delegator();
        data = abi.encodeCall(IUniversalDelegator.swapAdapters, (adapter1, adapter2));
        sendTransaction(target, data);

        Logs.log(
            string.concat(
                "Swap adapters",
                "\n    vault:",
                vm.toString(vault),
                "\n    adapter1:",
                vm.toString(adapter1),
                "\n    adapter2:",
                vm.toString(adapter2)
            )
        );
        Logs.logSimulationLink(target, data);
    }
}
