// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {V2DeployBaseScript} from "./base/V2DeployBase.s.sol";

// forge script script/deploy/V2Deploy.s.sol:V2DeployScript --rpc-url=RPC --private-key PRIVATE_KEY --broadcast
// forge script script/deploy/V2Deploy.s.sol:V2DeployScript --rpc-url=RPC --sender CORE_OWNER_ADDRESS --unlocked

contract V2DeployScript is V2DeployBaseScript {
    // Address that will own the new AdapterRegistry.
    address public ADAPTER_REGISTRY_OWNER = address(0);
    // Optional FeeRegistry address. Leave as zero address if instant-withdraw fees are disabled for now.
    address public FEE_REGISTRY = address(0);
    // Rewards contract address used by VaultV2.
    address public REWARDS = address(0);

    function run() public {
        runBase(ADAPTER_REGISTRY_OWNER, FEE_REGISTRY, REWARDS);
    }
}
