// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/SetNetworkLimitBase.s.sol";

import {console2} from "forge-std/Test.sol";

// forge script script/actions/SetNetworkLimit.s.sol:SetNetworkLimitScript --rpc-url=RPC --private-key PRIVATE_KEY --broadcast

contract SetNetworkLimitScript is SetNetworkLimitBaseScript {
    // Configuration constants - UPDATE THESE BEFORE EXECUTING

    // Address of the vault to configure
    address constant VAULT = address(0);
    // Subnetwork identifier to update
    bytes32 constant SUBNETWORK = bytes32(0);
    // Network limit value to assign
    uint256 constant NETWORK_LIMIT = 0;

    function run() public {
        run(VAULT, SUBNETWORK, NETWORK_LIMIT);
    }
}
