// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AaveV3AdapterDeployBaseScript} from "./base/AaveV3AdapterDeployBase.s.sol";

// forge script script/deploy/AaveV3AdapterDeploy.s.sol:AaveV3AdapterDeployScript --rpc-url RPC/hoodi --broadcast --verify --etherscan-api-key 5NEH7KHHDWPQSEXNXJT3YSVBSS67MXRFXE

contract AaveV3AdapterDeployScript is AaveV3AdapterDeployBaseScript {
    // Address that will own the adapter factory after deployment.
    address public constant ADAPTER_FACTORY_OWNER = 0x0000000000000000000000000000000000000000;
    // AaveV3 mock pool from AaveV3MocksDeployScript output.
    address public constant AAVE_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    // CuratorRegistry used by the adapter for curator-only recovery/configuration paths.
    address public constant CURATOR_REGISTRY = 0xF75D8d8F790178F0d7F2ee7656874567d382C21e;
    // CoW Protocol settlement used by the converter.
    address public constant COW_SWAP_SETTLEMENT = 0x0000000000000000000000000000000000000000;
    // CoW Protocol vault relayer approved by the converter.
    address public constant COW_SWAP_VAULT_RELAYER = 0x0000000000000000000000000000000000000000;
    // Protocol address allowed to convert immediately.
    address public constant PROTOCOL = 0x0000000000000000000000000000000000000000;
    // Maximum accepted CoW order validity duration.
    uint32 public constant MAX_VALID_TO_DURATION = 1 hours;
    // Rewards contract address used by the adapter.
    address public constant REWARDS = 0xa13e65cA0FeFa52cCb9615108fF400EF4806866B;

    function run() public {
        runBase(
            DeployParams({
                adapterFactoryOwner: ADAPTER_FACTORY_OWNER,
                aavePool: AAVE_POOL,
                curatorRegistry: CURATOR_REGISTRY,
                cowSwapSettlement: COW_SWAP_SETTLEMENT,
                cowSwapVaultRelayer: COW_SWAP_VAULT_RELAYER,
                protocol: PROTOCOL,
                maxValidToDuration: MAX_VALID_TO_DURATION,
                rewards: REWARDS
            })
        );
    }
}
