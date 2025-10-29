// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/SetMaxNetworkLimitBase.s.sol";

// forge script script/actions/SetMaxNetworkLimit.s.sol:SetMaxNetworkLimitScript --rpc-url=RPC --private-key PRIVATE_KEY --broadcast
// forge script script/actions/SetMaxNetworkLimit.s.sol:SetMaxNetworkLimitScript --rpc-url=RPC -—sender MULTISIG_ADDRESS —-unlocked

contract SetMaxNetworkLimitScript is SetMaxNetworkLimitBaseScript {
    // Configuration constants - UPDATE THESE BEFORE EXECUTING

    // Address of the Vault
    address constant VAULT = address(0);
    // Subnetwork Identifier (multiple subnetworks can be used, e.g., to have different max network limits for the same network)
    uint96 constant IDENTIFIER = 0;
    // Maximum amount of delegation that network is ready to receive
    uint256 constant MAX_NETWORK_LIMIT = 0;

    function run() public {
        (bytes memory data, address target) = runBase(VAULT, IDENTIFIER, MAX_NETWORK_LIMIT);
        Logs.log(
            string.concat(
                "SetMaxNetworkLimit data:", "\n    data:", vm.toString(data), "\n    target:", vm.toString(target)
            )
        );
    }
}
