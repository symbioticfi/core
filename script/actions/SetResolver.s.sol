// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/SetResolverBase.s.sol";

// forge script script/actions/SetResolver.s.sol:SetResolverScript --rpc-url=RPC --private-key PRIVATE_KEY --broadcast

contract SetResolverScript is SetResolverBaseScript {
    // Configuration constants - UPDATE THESE BEFORE EXECUTING

    // Address of the vault to configure
    address constant VAULT = address(0);
    // Identifier for the resolver slot
    uint96 constant IDENTIFIER = 0;
    // Address of the resolver contract
    address constant RESOLVER = address(0);

    function run() public {
        run(VAULT, IDENTIFIER, RESOLVER);
    }
}
