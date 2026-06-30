// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {DeployAppAdapterBase} from "./base/DeployAppAdapterBase.sol";

// forge script script/adapters/DeployAppAdapter.s.sol:DeployAppAdapterScript --rpc-url=RPC --account=ACCOUNT --sender=SENDER --broadcast

contract DeployAppAdapterScript is DeployAppAdapterBase {
    // Configurations - UPDATE THESE BEFORE DEPLOYMENT

    // Address that will own the adapter factory after deployment.
    address public constant ADAPTER_FACTORY_OWNER = 0x0000000000000000000000000000000000000000;
    // CoW Protocol settlement used by the converter.
    address public constant COW_SWAP_SETTLEMENT = 0x0000000000000000000000000000000000000000;
    // Network middleware service used to authorize app slashes.
    address public constant NETWORK_MIDDLEWARE_SERVICE = 0x0000000000000000000000000000000000000000;

    function run() public {
        runBase(
            DeployParams({
                adapterFactoryOwner: ADAPTER_FACTORY_OWNER,
                cowSwapSettlement: COW_SWAP_SETTLEMENT,
                networkMiddlewareService: NETWORK_MIDDLEWARE_SERVICE
            })
        );
    }
}
