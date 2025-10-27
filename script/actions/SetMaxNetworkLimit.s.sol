// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/SetMaxNetworkLimitBase.s.sol";

// forge script script/actions/SetMaxNetworkLimit.s.sol:SetMaxNetworkLimitScript --rpc-url=RPC --private-key PRIVATE_KEY --broadcast

contract SetMaxNetworkLimitScript is SetMaxNetworkLimitBaseScript {
    // Configuration constants - UPDATE THESE BEFORE EXECUTING

    // Address of the vault to configure
    address constant VAULT = address(0);
    // Identifier of the network parameter to adjust
    uint96 constant IDENTIFIER = 0;
    // Maximum network limit value to set
    uint256 constant MAX_NETWORK_LIMIT = 0;

    function run() public {
        run(VAULT, IDENTIFIER, MAX_NETWORK_LIMIT);
    }
}
