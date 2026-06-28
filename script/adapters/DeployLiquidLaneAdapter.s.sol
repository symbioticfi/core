// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {DeployLiquidLaneAdapterBase} from "./base/DeployLiquidLaneAdapterBase.sol";

// forge script script/adapters/DeployLiquidLaneAdapter.s.sol:DeployLiquidLaneAdapterScript --rpc-url=RPC --account=ACCOUNT --sender=SENDER --broadcast

contract DeployLiquidLaneAdapterScript is DeployLiquidLaneAdapterBase {
    // Configurations - UPDATE THESE BEFORE DEPLOYMENT

    // Address that will own the adapter factory after deployment.
    address public constant ADAPTER_FACTORY_OWNER = 0x0000000000000000000000000000000000000000;
    // Account registry mapping vault assets and redemption tokens to account factories.
    address public constant ACCOUNT_REGISTRY = 0x0000000000000000000000000000000000000000;

    function run() public {
        runBase(DeployParams({adapterFactoryOwner: ADAPTER_FACTORY_OWNER, accountRegistry: ACCOUNT_REGISTRY}));
    }
}
