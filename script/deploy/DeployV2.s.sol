// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {DeployV2BaseScript} from "./base/DeployV2Base.s.sol";

// forge script script/deploy/DeployV2.s.sol:DeployV2Script --rpc-url RPC/hoodi --broadcast --verify --etherscan-api-key 5NEH7KHHDWPQSEXNXJT3YSVBSS67MXRFXE

contract DeployV2Script is DeployV2BaseScript {
    // Address that will own the new AdapterRegistry.
    address public constant ADAPTER_REGISTRY_OWNER = 0x0000000000000000000000000000000000000000;
    // Address that will own the new ProtocolFeeRegistry.
    address public constant PROTOCOL_FEE_REGISTRY_OWNER = 0x0000000000000000000000000000000000000000;

    function run() public {
        runBase(ADAPTER_REGISTRY_OWNER, PROTOCOL_FEE_REGISTRY_OWNER);
    }
}
