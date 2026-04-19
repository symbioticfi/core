// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {
    IMorphoVaultV2Adapter
} from "../../../src/interfaces/vault/adapters/morpho_vaultv2_adapter/IMorphoVaultV2Adapter.sol";
import {Logs} from "../../utils/Logs.sol";
import {ScriptBase} from "../../utils/ScriptBase.s.sol";

contract SetMorphoVaultBaseScript is ScriptBase {
    function runBase(address adapter, address vault, address morphoVault)
        public
        virtual
        returns (bytes memory data, address target)
    {
        target = adapter;
        data = abi.encodeCall(IMorphoVaultV2Adapter.setMorphoVault, (vault, morphoVault));
        sendTransaction(target, data);

        Logs.log(
            string.concat(
                "Set Morpho vault",
                "\n    adapter:",
                vm.toString(adapter),
                "\n    vault:",
                vm.toString(vault),
                "\n    morphoVault:",
                vm.toString(morphoVault)
            )
        );
        Logs.logSimulationLink(target, data);
    }
}
