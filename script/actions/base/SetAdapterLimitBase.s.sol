// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IVaultV2} from "../../../src/interfaces/vault/IVaultV2.sol";
import {Logs} from "../../utils/Logs.sol";
import {ScriptBase} from "../../utils/ScriptBase.s.sol";

contract SetAdapterLimitBaseScript is ScriptBase {
    function runBase(address vault, address adapter, uint208 limit)
        public
        virtual
        returns (bytes memory data, address target)
    {
        target = vault;
        data = abi.encodeCall(IVaultV2.setAdapterLimit, (adapter, limit));
        sendTransaction(target, data);

        Logs.log(
            string.concat(
                "Set adapter limit",
                "\n    vault:",
                vm.toString(vault),
                "\n    adapter:",
                vm.toString(adapter),
                "\n    limit:",
                vm.toString(uint256(limit))
            )
        );
        Logs.logSimulationLink(target, data);
    }
}
