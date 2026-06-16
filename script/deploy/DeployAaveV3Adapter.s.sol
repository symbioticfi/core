// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {DeployAaveV3AdapterBaseScript} from "./base/DeployAaveV3AdapterBase.s.sol";

// forge script script/deploy/DeployAaveV3Adapter.s.sol:DeployAaveV3AdapterScript --rpc-url RPC/hoodi --broadcast --verify --etherscan-api-key 5NEH7KHHDWPQSEXNXJT3YSVBSS67MXRFXE

contract DeployAaveV3AdapterScript is DeployAaveV3AdapterBaseScript {
    // Address that will own the adapter factory after deployment.
    address public constant ADAPTER_FACTORY_OWNER = 0x0000000000000000000000000000000000000000;
    // AaveV3 pool used by the Aave adapter.
    address public constant AAVE_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;

    function run() public {
        runBase(DeployParams({adapterFactoryOwner: ADAPTER_FACTORY_OWNER, aavePool: AAVE_POOL}));
    }
}
