// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {MorphoVaultV2MocksDeployBaseScript} from "./base/MorphoVaultV2MocksDeployBase.s.sol";

// forge script script/deploy/testnet/MorphoVaultV2MocksDeploy.s.sol:MorphoVaultV2MocksDeployScript --rpc-url RPC/hoodi --broadcast --verify --etherscan-api-key 5NEH7KHHDWPQSEXNXJT3YSVBSS67MXRFXE

contract MorphoVaultV2MocksDeployScript is MorphoVaultV2MocksDeployBaseScript {
    // Address that will own the mock Morpho AdapterRegistry.
    address public constant ADAPTER_REGISTRY_OWNER = 0x0000000000000000000000000000000000000000;
    // Leave zero to deploy a new mock collateral, or replace with an existing collateral address.
    address public constant COLLATERAL = 0x0000000000000000000000000000000000000000;

    function run() public {
        runBase(DeployParams({adapterRegistryOwner: ADAPTER_REGISTRY_OWNER, collateral: COLLATERAL}));
    }
}
