// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AaveV3AdapterDeployBaseScript} from "./base/AaveV3AdapterDeployBase.s.sol";

// forge script script/deploy/AaveV3AdapterDeploy.s.sol:AaveV3AdapterDeployScript --rpc-url RPC/hoodi --broadcast --verify --etherscan-api-key 5NEH7KHHDWPQSEXNXJT3YSVBSS67MXRFXE

contract AaveV3AdapterDeployScript is AaveV3AdapterDeployBaseScript {
    // Address that will own the adapter factory after deployment.
    address public constant ADAPTER_FACTORY_OWNER = 0x0000000000000000000000000000000000000000;
    // AaveV3 mock pool from AaveV3MocksDeployScript output.
    address public constant AAVE_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;

    function run() public {
        runBase(
            DeployParams({
                adapterFactoryOwner: ADAPTER_FACTORY_OWNER,
                aavePool: AAVE_POOL
            })
        );
    }
}
