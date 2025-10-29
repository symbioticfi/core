// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/SetResolverBase.s.sol";

// forge script script/actions/SetResolver.s.sol:SetResolverScript --rpc-url=RPC --private-key PRIVATE_KEY --broadcast
// forge script script/actions/SetResolver.s.sol:SetResolverScript --rpc-url=RPC -—sender MULTISIG_ADDRESS —-unlocked

contract SetResolverScript is SetResolverBaseScript {
    // Configuration constants - UPDATE THESE BEFORE EXECUTING

    // Address of the Vault
    address constant VAULT = address(0);
    // Subnetwork Identifier (multiple subnetworks can be used, e.g., to have different resolvers for the same network)
    uint96 constant IDENTIFIER = 0;
    // Address of the Resolver to set
    address constant RESOLVER = address(0);

    function run() public {
        (bytes memory data, address target) = runBase(VAULT, IDENTIFIER, RESOLVER);
        Logs.log(
            string.concat("SetResolver data:", "\n    data:", vm.toString(data), "\n    target:", vm.toString(target))
        );
    }
}
