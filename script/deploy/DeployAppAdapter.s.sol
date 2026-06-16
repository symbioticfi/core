// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {DeployAppAdapterBaseScript} from "./base/DeployAppAdapterBase.s.sol";

// forge script script/deploy/DeployAppAdapter.s.sol:DeployAppAdapterScript --rpc-url RPC/hoodi --broadcast --verify --etherscan-api-key 5NEH7KHHDWPQSEXNXJT3YSVBSS67MXRFXE

contract DeployAppAdapterScript is DeployAppAdapterBaseScript {
    // Address that will own the adapter factory after deployment.
    address public constant ADAPTER_FACTORY_OWNER = 0x0000000000000000000000000000000000000000;
    // Network middleware service used to authorize app slashes.
    address public constant NETWORK_MIDDLEWARE_SERVICE = 0x0000000000000000000000000000000000000000;

    function run() public {
        runBase(
            DeployParams({
                adapterFactoryOwner: ADAPTER_FACTORY_OWNER, networkMiddlewareService: NETWORK_MIDDLEWARE_SERVICE
            })
        );
    }
}
