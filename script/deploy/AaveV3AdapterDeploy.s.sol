// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AaveV3AdapterDeployBaseScript} from "./base/AaveV3AdapterDeployBase.s.sol";

// forge script script/deploy/AaveV3AdapterDeploy.s.sol:AaveV3AdapterDeployScript --rpc-url https://ethereum-rpc.gprptest.net/hoodi --broadcast --verify --etherscan-api-key 5NEH7KHHDWPQSEXNXJT3YSVBSS67MXRFXE

contract AaveV3AdapterDeployScript is AaveV3AdapterDeployBaseScript {
    // Address that will own the adapter after deployment.
    address public constant ADAPTER_OWNER = 0x0000000000000000000000000000000000000000;
    // AaveV3 mock pool from AaveV3MocksDeployScript output.
    address public constant AAVE_POOL = 0x0000000000000000000000000000000000000000;
    // CuratorRegistry used by the adapter for curator-only recovery/configuration paths.
    address public constant CURATOR_REGISTRY = 0x0000000000000000000000000000000000000000;
    // Rewards contract address used by the adapter when skimming yield.
    address public constant REWARDS = 0x0000000000000000000000000000000000000000;

    function run() public {
        runBase(
            DeployParams({
                adapterOwner: ADAPTER_OWNER, aavePool: AAVE_POOL, curatorRegistry: CURATOR_REGISTRY, rewards: REWARDS
            })
        );
    }
}
