// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {DeployMorphoVaultV2MocksBaseScript} from "./base/DeployMorphoVaultV2MocksBase.s.sol";

// forge script script/deploy/testnet/DeployMorphoVaultV2Mocks.s.sol:DeployMorphoVaultV2MocksScript --rpc-url RPC/hoodi --broadcast --verify --etherscan-api-key 5NEH7KHHDWPQSEXNXJT3YSVBSS67MXRFXE

contract DeployMorphoVaultV2MocksScript is DeployMorphoVaultV2MocksBaseScript {
    // Address that will own the mock Morpho AdapterRegistry.
    address public constant ADAPTER_REGISTRY_OWNER = 0x0000000000000000000000000000000000000000;
    // Leave zero to deploy a new mock collateral, or replace with an existing collateral address.
    address public constant COLLATERAL = 0x0000000000000000000000000000000000000000;

    function run() public {
        runBase(DeployParams({adapterRegistryOwner: ADAPTER_REGISTRY_OWNER, collateral: COLLATERAL}));
    }
}
