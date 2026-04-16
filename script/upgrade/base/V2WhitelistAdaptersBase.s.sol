// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IAdapterRegistry} from "../../../src/interfaces/IAdapterRegistry.sol";
import {Logs} from "../../utils/Logs.sol";
import {ScriptBase} from "../../utils/ScriptBase.s.sol";

contract V2WhitelistAdaptersBaseScript is ScriptBase {
    function whitelistAdapter(address adapterRegistry, address adapter)
        public
        virtual
        returns (bytes memory data, address target)
    {
        target = adapterRegistry;
        data = abi.encodeCall(IAdapterRegistry.whitelistAdapter, (adapter));
        sendTransaction(target, data);

        Logs.log(
            string.concat(
                "Whitelist adapter",
                "\n    adapterRegistry:",
                vm.toString(adapterRegistry),
                "\n    adapter:",
                vm.toString(adapter)
            )
        );
        Logs.logSimulationLink(target, data);
    }
}
