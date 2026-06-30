// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {DeployEulerAdapterBase} from "./base/DeployEulerAdapterBase.sol";

// forge script script/adapters/DeployEulerAdapter.s.sol:DeployEulerAdapterScript --rpc-url=RPC --account=ACCOUNT --sender=SENDER --broadcast

contract DeployEulerAdapterScript is DeployEulerAdapterBase {
    // Configurations - UPDATE THESE BEFORE DEPLOYMENT

    // Address that will own the adapter factory after deployment.
    address public constant ADAPTER_FACTORY_OWNER = 0x0000000000000000000000000000000000000000;
    // Euler Lend vault factory used to validate target lend vaults.
    address public constant EULER_LEND_VAULT_FACTORY = 0x0000000000000000000000000000000000000000;
    // CoW Protocol settlement used by the converter.
    address public constant COW_SWAP_SETTLEMENT = 0x0000000000000000000000000000000000000000;
    // Merkl Distributor used by the reward claimer.
    address public constant MERKL_DISTRIBUTOR = 0x0000000000000000000000000000000000000000;

    function run() public {
        runBase(
            DeployParams({
                adapterFactoryOwner: ADAPTER_FACTORY_OWNER,
                eulerLendVaultFactory: EULER_LEND_VAULT_FACTORY,
                cowSwapSettlement: COW_SWAP_SETTLEMENT,
                merklDistributor: MERKL_DISTRIBUTOR
            })
        );
    }
}
