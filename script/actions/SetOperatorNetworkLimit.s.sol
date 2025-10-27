// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/SetOperatorNetworkLimitBase.s.sol";

// forge script script/actions/SetOperatorNetworkLimit.s.sol:SetOperatorNetworkLimitScript --rpc-url=RPC --private-key PRIVATE_KEY --broadcast

contract SetOperatorNetworkLimitScript is SetOperatorNetworkLimitBaseScript {
    // Configuration constants - UPDATE THESE BEFORE EXECUTING

    // Address of the vault to configure
    address constant VAULT = address(0);
    // Subnetwork identifier associated with the operator
    bytes32 constant SUBNETWORK = bytes32(0);
    // Address of the operator to update
    address constant OPERATOR = address(0);
    // Operator-specific network limit
    uint256 constant AMOUNT = 0;

    function run() public {
        run(VAULT, SUBNETWORK, OPERATOR, AMOUNT);
    }
}
