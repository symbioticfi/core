// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MorphoVaultV2AdapterDeployBaseScript} from "./base/MorphoVaultV2AdapterDeployBase.s.sol";

// forge script script/deploy/MorphoVaultV2AdapterDeploy.s.sol:MorphoVaultV2AdapterDeployScript --rpc-url RPC/hoodi --broadcast --verify --etherscan-api-key 5NEH7KHHDWPQSEXNXJT3YSVBSS67MXRFXE

contract MorphoVaultV2AdapterDeployScript is MorphoVaultV2AdapterDeployBaseScript {
    // Address that will own the adapter factory after deployment.
    address public constant ADAPTER_FACTORY_OWNER = 0x0000000000000000000000000000000000000000;
    // MorphoVaultV2 mocks from MorphoVaultV2MocksDeployScript output.
    address public constant MORPHO_VAULT_FACTORY = 0xA1D94F746dEfa1928926b84fB2596c06926C0405;
    address public constant MORPHO_ADAPTER_REGISTRY = 0x3696c5eAe4a7Ffd04Ea163564571E9CD8Ed9364e;
    // CuratorRegistry used by the adapter for curator-only recovery/configuration paths.
    address public constant CURATOR_REGISTRY = 0xF75D8d8F790178F0d7F2ee7656874567d382C21e;
    // CoW Protocol settlement used by the converter.
    address public constant COW_SWAP_SETTLEMENT = 0x0000000000000000000000000000000000000000;
    // CoW Protocol vault relayer approved by the converter.
    address public constant COW_SWAP_VAULT_RELAYER = 0x0000000000000000000000000000000000000000;
    // Maximum accepted CoW order validity duration.
    uint32 public constant MAX_VALID_TO_DURATION = 1 hours;
    // Rewards contract address used by the adapter.
    address public constant REWARDS = 0xa13e65cA0FeFa52cCb9615108fF400EF4806866B;

    function run() public {
        runBase(
            DeployParams({
                adapterFactoryOwner: ADAPTER_FACTORY_OWNER,
                morphoVaultFactory: MORPHO_VAULT_FACTORY,
                morphoAdapterRegistry: MORPHO_ADAPTER_REGISTRY,
                curatorRegistry: CURATOR_REGISTRY,
                cowSwapSettlement: COW_SWAP_SETTLEMENT,
                cowSwapVaultRelayer: COW_SWAP_VAULT_RELAYER,
                maxValidToDuration: MAX_VALID_TO_DURATION,
                rewards: REWARDS
            })
        );
    }
}
