// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {DeployAaveV3AdapterBaseScript} from "./base/DeployAaveV3AdapterBase.s.sol";

// forge script script/deploy/DeployAaveV3Adapter.s.sol:DeployAaveV3AdapterScript --rpc-url RPC/hoodi --broadcast --verify --etherscan-api-key 5NEH7KHHDWPQSEXNXJT3YSVBSS67MXRFXE

contract DeployAaveV3AdapterScript is DeployAaveV3AdapterBaseScript {
    // Address that will own the adapter factory after deployment.
    address public constant ADAPTER_FACTORY_OWNER = 0x0000000000000000000000000000000000000000;
    // AaveV3 pool used by the Aave adapter.
    address public constant AAVE_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    // CoW Protocol settlement used by the converter.
    address public constant COW_SWAP_SETTLEMENT = 0x0000000000000000000000000000000000000000;
    // CoW Protocol vault relayer approved by the converter.
    address public constant COW_SWAP_VAULT_RELAYER = 0x0000000000000000000000000000000000000000;
    // Mainnet Merkl Distributor used by the reward claimer.
    address public constant MERKL_DISTRIBUTOR = 0x3Ef3D8bA38EBe18DB133cEc108f4D14CE00Dd9Ae;

    function run() public {
        runBase(
            DeployParams({
                adapterFactoryOwner: ADAPTER_FACTORY_OWNER,
                aavePool: AAVE_POOL,
                cowSwapSettlement: COW_SWAP_SETTLEMENT,
                cowSwapVaultRelayer: COW_SWAP_VAULT_RELAYER,
                merklDistributor: MERKL_DISTRIBUTOR
            })
        );
    }
}
