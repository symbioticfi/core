// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {DeployV2BaseScript} from "./base/DeployV2Base.s.sol";

// forge script script/deploy/DeployV2.s.sol:DeployV2Script --rpc-url RPC/hoodi --broadcast --verify --etherscan-api-key <>

contract DeployV2Script is DeployV2BaseScript {
    // Address that will own the new AdapterRegistry.
    address public constant ADAPTER_REGISTRY_OWNER = 0x0000000000000000000000000000000000000000;
    // Address that will own the new ProtocolFeeRegistry.
    address public constant PROTOCOL_FEE_REGISTRY_OWNER = 0x0000000000000000000000000000000000000000;
    // Address that will own the new adapter factories.
    address public constant ADAPTER_FACTORY_OWNER = 0x0000000000000000000000000000000000000000;
    // Morpho Vault V2 factory used by MorphoVaultV2Adapter implementations.
    address public constant MORPHO_VAULT_FACTORY = 0xA1D94F746dEfa1928926b84fB2596c06926C0405;
    // Morpho liquidity adapter registry required by MorphoVaultV2Adapter implementations.
    address public constant MORPHO_ADAPTER_REGISTRY = 0x3696c5eAe4a7Ffd04Ea163564571E9CD8Ed9364e;
    // Aave V3 pool used by AaveV3Adapter implementations.
    address public constant AAVE_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    // CoW Protocol settlement used by converter-enabled adapters.
    address public constant COW_SWAP_SETTLEMENT = 0x9008D19f58AAbD9eD0D60971565AA8510560ab41;
    // Merkl distributor used by reward-claiming adapters.
    address public constant MERKL_DISTRIBUTOR = 0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae;
    // Network middleware service used by AppAdapter and RestakingAppAdapter implementations.
    address public constant NETWORK_MIDDLEWARE_SERVICE = 0xD7dC9B366c027743D90761F71858BCa83C6899Ad;

    function run() public {
        runBase(
            DeployParams({
                adapterRegistryOwner: ADAPTER_REGISTRY_OWNER,
                protocolFeeRegistryOwner: PROTOCOL_FEE_REGISTRY_OWNER,
                adapterFactoryOwner: ADAPTER_FACTORY_OWNER,
                morphoVaultFactory: MORPHO_VAULT_FACTORY,
                morphoAdapterRegistry: MORPHO_ADAPTER_REGISTRY,
                aavePool: AAVE_POOL,
                cowSwapSettlement: COW_SWAP_SETTLEMENT,
                merklDistributor: MERKL_DISTRIBUTOR,
                networkMiddlewareService: NETWORK_MIDDLEWARE_SERVICE
            })
        );
    }
}
