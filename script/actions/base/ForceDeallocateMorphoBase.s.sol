// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IMorphoVaultV2Adapter} from "../../../src/interfaces/adapters/IMorphoVaultV2Adapter.sol";
import {Logs} from "../../utils/Logs.sol";
import {ScriptBase} from "../../utils/ScriptBase.s.sol";

contract ForceDeallocateMorphoBaseScript is ScriptBase {
    function runBase(address adapter, uint256 amount) public virtual returns (bytes memory data, address target) {
        target = adapter;
        data = abi.encodeCall(IMorphoVaultV2Adapter.forceDeallocate, (amount));
        sendTransaction(target, data);

        Logs.log(
            string.concat(
                "Force deallocate Morpho adapter",
                "\n    adapter:",
                vm.toString(adapter),
                "\n    amount:",
                vm.toString(amount)
            )
        );
        Logs.logSimulationLink(target, data);
    }
}
