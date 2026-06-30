// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IAdapterRegistry} from "../../../src/interfaces/IAdapterRegistry.sol";
import {Logs} from "../../utils/Logs.sol";
import {ScriptBase} from "../../utils/ScriptBase.s.sol";

contract V2WhitelistAdaptersBaseScript is ScriptBase {
    function whitelistAdapterFactory(address adapterRegistry, address vault, address adapterFactory)
        public
        virtual
        returns (bytes memory data, address target)
    {
        target = adapterRegistry;
        data = abi.encodeCall(IAdapterRegistry.setWhitelistedStatus, (vault, adapterFactory, true));
        sendTransaction(target, data);

        Logs.log(
            string.concat(
                "Whitelist adapter factory",
                "\n    adapterRegistry:",
                vm.toString(adapterRegistry),
                "\n    vault:",
                vm.toString(vault),
                "\n    adapterFactory:",
                vm.toString(adapterFactory)
            )
        );
        Logs.logSimulationLink(target, data);
    }
}
