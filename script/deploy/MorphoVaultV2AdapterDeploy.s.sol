// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MorphoVaultV2AdapterDeployBaseScript} from "./base/MorphoVaultV2AdapterDeployBase.s.sol";

// forge script script/deploy/MorphoVaultV2AdapterDeploy.s.sol:MorphoVaultV2AdapterDeployScript --rpc-url https://ethereum-rpc.gprptest.net/hoodi --broadcast --verify --etherscan-api-key 5NEH7KHHDWPQSEXNXJT3YSVBSS67MXRFXE

contract MorphoVaultV2AdapterDeployScript is MorphoVaultV2AdapterDeployBaseScript {
    // Address that will own the adapter after deployment.
    address public constant ADAPTER_OWNER = 0x0000000000000000000000000000000000000000;
    // MorphoVaultV2 mocks from MorphoVaultV2MocksDeployScript output.
    address public constant MORPHO_VAULT_FACTORY = 0x0000000000000000000000000000000000000000;
    address public constant MORPHO_ADAPTER_REGISTRY = 0x0000000000000000000000000000000000000000;
    // CuratorRegistry used by the adapter for curator-only recovery/configuration paths.
    address public constant CURATOR_REGISTRY = 0x0000000000000000000000000000000000000000;
    // Rewards contract address used by the adapter when skimming yield.
    address public constant REWARDS = 0x0000000000000000000000000000000000000000;

    function run() public {
        runBase(
            DeployParams({
                adapterOwner: ADAPTER_OWNER,
                morphoVaultFactory: MORPHO_VAULT_FACTORY,
                morphoAdapterRegistry: MORPHO_ADAPTER_REGISTRY,
                curatorRegistry: CURATOR_REGISTRY,
                rewards: REWARDS
            })
        );
    }
}
