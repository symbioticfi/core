// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {DeployMorphoVaultV2AdapterBase} from "./base/DeployMorphoVaultV2AdapterBase.sol";

// forge script script/adapters/DeployMorphoVaultV2Adapter.s.sol:DeployMorphoVaultV2AdapterScript --rpc-url=RPC --account=ACCOUNT --sender=SENDER --broadcast

contract DeployMorphoVaultV2AdapterScript is DeployMorphoVaultV2AdapterBase {
    // Configurations - UPDATE THESE BEFORE DEPLOYMENT

    // Address that will own the adapter factory after deployment.
    address public constant ADAPTER_FACTORY_OWNER = 0x0000000000000000000000000000000000000000;
    // Morpho Vault V2 factory used to validate target Morpho vaults.
    address public constant MORPHO_VAULT_FACTORY = 0x0000000000000000000000000000000000000000;
    // Morpho adapter registry expected by target Morpho vaults.
    address public constant MORPHO_ADAPTER_REGISTRY = 0x0000000000000000000000000000000000000000;
    // CoW Protocol settlement used by the converter.
    address public constant COW_SWAP_SETTLEMENT = 0x0000000000000000000000000000000000000000;
    // Merkl Distributor used by the reward claimer.
    address public constant MERKL_DISTRIBUTOR = 0x0000000000000000000000000000000000000000;

    function run() public {
        runBase(
            DeployParams({
                adapterFactoryOwner: ADAPTER_FACTORY_OWNER,
                morphoVaultFactory: MORPHO_VAULT_FACTORY,
                morphoAdapterRegistry: MORPHO_ADAPTER_REGISTRY,
                cowSwapSettlement: COW_SWAP_SETTLEMENT,
                merklDistributor: MERKL_DISTRIBUTOR
            })
        );
    }
}
