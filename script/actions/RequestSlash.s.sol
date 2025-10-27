// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/RequestSlashBase.s.sol";

// forge script script/actions/RequestSlash.s.sol:RequestSlashScript --rpc-url=RPC --private-key PRIVATE_KEY --broadcast

contract RequestSlashScript is RequestSlashBaseScript {
    // Configuration constants - UPDATE THESE BEFORE EXECUTING

    // Address of the vault that holds operator collateral
    address constant VAULT = address(0);
    // Subnetwork identifier associated with the slashing request
    bytes32 constant SUBNETWORK = bytes32(0);
    // Address of the operator being slashed
    address constant OPERATOR = address(0);
    // Amount of collateral requested to slash
    uint256 constant AMOUNT = 0;
    // Capture timestamp tied to the slash request
    uint48 constant CAPTURE_TIMESTAMP = 0;

    function run() public {
        run(VAULT, SUBNETWORK, OPERATOR, AMOUNT, CAPTURE_TIMESTAMP);
    }
}
