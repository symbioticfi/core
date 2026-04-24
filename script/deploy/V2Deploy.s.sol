// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {V2DeployBaseScript} from "./base/V2DeployBase.s.sol";

// forge script script/deploy/V2Deploy.s.sol:V2DeployScript --rpc-url https://ethereum-rpc.gprptest.net/hoodi --broadcast --verify --etherscan-api-key 5NEH7KHHDWPQSEXNXJT3YSVBSS67MXRFXE

contract V2DeployScript is V2DeployBaseScript {
    // Address that will own the new AdapterRegistry.
    address public constant ADAPTER_REGISTRY_OWNER = 0x0000000000000000000000000000000000000000;
    // FeeRegistry address used by VaultV2.
    address public constant FEE_REGISTRY = 0x0000000000000000000000000000000000000000;
    // Rewards contract address used by VaultV2.
    address public constant REWARDS = 0x0000000000000000000000000000000000000000;

    function run() public {
        runBase(ADAPTER_REGISTRY_OWNER, FEE_REGISTRY, REWARDS);
    }
}
