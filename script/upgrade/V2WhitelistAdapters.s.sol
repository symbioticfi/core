// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./base/V2WhitelistAdaptersBase.s.sol";
import {Logs} from "../utils/Logs.sol";

// forge script script/upgrade/V2WhitelistAdapters.s.sol:V2WhitelistAdaptersScript --rpc-url RPC/hoodi --broadcast

contract V2WhitelistAdaptersScript is V2WhitelistAdaptersBaseScript {
    // Deployed V2 AdapterRegistry from V2DeployScript output.
    address constant ADAPTER_REGISTRY = 0x0000000000000000000000000000000000000000;
    // Vault scope for the adapter factory, or zero address for the global whitelist.
    address constant VAULT = 0x0000000000000000000000000000000000000000;
    // Deployed adapter factory from the adapter factory deploy script output.
    address constant ADAPTER_FACTORY = 0x0000000000000000000000000000000000000000;

    function run() public {
        (bytes memory whitelistAdapterFactoryData, address whitelistAdapterFactoryTarget) =
            whitelistAdapterFactory(ADAPTER_REGISTRY, VAULT, ADAPTER_FACTORY);

        Logs.log(
            string.concat(
                "V2WhitelistAdapters data:",
                "\n    whitelistAdapterFactoryData:",
                vm.toString(whitelistAdapterFactoryData),
                "\n    whitelistAdapterFactoryTarget:",
                vm.toString(whitelistAdapterFactoryTarget)
            )
        );
    }
}
