// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/SetOperatorNetworkSharesBase.s.sol";

// forge script script/actions/SetOperatorNetworkShares.s.sol:SetOperatorNetworkSharesScript --rpc-url=RPC --private-key PRIVATE_KEY --broadcast

contract SetOperatorNetworkSharesScript is SetOperatorNetworkSharesBaseScript {
    // Configuration constants - UPDATE THESE BEFORE EXECUTING

    // Address of the vault to configure
    address constant VAULT = address(0);
    // Subnetwork identifier associated with the operator
    bytes32 constant SUBNETWORK = bytes32(0);
    // Address of the operator being updated
    address constant OPERATOR = address(0);
    // Number of shares to assign to the operator
    uint256 constant OPERATOR_NETWORK_SHARES = 0;

    function run() public {
        run(VAULT, SUBNETWORK, OPERATOR, OPERATOR_NETWORK_SHARES);
    }
}
