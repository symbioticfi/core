// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IVaultV2} from "../../../../src/interfaces/vault/IVaultV2.sol";
import {IUniversalDelegator} from "../../../../src/interfaces/delegator/IUniversalDelegator.sol";
import {Logs} from "../../../utils/Logs.sol";
import {ScriptBase} from "../../../utils/ScriptBase.s.sol";

contract SetAutoAllocateAdaptersBaseScript is ScriptBase {
    function runBase(address vault, address[] memory adapters)
        public
        virtual
        returns (bytes memory data, address target)
    {
        target = IVaultV2(vault).delegator();
        data = abi.encodeCall(IUniversalDelegator.setAutoAllocateAdapters, (adapters));
        sendTransaction(target, data);

        Logs.log(string.concat("Set auto allocate adapters", "\n    vault:", vm.toString(vault)));
        Logs.logSimulationLink(target, data);
    }
}
