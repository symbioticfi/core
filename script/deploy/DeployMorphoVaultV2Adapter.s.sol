// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {DeployMorphoVaultV2AdapterBaseScript} from "./base/DeployMorphoVaultV2AdapterBase.s.sol";

// forge script script/deploy/DeployMorphoVaultV2Adapter.s.sol:DeployMorphoVaultV2AdapterScript --rpc-url RPC/hoodi --broadcast --verify --etherscan-api-key 5NEH7KHHDWPQSEXNXJT3YSVBSS67MXRFXE

contract DeployMorphoVaultV2AdapterScript is DeployMorphoVaultV2AdapterBaseScript {
    // Address that will own the adapter factory after deployment.
    address public constant ADAPTER_FACTORY_OWNER = 0x0000000000000000000000000000000000000000;
    // MorphoVaultV2 dependencies used by the Morpho adapter.
    address public constant MORPHO_VAULT_FACTORY = 0xA1D94F746dEfa1928926b84fB2596c06926C0405;
    address public constant MORPHO_ADAPTER_REGISTRY = 0x3696c5eAe4a7Ffd04Ea163564571E9CD8Ed9364e;

    function run() public {
        runBase(
            DeployParams({
                adapterFactoryOwner: ADAPTER_FACTORY_OWNER,
                morphoVaultFactory: MORPHO_VAULT_FACTORY,
                morphoAdapterRegistry: MORPHO_ADAPTER_REGISTRY
            })
        );
    }
}
