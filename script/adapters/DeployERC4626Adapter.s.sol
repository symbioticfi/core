// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {DeployERC4626AdapterBase} from "./base/DeployERC4626AdapterBase.sol";

// forge script script/adapters/DeployERC4626Adapter.s.sol:DeployERC4626AdapterScript --rpc-url=RPC --account=ACCOUNT --sender=SENDER --broadcast

contract DeployERC4626AdapterScript is DeployERC4626AdapterBase {
    // Configurations - UPDATE THESE BEFORE DEPLOYMENT

    // Address that will own the adapter factory after deployment.
    address public constant ADAPTER_FACTORY_OWNER = 0x0000000000000000000000000000000000000000;
    // CoW Protocol settlement used by the converter.
    address public constant COW_SWAP_SETTLEMENT = 0x0000000000000000000000000000000000000000;
    // Merkl Distributor used by the reward claimer.
    address public constant MERKL_DISTRIBUTOR = 0x0000000000000000000000000000000000000000;

    function run() public {
        runBase(
            DeployParams({
                adapterFactoryOwner: ADAPTER_FACTORY_OWNER,
                cowSwapSettlement: COW_SWAP_SETTLEMENT,
                merklDistributor: MERKL_DISTRIBUTOR
            })
        );
    }
}
