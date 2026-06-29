// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {DeployThreeFAdapterBase} from "./base/DeployThreeFAdapterBase.sol";

// forge script script/adapters/DeployThreeFAdapter.s.sol:DeployThreeFAdapterScript --rpc-url=RPC --account=ACCOUNT --sender=SENDER --broadcast

contract DeployThreeFAdapterScript is DeployThreeFAdapterBase {
    // Configurations - UPDATE THESE BEFORE DEPLOYMENT

    // Address that will own the adapter factory after deployment.
    address public constant ADAPTER_FACTORY_OWNER = 0x0000000000000000000000000000000000000000;
    // Whitelist contract used to authorize 3F requests.
    address public constant REQUEST_WHITELIST = 0x0000000000000000000000000000000000000000;

    function run() public {
        runBase(DeployParams({adapterFactoryOwner: ADAPTER_FACTORY_OWNER, requestWhitelist: REQUEST_WHITELIST}));
    }
}
