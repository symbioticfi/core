// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./base/V2WhitelistAdaptersBase.s.sol";
import {Logs} from "../utils/Logs.sol";

// forge script script/upgrade/V2WhitelistAdapters.s.sol:V2WhitelistAdaptersScript --rpc-url RPC/hoodi --broadcast

contract V2WhitelistAdaptersScript is V2WhitelistAdaptersBaseScript {
    // Deployed V2 AdapterRegistry from V2DeployScript output.
    address constant ADAPTER_REGISTRY = 0x0000000000000000000000000000000000000000;
    // Deployed AaveV3Adapter from AaveV3AdapterDeployScript output.
    address constant ADAPTER = 0x0000000000000000000000000000000000000000;

    function run() public {
        (bytes memory whitelistAdapterData, address whitelistAdapterTarget) =
            whitelistAdapter(ADAPTER_REGISTRY, ADAPTER);

        Logs.log(
            string.concat(
                "V2WhitelistAdapters data:",
                "\n    whitelistAdapterData:",
                vm.toString(whitelistAdapterData),
                "\n    whitelistAdapterTarget:",
                vm.toString(whitelistAdapterTarget)
            )
        );
    }
}
