// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {DeployMorphoVaultV2MocksBaseScript} from "./base/DeployMorphoVaultV2MocksBase.s.sol";

// forge script script/deploy/testnet/DeployMorphoVaultV2Mocks.s.sol:DeployMorphoVaultV2MocksScript --rpc-url RPC/hoodi --broadcast --verify --etherscan-api-key <>

contract DeployMorphoVaultV2MocksScript is DeployMorphoVaultV2MocksBaseScript {
    // Optional address that will own the mock Morpho AdapterRegistry. Leave zero to use the script owner.
    address public constant ADAPTER_REGISTRY_OWNER = 0x0000000000000000000000000000000000000000;
    // Leave zero to deploy a new mock collateral, or replace with an existing collateral address.
    address public constant COLLATERAL = 0x0000000000000000000000000000000000000000;

    function run() public {
        address owner = vm.envOr("TESTNET_ADAPTER_REGISTRY_OWNER", ADAPTER_REGISTRY_OWNER);
        if (owner == address(0)) {
            owner = _scriptOwner();
        }
        runBase(DeployParams({adapterRegistryOwner: owner, collateral: vm.envOr("TESTNET_COLLATERAL", COLLATERAL)}));
    }
}
