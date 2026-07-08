// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {DeployAdapterBase} from "./base/DeployAdapterBase.sol";

// forge script script/adapters/DeployThreeFAdapter.s.sol:DeployThreeFAdapterScript --rpc-url=RPC --broadcast

contract DeployThreeFAdapterScript is DeployAdapterBase {
    // Configurations - UPDATE THESE BEFORE DEPLOYMENT.

    address public constant ADAPTER_FACTORY = 0x0000000000000000000000000000000000000000;
    uint64 public constant VERSION = 1;
    address public constant OWNER = 0x0000000000000000000000000000000000000000;
    address public constant VAULT = 0x0000000000000000000000000000000000000000;

    function run() public returns (DeploymentData memory data) {
        data = runBase(
            DeployParams({adapterFactory: ADAPTER_FACTORY, version: VERSION, owner: OWNER, vault: VAULT, initData: ""})
        );
    }
}
