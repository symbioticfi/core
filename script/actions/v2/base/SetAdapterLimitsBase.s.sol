// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IVaultV2} from "../../../../src/interfaces/vault/IVaultV2.sol";
import {IUniversalDelegator} from "../../../../src/interfaces/delegator/IUniversalDelegator.sol";
import {Logs} from "../../../utils/Logs.sol";
import {ScriptBase} from "../../../utils/ScriptBase.s.sol";

contract SetAdapterLimitsBaseScript is ScriptBase {
    function runBase(address vault, address adapter, uint256 absoluteLimit, uint256 shareLimit)
        public
        virtual
        returns (bytes memory data, address target)
    {
        target = IVaultV2(vault).delegator();
        data = abi.encodeCall(IUniversalDelegator.setLimits, (adapter, absoluteLimit, shareLimit));
        sendTransaction(target, data);

        Logs.log(
            string.concat(
                "Set adapter limits",
                "\n    vault:",
                vm.toString(vault),
                "\n    adapter:",
                vm.toString(adapter),
                "\n    absoluteLimit:",
                vm.toString(absoluteLimit),
                "\n    shareLimit:",
                vm.toString(shareLimit)
            )
        );
        Logs.logSimulationLink(target, data);
    }
}
