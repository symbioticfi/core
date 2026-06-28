// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {DeployAaveV3AdapterBase} from "./base/DeployAaveV3AdapterBase.sol";

// forge script script/adapters/DeployAaveV3Adapter.s.sol:DeployAaveV3AdapterScript --rpc-url=RPC --account=ACCOUNT --sender=SENDER --broadcast

contract DeployAaveV3AdapterScript is DeployAaveV3AdapterBase {
    // Configurations - UPDATE THESE BEFORE DEPLOYMENT

    // Address that will own the adapter factory after deployment.
    address public constant ADAPTER_FACTORY_OWNER = 0x0000000000000000000000000000000000000000;
    // Aave V3 pool used by the Aave adapter.
    address public constant AAVE_POOL = 0x0000000000000000000000000000000000000000;
    // CoW Protocol settlement used by the converter.
    address public constant COW_SWAP_SETTLEMENT = 0x0000000000000000000000000000000000000000;
    // Merkl Distributor used by the reward claimer.
    address public constant MERKL_DISTRIBUTOR = 0x0000000000000000000000000000000000000000;

    function run() public {
        runBase(
            DeployParams({
                adapterFactoryOwner: ADAPTER_FACTORY_OWNER,
                aavePool: AAVE_POOL,
                cowSwapSettlement: COW_SWAP_SETTLEMENT,
                merklDistributor: MERKL_DISTRIBUTOR
            })
        );
    }
}
